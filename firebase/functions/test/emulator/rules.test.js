'use strict';

/**
 * Firestore Security Rules のテスト（仕様 11「Rules Emulator」）。
 * Firestore Emulator が必要：firebase/functions で `npm run test:rules`（手順は docs/FIREBASE_SETUP.md）
 */

const fs = require('node:fs');
const path = require('node:path');
const { before, after, beforeEach, describe, it } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp,
} = require('firebase/firestore');

let testEnv;

const GROUP = 'group-a';
const OTHER_GROUP = 'group-b';

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-lifeos',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../../../firestore.rules'), 'utf8') },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // alice（owner）と bob（member）の生活グループ、別の生活グループ（mallory だけ）
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const now = Timestamp.now();
    await setDoc(doc(db, `groups/${GROUP}`), { name: '池上家', createdBy: 'alice', createdAt: now, updatedAt: now });
    await setDoc(doc(db, `groups/${GROUP}/members/alice`), { role: 'owner', joinedAt: now, displayName: 'alice' });
    await setDoc(doc(db, `groups/${GROUP}/members/bob`), { role: 'member', joinedAt: now, displayName: 'bob' });
    await setDoc(doc(db, `groups/${GROUP}/items/item-1`), sharedItem('alice', now));
    await setDoc(doc(db, `groups/${OTHER_GROUP}`), { name: '別の家', createdBy: 'mallory', createdAt: now, updatedAt: now });
    await setDoc(doc(db, `groups/${OTHER_GROUP}/members/mallory`), { role: 'owner', joinedAt: now, displayName: 'mallory' });
    await setDoc(doc(db, `invites/hash-1`), { groupID: GROUP, createdBy: 'alice', expiresAt: now, usedAt: null, usedBy: null });
    await setDoc(doc(db, `users/bob/devices/device-1`), {
      fcmToken: 'token-bob', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, updatedAt: now,
    });
  });
});

/** 共有項目（作成時は createdAt・updatedAt にサーバーの時刻を使う） */
function sharedItem(uid, time = serverTimestamp()) {
  return {
    title: '歯医者',
    kind: 'event',
    date: Timestamp.fromDate(new Date('2026-10-12T10:30:00+09:00')),
    hasTime: true,
    assigneeUID: null,
    isCompleted: false,
    deferredTo: null,
    droppedAt: null,
    createdBy: uid,
    updatedBy: uid,
    createdAt: time,
    updatedAt: time,
  };
}

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

describe('メンバーでない人', () => {
  it('ほかの生活グループの共有項目・メンバー・グループを読めない', async () => {
    const db = as('mallory');
    await assertFails(getDoc(doc(db, `groups/${GROUP}`)));
    await assertFails(getDoc(doc(db, `groups/${GROUP}/items/item-1`)));
    await assertFails(getDocs(collection(db, `groups/${GROUP}/items`)));
    await assertFails(getDocs(collection(db, `groups/${GROUP}/members`)));
  });

  it('ほかの生活グループに共有項目を書けない・消せない', async () => {
    const db = as('mallory');
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/item-x`), sharedItem('mallory')));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), { title: '変更', updatedBy: 'mallory', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(db, `groups/${GROUP}/items/item-1`)));
  });

  it('サインインしていなければ何も読めない', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `groups/${GROUP}/items/item-1`)));
  });

  it('自分をメンバーに追加できない（既にあるグループの owner にもなれない）', async () => {
    const db = as('mallory');
    const now = serverTimestamp();
    await assertFails(setDoc(doc(db, `groups/${GROUP}/members/mallory`), { role: 'member', joinedAt: now, displayName: 'mallory' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/members/mallory`), { role: 'owner', joinedAt: now, displayName: 'mallory' }));
  });
});

describe('メンバー', () => {
  it('自分の生活グループの共有項目を読める', async () => {
    await assertSucceeds(getDoc(doc(as('bob'), `groups/${GROUP}/items/item-1`)));
    await assertSucceeds(getDocs(collection(as('bob'), `groups/${GROUP}/members`)));
  });

  it('決まった形の共有項目を作れる', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), `groups/${GROUP}/items/item-2`), sharedItem('bob')));
    const todo = { ...sharedItem('bob'), kind: 'shopping', hasTime: false, assigneeUID: 'alice' };
    await assertSucceeds(setDoc(doc(as('bob'), `groups/${GROUP}/items/item-3`), todo));
  });

  it('共有できない種類（支払予定・習慣）や、決まっていない項目（個人の印・メモなど）は拒否', async () => {
    const db = as('bob');
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/p1`), { ...sharedItem('bob'), kind: 'payment' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/p2`), { ...sharedItem('bob'), kind: 'habit' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/p3`), { ...sharedItem('bob'), ownership: 'personal' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/p4`), { ...sharedItem('bob'), memo: '個人のメモ' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/p5`), { ...sharedItem('bob'), title: '' }));
  });

  it('作成者・更新者を他人にできない、担当はメンバーだけ', async () => {
    const db = as('bob');
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/f1`), sharedItem('alice')));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/f2`), { ...sharedItem('bob'), assigneeUID: 'mallory' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/f3`), { ...sharedItem('bob'), createdAt: Timestamp.now() }));
  });

  it('更新できる（作成者・作成日時は変えられない）', async () => {
    const db = as('bob');
    await assertSucceeds(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
      isCompleted: true, updatedBy: 'bob', updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
      createdBy: 'bob', updatedBy: 'bob', updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
      isCompleted: false, updatedBy: 'alice', updatedAt: serverTimestamp(),
    }));
  });

  it('役割を変えられない（member から owner への昇格を拒否）', async () => {
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}/members/bob`), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/members/bob`), { role: 'owner' }));
  });

  it('ほかの人をメンバーに追加できない（招待の Function だけが追加する）', async () => {
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/members/carol`), {
      role: 'member', joinedAt: serverTimestamp(), displayName: 'carol',
    }));
  });

  it('自分は退出できるが、ほかの人は外せない', async () => {
    await assertFails(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/alice`)));
    await assertSucceeds(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/bob`)));
    // 退出したあとは読めない
    await assertFails(getDoc(doc(as('bob'), `groups/${GROUP}/items/item-1`)));
  });

  it('グループの名前だけ変えられる（作成者は変えられない）', async () => {
    await assertSucceeds(updateDoc(doc(as('bob'), `groups/${GROUP}`), { name: '池上家（新）', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}`), { createdBy: 'bob', updatedAt: serverTimestamp() }));
  });
});

describe('生活グループを作る', () => {
  it('同じ書き込みで自分を owner にすれば作れる', async () => {
    const db = as('carol');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-c'), { name: 'carol の家', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-c/members/carol'), { role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol' });
    await assertSucceeds(batch.commit());
  });

  it('自分を owner にしないグループや、他人を作成者にしたグループは作れない', async () => {
    const db = as('carol');
    await assertFails(setDoc(doc(db, 'groups/group-d'), { name: 'x', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-e'), { name: 'x', createdBy: 'alice', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-e/members/carol'), { role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol' });
    await assertFails(batch.commit());
  });
});

describe('招待・通知の記録・端末', () => {
  it('招待はアプリから読み書きできない', async () => {
    await assertFails(getDoc(doc(as('alice'), 'invites/hash-1')));
    await assertFails(setDoc(doc(as('alice'), 'invites/hash-2'), { groupID: GROUP }));
    await assertFails(updateDoc(doc(as('bob'), 'invites/hash-1'), { usedAt: serverTimestamp(), usedBy: 'bob' }));
  });

  it('通知の記録はアプリから読み書きできない', async () => {
    await assertFails(getDoc(doc(as('alice'), `groups/${GROUP}/notificationLog/item-1`)));
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/notificationLog/item-1`), { lastSentAt: serverTimestamp() }));
  });

  it('端末トークンは本人だけが登録・読み取り・削除できる', async () => {
    const device = {
      fcmToken: 'token-alice', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: false,
      showsPreview: false, updatedAt: serverTimestamp(),
    };
    await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/devices/d1'), device));
    await assertFails(setDoc(doc(as('bob'), 'users/alice/devices/d2'), device));
    await assertFails(getDoc(doc(as('alice'), 'users/bob/devices/device-1')));
    await assertFails(deleteDoc(doc(as('alice'), 'users/bob/devices/device-1')));
    await assertSucceeds(deleteDoc(doc(as('bob'), 'users/bob/devices/device-1')));
    await assertFails(setDoc(doc(as('alice'), 'users/alice/devices/d3'), { ...device, extra: 'x' }));
  });

  it('利用者情報は本人だけ', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), 'users/alice'), { displayName: 'alice', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('bob'), 'users/alice')));
    await assertFails(setDoc(doc(as('bob'), 'users/alice'), { displayName: 'x' }));
  });
});
