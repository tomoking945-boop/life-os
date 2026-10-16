'use strict';

const { toMillis } = require('./timestamps');

/**
 * 共有項目の変更を相手に通知するかどうかを決める（仕様 6「通知ルール」）。
 *
 * | 操作                               | 通知                  |
 * | 共有の予定を追加                     | する（eventAdded）     |
 * | 共有予定の日時を変更                 | する（eventChanged）   |
 * | 共有 ToDo・家事・買い物を追加         | する（taskAdded）      |
 * | 完了状態だけを変更                   | 初期値はしない         |
 * | 削除・そのほかの変更                 | しない                 |
 *
 * 個人項目は Firestore に存在しない（アプリが送らず、Security Rules も種類を限っている）ので、ここには来ない。
 * 操作した本人を除くのは宛先の選別（recipients.js）で行う。
 */

/** 共有できる種類（仕様 1・6：予定・ToDo・家事・買い物）。アプリと Security Rules も同じ一覧を使う */
const SHARED_KINDS = Object.freeze(['event', 'todo', 'chore', 'shopping']);

const NotificationType = Object.freeze({
  eventAdded: 'eventAdded',
  eventChanged: 'eventChanged',
  taskAdded: 'taskAdded',
  completionChanged: 'completionChanged',
});

/** 内容を表示しないとき（初期値）のロック画面の文言（仕様 5） */
const GENERIC_BODY = '共有情報が更新されました';

/** 内容の表示を許可したときの文言（仕様 6 の文言例） */
const BODY_BY_TYPE = Object.freeze({
  eventAdded: '共有予定が追加されました',
  eventChanged: '共有予定が変更されました',
  taskAdded: '共有のやることが追加されました',
  completionChanged: '共有のやることが完了しました',
});

function sameMillis(a, b) {
  return toMillis(a) === toMillis(b);
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
  if (!SHARED_KINDS.includes(after.kind)) return none;
  const actorUID = typeof after.updatedBy === 'string' ? after.updatedBy : null;
  if (!actorUID) return none; // 誰の操作か分からないものは送らない

  const isEvent = after.kind === 'event';
  if (!before) {
    return { notify: true, type: isEvent ? NotificationType.eventAdded : NotificationType.taskAdded, actorUID };
  }

  if (isEvent) {
    const timingChanged =
      !sameMillis(before.date, after.date) ||
      Boolean(before.hasTime) !== Boolean(after.hasTime) ||
      !sameMillis(before.deferredTo, after.deferredTo);
    if (timingChanged) {
      return { notify: true, type: NotificationType.eventChanged, actorUID };
    }
  }

  const completionChanged = Boolean(before.isCompleted) !== Boolean(after.isCompleted);
  if (completionChanged && options.notifyCompletion === true) {
    return { notify: true, type: NotificationType.completionChanged, actorUID };
  }
  return none;
}

/**
 * 通知の文面。内容の表示を許可していない端末には、項目名も種類も出さない。
 * @param {string} type NotificationType
 * @param {string} itemTitle 項目名
 * @param {boolean} showsPreview 内容の表示を許可しているか
 */
function buildMessage(type, itemTitle, showsPreview) {
  if (!showsPreview) {
    return { title: 'くらしOS', body: GENERIC_BODY };
  }
  const base = BODY_BY_TYPE[type] || GENERIC_BODY;
  const title = typeof itemTitle === 'string' ? itemTitle.trim() : '';
  return { title: 'くらしOS', body: title ? `${base}：${title}` : base };
}

module.exports = { SHARED_KINDS, NotificationType, GENERIC_BODY, BODY_BY_TYPE, decide, buildMessage };
