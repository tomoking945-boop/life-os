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
  assert.deepEqual(buildMessage('eventAdded', '歯医者', false), { title: 'くらしOS', body: GENERIC_BODY });
  assert.equal(GENERIC_BODY, '共有情報が更新されました');
  assert.equal(buildMessage('eventAdded', '歯医者', true).body, '共有予定が追加されました：歯医者');
  assert.equal(buildMessage('taskAdded', '  ', true).body, '共有のやることが追加されました');
});

// MARK: - 共有 ToDo・買い物（2026-10-28 Build 7）の通知の監査。docs/SHARED_TODO_SHOPPING_FOUNDATION.md

const { selectRecipients } = require('../../src/recipients');
const { shouldSend } = require('../../src/throttle');

const sharedTodo = {
  schemaVersion: 1,
  title: '牛乳を買う',
  kind: 'shopping',
  date: new Date('2026-10-28T00:00:00+09:00'),
  hasTime: false,
  assigneeUID: null,
  isCompleted: false,
  createdBy: 'alice',
  updatedBy: 'alice',
};

test('Build 7：共有の ToDo・買い物の追加だけを知らせる。完了・名前の変更・削除は知らせない', () => {
  assert.equal(decide(null, sharedTodo).type, 'taskAdded');
  assert.equal(decide(null, { ...sharedTodo, kind: 'todo' }).type, 'taskAdded');
  assert.equal(decide(sharedTodo, { ...sharedTodo, isCompleted: true, updatedBy: 'bob' }).notify, false, '完了（初期値）');
  assert.equal(decide(sharedTodo, { ...sharedTodo, title: '低脂肪牛乳を買う', updatedBy: 'bob' }).notify, false, '名前の変更');
  assert.equal(decide(sharedTodo, null).notify, false, '削除');
  assert.equal(decide(null, null).notify, false);
});

test('Build 7：個人項目（Firestore に無い・決まっていない形）では通知の処理が動かない', () => {
  // 個人項目はアプリが送らない。万一、決まっていない種類や更新者の無い文書が来ても送らない
  assert.equal(decide(null, { ...sharedTodo, kind: 'payment' }).notify, false);
  assert.equal(decide(null, { ...sharedTodo, kind: 'habit' }).notify, false);
  assert.equal(decide(null, { ...sharedTodo, updatedBy: null }).notify, false);
  assert.equal(decide(null, { title: '個人のメモ' }).notify, false);
});

test('Build 7：操作した本人には送らない（本人のどの端末にも）。同じトークンは1回だけ', () => {
  const recipients = selectRecipients({
    memberUIDs: ['alice', 'bob'],
    actorUID: 'alice',
    devicesByUID: {
      alice: [{ id: 'a1', fcmToken: 'token-a', notificationsEnabled: true, sharedUpdatesEnabled: true }],
      bob: [
        { id: 'b1', fcmToken: 'token-b', notificationsEnabled: true, sharedUpdatesEnabled: true },
        { id: 'b2', fcmToken: 'token-b', notificationsEnabled: true, sharedUpdatesEnabled: true },
      ],
    },
  });
  assert.deepEqual(recipients.map((r) => r.uid), ['bob']);
  // アプリはまだ端末（FCM トークン）を登録しないので、宛先は0件になり、何も送られない
  assert.deepEqual(selectRecipients({ memberUIDs: ['alice', 'bob'], actorUID: 'alice', devicesByUID: {} }), []);
});

test('Build 7：同じ項目の通知は30秒以内に2回送らない。文面に項目名を出すのは、内容の表示を許可した端末だけ', () => {
  const now = Date.parse('2026-10-28T10:00:00Z');
  assert.equal(shouldSend(null, now), true);
  assert.equal(shouldSend(now - 5_000, now), false);
  const hidden = buildMessage('taskAdded', sharedTodo.title, false);
  assert.equal(hidden.body, GENERIC_BODY);
  assert.equal(JSON.stringify(hidden).includes('牛乳'), false);
  for (const secret of ['alice', 'bob', 'token', '@']) {
    assert.equal(JSON.stringify(buildMessage('taskAdded', sharedTodo.title, true)).includes(secret), false, secret);
  }
});
