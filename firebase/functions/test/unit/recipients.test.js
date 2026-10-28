'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { selectRecipients, devicesToRemove } = require('../../src/recipients');

const device = (id, token, overrides = {}) => ({
  id, fcmToken: token, notificationsEnabled: true, sharedUpdatesEnabled: true, showsPreview: false, ...overrides,
});

test('操作した本人のすべての端末は除く（同じ人の別の iPhone にも送らない）', () => {
  const recipients = selectRecipients({
    memberUIDs: ['alice', 'bob'],
    actorUID: 'alice',
    devicesByUID: {
      alice: [device('a1', 'ta1'), device('a2', 'ta2')],
      bob: [device('b1', 'tb1')],
    },
  });
  assert.deepEqual(recipients.map((r) => r.token), ['tb1']);
});

test('通知 OFF・「共有の更新」OFF・トークン無しの端末には送らない', () => {
  const recipients = selectRecipients({
    memberUIDs: ['alice', 'bob'],
    actorUID: 'alice',
    devicesByUID: {
      bob: [
        device('b1', 'tb1', { notificationsEnabled: false }),
        device('b2', 'tb2', { sharedUpdatesEnabled: false }),
        device('b3', ''),
        device('b4', 'tb4', { showsPreview: true }),
        device('b5', 'tb4'),
      ],
    },
  });
  assert.deepEqual(recipients, [{ uid: 'bob', deviceID: 'b4', token: 'tb4', showsPreview: true }]);
});

test('メンバーでない人の端末には送らない', () => {
  const recipients = selectRecipients({
    memberUIDs: ['alice'],
    actorUID: 'alice',
    devicesByUID: { mallory: [device('m1', 'tm1')] },
  });
  assert.deepEqual(recipients, []);
});

test('使えなくなったトークンだけを削除の対象にする', () => {
  const recipients = [
    { uid: 'bob', deviceID: 'b1' },
    { uid: 'bob', deviceID: 'b2' },
    { uid: 'carol', deviceID: 'c1' },
  ];
  const responses = [
    { success: true },
    { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    { success: false, error: { code: 'messaging/internal-error' } },
  ];
  assert.deepEqual(devicesToRemove(recipients, responses), [{ uid: 'bob', deviceID: 'b2' }]);
});

test('Build 8：本人の端末と同じトークンは、相手の端末として登録されていても送らない', () => {
  const recipients = selectRecipients({
    memberUIDs: ['alice', 'bob'],
    actorUID: 'alice',
    devicesByUID: {
      alice: [device('a1', 'shared-phone-token')],
      bob: [device('b1', 'shared-phone-token'), device('b2', 'tb2')],
    },
  });
  assert.deepEqual(recipients.map((r) => r.token), ['tb2']);
});
