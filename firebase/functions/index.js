'use strict';

/**
 * 生活OS：パートナー共有・通知の Cloud Functions（docs/PARTNER_NOTIFICATIONS_IMPLEMENTATION.md 8）
 *
 * - createInvite：所属を確認したうえで、期限つき（24時間）・一度だけ使える招待トークンを発行する
 * - acceptInvite：トークンをトランザクションで一度だけ消費し、メンバーを追加する
 * - onSharedItemWritten：共有項目の追加・重要な変更を見つけ、操作した本人を除くメンバーへ通知する
 *   使えなくなった FCM トークンは送信結果から削除する
 *
 * 招待の2つ（Callable）は App Check を必須にする（enforceAppCheck: true。2026-10-20 監査）。
 * 正規のくらしOSアプリが付ける App Check の情報が無い・正しくない呼び出しは、関数の中に入る前に
 * unauthenticated で断られる。App Check は「本物のアプリか」の確認で「誰か」の確認ではないため、
 * サインインの確認（requireUID）もこれまでどおり行う。onSharedItemWritten は Firestore の
 * トリガーでアプリから直接呼ばれないため、この設定の対象ではない（docs/FIRESTORE_SHARING_RULES_AUDIT.md）。
 *
 * 判定のロジックは src/ の小さな関数に分け、firebase なしで単体テストしている（test/unit）。
 * 個人項目はアプリが送らないため、ここには届かない（Security Rules も共有の種類だけを受け付ける）。
 */

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');

const { toMillis } = require('./src/timestamps');
const { decide, buildMessage } = require('./src/notificationPolicy');
const { shouldSend, collapseID } = require('./src/throttle');
const {
  INVITE_TTL_MS,
  generateToken,
  isValidTokenFormat,
  hashToken,
  buildInviteURL,
  validateInviteForAccept,
  sanitizeDisplayName,
} = require('./src/invites');
const { selectRecipients, devicesToRemove } = require('./src/recipients');

initializeApp();
// 日本の利用者向けに東京リージョン
setGlobalOptions({ region: 'asia-northeast1', maxInstances: 10 });

const db = getFirestore();

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function requireUID(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'サインインが必要です。');
  }
  return uid;
}

/** 招待リンクの土台の URL（Universal Link のドメイン）。未設定なら Firebase Hosting の既定のドメイン */
function inviteBaseURL() {
  if (process.env.INVITE_BASE_URL) return process.env.INVITE_BASE_URL;
  const projectID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
  return `https://${projectID}.web.app`;
}

// MARK: - 招待

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.createInvite = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  const groupID = request.data && request.data.groupID;
  if (typeof groupID !== 'string' || !ID_PATTERN.test(groupID)) {
    throw new HttpsError('invalid-argument', '生活グループの指定が正しくありません。');
  }

  const member = await db.doc(`groups/${groupID}/members/${uid}`).get();
  if (!member.exists) {
    throw new HttpsError('permission-denied', 'この生活グループのメンバーではありません。');
  }

  const token = generateToken();
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);
  // 生のトークンは保存しない（ハッシュだけ）
  await db.doc(`invites/${hashToken(token)}`).create({
    groupID,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    usedAt: null,
    usedBy: null,
  });

  return { token, url: buildInviteURL(inviteBaseURL(), token), expiresAt: expiresAt.toMillis() };
});

const ACCEPT_ERRORS = {
  'not-found': ['not-found', 'この招待は見つかりませんでした。'],
  expired: ['failed-precondition', 'この招待の期限（24時間）が切れています。もう一度招待してもらってください。'],
  'already-used': ['failed-precondition', 'この招待はすでに使われています。'],
  'own-invite': ['failed-precondition', '自分で作った招待は使えません。'],
  'already-member': ['already-exists', 'すでにこの生活グループのメンバーです。'],
};

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.acceptInvite = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  const token = request.data && request.data.token;
  if (!isValidTokenFormat(token)) {
    throw new HttpsError('invalid-argument', '招待のリンクが正しくありません。');
  }
  const displayName = sanitizeDisplayName(request.data && request.data.displayName);
  const inviteRef = db.doc(`invites/${hashToken(token)}`);

  const result = await db.runTransaction(async (transaction) => {
    const inviteSnap = await transaction.get(inviteRef);
    const invite = inviteSnap.exists ? inviteSnap.data() : null;
    let memberRef = null;
    let isAlreadyMember = false;
    if (invite && typeof invite.groupID === 'string') {
      memberRef = db.doc(`groups/${invite.groupID}/members/${uid}`);
      isAlreadyMember = (await transaction.get(memberRef)).exists;
    }

    const validation = validateInviteForAccept(invite, uid, Date.now(), { isAlreadyMember });
    if (!validation.ok) return validation;

    // 一度だけ：使用済みにしてからメンバーを追加する（同じトランザクションの中）
    transaction.update(inviteRef, { usedAt: FieldValue.serverTimestamp(), usedBy: uid });
    transaction.set(memberRef, { role: 'member', joinedAt: FieldValue.serverTimestamp(), displayName });
    transaction.update(db.doc(`groups/${invite.groupID}`), { updatedAt: FieldValue.serverTimestamp() });
    return { ok: true, groupID: invite.groupID };
  });

  if (!result.ok) {
    const [code, message] = ACCEPT_ERRORS[result.code] || ['failed-precondition', '招待を使えませんでした。'];
    throw new HttpsError(code, message, { reason: result.code });
  }
  return { groupID: result.groupID };
});

// MARK: - 共有更新の通知

/**
 * 送信の窓口。エミュレーターのテストでは、本物の FCM へ送らず Firestore に記録する
 * （FUNCTIONS_EMULATOR と LIFEOS_FAKE_MESSAGING の両方があるときだけ。本番では必ず本物）。
 */
function messenger() {
  const isEmulatorTest = process.env.FUNCTIONS_EMULATOR === 'true' && process.env.LIFEOS_FAKE_MESSAGING === '1';
  if (!isEmulatorTest) {
    return { sendEach: (messages) => getMessaging().sendEach(messages) };
  }
  return {
    async sendEach(messages) {
      const responses = [];
      for (const message of messages) {
        if (message.token.startsWith('invalid-')) {
          responses.push({ success: false, error: { code: 'messaging/registration-token-not-registered' } });
          continue;
        }
        await db.collection('_emulatorSentMessages').add({ ...message, sentAt: FieldValue.serverTimestamp() });
        responses.push({ success: true });
      }
      return { responses };
    },
  };
}

exports.onSharedItemWritten = onDocumentWritten('groups/{groupID}/items/{itemID}', async (event) => {
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const decision = decide(before, after, { notifyCompletion: false });
  if (!decision.notify) return;

  const { groupID, itemID } = event.params;

  // 30秒以内の同じ項目はまとめる（2回目以降は送らない）
  const logRef = db.doc(`groups/${groupID}/notificationLog/${itemID}`);
  const now = Date.now();
  const allowed = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(logRef);
    const last = snap.exists ? toMillis(snap.data().lastSentAt) : null;
    if (!shouldSend(last, now)) return false;
    transaction.set(logRef, { lastSentAt: Timestamp.fromMillis(now) });
    return true;
  });
  if (!allowed) return;

  const membersSnap = await db.collection(`groups/${groupID}/members`).get();
  const memberUIDs = membersSnap.docs.map((doc) => doc.id);
  // 操作した本人が今もメンバーでなければ送らない（退出後の書き込みはルールで拒否されるが念のため）
  if (!memberUIDs.includes(decision.actorUID)) return;

  const devicesByUID = {};
  await Promise.all(
    memberUIDs
      .filter((memberUID) => memberUID !== decision.actorUID)
      .map(async (memberUID) => {
        const devices = await db.collection(`users/${memberUID}/devices`).get();
        devicesByUID[memberUID] = devices.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      })
  );

  const recipients = selectRecipients({ memberUIDs, actorUID: decision.actorUID, devicesByUID });
  if (recipients.length === 0) return;

  const messages = recipients.map((recipient) => ({
    token: recipient.token,
    notification: buildMessage(decision.type, after.title, recipient.showsPreview),
    // 通知をタップしたとき、アプリが該当の項目を開くための情報（項目名は入れない）
    data: { groupID, itemID, type: decision.type },
    apns: {
      headers: { 'apns-collapse-id': collapseID(groupID, itemID) },
      payload: { aps: { sound: 'default', 'thread-id': groupID } },
    },
  }));

  const result = await messenger().sendEach(messages);
  const removals = devicesToRemove(recipients, result.responses);
  await Promise.all(removals.map((removal) => db.doc(`users/${removal.uid}/devices/${removal.deviceID}`).delete()));
});
