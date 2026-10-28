'use strict';

/**
 * 「わが家」の作成・招待・参加を Firestore に対して行う（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）。
 * index.js の Callable Function と、Emulator のテストから呼ぶ（db は firebase-admin の Firestore）。
 *
 * データ：
 *   groups/{groupID}                 { name, createdBy, createdAt, updatedAt, sharedKinds }
 *   groups/{groupID}/members/{uid}   { uid, role: 'owner' | 'member', joinedAt, displayName }
 *   memberships/{uid}                { groupID, joinedAt }  ← 1人1つのわが家を見分ける（サーバーだけが読み書き）
 *   invites/{tokenHash}              { groupID, createdBy, createdAt, expiresAt, usedAt, usedBy, revokedAt }
 *
 * 人数・1人1つ・招待の使用済み／取り消しは、Security Rules ではなく、ここのトランザクションで守る。
 * 招待トークンそのものは保存しない（SHA-256 のハッシュを文書 ID にする）。ログも出さない（この中ではログを出さない）。
 */

const {
  INVITE_TTL_MS,
  generateToken,
  isValidTokenFormat,
  hashToken,
  buildInviteURL,
  validateInviteForAccept,
  isActiveInvite,
  isRevocableInvite,
  sanitizeDisplayName,
} = require('./invites');
const {
  MAX_MEMBERS,
  HouseholdError,
  validateSharedKinds,
  validateGroupName,
  planSharedKindsUpdate,
  buildHouseholdSummary,
  buildInvitePreview,
  pickActiveInvite,
} = require('./household');

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/** アプリに理由を伝えるエラー（reason は決まった英語の値。中身の情報は入れない） */
class HouseholdFailure extends Error {
  constructor(reason) {
    super(reason);
    this.name = 'HouseholdFailure';
    this.reason = reason;
  }
}

/** トランザクションの外で読むときの窓口（トランザクションと同じ get だけを使う） */
function directReader() {
  return { get: (refOrQuery) => refOrQuery.get() };
}

function requireValidUID(uid) {
  if (typeof uid !== 'string' || !ID_PATTERN.test(uid)) throw new HouseholdFailure('invalid-uid');
}

/**
 * いま参加しているわが家（無ければ null）。
 * memberships/{uid} を見て、念のため members の uid でも探す（memberships が無い古いデータ・途中の状態にも対応）。
 * グループの文書と本人のメンバー文書の両方が在るものだけを「参加中」とする（退出・削除のあとの古い記録は無視）
 * @param {{get: Function}} reader トランザクション、または directReader()
 */
async function findCurrentHousehold(reader, db, uid) {
  const candidates = [];
  const membership = await reader.get(db.doc(`memberships/${uid}`));
  if (membership.exists && typeof membership.get('groupID') === 'string') candidates.push(membership.get('groupID'));
  const found = await reader.get(db.collectionGroup('members').where('uid', '==', uid).limit(5));
  for (const doc of found.docs) {
    const group = doc.ref.parent.parent;
    if (doc.id === uid && group && group.parent && group.parent.id === 'groups') candidates.push(group.id);
  }
  for (const groupID of [...new Set(candidates)]) {
    if (!ID_PATTERN.test(groupID)) continue;
    const groupSnap = await reader.get(db.doc(`groups/${groupID}`));
    const memberSnap = await reader.get(db.doc(`groups/${groupID}/members/${uid}`));
    if (groupSnap.exists && memberSnap.exists) {
      return { groupID, role: memberSnap.get('role') === 'owner' ? 'owner' : 'member', group: groupSnap.data() };
    }
  }
  return null;
}

function membersOf(snap) {
  return snap.docs.map((doc) => ({ uid: doc.id, role: doc.get('role'), joinedAt: doc.get('joinedAt') }));
}

/** 見ている人のわが家の情報（無ければ null）。UID は返さない */
async function getHouseholdSummary({ db, uid, nowMs = Date.now() }) {
  requireValidUID(uid);
  const current = await findCurrentHousehold(directReader(), db, uid);
  if (!current) return null;
  const members = membersOf(await db.collection(`groups/${current.groupID}/members`).get());
  let activeInvite = null;
  if (current.role === 'owner') {
    const invites = await db.collection('invites').where('groupID', '==', current.groupID).get();
    activeInvite = pickActiveInvite(invites.docs.map((doc) => doc.data()), nowMs, isActiveInvite);
  }
  return buildHouseholdSummary(current.group, members, uid, activeInvite, current.groupID);
}

/** わが家を作る（グループ・オーナーのメンバー・memberships をまとめて一度に作る） */
async function createHousehold({ db, FieldValue, uid, name, sharedKinds, nowMs = Date.now() }) {
  requireValidUID(uid);
  const checkedName = validateGroupName(name);
  if (!checkedName.ok) throw new HouseholdFailure(checkedName.code);
  const checkedKinds = validateSharedKinds(sharedKinds);
  if (!checkedKinds.ok) throw new HouseholdFailure(checkedKinds.code);

  const groupRef = db.collection('groups').doc();
  await db.runTransaction(async (transaction) => {
    // 1人1つ：同じ人の作成が同時に2回届いても、memberships/{uid} を読んでから書くので、どちらか1つだけになる
    const current = await findCurrentHousehold(transaction, db, uid);
    if (current) throw new HouseholdFailure(HouseholdError.alreadyInHousehold);
    const now = FieldValue.serverTimestamp();
    transaction.create(groupRef, {
      name: checkedName.name,
      createdBy: uid,
      createdAt: now,
      updatedAt: now,
      sharedKinds: checkedKinds.kinds,
    });
    transaction.create(groupRef.collection('members').doc(uid), {
      uid,
      role: 'owner',
      joinedAt: now,
      displayName: sanitizeDisplayName(undefined),
    });
    transaction.set(db.doc(`memberships/${uid}`), { groupID: groupRef.id, joinedAt: now });
  });
  return getHouseholdSummary({ db, uid, nowMs });
}

/** オーナーのわが家（オーナーでなければエラー） */
async function requireOwnedHousehold(reader, db, uid) {
  const current = await findCurrentHousehold(reader, db, uid);
  if (!current) throw new HouseholdFailure(HouseholdError.noHousehold);
  if (current.role !== 'owner') throw new HouseholdFailure(HouseholdError.notOwner);
  return current;
}

/**
 * 招待を作る（オーナーだけ・2人未満のときだけ）。前の未使用の招待は取り消す。24時間・1回だけ
 * @returns {{url: string, expiresAt: number}} 招待のリンク（トークンはリンクの中だけ。保存はハッシュだけ）
 */
async function createInvite({ db, FieldValue, Timestamp, uid, baseURL, nowMs = Date.now() }) {
  requireValidUID(uid);
  const token = generateToken();
  const inviteRef = db.doc(`invites/${hashToken(token)}`);
  const expiresAt = Timestamp.fromMillis(nowMs + INVITE_TTL_MS);

  await db.runTransaction(async (transaction) => {
    const current = await requireOwnedHousehold(transaction, db, uid);
    const members = await transaction.get(db.collection(`groups/${current.groupID}/members`));
    if (members.size >= MAX_MEMBERS) throw new HouseholdFailure(HouseholdError.householdFull);
    const invites = await transaction.get(db.collection('invites').where('groupID', '==', current.groupID));
    const now = FieldValue.serverTimestamp();
    for (const doc of invites.docs) {
      if (isRevocableInvite(doc.data())) transaction.update(doc.ref, { revokedAt: now });
    }
    transaction.create(inviteRef, {
      groupID: current.groupID,
      createdBy: uid,
      createdAt: now,
      expiresAt,
      usedAt: null,
      usedBy: null,
      revokedAt: null,
    });
  });
  return { url: buildInviteURL(baseURL, token), expiresAt: expiresAt.toMillis() };
}

/** 未使用の招待を取り消す（オーナーだけ） */
async function revokeInvites({ db, FieldValue, uid }) {
  requireValidUID(uid);
  return db.runTransaction(async (transaction) => {
    const current = await requireOwnedHousehold(transaction, db, uid);
    const invites = await transaction.get(db.collection('invites').where('groupID', '==', current.groupID));
    let revoked = 0;
    for (const doc of invites.docs) {
      if (isRevocableInvite(doc.data())) {
        transaction.update(doc.ref, { revokedAt: FieldValue.serverTimestamp() });
        revoked += 1;
      }
    }
    return { revoked };
  });
}

/** 招待の状態を読む（参加の前の確認・参加の両方で同じ確かめ方をする） */
async function readInviteState(reader, db, uid, inviteRef) {
  const inviteSnap = await reader.get(inviteRef);
  const invite = inviteSnap.exists ? inviteSnap.data() : null;
  let groupSnap = null;
  let members = [];
  if (invite && typeof invite.groupID === 'string' && ID_PATTERN.test(invite.groupID)) {
    groupSnap = await reader.get(db.doc(`groups/${invite.groupID}`));
    members = membersOf(await reader.get(db.collection(`groups/${invite.groupID}/members`)));
  }
  const current = await findCurrentHousehold(reader, db, uid);
  const state = {
    groupExists: Boolean(groupSnap && groupSnap.exists),
    isAlreadyMember: members.some((member) => member.uid === uid),
    inOtherHousehold: Boolean(current && invite && current.groupID !== invite.groupID),
    memberCount: members.length,
    maxMembers: MAX_MEMBERS,
  };
  return { invite, groupSnap, state };
}

/** 参加の前に見せる内容（参加はしない・何も書かない）。グループ名・共有する種類・期限だけ */
async function getInvitePreview({ db, uid, token, nowMs = Date.now() }) {
  requireValidUID(uid);
  if (!isValidTokenFormat(token)) throw new HouseholdFailure('invalid-token');
  const { invite, groupSnap, state } = await readInviteState(directReader(), db, uid, db.doc(`invites/${hashToken(token)}`));
  const validation = validateInviteForAccept(invite, uid, nowMs, state);
  if (!validation.ok) throw new HouseholdFailure(validation.code);
  if (validation.alreadyJoined) throw new HouseholdFailure('already-member');
  return buildInvitePreview(groupSnap.data(), invite);
}

/**
 * 招待で参加する（トランザクションの中で、期限・未使用・取り消し・人数・自分の所属を確かめ直す）。
 * 同じ人の同じ参加が2回届いても、メンバーは1人だけ（2回目は何も書かずに成功）
 */
async function acceptInvite({ db, FieldValue, uid, token, nowMs = Date.now() }) {
  requireValidUID(uid);
  if (!isValidTokenFormat(token)) throw new HouseholdFailure('invalid-token');
  const inviteRef = db.doc(`invites/${hashToken(token)}`);

  await db.runTransaction(async (transaction) => {
    const { invite, state } = await readInviteState(transaction, db, uid, inviteRef);
    const validation = validateInviteForAccept(invite, uid, nowMs, state);
    if (!validation.ok) throw new HouseholdFailure(validation.code);
    if (validation.alreadyJoined) return;

    const now = FieldValue.serverTimestamp();
    // 使用済みにする・メンバーを追加する・memberships を作る・グループの更新日時を、まとめて一度に行う
    transaction.update(inviteRef, { usedAt: now, usedBy: uid });
    transaction.create(db.doc(`groups/${invite.groupID}/members/${uid}`), {
      uid,
      role: 'member',
      joinedAt: now,
      displayName: sanitizeDisplayName(undefined),
    });
    transaction.set(db.doc(`memberships/${uid}`), { groupID: invite.groupID, joinedAt: now });
    transaction.update(db.doc(`groups/${invite.groupID}`), { updatedAt: now });
  });
  return getHouseholdSummary({ db, uid, nowMs });
}

// MARK: - わが家の設定・削除・退出（2026-10-28。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）

const PAGE_SIZE = 300;

/** クエリに当たる文書を、少しずつ消す（何度実行しても同じ結果になる） */
async function deleteAllMatching(db, query) {
  let total = 0;
  for (;;) {
    const snap = await query.limit(PAGE_SIZE).get();
    if (snap.empty) return total;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    total += snap.size;
  }
}

/**
 * わが家の名前・共有する種類を変える（オーナー・パートナーのどちらも。トランザクションの中でメンバーかを確かめ直す）
 * - name：新しい名前（省略可）
 * - syncKinds：同期できる種類（ToDo・買い物）のうち、オンにするもの（省略可）。「今後対応」の種類は保存されたまま残す
 * - 種類をオフにしても、すでにある共有項目は消さない（新しく作れなくなるだけ。Security Rules で確かめる）
 */
async function updateHousehold({ db, FieldValue, uid, name, syncKinds, nowMs = Date.now() }) {
  requireValidUID(uid);
  if (name === undefined && syncKinds === undefined) throw new HouseholdFailure('invalid-update');
  let checkedName = null;
  if (name !== undefined) {
    const result = validateGroupName(name);
    if (!result.ok) throw new HouseholdFailure(result.code);
    checkedName = result.name;
  }
  await db.runTransaction(async (transaction) => {
    const current = await findCurrentHousehold(transaction, db, uid);
    if (!current) throw new HouseholdFailure(HouseholdError.noHousehold);
    const changes = { updatedAt: FieldValue.serverTimestamp() };
    if (checkedName !== null) changes.name = checkedName;
    if (syncKinds !== undefined) {
      const planned = planSharedKindsUpdate(current.group.sharedKinds, syncKinds);
      if (!planned.ok) throw new HouseholdFailure(planned.code);
      changes.sharedKinds = planned.kinds;
    }
    transaction.update(db.doc(`groups/${current.groupID}`), changes);
  });
  return getHouseholdSummary({ db, uid, nowMs });
}

/** わが家の文書と、その下（items・members・notificationLog など）・招待・memberships をすべて消す（何度実行しても同じ結果） */
async function finishHouseholdDeletion(db, groupID) {
  await db.recursiveDelete(db.doc(`groups/${groupID}`));
  await deleteAllMatching(db, db.collection('invites').where('groupID', '==', groupID));
  // memberships は最後に消す（途中で止まっても、次の実行で「途中まで消したわが家」を見つけられるように）
  await deleteAllMatching(db, db.collection('memberships').where('groupID', '==', groupID));
}

/**
 * わが家を削除する（オーナーだけ・メンバーが自分1人のときだけ）。
 * Firebase Authentication のアカウントと、端末の中のデータは消さない。
 * 1. トランザクションの中で、オーナーであること・1人であることを確かめ、未使用の招待をすべて取り消す（同時に参加されないように）
 * 2. わが家の下の共有項目・メンバー・通知の記録、招待、memberships を消す
 * 途中で止まったときは、もう一度呼べば続きから消す（memberships が残っていて、わが家の文書が無いとき）
 */
async function deleteHousehold({ db, FieldValue, uid }) {
  requireValidUID(uid);
  const current = await findCurrentHousehold(directReader(), db, uid);
  if (!current) {
    // 前回、途中で止まった削除の続き：自分の memberships が、もう無いわが家を指している
    const membership = await db.doc(`memberships/${uid}`).get();
    const groupID = membership.exists ? membership.get('groupID') : null;
    if (typeof groupID === 'string' && ID_PATTERN.test(groupID) && !(await db.doc(`groups/${groupID}`).get()).exists) {
      await finishHouseholdDeletion(db, groupID);
      await db.doc(`memberships/${uid}`).delete();
      return { deleted: true };
    }
    throw new HouseholdFailure(HouseholdError.noHousehold);
  }

  const groupID = await db.runTransaction(async (transaction) => {
    const now = await findCurrentHousehold(transaction, db, uid);
    if (!now) throw new HouseholdFailure(HouseholdError.noHousehold);
    if (now.role !== 'owner') throw new HouseholdFailure(HouseholdError.notOwner);
    const members = await transaction.get(db.collection(`groups/${now.groupID}/members`));
    if (members.size !== 1 || members.docs[0].id !== uid) throw new HouseholdFailure(HouseholdError.householdNotEmpty);
    const invites = await transaction.get(db.collection('invites').where('groupID', '==', now.groupID));
    for (const doc of invites.docs) {
      if (isRevocableInvite(doc.data())) transaction.update(doc.ref, { revokedAt: FieldValue.serverTimestamp() });
    }
    return now.groupID;
  });

  await finishHouseholdDeletion(db, groupID);
  await db.doc(`memberships/${uid}`).delete();
  return { deleted: true };
}

/**
 * わが家から退出する（パートナーだけ。オーナーは2人いるあいだ退出できない。所有権の移し替えは次の段階）。
 * 自分のメンバー文書と memberships を消す。わが家・オーナー・共有項目は残す。
 * 自分が担当になっている共有項目は、担当を null にする（Security Rules の「担当はメンバーだけ」で更新できなくならないように）
 */
async function leaveHousehold({ db, FieldValue, uid }) {
  requireValidUID(uid);
  const groupID = await db.runTransaction(async (transaction) => {
    const current = await findCurrentHousehold(transaction, db, uid);
    if (!current) throw new HouseholdFailure(HouseholdError.noHousehold);
    if (current.role === 'owner') throw new HouseholdFailure(HouseholdError.ownerCannotLeave);
    transaction.delete(db.doc(`groups/${current.groupID}/members/${uid}`));
    transaction.delete(db.doc(`memberships/${uid}`));
    transaction.update(db.doc(`groups/${current.groupID}`), { updatedAt: FieldValue.serverTimestamp() });
    return current.groupID;
  });

  for (;;) {
    const snap = await db.collection(`groups/${groupID}/items`).where('assigneeUID', '==', uid).limit(PAGE_SIZE).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.update(doc.ref, { assigneeUID: null, updatedAt: FieldValue.serverTimestamp() });
    await batch.commit();
  }
  return { left: true };
}

module.exports = {
  HouseholdFailure,
  updateHousehold,
  deleteHousehold,
  leaveHousehold,
  findCurrentHousehold,
  getHouseholdSummary,
  createHousehold,
  createInvite,
  revokeInvites,
  getInvitePreview,
  acceptInvite,
};
