'use strict';

/**
 * アカウント削除のあとの Firestore の整理のテスト（docs/FIREBASE_ACCOUNT_DELETION_CLEANUP.md）。
 * Auth・Firestore・Functions の Emulator が必要：firebase/functions で `npm run test:functions`
 *
 * - 整理の処理（src/accountCleanupRunner.js）を Emulator の Firestore に対して直接動かして、結果を確かめる
 * - 最後に、Auth Emulator で利用者を1人削除し、削除トリガー（onAuthUserDeleted）が実際に動くことを確かめる
 *
 * 本物の Firebase・ネットワークには接続しない。テストごとに別の ID を使い、ほかのテストのデータに触れない。
 */

const crypto = require('node:crypto');
const { before, describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { cleanupDeletedUser } = require('../../src/accountCleanupRunner');

const PROJECT = 'demo-lifeos';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

initializeApp({ projectId: PROJECT }, 'account-deletion-test');
const db = getFirestore(require('firebase-admin/app').getApp('account-deletion-test'));

/** テストごとに重ならない ID */
const RUN = crypto.randomUUID().slice(0, 8);
let counter = 0;
function newID(name) {
  counter += 1;
  return `${name}-${RUN}-${counter}`;
}

const T = (ms) => Timestamp.fromMillis(Date.UTC(2026, 9, 1) + ms);

async function cleanup(uid) {
  return cleanupDeletedUser({ db, FieldValue, uid });
}

/** 生活グループを作る。members：[uid, role, 参加の時刻(ms)] */
async function seedGroup(groupID, createdBy, members) {
  await db.doc(`groups/${groupID}`).set({ name: 'わが家', createdBy, createdAt: T(0), updatedAt: T(0) });
  for (const [uid, role, joinedMs] of members) {
    await db.doc(`groups/${groupID}/members/${uid}`).set({ uid, role, joinedAt: T(joinedMs), displayName: uid });
  }
}

/**
 * 共有項目。updatedBy は既定で null（このテストでは通知の Function を動かさないため）。
 * 作成者・更新者の記録が残ることを確かめるときだけ指定する
 */
async function seedItem(groupID, itemID, { assigneeUID = null, createdBy = 'someone', updatedBy = null } = {}) {
  await db.doc(`groups/${groupID}/items/${itemID}`).set({
    title: '歯医者', kind: 'todo', date: T(0), hasTime: false, assigneeUID, isCompleted: false,
    deferredTo: null, droppedAt: null, createdBy, updatedBy, createdAt: T(0), updatedAt: T(0),
  });
}

async function seedUser(uid) {
  await db.doc(`users/${uid}`).set({ displayName: uid, createdAt: T(0), updatedAt: T(0) });
  await db.doc(`users/${uid}/devices/d1`).set({
    fcmToken: `token-${uid}`, platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, updatedAt: T(0),
  });
  // devices 以外のサブコレクションも消えることを確かめるため
  await db.doc(`users/${uid}/settings/s1`).set({ value: 1 });
}

const exists = async (path) => (await db.doc(path).get()).exists;
const data = async (path) => (await db.doc(path).get()).data();
const memberIDs = async (groupID) => (await db.collection(`groups/${groupID}/members`).get()).docs.map((d) => d.id).sort();
const subcollections = async (path) => (await db.doc(path).listCollections()).map((c) => c.id).sort();

async function waitFor(check, timeoutMs = 20000) {
  const start = Date.now();
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() - start > timeoutMs) return value;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

describe('一般メンバーが削除されたとき', () => {
  it('本人のメンバー文書と利用者の情報が消え、ほかのメンバー・共有項目は残る。本人が担当の項目は担当が null になる', async () => {
    const g = newID('g');
    const [owner, deleted, partner] = [newID('owner'), newID('m'), newID('p')];
    await seedGroup(g, owner, [[owner, 'owner', 0], [deleted, 'member', 10], [partner, 'member', 20]]);
    await seedItem(g, 'mine', { assigneeUID: deleted, createdBy: deleted, updatedBy: deleted });
    await seedItem(g, 'partners', { assigneeUID: partner });
    await seedItem(g, 'nobody');
    await seedUser(deleted);
    await seedUser(partner);

    const summary = await cleanup(deleted);

    // 1：本人のメンバー文書・利用者の情報（下のコレクションも）が消える
    assert.equal(await exists(`groups/${g}/members/${deleted}`), false);
    assert.equal(await exists(`users/${deleted}`), false);
    assert.deepEqual(await subcollections(`users/${deleted}`), [], 'devices・settings も残らない');
    // 2：ほかのメンバー（役割もそのまま）・グループ・共有項目は残る
    assert.deepEqual(await memberIDs(g), [owner, partner].sort());
    assert.equal((await data(`groups/${g}/members/${owner}`)).role, 'owner');
    assert.equal((await data(`groups/${g}/members/${partner}`)).role, 'member');
    assert.equal((await data(`groups/${g}`)).createdBy, owner);
    for (const id of ['mine', 'partners', 'nobody']) assert.ok(await exists(`groups/${g}/items/${id}`), id);
    // 3：本人が担当の項目は null。作成者・更新者の記録は残す
    const mine = await data(`groups/${g}/items/mine`);
    assert.equal(mine.assigneeUID, null);
    assert.equal(mine.createdBy, deleted);
    assert.equal(mine.updatedBy, deleted);
    assert.equal(mine.title, '歯医者');
    assert.equal((await data(`groups/${g}/items/partners`)).assigneeUID, partner);
    // 15：ほかの人の端末は残る
    assert.ok(await exists(`users/${partner}/devices/d1`));
    // 作業の記録は最後に消える
    assert.equal(await exists(`accountDeletions/${deleted}`), false);
    assert.equal(summary.removedMemberships, 1);
    assert.equal(summary.clearedAssignees, 1);
  });
});

describe('owner が削除され、ほかのメンバーがいるとき', () => {
  it('ほかのメンバーが owner を引き継ぎ、グループと共有項目は残る（createdBy はそのまま、updatedAt は更新）', async () => {
    const g = newID('g');
    const [owner, partner] = [newID('o'), newID('p')];
    await seedGroup(g, owner, [[owner, 'owner', 0], [partner, 'member', 10]]);
    await seedItem(g, 'i1', { assigneeUID: owner });

    await cleanup(owner);

    assert.deepEqual(await memberIDs(g), [partner]);
    assert.equal((await data(`groups/${g}/members/${partner}`)).role, 'owner');
    const group = await data(`groups/${g}`);
    assert.equal(group.createdBy, owner, '作成の記録は変えない');
    assert.ok(group.updatedAt.toMillis() > T(0).toMillis(), 'updatedAt はサーバーの時刻に');
    assert.ok(await exists(`groups/${g}/items/i1`));
    assert.equal((await data(`groups/${g}/items/i1`)).assigneeUID, null);
  });

  it('複数人いるときは、参加がいちばん古い人が owner になる', async () => {
    const g = newID('g');
    const [owner, a, b, c] = [newID('o'), newID('a'), newID('b'), newID('c')];
    await seedGroup(g, owner, [[owner, 'owner', 0], [a, 'member', 300], [b, 'member', 100], [c, 'member', 200]]);

    await cleanup(owner);

    assert.equal((await data(`groups/${g}/members/${b}`)).role, 'owner');
    assert.equal((await data(`groups/${g}/members/${a}`)).role, 'member');
    assert.equal((await data(`groups/${g}/members/${c}`)).role, 'member');
  });

  it('参加の時刻が同じなら、UID の文字順で先の人が owner になる', async () => {
    const g = newID('g');
    const owner = newID('o');
    const [zed, amy, bob] = [`zed-${RUN}`, `amy-${RUN}`, `bob-${RUN}`];
    await seedGroup(g, owner, [[owner, 'owner', 0], [zed, 'member', 50], [amy, 'member', 50], [bob, 'member', 50]]);

    await cleanup(owner);

    assert.equal((await data(`groups/${g}/members/${amy}`)).role, 'owner');
    assert.equal((await data(`groups/${g}/members/${bob}`)).role, 'member');
    assert.equal((await data(`groups/${g}/members/${zed}`)).role, 'member');
  });
});

describe('owner しかいない生活グループ', () => {
  it('items・members・notificationLog など、下のコレクションを含めて丸ごと消える。招待も消える', async () => {
    const g = newID('g');
    const owner = newID('o');
    const other = newID('x');
    await seedGroup(g, owner, [[owner, 'owner', 0]]);
    await seedItem(g, 'i1', { assigneeUID: owner });
    await seedItem(g, 'i2');
    await db.doc(`groups/${g}/notificationLog/i1`).set({ lastSentAt: T(0) });
    await db.doc(`groups/${g}/somethingElse/x`).set({ value: 1 });
    await db.doc(`invites/${newID('inv')}`).set({ groupID: g, createdBy: other, expiresAt: T(0), usedAt: null, usedBy: null });
    const keepInvite = newID('inv');
    await db.doc(`invites/${keepInvite}`).set({ groupID: newID('elsewhere'), createdBy: other, expiresAt: T(0), usedAt: null, usedBy: null });

    const summary = await cleanup(owner);

    assert.equal(await exists(`groups/${g}`), false);
    assert.deepEqual(await subcollections(`groups/${g}`), [], '孤立したサブコレクションが残らない');
    assert.equal((await db.collection('invites').where('groupID', '==', g).get()).size, 0);
    assert.ok(await exists(`invites/${keepInvite}`), 'ほかのグループの招待は残す');
    assert.equal(summary.deletedGroups, 1);
  });
});

describe('複数の生活グループ・やり直し・ほかの人のデータ', () => {
  it('所属しているすべての生活グループを、1回で整理する', async () => {
    const uid = newID('u');
    const [g1, g2, g3] = [newID('g'), newID('g'), newID('g')];
    const [o1, p2] = [newID('o'), newID('p')];
    await seedGroup(g1, o1, [[o1, 'owner', 0], [uid, 'member', 10]]);
    await seedGroup(g2, uid, [[uid, 'owner', 0], [p2, 'member', 10]]);
    await seedGroup(g3, uid, [[uid, 'owner', 0]]);
    await seedItem(g1, 'i', { assigneeUID: uid });
    await seedItem(g2, 'i', { assigneeUID: uid });
    await seedUser(uid);

    const summary = await cleanup(uid);

    assert.deepEqual(await memberIDs(g1), [o1]);
    assert.deepEqual(await memberIDs(g2), [p2]);
    assert.equal((await data(`groups/${g2}/members/${p2}`)).role, 'owner');
    assert.equal(await exists(`groups/${g3}`), false);
    assert.equal((await data(`groups/${g1}/items/i`)).assigneeUID, null);
    assert.equal((await data(`groups/${g2}/items/i`)).assigneeUID, null);
    assert.equal(await exists(`users/${uid}`), false);
    assert.deepEqual(
      { groups: summary.groups, removed: summary.removedMemberships, transferred: summary.transferredOwnerships, deleted: summary.deletedGroups },
      { groups: 3, removed: 1, transferred: 1, deleted: 1 }
    );
  });

  it('同じ処理を2回実行しても成功し、結果は変わらない（同じ削除イベントが2回届いたとき）', async () => {
    const uid = newID('u');
    const g = newID('g');
    const p = newID('p');
    await seedGroup(g, uid, [[uid, 'owner', 0], [p, 'member', 10]]);
    await seedItem(g, 'i', { assigneeUID: uid });
    await seedUser(uid);

    await cleanup(uid);
    const second = await cleanup(uid);

    assert.deepEqual(await memberIDs(g), [p]);
    assert.equal((await data(`groups/${g}/members/${p}`)).role, 'owner');
    assert.ok(await exists(`groups/${g}/items/i`));
    assert.equal(second.groups, 0);
    assert.equal(second.transferredOwnerships, 0);
    assert.equal(await exists(`accountDeletions/${uid}`), false);
  });

  it('同じ削除イベントが同時に2回届いても壊れない', async () => {
    const uid = newID('u');
    const g = newID('g');
    const p = newID('p');
    await seedGroup(g, uid, [[uid, 'owner', 0], [p, 'member', 10]]);
    await seedUser(uid);

    await Promise.all([cleanup(uid), cleanup(uid)]);

    assert.deepEqual(await memberIDs(g), [p]);
    assert.equal((await data(`groups/${g}/members/${p}`)).role, 'owner');
    assert.equal(await exists(`users/${uid}`), false);
  });

  it('一部がすでに消えていても成功する（途中で止まったあとのやり直し）', async () => {
    const uid = newID('u');
    const [gDone, gHalf, gTodo] = [newID('g'), newID('g'), newID('g')];
    const [p1, p3] = [newID('p'), newID('p')];
    // gDone：前回、本人のメンバー文書はもう消した
    await seedGroup(gDone, p1, [[p1, 'owner', 0]]);
    // gHalf：前回、owner だけのグループを消す途中で止まった（グループの文書とメンバーは消えたが、項目と記録が残っている）
    await seedItem(gHalf, 'left-over');
    await db.doc(`groups/${gHalf}/notificationLog/left-over`).set({ lastSentAt: T(0) });
    // gTodo：まだ手を付けていない
    await seedGroup(gTodo, p3, [[p3, 'owner', 0], [uid, 'member', 10]]);
    // 前回の作業の記録（利用者の情報はもう消えている）
    await db.doc(`accountDeletions/${uid}`).set({ groupIDs: [gDone, gHalf], startedAt: T(0) });

    await cleanup(uid);

    assert.deepEqual(await memberIDs(gDone), [p1], '済んでいるグループには触れない');
    assert.equal((await data(`groups/${gDone}/members/${p1}`)).role, 'owner');
    assert.deepEqual(await subcollections(`groups/${gHalf}`), [], '途中だったグループの残りが消える');
    assert.deepEqual(await memberIDs(gTodo), [p3]);
    assert.equal(await exists(`accountDeletions/${uid}`), false);
  });

  it('ほかの人の端末・グループ・共有データ・招待を消さない', async () => {
    const uid = newID('u');
    const [mine, others] = [newID('g'), newID('g')];
    const [o, x, y] = [newID('o'), newID('x'), newID('y')];
    await seedGroup(mine, o, [[o, 'owner', 0], [uid, 'member', 10]]);
    await seedGroup(others, x, [[x, 'owner', 0], [y, 'member', 10]]);
    await seedItem(others, 'theirs', { assigneeUID: y, createdBy: x });
    await seedUser(uid);
    await seedUser(x);
    await seedUser(y);
    // 文書 ID は別人なのに uid だけ削除された人になっている文書（ルール上は作れない）も、消さない
    await db.doc(`groups/${others}/members/${x}-fake`).set({ uid, role: 'member', joinedAt: T(5), displayName: 'fake' });
    const theirInvite = newID('inv');
    await db.doc(`invites/${theirInvite}`).set({ groupID: others, createdBy: x, expiresAt: T(0), usedAt: null, usedBy: null });
    const myInvite = newID('inv');
    await db.doc(`invites/${myInvite}`).set({ groupID: mine, createdBy: uid, expiresAt: T(0), usedAt: null, usedBy: null });

    await cleanup(uid);

    assert.deepEqual(await memberIDs(others), [x, `${x}-fake`, y].sort());
    assert.equal((await data(`groups/${others}/members/${x}`)).role, 'owner');
    assert.equal((await data(`groups/${others}/items/theirs`)).assigneeUID, y);
    for (const person of [x, y]) {
      assert.ok(await exists(`users/${person}`), person);
      assert.ok(await exists(`users/${person}/devices/d1`), person);
    }
    assert.ok(await exists(`invites/${theirInvite}`), 'ほかの人の招待は残す');
    assert.equal(await exists(`invites/${myInvite}`), false, '削除された人が作った招待は消す');
    assert.deepEqual(await memberIDs(mine), [o]);
  });

  it('退出したグループに残っていた担当も null にする（項目は消さない）', async () => {
    const uid = newID('u');
    const g = newID('g');
    const o = newID('o');
    await seedGroup(g, o, [[o, 'owner', 0]]);
    await seedItem(g, 'old', { assigneeUID: uid });

    await cleanup(uid);

    assert.equal((await data(`groups/${g}/items/old`)).assigneeUID, null);
    assert.deepEqual(await memberIDs(g), [o]);
  });

  it('使えない UID では何もしない（エラーにする）', async () => {
    await assert.rejects(cleanup(''), /invalid-uid/);
    await assert.rejects(cleanup('a/b'), /invalid-uid/);
  });
});

/** Auth Emulator で利用者を作る */
async function signUp(name) {
  const response = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${name}-${crypto.randomUUID()}@example.com`, password: 'password', returnSecureToken: true }),
  });
  const body = await response.json();
  return { uid: body.localId, idToken: body.idToken };
}

/** Auth Emulator で利用者を削除する（アプリの「アカウントを削除」の最後の手順と同じ：本人が自分を削除） */
async function deleteAccount(idToken) {
  const response = await fetch(`http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:delete?key=demo`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ idToken }),
  });
  assert.equal(response.status, 200, await response.text());
}

describe('削除トリガー（Auth Emulator で利用者を削除）', () => {
  let dave;
  before(async () => {
    dave = await signUp('dave');
  });

  it('Authentication の利用者を1人削除すると、削除の Function が動いて整理される', async () => {
    const [g1, g2] = [newID('g'), newID('g')];
    const partner = newID('erin');
    await seedGroup(g1, dave.uid, [[dave.uid, 'owner', 0], [partner, 'member', 10]]);
    await seedGroup(g2, dave.uid, [[dave.uid, 'owner', 0]]);
    await seedItem(g1, 'i', { assigneeUID: dave.uid });
    await seedUser(dave.uid);
    await seedUser(partner);

    await deleteAccount(dave.idToken);

    const done = await waitFor(async () =>
      !(await exists(`users/${dave.uid}/devices/d1`)) &&
      !(await exists(`groups/${g1}/members/${dave.uid}`)) &&
      !(await exists(`groups/${g2}`)) &&
      !(await exists(`accountDeletions/${dave.uid}`))
    );
    assert.ok(done, '削除の Function が動いていない（20秒待った）');
    assert.equal((await data(`groups/${g1}/members/${partner}`)).role, 'owner');
    assert.equal((await data(`groups/${g1}/items/i`)).assigneeUID, null);
    assert.deepEqual(await subcollections(`users/${dave.uid}`), []);
    assert.deepEqual(await subcollections(`groups/${g2}`), []);
    assert.ok(await exists(`users/${partner}/devices/d1`), 'パートナーの端末は残る');
  });
});
