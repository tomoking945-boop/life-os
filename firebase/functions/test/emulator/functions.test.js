'use strict';

/**
 * Cloud Functions のテスト（仕様 11「Functions Emulator」）。
 * Auth・Firestore・Functions の Emulator が必要：firebase/functions で `npm run test:functions`
 *
 * - 招待：期限・一度きりの利用・メンバーでない人は発行できない・生のトークンを保存しない
 * - 通知：操作した本人を除く・通知 OFF の端末を除く・完了だけの変更は送らない・30秒以内はまとめる
 * - 無効なトークン：送信結果を受けて端末を削除する
 * - App Check（2026-10-20 監査）：App Check の情報が無い招待の呼び出しは、サインインしていても断られる。
 *   App Check だけではサインイン済みにならない
 *
 * App Check について：Functions Emulator は App Check の署名を確かめない（本番では Firebase が確かめる）。
 * そのため、ここでは「App Check の情報が付いているか」だけを試す。テスト用の偽の値は、本物のアプリの ID や
 * Debug Token とは関係ない、ここで作った値（本番では使えない）。
 *
 * 本物の FCM へは送らない（.env.demo-lifeos の LIFEOS_FAKE_MESSAGING=1 で、Firestore に記録する）。
 */

const crypto = require('node:crypto');
const { before, beforeEach, describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');

const PROJECT = 'demo-lifeos';
const REGION = 'asia-northeast1';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FUNCTIONS_HOST = '127.0.0.1:5001';
const GROUP = 'group-a';

initializeApp({ projectId: PROJECT });
const db = getFirestore();

/** Auth Emulator で利用者を作り、ID トークンと uid を受け取る */
async function signUp(name) {
  const response = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${name}-${crypto.randomUUID()}@example.com`, password: 'password', returnSecureToken: true }),
  });
  const body = await response.json();
  return { uid: body.localId, idToken: body.idToken };
}

/**
 * テスト用の偽の App Check の値（JWT の形だけ。署名なし）。
 * Emulator は署名を確かめないので通るが、本番の Firebase では必ず断られる
 */
const base64url = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const FAKE_APP_CHECK_TOKEN = [
  base64url({ alg: 'none', typ: 'JWT' }),
  base64url({ sub: '1:000000000000:ios:emulatoronly', aud: [`projects/${PROJECT}`], iss: 'emulator-test' }),
  'emulator-test',
].join('.');

/**
 * Callable Function を呼ぶ。正規のアプリと同じく、ふだんは App Check の情報を付ける
 * （`{ appCheck: false }` で付けない呼び出しを試す）
 */
async function call(name, data, idToken, { appCheck = true } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  if (appCheck) headers['X-Firebase-AppCheck'] = FAKE_APP_CHECK_TOKEN;
  const response = await fetch(`http://${FUNCTIONS_HOST}/${PROJECT}/${REGION}/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ data }),
  });
  return response.json();
}

async function waitFor(check, timeoutMs = 10000) {
  const start = Date.now();
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() - start > timeoutMs) return value;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function clearCollection(path) {
  const snap = await db.collection(path).get();
  await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
}

async function sentMessages() {
  const snap = await db.collection('_emulatorSentMessages').get();
  return snap.docs.map((doc) => doc.data());
}

let alice;
let bob;
let carol;

before(async () => {
  alice = await signUp('alice');
  bob = await signUp('bob');
  carol = await signUp('carol');
});

beforeEach(async () => {
  for (const path of ['_emulatorSentMessages', 'invites', `groups/${GROUP}/items`, `groups/${GROUP}/members`, `groups/${GROUP}/notificationLog`]) {
    await clearCollection(path);
  }
  for (const user of [alice, bob, carol]) {
    await clearCollection(`users/${user.uid}/devices`);
  }
  const now = Timestamp.now();
  await db.doc(`groups/${GROUP}`).set({ name: 'わが家', createdBy: alice.uid, createdAt: now, updatedAt: now });
  await db.doc(`groups/${GROUP}/members/${alice.uid}`).set({ uid: alice.uid, role: 'owner', joinedAt: now, displayName: 'alice' });
});

describe('招待', () => {
  it('メンバーは招待を発行できる。保存されるのはハッシュだけ', async () => {
    const response = await call('createInvite', { groupID: GROUP }, alice.idToken);
    assert.ok(response.result, JSON.stringify(response));
    const { token, url, expiresAt } = response.result;
    assert.match(token, /^[A-Za-z0-9_-]{43}$/);
    assert.ok(url.endsWith(`/invite?token=${token}`));
    assert.ok(Math.abs(expiresAt - (Date.now() + 24 * 60 * 60 * 1000)) < 60 * 1000, '期限は24時間');

    const hash = crypto.createHash('sha256').update(token).digest('hex');
    const invite = await db.doc(`invites/${hash}`).get();
    assert.ok(invite.exists);
    assert.ok(!JSON.stringify(invite.data()).includes(token), '生のトークンは保存しない');
  });

  it('メンバーでない人・サインインしていない人は発行できない', async () => {
    assert.equal((await call('createInvite', { groupID: GROUP }, carol.idToken)).error.status, 'PERMISSION_DENIED');
    assert.equal((await call('createInvite', { groupID: GROUP })).error.status, 'UNAUTHENTICATED');
  });

  it('一度だけ使える：bob が参加したら、carol は同じ招待で参加できない', async () => {
    const { token } = (await call('createInvite', { groupID: GROUP }, alice.idToken)).result;
    const accepted = await call('acceptInvite', { token, displayName: 'bob' }, bob.idToken);
    assert.deepEqual(accepted.result, { groupID: GROUP });
    const member = await db.doc(`groups/${GROUP}/members/${bob.uid}`).get();
    assert.equal(member.data().role, 'member');
    // uid は参加した本人の UID（文書 ID と同じ。アカウント削除の整理で使う）
    assert.equal(member.data().uid, bob.uid);
    assert.equal(member.data().uid, member.id);

    const reused = await call('acceptInvite', { token, displayName: 'carol' }, carol.idToken);
    assert.equal(reused.error.details.reason, 'already-used');
    assert.equal((await db.doc(`groups/${GROUP}/members/${carol.uid}`).get()).exists, false);
  });

  it('期限が切れた招待・自分の招待・間違ったトークンは使えない', async () => {
    const token = crypto.randomBytes(32).toString('base64url');
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    await db.doc(`invites/${hash}`).set({
      groupID: GROUP, createdBy: alice.uid, createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() - 1000), usedAt: null, usedBy: null,
    });
    assert.equal((await call('acceptInvite', { token }, bob.idToken)).error.details.reason, 'expired');

    const own = (await call('createInvite', { groupID: GROUP }, alice.idToken)).result.token;
    assert.equal((await call('acceptInvite', { token: own }, alice.idToken)).error.details.reason, 'own-invite');

    assert.equal((await call('acceptInvite', { token: 'short' }, bob.idToken)).error.status, 'INVALID_ARGUMENT');
    const unknown = crypto.randomBytes(32).toString('base64url');
    assert.equal((await call('acceptInvite', { token: unknown }, bob.idToken)).error.status, 'NOT_FOUND');
  });
});

describe('招待の App Check（2026-10-20 監査）', () => {
  async function inviteCount() {
    return (await db.collection('invites').get()).size;
  }

  it('App Check の情報が無いと、サインインしていても招待を発行できない', async () => {
    const response = await call('createInvite', { groupID: GROUP }, alice.idToken, { appCheck: false });
    assert.equal(response.error && response.error.status, 'UNAUTHENTICATED', JSON.stringify(response));
    assert.equal(await inviteCount(), 0, '招待が作られていない');
  });

  it('App Check の情報が無いと、サインインしていても招待を使えない（招待は未使用のまま）', async () => {
    const { token } = (await call('createInvite', { groupID: GROUP }, alice.idToken)).result;
    const response = await call('acceptInvite', { token, displayName: 'bob' }, bob.idToken, { appCheck: false });
    assert.equal(response.error && response.error.status, 'UNAUTHENTICATED', JSON.stringify(response));
    assert.equal((await db.doc(`groups/${GROUP}/members/${bob.uid}`).get()).exists, false, 'メンバーに追加されていない');
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    assert.equal((await db.doc(`invites/${hash}`).get()).data().usedAt, null, '招待は使われていない');

    // 同じ招待も、App Check の情報を付ければ使える（断られたのは App Check が無かったため）
    assert.deepEqual((await call('acceptInvite', { token, displayName: 'bob' }, bob.idToken)).result, { groupID: GROUP });
  });

  it('App Check の情報だけでは、サインインしたことにならない', async () => {
    assert.equal((await call('createInvite', { groupID: GROUP })).error.status, 'UNAUTHENTICATED');
    assert.equal(await inviteCount(), 0);
    const { token } = (await call('createInvite', { groupID: GROUP }, alice.idToken)).result;
    assert.equal((await call('acceptInvite', { token, displayName: 'x' })).error.status, 'UNAUTHENTICATED');
  });

  it('App Check もサインインも無い呼び出しは断られる', async () => {
    assert.equal((await call('createInvite', { groupID: GROUP }, null, { appCheck: false })).error.status, 'UNAUTHENTICATED');
    assert.equal(await inviteCount(), 0);
  });
});

describe('共有更新の通知', () => {
  async function addMembersAndDevices() {
    const now = Timestamp.now();
    await db.doc(`groups/${GROUP}/members/${bob.uid}`).set({ uid: bob.uid, role: 'member', joinedAt: now, displayName: 'bob' });
    const device = (token, overrides = {}) => ({
      fcmToken: token, platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true,
      showsPreview: false, updatedAt: now, ...overrides,
    });
    await db.doc(`users/${alice.uid}/devices/a1`).set(device('token-alice-iphone'));
    await db.doc(`users/${alice.uid}/devices/a2`).set(device('token-alice-ipad'));
    await db.doc(`users/${bob.uid}/devices/b1`).set(device('token-bob'));
    await db.doc(`users/${bob.uid}/devices/b2`).set(device('token-bob-off', { sharedUpdatesEnabled: false }));
    await db.doc(`users/${bob.uid}/devices/b3`).set(device('invalid-old-token'));
    // メンバーでない carol の端末
    await db.doc(`users/${carol.uid}/devices/c1`).set(device('token-carol'));
  }

  function item(actorUID, overrides = {}) {
    return {
      title: '歯医者', kind: 'event', date: Timestamp.fromDate(new Date('2026-10-12T10:30:00+09:00')), hasTime: true,
      assigneeUID: null, isCompleted: false, deferredTo: null, droppedAt: null,
      createdBy: actorUID, updatedBy: actorUID, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      ...overrides,
    };
  }

  it('alice が共有予定を追加すると、bob の通知 ON の端末にだけ1回届く', async () => {
    await addMembersAndDevices();
    await db.doc(`groups/${GROUP}/items/item-1`).set(item(alice.uid));

    const messages = await waitFor(async () => {
      const list = await sentMessages();
      return list.length > 0 ? list : null;
    });
    assert.ok(messages, '通知が記録されない');
    await sleep(1500);
    const all = await sentMessages();
    assert.deepEqual(all.map((m) => m.token), ['token-bob'], '本人・通知 OFF・メンバー外には送らない');
    assert.equal(all[0].notification.body, '共有情報が更新されました', '内容の表示を許可していなければ項目名を出さない');
    assert.deepEqual(all[0].data, { groupID: GROUP, itemID: 'item-1', type: 'eventAdded' });
  });

  it('使えなくなったトークンの端末は削除される', async () => {
    await addMembersAndDevices();
    await db.doc(`groups/${GROUP}/items/item-2`).set(item(alice.uid));
    const removed = await waitFor(async () => !(await db.doc(`users/${bob.uid}/devices/b3`).get()).exists);
    assert.ok(removed, '無効なトークンの端末が残っている');
    assert.ok((await db.doc(`users/${bob.uid}/devices/b1`).get()).exists, '有効な端末は残す');
  });

  it('完了状態だけの変更では送らない', async () => {
    await addMembersAndDevices();
    const ref = db.doc(`groups/${GROUP}/items/item-3`);
    await ref.set(item(alice.uid, { kind: 'todo', hasTime: false, title: '牛乳を買う' }));
    await waitFor(async () => (await sentMessages()).length > 0);
    await clearCollection('_emulatorSentMessages');
    await db.doc(`groups/${GROUP}/notificationLog/item-3`).delete();

    await ref.update({ isCompleted: true, updatedBy: bob.uid, updatedAt: FieldValue.serverTimestamp() });
    await sleep(3000);
    assert.equal((await sentMessages()).length, 0);
  });

  it('30秒以内に同じ予定を何度変えても、通知は1回にまとめる', async () => {
    await addMembersAndDevices();
    const ref = db.doc(`groups/${GROUP}/items/item-4`);
    await ref.set(item(alice.uid));
    await waitFor(async () => (await sentMessages()).length > 0);
    await ref.update({ date: Timestamp.fromDate(new Date('2026-10-12T11:00:00+09:00')), updatedBy: alice.uid });
    await ref.update({ date: Timestamp.fromDate(new Date('2026-10-12T11:30:00+09:00')), updatedBy: alice.uid });
    await sleep(3000);
    assert.equal((await sentMessages()).length, 1);
  });

  it('生活グループがもう無いときは、通知の記録も通知も作らない（孤立した記録を残さない）', async () => {
    const ghost = `ghost-${crypto.randomUUID()}`;
    const now = Timestamp.now();
    await db.doc(`groups/${ghost}/members/${alice.uid}`).set({ uid: alice.uid, role: 'owner', joinedAt: now, displayName: 'alice' });
    await db.doc(`groups/${ghost}/members/${bob.uid}`).set({ uid: bob.uid, role: 'member', joinedAt: now, displayName: 'bob' });
    await addMembersAndDevices();
    await db.doc(`groups/${ghost}/items/item-g`).set(item(alice.uid));
    await sleep(3000);
    assert.equal((await db.doc(`groups/${ghost}/notificationLog/item-g`).get()).exists, false);
    assert.equal((await sentMessages()).length, 0);
    await db.recursiveDelete(db.doc(`groups/${ghost}`));
  });

  it('bob が変更すると alice に届く（双方向）', async () => {
    await addMembersAndDevices();
    await db.doc(`groups/${GROUP}/items/item-5`).set(item(bob.uid, { kind: 'shopping', hasTime: false, title: '牛乳' }));
    const messages = await waitFor(async () => {
      const list = await sentMessages();
      return list.length >= 2 ? list : null;
    });
    assert.ok(messages);
    assert.deepEqual(messages.map((m) => m.token).sort(), ['token-alice-ipad', 'token-alice-iphone']);
    assert.equal(messages[0].data.type, 'taskAdded');
  });
});
