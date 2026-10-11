'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { decide, buildMessage, GENERIC_BODY, SHARED_KINDS } = require('../../src/notificationPolicy');

const base = {
  title: '歯医者',
  kind: 'event',
  date: new Date('2026-10-12T10:30:00+09:00'),
  hasTime: true,
  assigneeUID: null,
  isCompleted: false,
  deferredTo: null,
  droppedAt: null,
  createdBy: 'alice',
  updatedBy: 'alice',
};

test('共有予定の追加は eventAdded', () => {
  assert.deepEqual(decide(null, base), { notify: true, type: 'eventAdded', actorUID: 'alice' });
});

test('共有の ToDo・家事・買い物の追加は taskAdded', () => {
  for (const kind of ['todo', 'chore', 'shopping']) {
    assert.equal(decide(null, { ...base, kind }).type, 'taskAdded', kind);
  }
});

test('共有予定の日時の変更は eventChanged（Timestamp 形式も比べられる）', () => {
  const after = { ...base, date: { seconds: base.date.getTime() / 1000 + 3600, nanoseconds: 0 }, updatedBy: 'bob' };
  assert.deepEqual(decide(base, after), { notify: true, type: 'eventChanged', actorUID: 'bob' });
  assert.equal(decide(base, { ...base, hasTime: false }).type, 'eventChanged');
  assert.equal(decide(base, { ...base, deferredTo: new Date('2026-10-13T00:00:00+09:00') }).type, 'eventChanged');
});

test('同じ日時（形式が違っても）なら通知しない', () => {
  const sameTime = { ...base, date: { seconds: base.date.getTime() / 1000, nanoseconds: 0 } };
  assert.equal(decide(base, sameTime).notify, false);
});

test('完了状態だけの変更は、初期値では通知しない', () => {
  const todo = { ...base, kind: 'todo' };
  assert.equal(decide(todo, { ...todo, isCompleted: true }).notify, false);
  assert.equal(decide(todo, { ...todo, isCompleted: true }, { notifyCompletion: true }).type, 'completionChanged');
});

test('タイトルだけの変更・削除・ToDo の日付変更は通知しない', () => {
  assert.equal(decide(base, { ...base, title: '歯医者（定期）' }).notify, false);
  assert.equal(decide(base, null).notify, false);
  const todo = { ...base, kind: 'todo' };
  assert.equal(decide(todo, { ...todo, date: new Date('2026-10-20T00:00:00+09:00') }).notify, false);
});

test('共有できない種類（支払予定・習慣など）や、操作した人が分からないものは通知しない', () => {
  assert.equal(decide(null, { ...base, kind: 'payment' }).notify, false);
  assert.equal(decide(null, { ...base, kind: 'habit' }).notify, false);
  assert.equal(decide(null, { ...base, updatedBy: undefined }).notify, false);
  assert.deepEqual(SHARED_KINDS, ['event', 'todo', 'chore', 'shopping']);
});

test('内容の表示を許可していなければ、項目名も種類も出さない', () => {
  assert.deepEqual(buildMessage('eventAdded', '歯医者', false), { title: '生活OS', body: GENERIC_BODY });
  assert.equal(GENERIC_BODY, '共有情報が更新されました');
  assert.equal(buildMessage('eventAdded', '歯医者', true).body, '共有予定が追加されました：歯医者');
  assert.equal(buildMessage('taskAdded', '  ', true).body, '共有のやることが追加されました');
});
