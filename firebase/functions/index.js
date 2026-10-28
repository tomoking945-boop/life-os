'use strict';

/**
 * 生活OS：パートナー共有・通知の Cloud Functions（docs/PARTNER_NOTIFICATIONS_IMPLEMENTATION.md 8）
 *
 * - createHousehold・getMyHousehold・createInvite・revokeInvite・getInvitePreview・acceptInvite：
 *   わが家の作成・招待・参加（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）。1人1つ・最大2人・招待はオーナーだけ・24時間・1回だけ
 * - onSharedItemWritten：共有項目の追加・重要な変更を見つけ、操作した本人を除くメンバーへ通知する
 *   使えなくなった FCM トークンは送信結果から削除する
 * - onAuthUserDeleted：Firebase Authentication の利用者が削除されたあと、その人の Firestore の情報を整理する
 *   （第1世代の安定版の削除トリガー。第2世代には利用者の削除イベントが無いため。docs/FIREBASE_ACCOUNT_DELETION_CLEANUP.md）
 *
 * Callable はすべて App Check を必須にする（enforceAppCheck: true。2026-10-20 監査、2026-10-22 わが家の Function を追加）。
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
const functionsV1 = require('firebase-functions/v1');
const logger = require('firebase-functions/logger');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');

const { toMillis } = require('./src/timestamps');
const { decide, buildMessage } = require('./src/notificationPolicy');
const { shouldSend, collapseID } = require('./src/throttle');
const householdStore = require('./src/householdStore');
const { HouseholdFailure } = householdStore;
const { selectRecipients, devicesToRemove } = require('./src/recipients');
const { cleanupDeletedUser } = require('./src/accountCleanupRunner');

initializeApp();
// 日本の利用者向けに東京リージョン（第2世代。第1世代の削除トリガーは下で個別に指定）
const REGION = 'asia-northeast1';
setGlobalOptions({ region: REGION, maxInstances: 10 });

const db = getFirestore();

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

// MARK: - わが家・招待（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
//
// すべて App Check 必須（enforceAppCheck: true）＋サインイン必須（requireUID）。
// 人数・1人1つ・招待の使用済み／取り消しは src/householdStore.js のトランザクションで守る。
// 招待トークン・UID はログに出さない。アプリへは決まった理由（details.reason）だけを返す。

/** 理由 → Callable のエラーの種類 */
const HOUSEHOLD_FAILURES = {
  'invalid-token': 'invalid-argument',
  'invalid-kinds': 'invalid-argument',
  'invalid-name': 'invalid-argument',
  'invalid-uid': 'invalid-argument',
  'not-found': 'not-found',
  expired: 'failed-precondition',
  'already-used': 'failed-precondition',
  revoked: 'failed-precondition',
  'own-invite': 'failed-precondition',
  'already-member': 'already-exists',
  'already-in-household': 'already-exists',
  'household-full': 'failed-precondition',
  'no-household': 'failed-precondition',
  'not-owner': 'permission-denied',
  'invalid-update': 'invalid-argument',
  'household-not-empty': 'failed-precondition',
  'owner-cannot-leave': 'failed-precondition',
};

/** 処理を実行し、決まった理由のエラーだけをアプリへ返す（中身の情報・UID・トークンは返さない・ログに出さない） */
async function runHousehold(name, handler) {
  try {
    return await handler();
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error instanceof HouseholdFailure && HOUSEHOLD_FAILURES[error.reason]) {
      throw new HttpsError(HOUSEHOLD_FAILURES[error.reason], 'わが家の操作ができませんでした。', { reason: error.reason });
    }
    const code = error && error.code !== undefined ? String(error.code) : 'unknown';
    logger.error('household function failed', { function: name, code });
    throw new HttpsError('internal', 'わが家の操作ができませんでした。', { reason: 'internal' });
  }
}

const data = (request) => (request.data && typeof request.data === 'object' ? request.data : {});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.createHousehold = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('createHousehold', async () => ({
    household: await householdStore.createHousehold({
      db, FieldValue, uid, name: data(request).name, sharedKinds: data(request).sharedKinds,
    }),
  }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.getMyHousehold = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('getMyHousehold', async () => ({
    household: await householdStore.getHouseholdSummary({ db, uid }),
  }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.createInvite = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('createInvite', () =>
    householdStore.createInvite({ db, FieldValue, Timestamp, uid, baseURL: inviteBaseURL() })
  );
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.revokeInvite = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('revokeInvite', () => householdStore.revokeInvites({ db, FieldValue, uid }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.getInvitePreview = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('getInvitePreview', async () => ({
    preview: await householdStore.getInvitePreview({ db, uid, token: data(request).token }),
  }));
});

// MARK: - わが家の設定・削除・退出（2026-10-28。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.updateHousehold = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('updateHousehold', async () => ({
    household: await householdStore.updateHousehold({
      db, FieldValue, uid, name: data(request).name, syncKinds: data(request).syncKinds,
    }),
  }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.deleteHousehold = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('deleteHousehold', () => householdStore.deleteHousehold({ db, FieldValue, uid }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.leaveHousehold = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('leaveHousehold', () => householdStore.leaveHousehold({ db, FieldValue, uid }));
});

// App Check 必須（正規のアプリから）＋サインイン必須（requireUID）
exports.acceptInvite = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireUID(request);
  return runHousehold('acceptInvite', async () => ({
    household: await householdStore.acceptInvite({ db, FieldValue, uid, token: data(request).token }),
  }));
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
    // 生活グループがもう無い（アカウント削除の整理などで消えた）ときは、通知の記録を作らない（孤立した記録を残さない）
    const groupSnap = await transaction.get(db.doc(`groups/${groupID}`));
    if (!groupSnap.exists) return false;
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

// MARK: - アカウント削除のあとの整理

/**
 * Firebase Authentication の利用者が削除されたら、その人の Firestore の情報をサーバーで整理する（非同期）。
 * - 失敗したら自動でやり直す（failurePolicy）。整理は何度実行しても同じ結果になる
 * - ログに出すのは UID と件数だけ。メールアドレス・Apple の情報・端末トークン・生活の内容は出さない
 */
exports.onAuthUserDeleted = functionsV1
  .region(REGION)
  .runWith({ failurePolicy: true, maxInstances: 10 })
  .auth.user()
  .onDelete(async (user) => {
    const uid = user && user.uid;
    try {
      const summary = await cleanupDeletedUser({ db, FieldValue, uid });
      logger.info('account cleanup finished', { uid, ...summary });
    } catch (error) {
      const code = error && error.code !== undefined ? String(error.code) : 'unknown';
      logger.error('account cleanup failed', { uid, code });
      // 失敗を握りつぶさず、やり直してもらう。元のエラーの文面（パスなど）はログに出さない
      throw new Error(`account cleanup failed (${code})`);
    }
  });
