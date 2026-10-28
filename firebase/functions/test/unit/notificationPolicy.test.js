'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  decide, buildMessage, GENERIC_BODY, SHARED_KINDS, NOTIFY_KINDS, MAX_TITLE_LENGTH,
} = require('../../src/notificationPolicy');

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

// 2026-10-28（Build 8）：通知するのは共有の ToDo・買い物の追加と名前の変更だけ。予定・家事は通知しない
// （予定・家事は Build 7 から新しく作れない。docs/SHARED_PUSH_NOTIFICATIONS.md）

const todoBase = { ...base, kind: 'todo', title: '書類を出す', hasTime: false };

test('Build 8：共有の ToDo・買い物の追加は taskAdded', () => {
  assert.deepEqual(decide(null, todoBase), { notify: true, type: 'taskAdded', actorUID: 'alice' });
  assert.equal(decide(null, { ...todoBase, kind: 'shopping' }).type, 'taskAdded');
});

test('Build 8：名前の変更は taskChanged（前後の空白・改行だけの違いは変更にしない）', () => {
  assert.deepEqual(decide(todoBase, { ...todoBase, title: '書類を出す（市役所）', updatedBy: 'bob' }), { notify: true, type: 'taskChanged', actorUID: 'bob' });
  assert.equal(decide(todoBase, { ...todoBase, title: ' 書類を出す\n' }).notify, false);
});

test('Build 8：予定・家事は、追加しても日時を変えても通知しない', () => {
  assert.equal(decide(null, base).notify, false);
  assert.equal(decide(null, { ...base, kind: 'chore' }).notify, false);
  const after = { ...base, date: { seconds: base.date.getTime() / 1000 + 3600, nanoseconds: 0 }, updatedBy: 'bob' };
  assert.equal(decide(base, after).notify, false);
});

test('完了状態だけの変更は、初期値では通知しない（未完了に戻すのも通知しない）', () => {
  assert.equal(decide(todoBase, { ...todoBase, isCompleted: true }).notify, false);
  assert.equal(decide(todoBase, { ...todoBase, isCompleted: true }, { notifyCompletion: true }).type, 'completionChanged');
  const done = { ...todoBase, isCompleted: true };
  assert.equal(decide(done, { ...done, isCompleted: false }, { notifyCompletion: true }).notify, false);
});

test('削除・日付の変更・あとで・もうやらない・担当の解除は通知しない', () => {
  assert.equal(decide(todoBase, null).notify, false);
  assert.equal(decide(todoBase, { ...todoBase, date: new Date('2026-10-20T00:00:00+09:00') }).notify, false);
  assert.equal(decide(todoBase, { ...todoBase, deferredTo: new Date('2026-10-13T00:00:00+09:00') }).notify, false);
  assert.equal(decide(todoBase, { ...todoBase, droppedAt: new Date('2026-10-13T00:00:00+09:00') }).notify, false);
  assert.equal(decide({ ...todoBase, assigneeUID: 'bob' }, { ...todoBase, assigneeUID: null }).notify, false);
});

test('共有できない種類（支払予定・習慣など）や、操作した人が分からないものは通知しない', () => {
  assert.equal(decide(null, { ...todoBase, kind: 'payment' }).notify, false);
  assert.equal(decide(null, { ...todoBase, kind: 'habit' }).notify, false);
  assert.equal(decide(null, { ...todoBase, updatedBy: undefined }).notify, false);
  assert.equal(decide(null, { ...todoBase, updatedBy: '' }).notify, false);
  assert.deepEqual(SHARED_KINDS, ['event', 'todo', 'chore', 'shopping']);
  assert.deepEqual(NOTIFY_KINDS, ['todo', 'shopping']);
});

test('Build 8：内容の表示を許可していなければ、「わが家のToDoが更新されました」だけ（項目名を出さない）', () => {
  assert.deepEqual(buildMessage('taskAdded', { kind: 'todo', title: '書類を出す' }, false), { title: 'くらしOS', body: 'わが家のToDoが更新されました' });
  assert.equal(buildMessage('taskChanged', { kind: 'shopping', title: '洗剤を買う' }, false).body, 'わが家の買い物が更新されました');
  assert.equal(buildMessage('taskAdded', { kind: 'event', title: '歯医者' }, false).body, GENERIC_BODY);
  assert.equal(GENERIC_BODY, '共有情報が更新されました');
});

test('Build 8：内容の表示を許可した端末には、項目名だけ（40文字まで・改行なし）', () => {
  assert.equal(buildMessage('taskAdded', { kind: 'shopping', title: '洗剤を買う' }, true).body, '「洗剤を買う」が追加されました');
  assert.equal(buildMessage('taskChanged', { kind: 'todo', title: '書類\nを出す' }, true).body, '「書類 を出す」に変更されました');
  assert.equal(buildMessage('completionChanged', { kind: 'todo', title: '書類を出す' }, true).body, '「書類を出す」が完了しました');
  assert.equal(buildMessage('taskAdded', { kind: 'todo', title: '  ' }, true).body, 'わが家のToDoが更新されました', '名前が無ければ内容を出さない形');
  const long = buildMessage('taskAdded', { kind: 'todo', title: 'あ'.repeat(60) }, true).body;
  assert.equal(long, `「${'あ'.repeat(MAX_TITLE_LENGTH)}…」が追加されました`);
  // 名前以外（日付・作成者・担当など）は文面に入れない
  const message = buildMessage('taskAdded', { ...todoBase, createdBy: 'alice-uid', assigneeUID: 'bob-uid' }, true);
  assert.equal(JSON.stringify(message).includes('uid'), false);
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

test('Build 7（Build 8 で名前の変更も知らせるように変更）：完了・削除は知らせない', () => {
  assert.equal(decide(null, sharedTodo).type, 'taskAdded');
  assert.equal(decide(null, { ...sharedTodo, kind: 'todo' }).type, 'taskAdded');
  assert.equal(decide(sharedTodo, { ...sharedTodo, isCompleted: true, updatedBy: 'bob' }).notify, false, '完了（初期値）');
  assert.equal(decide(sharedTodo, { ...sharedTodo, title: '低脂肪牛乳を買う', updatedBy: 'bob' }).type, 'taskChanged', '名前の変更（Build 8）');
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
  const hidden = buildMessage('taskAdded', sharedTodo, false);
  assert.equal(hidden.body, 'わが家の買い物が更新されました');
  assert.equal(JSON.stringify(hidden).includes('牛乳'), false);
  for (const secret of ['alice', 'bob', 'token', '@']) {
    assert.equal(JSON.stringify(buildMessage('taskAdded', sharedTodo, true)).includes(secret), false, secret);
  }
});
