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
async function call(name, data = {}, idToken, { appCheck = true } = {}) {
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
  for (const path of ['_emulatorSentMessages', 'invites', 'memberships', `groups/${GROUP}/items`, `groups/${GROUP}/members`, `groups/${GROUP}/notificationLog`]) {
    await clearCollection(path);
  }
  for (const user of [alice, bob, carol]) {
    await clearCollection(`users/${user.uid}/devices`);
  }
  const now = Timestamp.now();
  await db.doc(`groups/${GROUP}`).set({ name: 'わが家', createdBy: alice.uid, createdAt: now, updatedAt: now, sharedKinds: ['todo', 'shopping'] });
  await db.doc(`groups/${GROUP}/members/${alice.uid}`).set({ uid: alice.uid, role: 'owner', joinedAt: now, displayName: 'alice' });
  await db.doc(`memberships/${alice.uid}`).set({ groupID: GROUP, joinedAt: now });
});

const tokenOf = (url) => new URL(url).searchParams.get('token');
const hashOf = (token) => crypto.createHash('sha256').update(token).digest('hex');

describe('招待', () => {
  it('オーナーは招待を発行できる。返すのはリンクと期限だけで、保存されるのはハッシュだけ', async () => {
    const response = await call('createInvite', {}, alice.idToken);
    assert.ok(response.result, JSON.stringify(response));
    assert.deepEqual(Object.keys(response.result).sort(), ['expiresAt', 'url']);
    const { url, expiresAt } = response.result;
    const token = tokenOf(url);
    assert.match(token, /^[A-Za-z0-9_-]{43}$/);
    assert.ok(url.endsWith(`/invite?token=${token}`));
    assert.ok(Math.abs(expiresAt - (Date.now() + 24 * 60 * 60 * 1000)) < 60 * 1000, '期限は24時間');

    const invite = await db.doc(`invites/${hashOf(token)}`).get();
    assert.ok(invite.exists);
    assert.equal(invite.data().revokedAt, null);
    assert.ok(!JSON.stringify(invite.data()).includes(token), '生のトークンは保存しない');
  });

  it('メンバーでない人・サインインしていない人は発行できない', async () => {
    const response = await call('createInvite', {}, carol.idToken);
    assert.equal(response.error.details.reason, 'no-household');
    assert.equal((await call('createInvite', {})).error.status, 'UNAUTHENTICATED');
  });

  it('一度だけ使える：bob が参加したら、carol は同じ招待で参加できない', async () => {
    const token = tokenOf((await call('createInvite', {}, alice.idToken)).result.url);
    const accepted = await call('acceptInvite', { token }, bob.idToken);
    assert.ok(accepted.result, JSON.stringify(accepted));
    assert.equal(accepted.result.household.isOwner, false);
    const member = await db.doc(`groups/${GROUP}/members/${bob.uid}`).get();
    assert.equal(member.data().role, 'member');
    // uid は参加した本人の UID（文書 ID と同じ。アカウント削除の整理で使う）
    assert.equal(member.data().uid, bob.uid);
    assert.equal(member.data().uid, member.id);
    assert.equal((await db.doc(`memberships/${bob.uid}`).get()).data().groupID, GROUP);

    const reused = await call('acceptInvite', { token }, carol.idToken);
    assert.equal(reused.error.details.reason, 'already-used');
    assert.equal((await db.doc(`groups/${GROUP}/members/${carol.uid}`).get()).exists, false);
  });

  it('期限が切れた招待・自分の招待・間違ったトークンは使えない', async () => {
    const token = crypto.randomBytes(32).toString('base64url');
    await db.doc(`invites/${hashOf(token)}`).set({
      groupID: GROUP, createdBy: alice.uid, createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() - 1000), usedAt: null, usedBy: null, revokedAt: null,
    });
    assert.equal((await call('acceptInvite', { token }, bob.idToken)).error.details.reason, 'expired');

    const own = tokenOf((await call('createInvite', {}, alice.idToken)).result.url);
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
    const response = await call('createInvite', {}, alice.idToken, { appCheck: false });
    assert.equal(response.error && response.error.status, 'UNAUTHENTICATED', JSON.stringify(response));
    assert.equal(await inviteCount(), 0, '招待が作られていない');
  });

  it('App Check の情報が無いと、サインインしていても招待を使えない（招待は未使用のまま）', async () => {
    const token = tokenOf((await call('createInvite', {}, alice.idToken)).result.url);
    const response = await call('acceptInvite', { token }, bob.idToken, { appCheck: false });
    assert.equal(response.error && response.error.status, 'UNAUTHENTICATED', JSON.stringify(response));
    assert.equal((await db.doc(`groups/${GROUP}/members/${bob.uid}`).get()).exists, false, 'メンバーに追加されていない');
    assert.equal((await db.doc(`invites/${hashOf(token)}`).get()).data().usedAt, null, '招待は使われていない');

    // 同じ招待も、App Check の情報を付ければ使える（断られたのは App Check が無かったため）
    assert.ok((await call('acceptInvite', { token }, bob.idToken)).result);
  });

  it('App Check の情報だけでは、サインインしたことにならない', async () => {
    assert.equal((await call('createInvite', {})).error.status, 'UNAUTHENTICATED');
    assert.equal(await inviteCount(), 0);
    const token = tokenOf((await call('createInvite', {}, alice.idToken)).result.url);
    assert.equal((await call('acceptInvite', { token })).error.status, 'UNAUTHENTICATED');
  });

  it('App Check もサインインも無い呼び出しは断られる', async () => {
    assert.equal((await call('createInvite', {}, null, { appCheck: false })).error.status, 'UNAUTHENTICATED');
    assert.equal(await inviteCount(), 0);
  });
});

// MARK: - わが家の作成・招待・参加（2026-10-22。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）

const HOUSEHOLD_FUNCTIONS = ['createHousehold', 'getMyHousehold', 'createInvite', 'revokeInvite', 'getInvitePreview', 'acceptInvite'];

describe('わが家：作成', () => {
  it('わが家を作れる（グループ・オーナー・共有する種類・memberships）。返す内容に UID は入らない', async () => {
    const owner = await signUp('owner');
    const response = await call('createHousehold', { name: ' わが家 ', sharedKinds: ['shopping', 'todo'] }, owner.idToken);
    assert.ok(response.result, JSON.stringify(response));
    const household = response.result.household;
    assert.equal(household.name, 'わが家');
    assert.deepEqual(household.sharedKinds, ['todo', 'shopping'], '決まった並びで保存');
    assert.equal(household.isOwner, true);
    assert.equal(household.maxMembers, 2);
    assert.equal(household.members.length, 1);
    assert.deepEqual(Object.keys(household.members[0]).sort(), ['isSelf', 'joinedAt', 'role']);
    assert.equal(household.activeInvite, null);
    assert.ok(!JSON.stringify(response).includes(owner.uid), 'UID を返さない');

    const membership = await db.doc(`memberships/${owner.uid}`).get();
    const groupID = membership.data().groupID;
    const group = (await db.doc(`groups/${groupID}`).get()).data();
    assert.equal(group.createdBy, owner.uid);
    assert.deepEqual(group.sharedKinds, ['todo', 'shopping']);
    const member = (await db.doc(`groups/${groupID}/members/${owner.uid}`).get()).data();
    assert.equal(member.role, 'owner');
    assert.equal(member.uid, owner.uid);
  });

  it('共有する種類が空・決まっていない値・重複・多すぎる、名前が空・長すぎるときは作れない', async () => {
    const owner = await signUp('owner');
    for (const sharedKinds of [[], ['payment'], ['todo', 'todo'], ['todo', 'Todo'], 'todo', null,
      ['event', 'todo', 'chore', 'shopping', 'money', 'warranty', 'list', 'event']]) {
      const response = await call('createHousehold', { name: 'わが家', sharedKinds }, owner.idToken);
      assert.equal(response.error && response.error.details.reason, 'invalid-kinds', JSON.stringify(sharedKinds));
    }
    for (const name of ['', '   ', 'あ'.repeat(51), 'わが\n家', 5]) {
      const response = await call('createHousehold', { name, sharedKinds: ['todo'] }, owner.idToken);
      assert.equal(response.error && response.error.details.reason, 'invalid-name', JSON.stringify(name));
    }
    assert.equal((await db.doc(`memberships/${owner.uid}`).get()).exists, false, '何も作られていない');
    // 7種類すべてなら作れる
    const all = await call('createHousehold', {
      name: 'わが家', sharedKinds: ['list', 'warranty', 'money', 'shopping', 'chore', 'todo', 'event'],
    }, owner.idToken);
    assert.deepEqual(all.result.household.sharedKinds, ['event', 'todo', 'chore', 'shopping', 'money', 'warranty', 'list']);
  });

  it('1人1つ：もう1つは作れない。同時に2回届いても1つだけ', async () => {
    const owner = await signUp('owner');
    const results = await Promise.all([
      call('createHousehold', { name: 'A', sharedKinds: ['todo'] }, owner.idToken),
      call('createHousehold', { name: 'B', sharedKinds: ['todo'] }, owner.idToken),
    ]);
    assert.equal(results.filter((r) => r.result).length, 1, JSON.stringify(results));
    assert.equal(results.find((r) => r.error).error.details.reason, 'already-in-household');
    const groups = await db.collection('groups').where('createdBy', '==', owner.uid).get();
    assert.equal(groups.size, 1);
    const again = await call('createHousehold', { name: 'C', sharedKinds: ['todo'] }, owner.idToken);
    assert.equal(again.error.details.reason, 'already-in-household');
  });

  it('自分のわが家を読める。参加していなければ null', async () => {
    const owner = await signUp('owner');
    assert.deepEqual((await call('getMyHousehold', {}, owner.idToken)).result, { household: null });
    await call('createHousehold', { name: 'わが家', sharedKinds: ['todo'] }, owner.idToken);
    const household = (await call('getMyHousehold', {}, owner.idToken)).result.household;
    assert.equal(household.name, 'わが家');
    assert.equal(household.members[0].isSelf, true);
  });
});

describe('わが家：招待と参加', () => {
  /** オーナーがわが家を作り、招待を発行する */
  async function ownerWithInvite(kinds = ['todo', 'shopping', 'money']) {
    const owner = await signUp('owner');
    const created = await call('createHousehold', { name: '池上家', sharedKinds: kinds }, owner.idToken);
    assert.ok(created.result, JSON.stringify(created));
    const invite = (await call('createInvite', {}, owner.idToken)).result;
    const groupID = (await db.doc(`memberships/${owner.uid}`).get()).data().groupID;
    return { owner, invite, token: tokenOf(invite.url), groupID };
  }

  it('招待の内容（Preview）はグループ名・共有する種類・期限だけ。Preview では参加しない', async () => {
    const { owner, token, groupID, invite } = await ownerWithInvite();
    const partner = await signUp('partner');
    const response = await call('getInvitePreview', { token }, partner.idToken);
    assert.ok(response.result, JSON.stringify(response));
    assert.deepEqual(response.result.preview, { groupName: '池上家', sharedKinds: ['todo', 'shopping', 'money'], expiresAt: invite.expiresAt });
    assert.ok(!JSON.stringify(response).includes(owner.uid), '招待した人の UID を返さない');
    // 参加していない
    assert.equal((await db.doc(`groups/${groupID}/members/${partner.uid}`).get()).exists, false);
    assert.equal((await db.doc(`invites/${hashOf(token)}`).get()).data().usedAt, null);
    assert.deepEqual((await call('getMyHousehold', {}, partner.idToken)).result, { household: null });
  });

  it('「参加する」で参加できる。オーナーとパートナーの2人になり、招待は使用済み', async () => {
    const { owner, token, groupID } = await ownerWithInvite();
    const partner = await signUp('partner');
    const joined = await call('acceptInvite', { token }, partner.idToken);
    assert.ok(joined.result, JSON.stringify(joined));
    assert.equal(joined.result.household.members.length, 2);
    assert.equal(joined.result.household.isOwner, false);
    assert.equal(joined.result.household.activeInvite, null, 'パートナーには招待を見せない');
    const invite = (await db.doc(`invites/${hashOf(token)}`).get()).data();
    assert.equal(invite.usedBy, partner.uid);
    const ownerView = (await call('getMyHousehold', {}, owner.idToken)).result.household;
    assert.deepEqual(ownerView.members.map((m) => [m.role, m.isSelf]), [['owner', true], ['member', false]]);
    assert.equal(ownerView.activeInvite, null);
    assert.equal((await db.doc(`memberships/${partner.uid}`).get()).data().groupID, groupID);
  });

  it('同じ参加が2回・同時に届いても、メンバーは1人だけ増える', async () => {
    const { token, groupID } = await ownerWithInvite();
    const partner = await signUp('partner');
    const results = await Promise.all([
      call('acceptInvite', { token }, partner.idToken),
      call('acceptInvite', { token }, partner.idToken),
    ]);
    assert.ok(results.every((r) => r.result), JSON.stringify(results));
    const again = await call('acceptInvite', { token }, partner.idToken);
    assert.ok(again.result, '3回目も成功（何も書かない）');
    assert.equal((await db.collection(`groups/${groupID}/members`).get()).size, 2);
  });

  it('招待はオーナーだけが作れる・取り消せる', async () => {
    const { token } = await ownerWithInvite();
    const partner = await signUp('partner');
    await call('acceptInvite', { token }, partner.idToken);
    assert.equal((await call('createInvite', {}, partner.idToken)).error.details.reason, 'not-owner');
    assert.equal((await call('revokeInvite', {}, partner.idToken)).error.details.reason, 'not-owner');
    const stranger = await signUp('stranger');
    assert.equal((await call('createInvite', {}, stranger.idToken)).error.details.reason, 'no-household');
    assert.equal((await call('revokeInvite', {}, stranger.idToken)).error.details.reason, 'no-household');
  });

  it('期限は24時間。新しい招待を作ると、前の未使用の招待は使えなくなる', async () => {
    const { owner, token: first, invite } = await ownerWithInvite();
    assert.ok(Math.abs(invite.expiresAt - (Date.now() + 24 * 60 * 60 * 1000)) < 60 * 1000);
    const second = (await call('createInvite', {}, owner.idToken)).result;
    const partner = await signUp('partner');
    assert.equal((await call('getInvitePreview', { token: first }, partner.idToken)).error.details.reason, 'revoked');
    assert.equal((await call('acceptInvite', { token: first }, partner.idToken)).error.details.reason, 'revoked');
    const view = (await call('getMyHousehold', {}, owner.idToken)).result.household;
    assert.equal(view.activeInvite.expiresAt, second.expiresAt, '有効なのは新しい招待だけ');
    assert.ok((await call('acceptInvite', { token: tokenOf(second.url) }, partner.idToken)).result);
  });

  it('取り消した招待・期限切れ・使用済みの招待は、Preview も参加もできない', async () => {
    const { owner, token, groupID } = await ownerWithInvite();
    const partner = await signUp('partner');
    assert.deepEqual((await call('revokeInvite', {}, owner.idToken)).result, { revoked: 1 });
    assert.equal((await call('getInvitePreview', { token }, partner.idToken)).error.details.reason, 'revoked');
    assert.equal((await call('acceptInvite', { token }, partner.idToken)).error.details.reason, 'revoked');
    assert.equal((await call('getMyHousehold', {}, owner.idToken)).result.household.activeInvite, null);

    const expired = crypto.randomBytes(32).toString('base64url');
    await db.doc(`invites/${hashOf(expired)}`).set({
      groupID, createdBy: owner.uid, createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() - 1000), usedAt: null, usedBy: null, revokedAt: null,
    });
    assert.equal((await call('getInvitePreview', { token: expired }, partner.idToken)).error.details.reason, 'expired');
    assert.equal((await call('acceptInvite', { token: expired }, partner.idToken)).error.details.reason, 'expired');

    const fresh = tokenOf((await call('createInvite', {}, owner.idToken)).result.url);
    await call('acceptInvite', { token: fresh }, partner.idToken);
    const third = await signUp('third');
    assert.equal((await call('getInvitePreview', { token: fresh }, third.idToken)).error.details.reason, 'already-used');
    assert.equal((await call('acceptInvite', { token: fresh }, third.idToken)).error.details.reason, 'already-used');
  });

  it('自分の招待には参加できない（Preview も）', async () => {
    const { owner, token } = await ownerWithInvite();
    assert.equal((await call('getInvitePreview', { token }, owner.idToken)).error.details.reason, 'own-invite');
    assert.equal((await call('acceptInvite', { token }, owner.idToken)).error.details.reason, 'own-invite');
  });

  it('3人目は参加できない（満員）。満員のあいだは招待も作れない', async () => {
    const { owner, token, groupID } = await ownerWithInvite();
    const partner = await signUp('partner');
    await call('acceptInvite', { token }, partner.idToken);
    assert.equal((await call('createInvite', {}, owner.idToken)).error.details.reason, 'household-full');
    // 満員の前に作られていた招待が残っていても、3人目は入れない
    const leftover = crypto.randomBytes(32).toString('base64url');
    await db.doc(`invites/${hashOf(leftover)}`).set({
      groupID, createdBy: owner.uid, createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000), usedAt: null, usedBy: null, revokedAt: null,
    });
    const third = await signUp('third');
    assert.equal((await call('getInvitePreview', { token: leftover }, third.idToken)).error.details.reason, 'household-full');
    assert.equal((await call('acceptInvite', { token: leftover }, third.idToken)).error.details.reason, 'household-full');
    assert.equal((await db.collection(`groups/${groupID}/members`).get()).size, 2);
  });

  it('別のわが家に参加している人は参加できない（1人1つ）', async () => {
    const { token } = await ownerWithInvite();
    const other = await signUp('other');
    await call('createHousehold', { name: '別の家', sharedKinds: ['todo'] }, other.idToken);
    assert.equal((await call('getInvitePreview', { token }, other.idToken)).error.details.reason, 'already-in-household');
    assert.equal((await call('acceptInvite', { token }, other.idToken)).error.details.reason, 'already-in-household');
  });

  it('App Check が無い・サインインしていない呼び出しは、6つの Function すべてで断られる', async () => {
    const { token } = await ownerWithInvite();
    const partner = await signUp('partner');
    for (const name of HOUSEHOLD_FUNCTIONS) {
      const payload = { token, name: 'x', sharedKinds: ['todo'] };
      assert.equal((await call(name, payload, partner.idToken, { appCheck: false })).error.status, 'UNAUTHENTICATED', `${name}：App Check なし`);
      assert.equal((await call(name, payload)).error.status, 'UNAUTHENTICATED', `${name}：サインインなし`);
    }
    assert.deepEqual((await call('getMyHousehold', {}, partner.idToken)).result, { household: null }, '何も作られていない');
    assert.equal((await db.doc(`invites/${hashOf(token)}`).get()).data().usedAt, null);
  });

  it('エラーの返事に、トークン・UID・Firebase の生のエラー文は入らない', async () => {
    const { owner, token } = await ownerWithInvite();
    const responses = [
      await call('acceptInvite', { token }, owner.idToken),
      await call('getInvitePreview', { token: 'short' }, owner.idToken),
      await call('createHousehold', { name: 'x', sharedKinds: ['todo'] }, owner.idToken),
    ];
    for (const response of responses) {
      const text = JSON.stringify(response);
      assert.ok(response.error, text);
      assert.ok(!text.includes(token) && !text.includes(owner.uid), text);
      assert.deepEqual(Object.keys(response.error.details), ['reason']);
    }
  });
});

describe('わが家：設定・削除・退出（2026-10-28）', () => {
  /** オーナーがわが家を作り、パートナーが参加する（partner を省略するとオーナー1人） */
  async function household({ withPartner = true, kinds = ['todo', 'shopping'] } = {}) {
    const owner = await signUp('owner');
    const created = await call('createHousehold', { name: 'わが家', sharedKinds: kinds }, owner.idToken);
    assert.ok(created.result, JSON.stringify(created));
    const groupID = created.result.household.groupID;
    let partner = null;
    if (withPartner) {
      partner = await signUp('partner');
      const token = tokenOf((await call('createInvite', {}, owner.idToken)).result.url);
      assert.ok((await call('acceptInvite', { token }, partner.idToken)).result);
    }
    return { owner, partner, groupID };
  }

  it('わが家の情報に groupID を返す（UID は返さない）', async () => {
    const { owner, groupID } = await household({ withPartner: false });
    const view = (await call('getMyHousehold', {}, owner.idToken)).result.household;
    assert.equal(view.groupID, groupID);
    assert.ok(!JSON.stringify(view).includes(owner.uid));
  });

  it('名前と共有する種類は、オーナーもパートナーも変えられる。今後対応の種類は消さない', async () => {
    const { owner, partner, groupID } = await household({ kinds: ['todo', 'shopping', 'money'] });
    const byOwner = await call('updateHousehold', { name: '新しいわが家' }, owner.idToken);
    assert.equal(byOwner.result.household.name, '新しいわが家');
    const byPartner = await call('updateHousehold', { syncKinds: ['shopping'] }, partner.idToken);
    assert.deepEqual(byPartner.result.household.sharedKinds, ['shopping', 'money'], '家計簿（今後対応）は残る');
    const group = (await db.doc(`groups/${groupID}`).get()).data();
    assert.deepEqual(group.sharedKinds, ['shopping', 'money']);
    assert.equal(group.name, '新しいわが家');
    // 送れない値・空の名前・何も送らない
    assert.equal((await call('updateHousehold', { syncKinds: ['event'] }, owner.idToken)).error.details.reason, 'invalid-kinds');
    assert.equal((await call('updateHousehold', { name: '  ' }, owner.idToken)).error.details.reason, 'invalid-name');
    assert.equal((await call('updateHousehold', {}, owner.idToken)).error.details.reason, 'invalid-update');
    const stranger = await signUp('stranger');
    assert.equal((await call('updateHousehold', { name: 'x' }, stranger.idToken)).error.details.reason, 'no-household');
  });

  it('種類をオフにしても、すでにある共有項目は消さない', async () => {
    const { owner, groupID } = await household();
    await db.doc(`groups/${groupID}/items/keep`).set({
      title: '牛乳', kind: 'shopping', date: Timestamp.now(), hasTime: false, assigneeUID: null, isCompleted: false,
      deferredTo: null, droppedAt: null, createdBy: owner.uid, updatedBy: null, createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
    assert.ok((await call('updateHousehold', { syncKinds: ['todo'] }, owner.idToken)).result);
    assert.ok((await db.doc(`groups/${groupID}/items/keep`).get()).exists);
  });

  it('1人のオーナーはわが家を削除できる（共有項目・メンバー・招待・通知の記録・memberships を消す。アカウントは残る）', async () => {
    const { owner, groupID } = await household({ withPartner: false });
    await call('createInvite', {}, owner.idToken);
    await db.doc(`groups/${groupID}/items/i1`).set({ title: 'x', kind: 'todo', updatedBy: null });
    await db.doc(`groups/${groupID}/notificationLog/i1`).set({ lastSentAt: Timestamp.now() });
    const response = await call('deleteHousehold', {}, owner.idToken);
    assert.deepEqual(response.result, { deleted: true }, JSON.stringify(response));
    assert.equal((await db.doc(`groups/${groupID}`).get()).exists, false);
    assert.deepEqual((await db.doc(`groups/${groupID}`).listCollections()).map((c) => c.id), []);
    assert.equal((await db.collection('invites').where('groupID', '==', groupID).get()).size, 0);
    assert.equal((await db.doc(`memberships/${owner.uid}`).get()).exists, false);
    // アカウントは残っている（サインインのまま、新しく作れる）
    assert.deepEqual((await call('getMyHousehold', {}, owner.idToken)).result, { household: null });
    assert.ok((await call('createHousehold', { name: '次の家', sharedKinds: ['todo'] }, owner.idToken)).result);
  });

  it('2人いるときは、オーナーでも削除できない。パートナーは削除できない', async () => {
    const { owner, partner, groupID } = await household();
    assert.equal((await call('deleteHousehold', {}, owner.idToken)).error.details.reason, 'household-not-empty');
    assert.equal((await call('deleteHousehold', {}, partner.idToken)).error.details.reason, 'not-owner');
    assert.ok((await db.doc(`groups/${groupID}`).get()).exists);
    assert.equal((await db.collection(`groups/${groupID}/members`).get()).size, 2);
  });

  it('パートナーは退出でき、わが家・オーナー・共有項目は残る。退出したあと別の招待へ参加できる', async () => {
    const { owner, partner, groupID } = await household();
    await db.doc(`groups/${groupID}/items/mine`).set({
      title: '電池', kind: 'shopping', date: Timestamp.now(), hasTime: false, assigneeUID: partner.uid, isCompleted: false,
      deferredTo: null, droppedAt: null, createdBy: partner.uid, updatedBy: null, createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
    assert.deepEqual((await call('leaveHousehold', {}, partner.idToken)).result, { left: true });
    assert.equal((await db.doc(`groups/${groupID}/members/${partner.uid}`).get()).exists, false);
    assert.equal((await db.doc(`memberships/${partner.uid}`).get()).exists, false);
    assert.ok((await db.doc(`groups/${groupID}/members/${owner.uid}`).get()).exists);
    const item = (await db.doc(`groups/${groupID}/items/mine`).get()).data();
    assert.equal(item.title, '電池', '共有項目は残る');
    assert.equal(item.assigneeUID, null, '退出した人の担当は外す');
    assert.deepEqual((await call('getMyHousehold', {}, partner.idToken)).result, { household: null });
    assert.equal((await call('leaveHousehold', {}, partner.idToken)).error.details.reason, 'no-household');

    // 別の招待へ参加できる
    const other = await household({ withPartner: false });
    const token = tokenOf((await call('createInvite', {}, other.owner.idToken)).result.url);
    assert.ok((await call('acceptInvite', { token }, partner.idToken)).result);
    // 元のオーナーはまた招待できる（1人に戻った）
    assert.ok((await call('createInvite', {}, owner.idToken)).result);
  });

  it('オーナーは2人いるあいだ退出できない', async () => {
    const { owner, groupID } = await household();
    assert.equal((await call('leaveHousehold', {}, owner.idToken)).error.details.reason, 'owner-cannot-leave');
    assert.equal((await db.collection(`groups/${groupID}/members`).get()).size, 2);
  });

  it('App Check が無い・サインインしていない管理の呼び出しは断られる', async () => {
    const { owner, groupID } = await household({ withPartner: false });
    for (const name of ['updateHousehold', 'deleteHousehold', 'leaveHousehold']) {
      const payload = { name: 'x', syncKinds: ['todo'] };
      assert.equal((await call(name, payload, owner.idToken, { appCheck: false })).error.status, 'UNAUTHENTICATED', `${name}：App Check なし`);
      assert.equal((await call(name, payload)).error.status, 'UNAUTHENTICATED', `${name}：サインインなし`);
    }
    assert.ok((await db.doc(`groups/${groupID}`).get()).exists, '何も変わっていない');
    assert.equal((await db.doc(`groups/${groupID}`).get()).data().name, 'わが家');
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

  // 2026-10-28（Build 8）：通知するのは共有の ToDo・買い物だけなので、見本は ToDo にした
  function item(actorUID, overrides = {}) {
    return {
      schemaVersion: 1, title: '書類を出す', kind: 'todo', date: Timestamp.fromDate(new Date('2026-10-12T00:00:00+09:00')), hasTime: false,
      assigneeUID: null, isCompleted: false, deferredTo: null, droppedAt: null,
      createdBy: actorUID, updatedBy: actorUID, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      ...overrides,
    };
  }

  it('alice が共有の ToDo を追加すると、bob の通知 ON の端末にだけ1回届く', async () => {
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
    assert.equal(all[0].notification.body, 'わが家のToDoが更新されました', '内容の表示を許可していなければ項目名を出さない');
    assert.deepEqual(all[0].data, { groupID: GROUP, itemID: 'item-1', type: 'taskAdded', kind: 'todo' });
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

  it('30秒以内に同じ ToDo の名前を何度変えても、通知は1回にまとめる', async () => {
    await addMembersAndDevices();
    const ref = db.doc(`groups/${GROUP}/items/item-4`);
    await ref.set(item(alice.uid));
    await waitFor(async () => (await sentMessages()).length > 0);
    await ref.update({ title: '書類を出す（1）', updatedBy: alice.uid });
    await ref.update({ title: '書類を出す（2）', updatedBy: alice.uid });
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
    assert.equal(messages[0].data.kind, 'shopping');
  });

  // MARK: Build 8（2026-10-28）。docs/SHARED_PUSH_NOTIFICATIONS.md

  it('Build 8：内容の表示を許可した端末には項目名だけ、許可していない端末には出さない', async () => {
    await addMembersAndDevices();
    await db.doc(`users/${bob.uid}/devices/b1`).update({ showsPreview: true });
    await db.doc(`users/${bob.uid}/devices/b4`).set({
      fcmToken: 'token-bob-ipad', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, showsPreview: false, updatedAt: Timestamp.now(),
    });
    await db.doc(`groups/${GROUP}/items/item-6`).set(item(alice.uid, { kind: 'shopping', title: '洗剤を買う' }));
    const messages = await waitFor(async () => {
      const list = await sentMessages();
      return list.length >= 2 ? list : null;
    });
    assert.ok(messages);
    const byToken = Object.fromEntries(messages.map((m) => [m.token, m.notification.body]));
    assert.equal(byToken['token-bob'], '「洗剤を買う」が追加されました');
    assert.equal(byToken['token-bob-ipad'], 'わが家の買い物が更新されました');
    for (const message of messages) {
      assert.equal(JSON.stringify(message).includes(alice.uid), false, '送信者の UID を入れない');
      assert.equal(JSON.stringify(message).includes(bob.uid), false);
    }
  });

  it('Build 8：予定・家事は通知しない。名前の変更は通知する', async () => {
    await addMembersAndDevices();
    await db.doc(`groups/${GROUP}/items/item-7`).set(item(alice.uid, { kind: 'event', hasTime: true }));
    await db.doc(`groups/${GROUP}/items/item-8`).set(item(alice.uid, { kind: 'chore' }));
    await sleep(3000);
    assert.equal((await sentMessages()).length, 0, '予定・家事');

    const ref = db.doc(`groups/${GROUP}/items/item-9`);
    await ref.set(item(alice.uid));
    await waitFor(async () => (await sentMessages()).length > 0);
    await clearCollection('_emulatorSentMessages');
    await db.doc(`groups/${GROUP}/notificationLog/item-9`).delete();
    await ref.update({ title: '書類を出す（市役所）', updatedBy: bob.uid, updatedAt: FieldValue.serverTimestamp() });
    const changed = await waitFor(async () => {
      const list = await sentMessages();
      return list.length > 0 ? list : null;
    });
    assert.ok(changed, '名前の変更が届かない');
    assert.deepEqual(changed.map((m) => m.data.type), ['taskChanged', 'taskChanged']);
    assert.deepEqual(changed.map((m) => m.token).sort(), ['token-alice-ipad', 'token-alice-iphone'], '変えた bob には送らない');
  });

  it('Build 8：退出した人（メンバーでない人）には送らない。本人と同じトークンにも送らない', async () => {
    await addMembersAndDevices();
    // bob の端末に、alice と同じトークンが残っている（同じ iPhone を使い回した など）
    await db.doc(`users/${bob.uid}/devices/b5`).set({
      fcmToken: 'token-alice-iphone', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, showsPreview: true, updatedAt: Timestamp.now(),
    });
    await db.doc(`groups/${GROUP}/items/item-10`).set(item(alice.uid));
    await waitFor(async () => (await sentMessages()).length > 0);
    await sleep(1500);
    assert.deepEqual((await sentMessages()).map((m) => m.token), ['token-bob']);

    // bob が退出（メンバー文書が無い）したあとは、bob の端末には送らない
    await clearCollection('_emulatorSentMessages');
    await db.doc(`groups/${GROUP}/members/${bob.uid}`).delete();
    await db.doc(`groups/${GROUP}/items/item-11`).set(item(alice.uid));
    await sleep(3000);
    assert.equal((await sentMessages()).length, 0);
  });

  it('Build 8：同じ出来事が2回届いても（再試行）、通知の記録に出来事の ID が残り、2回は送らない', async () => {
    await addMembersAndDevices();
    await db.doc(`groups/${GROUP}/items/item-12`).set(item(alice.uid));
    await waitFor(async () => (await sentMessages()).length > 0);
    const log = await waitFor(async () => {
      const snap = await db.doc(`groups/${GROUP}/notificationLog/item-12`).get();
      return snap.exists ? snap.data() : null;
    });
    assert.ok(log);
    assert.equal(typeof log.lastEventID, 'string', '出来事の ID を記録する');
    assert.deepEqual(Object.keys(log).sort(), ['lastEventID', 'lastSentAt'], '通知の記録に項目名・UID を入れない');
  });
});
