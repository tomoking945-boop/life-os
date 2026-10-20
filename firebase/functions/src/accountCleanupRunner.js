'use strict';

const { GroupAction, planGroupCleanup, mergeGroupIDs, isValidUID, emptySummary } = require('./accountCleanup');

/**
 * アカウント削除のあとの Firestore の整理を実行する（docs/FIREBASE_ACCOUNT_DELETION_CLEANUP.md）。
 * index.js の削除トリガーと、Emulator のテストから呼ぶ（db は firebase-admin の Firestore）。
 *
 * 順番：
 *   1. 所属している生活グループを探す（メンバー文書の uid で collection group 検索。全グループの総当たりはしない）
 *   2. 作業の記録 accountDeletions/{uid} に、整理するグループの ID を残す（途中で止まっても、次の実行で続きができる）
 *   3. グループごとに、トランザクションで「本人を外す」「owner を引き継ぐ」を行う。誰も残らないグループは丸ごと消す
 *   4. 削除された人が担当の共有項目は、担当を null にする（項目は消さない。作成者・更新者の記録は残す）
 *   5. 削除された人が作った・使った招待と、消したグループの招待を消す
 *   6. users/{uid} を、下の devices なども含めて丸ごと消す
 *   7. 作業の記録を消す
 *
 * Firestore の削除は全体をまとめて一度に行えない（原子的でない）ため、どこで止まっても、
 * もう一度実行すれば同じ結果になるように作っている（同じイベントが2回届いても壊れない）。
 */

const PAGE_SIZE = 300;

function groupIDOfMember(doc) {
  const group = doc.ref.parent.parent;
  if (!group || !group.parent || group.parent.id !== 'groups') return null;
  return group.id;
}

function isSharedItem(doc) {
  const group = doc.ref.parent.parent;
  return Boolean(group && group.parent && group.parent.id === 'groups');
}

/** 所属している生活グループ（メンバー文書の ID と uid の両方が本人のものだけ） */
async function findMemberships(db, uid) {
  const snap = await db.collectionGroup('members').where('uid', '==', uid).get();
  return snap.docs.filter((doc) => doc.id === uid).map(groupIDOfMember).filter(Boolean);
}

/** 1つの生活グループを整理する */
async function cleanupGroup(db, FieldValue, groupID, uid) {
  const groupRef = db.doc(`groups/${groupID}`);
  const membersRef = groupRef.collection('members');

  const plan = await db.runTransaction(async (transaction) => {
    const groupSnap = await transaction.get(groupRef);
    const membersSnap = await transaction.get(membersRef);
    const members = membersSnap.docs.map((doc) => ({ uid: doc.id, role: doc.get('role'), joinedAt: doc.get('joinedAt') }));
    const decided = planGroupCleanup(uid, members);

    if (decided.action === GroupAction.removeMember) {
      transaction.delete(membersRef.doc(uid));
    } else if (decided.action === GroupAction.transferOwnership) {
      // 新しい owner への変更と本人の削除を、同じトランザクションで行う（どちらか片方だけにはならない）
      transaction.update(membersRef.doc(decided.newOwnerUID), { role: 'owner' });
      transaction.delete(membersRef.doc(uid));
      // createdBy は作成の記録なので変えない。updatedAt だけサーバーの時刻にする
      if (groupSnap.exists) transaction.update(groupRef, { updatedAt: FieldValue.serverTimestamp() });
    }
    return decided;
  });

  if (plan.action === GroupAction.deleteGroup) {
    // items・members・notificationLog など、下のコレクションをすべて含めて消す（グループの文書が無くても下を消す）
    await db.recursiveDelete(groupRef);
  }
  return plan;
}

/** 削除された人が担当の共有項目の担当を null にする（どの生活グループでも。退出したグループに残った分も） */
async function clearAssignee(db, FieldValue, uid) {
  let total = 0;
  for (;;) {
    const snap = await db.collectionGroup('items').where('assigneeUID', '==', uid).limit(PAGE_SIZE).get();
    const targets = snap.docs.filter(isSharedItem);
    if (targets.length === 0) return total;
    const batch = db.batch();
    for (const doc of targets) {
      batch.update(doc.ref, { assigneeUID: null, updatedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
    total += targets.length;
    if (targets.length < snap.size) return total; // 共有項目でないもの（ルール上は無い）だけが残ったら終える
  }
}

/** 招待を消す（本人が作った・使ったもの、消した生活グループのもの） */
async function deleteInvites(db, uid, deletedGroupIDs) {
  const queries = [
    db.collection('invites').where('createdBy', '==', uid),
    db.collection('invites').where('usedBy', '==', uid),
    ...deletedGroupIDs.map((groupID) => db.collection('invites').where('groupID', '==', groupID)),
  ];
  let total = 0;
  for (const query of queries) {
    for (;;) {
      const snap = await query.limit(PAGE_SIZE).get();
      if (snap.empty) break;
      const batch = db.batch();
      for (const doc of snap.docs) batch.delete(doc.ref);
      await batch.commit();
      total += snap.size;
    }
  }
  return total;
}

/**
 * @param {{db: FirebaseFirestore.Firestore, FieldValue: typeof FirebaseFirestore.FieldValue, uid: string}} params
 * @returns {Promise<object>} 件数だけの集計（ログ用）
 */
async function cleanupDeletedUser({ db, FieldValue, uid }) {
  if (!isValidUID(uid)) throw new Error('invalid-uid');
  const summary = emptySummary();
  const jobRef = db.doc(`accountDeletions/${uid}`);

  // 1・2：整理するグループ（今回見つけた分 ＋ 前回の実行で記録した分）
  const found = await findMemberships(db, uid);
  const jobSnap = await jobRef.get();
  const recorded = jobSnap.exists ? jobSnap.get('groupIDs') : [];
  const groupIDs = mergeGroupIDs(recorded, found);
  await jobRef.set(
    {
      groupIDs,
      startedAt: jobSnap.exists && jobSnap.get('startedAt') ? jobSnap.get('startedAt') : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  summary.groups = groupIDs.length;

  // 3：グループごと
  const deletedGroupIDs = [];
  for (const groupID of groupIDs) {
    const plan = await cleanupGroup(db, FieldValue, groupID, uid);
    if (plan.action === GroupAction.removeMember) summary.removedMemberships += 1;
    if (plan.action === GroupAction.transferOwnership) summary.transferredOwnerships += 1;
    if (plan.action === GroupAction.deleteGroup) {
      summary.deletedGroups += 1;
      deletedGroupIDs.push(groupID);
    }
  }

  // 4・5
  summary.clearedAssignees = await clearAssignee(db, FieldValue, uid);
  summary.deletedInvites = await deleteInvites(db, uid, deletedGroupIDs);

  // 6：利用者の情報（devices など下のコレクションも）
  await db.recursiveDelete(db.doc(`users/${uid}`));

  // 7：すべて終わってから作業の記録を消す
  await jobRef.delete();
  return summary;
}

module.exports = { cleanupDeletedUser, findMemberships, cleanupGroup, clearAssignee, deleteInvites };
