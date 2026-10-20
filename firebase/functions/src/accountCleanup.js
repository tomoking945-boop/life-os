'use strict';

const { toMillis } = require('./timestamps');

/**
 * アカウント削除のあとの整理（docs/FIREBASE_ACCOUNT_DELETION_CLEANUP.md）：生活グループごとに何をするかを決める。
 * firebase-admin に依存しない（単体テストでそのまま確かめる）。
 *
 * | 削除された人 | ほかのメンバー | すること |
 * | --- | --- | --- |
 * | member | いる | 本人のメンバー情報だけ消す（removeMember） |
 * | owner | いる（owner はいない） | 参加がいちばん古い人を owner にして、本人を消す（transferOwnership） |
 * | owner | いる（ほかにも owner がいる） | 本人だけ消す（removeMember） |
 * | どちらでも | いない | グループを丸ごと消す（deleteGroup）。誰も読めないグループを残さない |
 * | もう消えている | いる | 何もしない（nothing）。前回の実行で済んでいる |
 * | もう消えている | いない | グループを丸ごと消す（前回、途中で止まったときの続き） |
 */

const GroupAction = Object.freeze({
  nothing: 'nothing',
  removeMember: 'removeMember',
  transferOwnership: 'transferOwnership',
  deleteGroup: 'deleteGroup',
});

const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/** UID の文字順（コードの並び。言語の設定に左右されず、毎回同じ結果になる） */
function compareUID(a, b) {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

/**
 * 次の owner を選ぶ：参加（joinedAt）がいちばん古い人。同じ時刻なら UID の文字順で先の人。
 * 参加の時刻が無い人は最後に回す。
 * @param {{uid: string, joinedAt?: unknown}[]} candidates
 * @returns {string|null}
 */
function chooseSuccessor(candidates) {
  const list = (candidates || [])
    .filter((member) => member && typeof member.uid === 'string' && member.uid.length > 0)
    .map((member) => ({ uid: member.uid, joined: toMillis(member.joinedAt) }));
  if (list.length === 0) return null;
  list.sort((a, b) => {
    const aMissing = a.joined === null;
    const bMissing = b.joined === null;
    if (aMissing !== bMissing) return aMissing ? 1 : -1;
    if (!aMissing && a.joined !== b.joined) return a.joined - b.joined;
    return compareUID(a.uid, b.uid);
  });
  return list[0].uid;
}

/**
 * 1つの生活グループで何をするかを決める（入力は変えない）
 * @param {string} deletedUID 削除された利用者
 * @param {{uid: string, role?: string, joinedAt?: unknown}[]} members いまのメンバー（uid はメンバー文書の ID）
 * @returns {{action: string, newOwnerUID?: string}}
 */
function planGroupCleanup(deletedUID, members) {
  const list = Array.isArray(members) ? members.filter((member) => member && typeof member.uid === 'string') : [];
  const self = list.find((member) => member.uid === deletedUID);
  const others = list.filter((member) => member.uid !== deletedUID);

  if (others.length === 0) return { action: GroupAction.deleteGroup };
  if (!self) return { action: GroupAction.nothing };

  const anotherOwner = others.some((member) => member.role === 'owner');
  if (self.role === 'owner' && !anotherOwner) {
    return { action: GroupAction.transferOwnership, newOwnerUID: chooseSuccessor(others) };
  }
  return { action: GroupAction.removeMember };
}

/** 整理する生活グループの ID をまとめる（重複を除き、並びをそろえる。おかしな ID は使わない） */
function mergeGroupIDs(...lists) {
  const ids = new Set();
  for (const list of lists) {
    if (!Array.isArray(list)) continue;
    for (const id of list) {
      if (typeof id === 'string' && ID_PATTERN.test(id)) ids.add(id);
    }
  }
  return Array.from(ids).sort(compareUID);
}

/** 削除イベントの UID が使えるか（Firestore のパスに入れるため） */
function isValidUID(uid) {
  return typeof uid === 'string' && ID_PATTERN.test(uid);
}

/** ログに出してよい集計（件数だけ。名前・メール・トークン・生活の内容は入れない） */
function emptySummary() {
  return {
    groups: 0,
    removedMemberships: 0,
    transferredOwnerships: 0,
    deletedGroups: 0,
    clearedAssignees: 0,
    deletedInvites: 0,
  };
}

module.exports = {
  GroupAction,
  compareUID,
  chooseSuccessor,
  planGroupCleanup,
  mergeGroupIDs,
  isValidUID,
  emptySummary,
};
