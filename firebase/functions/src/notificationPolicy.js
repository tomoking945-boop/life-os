'use strict';

/**
 * 共有項目の変更を相手に通知するかどうかを決める（2026-10-28 Build 8。docs/SHARED_PUSH_NOTIFICATIONS.md）。
 *
 * | 操作                                   | 通知                    |
 * | 共有の ToDo・買い物を追加               | する（taskAdded）        |
 * | 共有の ToDo・買い物の名前を変更         | する（taskChanged）      |
 * | 完了状態だけを変更                     | 初期値はしない           |
 * | 削除・あとで・もうやらない・そのほか     | しない                   |
 * | 予定・家事（Build 7 から新しく作れない） | しない                   |
 *
 * 個人項目は Firestore に存在しない（アプリが送らず、Security Rules も種類を限っている）ので、ここには来ない。
 * 操作した本人を除くのは宛先の選別（recipients.js）で行う。
 */

/** 共有できる種類（以前の仕様：予定・ToDo・家事・買い物）。Security Rules の項目の形と同じ一覧 */
const SHARED_KINDS = Object.freeze(['event', 'todo', 'chore', 'shopping']);

/** 通知する種類（Build 8：ToDo・買い物だけ） */
const NOTIFY_KINDS = Object.freeze(['todo', 'shopping']);

const NotificationType = Object.freeze({
  taskAdded: 'taskAdded',
  taskChanged: 'taskChanged',
  completionChanged: 'completionChanged',
});

/** 種類が分からないときの文言（内容を出さない） */
const GENERIC_BODY = '共有情報が更新されました';

/** 内容を出さないときの文言で使う種類の名前 */
const KIND_LABELS = Object.freeze({ todo: 'ToDo', shopping: '買い物' });

/** 内容を出すときの項目名の長さの上限（必要最小限） */
const MAX_TITLE_LENGTH = 40;

function titleText(value) {
  return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '';
}

/**
 * @param {object|null} before 変更前のドキュメント（追加なら null）
 * @param {object|null} after  変更後のドキュメント（削除なら null）
 * @param {{notifyCompletion?: boolean}} [options] 完了状態の変更も通知するか（初期値 false）
 * @returns {{notify: boolean, type: string|null, actorUID: string|null}}
 */
function decide(before, after, options = {}) {
  const none = { notify: false, type: null, actorUID: null };
  if (!after) return none; // 削除は通知しない
  if (!NOTIFY_KINDS.includes(after.kind)) return none;
  const actorUID = typeof after.updatedBy === 'string' && after.updatedBy ? after.updatedBy : null;
  if (!actorUID) return none; // 誰の操作か分からないものは送らない

  if (!before) {
    return { notify: true, type: NotificationType.taskAdded, actorUID };
  }
  // 名前・完了だけを見る（退出のときのサーバーの片付け＝担当の解除などは通知しない）
  if (titleText(before.title) !== titleText(after.title)) {
    return { notify: true, type: NotificationType.taskChanged, actorUID };
  }
  const completed = !before.isCompleted && Boolean(after.isCompleted);
  if (completed && options.notifyCompletion === true) {
    return { notify: true, type: NotificationType.completionChanged, actorUID };
  }
  return none;
}

/**
 * 通知の文面。
 * - 内容の表示を許可していない端末：「わが家のToDoが更新されました」だけ（項目名・金額・メモなどは出さない）
 * - 許可した端末：「「洗剤を買う」が追加されました」のように、項目名だけ（40文字まで）
 * @param {string} type NotificationType
 * @param {{kind?: string, title?: string}} item 変更後の項目（名前と種類だけを使う）
 * @param {boolean} showsPreview 内容の表示を許可しているか
 */
function buildMessage(type, item, showsPreview) {
  const label = item && KIND_LABELS[item.kind];
  const hidden = { title: 'くらしOS', body: label ? `わが家の${label}が更新されました` : GENERIC_BODY };
  if (!showsPreview) return hidden;
  let title = titleText(item && item.title);
  if (!title) return hidden;
  if (Array.from(title).length > MAX_TITLE_LENGTH) title = `${Array.from(title).slice(0, MAX_TITLE_LENGTH).join('')}…`;
  switch (type) {
    case NotificationType.taskAdded: return { title: 'くらしOS', body: `「${title}」が追加されました` };
    case NotificationType.taskChanged: return { title: 'くらしOS', body: `「${title}」に変更されました` };
    case NotificationType.completionChanged: return { title: 'くらしOS', body: `「${title}」が完了しました` };
    default: return hidden;
  }
}

module.exports = {
  SHARED_KINDS, NOTIFY_KINDS, NotificationType, GENERIC_BODY, KIND_LABELS, MAX_TITLE_LENGTH, decide, buildMessage,
};
