'use strict';

/**
 * Firestore Security Rules のテスト（仕様 11「Rules Emulator」）。
 * Firestore Emulator が必要：firebase/functions で `npm run test:rules`（手順は docs/FIREBASE_SETUP.md）
 * 2026-10-20 の監査で追加したテストは、下の「監査（2026-10-20）」の各 describe（docs/FIRESTORE_SHARING_RULES_AUDIT.md）
 */

const fs = require('node:fs');
const path = require('node:path');
const { before, after, beforeEach, describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, getDocs, collection, collectionGroup, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp,
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
    await setDoc(doc(db, `groups/${GROUP}`), { name: 'わが家', createdBy: 'alice', createdAt: now, updatedAt: now, sharedKinds: ['todo', 'shopping'] });
    await setDoc(doc(db, `groups/${GROUP}/members/alice`), { uid: 'alice', role: 'owner', joinedAt: now, displayName: 'alice' });
    await setDoc(doc(db, `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'member', joinedAt: now, displayName: 'bob' });
    await setDoc(doc(db, `groups/${GROUP}/items/item-1`), sharedItem('alice', now));
    await setDoc(doc(db, `groups/${OTHER_GROUP}`), { name: '別の家', createdBy: 'mallory', createdAt: now, updatedAt: now });
    await setDoc(doc(db, `groups/${OTHER_GROUP}/members/mallory`), { uid: 'mallory', role: 'owner', joinedAt: now, displayName: 'mallory' });
    await setDoc(doc(db, `invites/hash-1`), { groupID: GROUP, createdBy: 'alice', expiresAt: now, usedAt: null, usedBy: null });
    await setDoc(doc(db, `users/bob/devices/device-1`), {
      fcmToken: 'token-bob', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, updatedAt: now,
    });
  });
});

/** メンバー文書を外す（退出・削除はサーバーの Function だけが行うので、テストの準備はルールを止めて書く） */
async function removeMemberAsServer(uid) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), `groups/${GROUP}/members/${uid}`));
  });
}

/**
 * 共有項目（作成時は createdAt・updatedAt にサーバーの時刻を使う）。
 * 2026-10-28（Build 7）から新しく作れるのは ToDo・買い物だけ（schemaVersion 1）なので、見本は ToDo にした
 */
function sharedItem(uid, time = serverTimestamp()) {
  return {
    schemaVersion: 1,
    title: '歯医者を予約',
    kind: 'todo',
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
    await assertFails(setDoc(doc(db, `groups/${GROUP}/members/mallory`), { uid: 'mallory', role: 'member', joinedAt: now, displayName: 'mallory' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/members/mallory`), { uid: 'mallory', role: 'owner', joinedAt: now, displayName: 'mallory' }));
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
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'owner' }));
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'owner' }));
  });

  it('ほかの人をメンバーに追加できない（招待の Function だけが追加する）', async () => {
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/members/carol`), {
      uid: 'carol', role: 'member', joinedAt: serverTimestamp(), displayName: 'carol',
    }));
  });

  it('アプリからはメンバー文書を消せない（自分も他人も。退出は leaveHousehold だけ。2026-10-28）', async () => {
    await assertFails(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/alice`)));
    await assertFails(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/bob`)));
    await assertFails(deleteDoc(doc(as('alice'), `groups/${GROUP}/members/alice`)));
    await assertFails(deleteDoc(doc(as('alice'), `groups/${GROUP}/members/bob`)));
    // サーバーが退出させたあとは読めない
    await removeMemberAsServer('bob');
    await assertFails(getDoc(doc(as('bob'), `groups/${GROUP}/items/item-1`)));
  });

  it('グループの名前だけ変えられる（作成者は変えられない）', async () => {
    await assertSucceeds(updateDoc(doc(as('bob'), `groups/${GROUP}`), { name: 'わが家（新）', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}`), { createdBy: 'bob', updatedAt: serverTimestamp() }));
  });
});

describe('生活グループを作る', () => {
  // 2026-10-22：わが家の作成は createHousehold（サーバー）だけ（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
  it('アプリからは、自分を owner にする同じ書き込みでも作れない（createHousehold だけが作る）', async () => {
    const db = as('carol');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-c'), { name: 'carol の家', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-c/members/carol'), { uid: 'carol', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol' });
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(db, 'groups/group-c2'), {
      name: 'x', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), sharedKinds: ['todo'],
    }));
  });

  it('自分を owner にしないグループや、他人を作成者にしたグループは作れない', async () => {
    const db = as('carol');
    await assertFails(setDoc(doc(db, 'groups/group-d'), { name: 'x', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-e'), { name: 'x', createdBy: 'alice', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-e/members/carol'), { uid: 'carol', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol' });
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

// MARK: - 監査（2026-10-20）で追加したテスト（docs/FIRESTORE_SHARING_RULES_AUDIT.md）

const unauthenticated = () => testEnv.unauthenticatedContext().firestore();

describe('監査（2026-10-20）：サインインしていない利用者', () => {
  it('グループ・メンバー・利用者情報・端末も読めない', async () => {
    const db = unauthenticated();
    await assertFails(getDoc(doc(db, `groups/${GROUP}`)));
    await assertFails(getDocs(collection(db, `groups/${GROUP}/members`)));
    await assertFails(getDocs(collection(db, `groups/${GROUP}/items`)));
    await assertFails(getDoc(doc(db, 'users/bob')));
    await assertFails(getDoc(doc(db, 'users/bob/devices/device-1')));
  });

  it('共有項目・利用者情報・端末・招待に書き込めない（作成・更新・削除）', async () => {
    const db = unauthenticated();
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/anon-1`), sharedItem('anon')));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), { title: '変更', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(db, `groups/${GROUP}/items/item-1`)));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/members/anon`), { uid: 'anon', role: 'member', joinedAt: serverTimestamp(), displayName: 'anon' }));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}`), { name: '変更', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db, 'users/anon'), { displayName: 'anon' }));
    await assertFails(setDoc(doc(db, 'users/anon/devices/d1'), {
      fcmToken: 't', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, updatedAt: serverTimestamp(),
    }));
    await assertFails(deleteDoc(doc(db, 'users/bob/devices/device-1')));
    await assertFails(setDoc(doc(db, 'invites/hash-anon'), { groupID: GROUP }));
  });

  it('生活グループを作れない（自分を owner にする同じ書き込みでも拒否）', async () => {
    const db = unauthenticated();
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-anon'), { name: '匿名の家', createdBy: 'anon', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-anon/members/anon'), { uid: 'anon', role: 'owner', joinedAt: serverTimestamp(), displayName: 'anon' });
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(db, 'groups/group-anon2'), { name: 'x', createdBy: 'anon', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
});

describe('監査（2026-10-20）：ルールに書かれていない場所', () => {
  it('知らない場所は、本人・メンバーでも読み書きできない', async () => {
    const alice = as('alice');
    const bob = as('bob');
    // いちばん上の、ルールに無いコレクション
    await assertFails(setDoc(doc(alice, 'personalItems/p1'), { title: '個人の予定' }));
    await assertFails(getDoc(doc(alice, 'personalItems/p1')));
    await assertFails(getDocs(collection(alice, 'personalItems')));
    // 自分の利用者情報の下でも、devices 以外は置けない
    await assertFails(setDoc(doc(alice, 'users/alice/items/i1'), { title: '個人の予定' }));
    await assertFails(getDocs(collection(alice, 'users/alice/items')));
    // 自分の生活グループの下でも、members・items 以外は置けない
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/personal/p1`), { title: '個人の予定' }));
    await assertFails(getDocs(collection(bob, `groups/${GROUP}/personal`)));
    // 共有項目の下にさらに置くこともできない
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/item-1/notes/n1`), { text: 'メモ' }));
  });

  it('グループをまたいだ一括検索（collection group）はできない', async () => {
    await assertFails(getDocs(collectionGroup(as('bob'), 'items')));
    await assertFails(getDocs(collectionGroup(as('bob'), 'members')));
    await assertFails(getDocs(collectionGroup(as('alice'), 'devices')));
  });
});

describe('監査（2026-10-20）：個人データらしい項目・場所', () => {
  it('支払・習慣・保証書・お金・メモなどの場所は、本人の下でもグループの下でも作れない', async () => {
    const alice = as('alice');
    for (const name of ['payments', 'habits', 'warranties', 'money', 'memos', 'photos']) {
      await assertFails(setDoc(doc(alice, `${name}/x1`), { title: '個人' }), name);
      await assertFails(setDoc(doc(alice, `users/alice/${name}/x1`), { title: '個人' }), `users/alice/${name}`);
      await assertFails(setDoc(doc(alice, `groups/${GROUP}/${name}/x1`), { title: '個人' }), `groups/${GROUP}/${name}`);
    }
  });

  it('共有項目に、決まっていない項目（金額・場所・写真・メモ・個人の印）を足せない', async () => {
    const db = as('bob');
    for (const [key, value] of [
      ['amount', 12000], ['location', '駅前の歯医者'], ['photoURL', 'https://example.com/a.jpg'],
      ['note', '保険証を持っていく'], ['ownership', 'personal'], ['isPrivate', true],
    ]) {
      await assertFails(setDoc(doc(db, `groups/${GROUP}/items/extra-${key}`), { ...sharedItem('bob'), [key]: value }), `作成：${key}`);
      await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
        [key]: value, updatedBy: 'bob', updatedAt: serverTimestamp(),
      }), `更新：${key}`);
    }
  });

  it('利用者情報・グループ・メンバー・端末にも、決まっていない項目を足せない', async () => {
    const alice = as('alice');
    await assertFails(setDoc(doc(alice, 'users/alice'), { displayName: 'alice', birthday: '1990-01-01' }));
    await assertFails(setDoc(doc(alice, 'users/alice'), { displayName: 'alice', memo: '個人のメモ' }));
    await assertFails(updateDoc(doc(alice, `groups/${GROUP}`), { name: 'わが家', memo: '個人のメモ', updatedAt: serverTimestamp() }));
    // 新しいグループを作るときも、決まっていない項目は拒否
    const carol = as('carol');
    const batch = writeBatch(carol);
    batch.set(doc(carol, 'groups/group-f'), { name: 'x', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(carol, 'groups/group-f/members/carol'), { uid: 'carol', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol', phone: '090' });
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(as('bob'), 'users/bob/devices/device-2'), {
      fcmToken: 'token-bob-2', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true,
      updatedAt: serverTimestamp(), location: '自宅',
    }));
  });
});

describe('監査（2026-10-20）：権限・作成の情報', () => {
  it('退出した人は、同じ生活グループに owner としても member としても戻れない', async () => {
    const bob = as('bob');
    await removeMemberAsServer('bob');
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'owner', joinedAt: serverTimestamp(), displayName: 'bob' }));
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'member', joinedAt: serverTimestamp(), displayName: 'bob' }));
    // グループを作り直して owner になることもできない（既にあるグループは「作成」ではない）
    const batch = writeBatch(bob);
    batch.set(doc(bob, `groups/${GROUP}`), { name: 'わが家', createdBy: 'bob', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(bob, `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'owner', joinedAt: serverTimestamp(), displayName: 'bob' });
    await assertFails(batch.commit());
    await assertFails(getDoc(doc(bob, `groups/${GROUP}/items/item-1`)));
  });

  it('owner も一度退出すると戻れない（owner の役割を取り直せない）', async () => {
    const alice = as('alice');
    await removeMemberAsServer('alice');
    await assertFails(setDoc(doc(alice, `groups/${GROUP}/members/alice`), { uid: 'alice', role: 'owner', joinedAt: serverTimestamp(), displayName: 'alice' }));
  });

  it('更新で createdAt を変えられない（サーバーの時刻でも、端末の時刻でも）', async () => {
    const db = as('bob');
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
      createdAt: serverTimestamp(), updatedBy: 'bob', updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), {
      createdAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')), updatedBy: 'bob', updatedAt: serverTimestamp(),
    }));
  });

  it('作成のとき updatedBy を他人の UID にできない', async () => {
    const db = as('bob');
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/u1`), { ...sharedItem('bob'), updatedBy: 'alice' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/u2`), { ...sharedItem('bob'), updatedBy: 'mallory' }));
    // 比べるため：本人なら作れる
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/u3`), sharedItem('bob')));
  });

  it('更新で担当者をメンバーでない人に変えられない（メンバー・null には変えられる）', async () => {
    const db = as('bob');
    const ref = doc(db, `groups/${GROUP}/items/item-1`);
    await assertFails(updateDoc(ref, { assigneeUID: 'mallory', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { assigneeUID: 'nobody', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { assigneeUID: 123, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { assigneeUID: 'alice', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { assigneeUID: null, updatedBy: 'bob', updatedAt: serverTimestamp() }));
  });

  it('退出した人は、担当者に設定できない', async () => {
    await removeMemberAsServer('bob');
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/items/item-1`), {
      assigneeUID: 'bob', updatedBy: 'alice', updatedAt: serverTimestamp(),
    }));
  });
});

// MARK: - アカウント削除のあとの整理（2026-10-20）で追加したテスト（docs/FIREBASE_ACCOUNT_DELETION_CLEANUP.md）

describe('メンバー文書の uid（アカウント削除の整理で使う）', () => {
  function createGroupBatch(db, uid, memberData) {
    const batch = writeBatch(db);
    batch.set(doc(db, `groups/group-${uid}`), { name: 'x', createdBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, `groups/group-${uid}/members/${uid}`), memberData);
    return batch;
  }

  it('アプリからは、自分の UID を uid に入れても作れない（作成はサーバーだけ）', async () => {
    const db = as('carol');
    await assertFails(createGroupBatch(db, 'carol', {
      uid: 'carol', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol',
    }).commit());
  });

  it('uid を別人の UID にできない（偽装できない）', async () => {
    const db = as('carol');
    await assertFails(createGroupBatch(db, 'carol', {
      uid: 'alice', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol',
    }).commit());
    await assertFails(createGroupBatch(db, 'carol', {
      uid: '', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol',
    }).commit());
  });

  it('uid が無いメンバー文書は作れない', async () => {
    const db = as('carol');
    await assertFails(createGroupBatch(db, 'carol', {
      role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol',
    }).commit());
  });

  it('uid をあとから変えられない（本人も owner も）', async () => {
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}/members/bob`), { uid: 'mallory' }));
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/members/bob`), { uid: 'alice' }));
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/members/alice`), { uid: 'bob' }));
  });

  it('アカウント削除の作業記録（accountDeletions）は、アプリから読み書きできない', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'accountDeletions/bob'), { groupIDs: [GROUP] });
    });
    await assertFails(getDoc(doc(as('bob'), 'accountDeletions/bob')));
    await assertFails(setDoc(doc(as('bob'), 'accountDeletions/bob'), { groupIDs: [] }));
    await assertFails(deleteDoc(doc(as('bob'), 'accountDeletions/bob')));
    await assertFails(getDocs(collection(as('alice'), 'accountDeletions')));
  });
});

// MARK: - わが家の作成・招待・参加（2026-10-22）で追加したテスト（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）

describe('わが家：共有する種類・メンバー・memberships', () => {
  it('メンバーは共有する種類を読めるが、変えられない', async () => {
    const snap = await assertSucceeds(getDoc(doc(as('bob'), `groups/${GROUP}`)));
    assert.deepEqual(snap.data().sharedKinds, ['todo', 'shopping']);
    for (const kinds of [['todo', 'shopping', 'money'], [], ['payment'], ['todo', 'todo']]) {
      await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}`), { sharedKinds: kinds, updatedAt: serverTimestamp() }));
    }
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}`), { name: 'わが家', sharedKinds: ['money'], updatedAt: serverTimestamp() }));
  });

  it('メンバーでない人は、共有する種類もメンバーも読めない', async () => {
    await assertFails(getDoc(doc(as('mallory'), `groups/${GROUP}`)));
    await assertFails(getDocs(collection(as('mallory'), `groups/${GROUP}/members`)));
    await assertFails(getDoc(doc(as('carol'), `groups/${GROUP}/members/alice`)));
  });

  it('オーナーでも、アプリからメンバーを足して2人の上限を超えられない（自分も他人も）', async () => {
    const member = (uid, role) => ({ uid, role, joinedAt: serverTimestamp(), displayName: uid });
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/members/carol`), member('carol', 'member')));
    await assertFails(setDoc(doc(as('carol'), `groups/${GROUP}/members/carol`), member('carol', 'member')));
    await assertFails(setDoc(doc(as('carol'), `groups/${GROUP}/members/carol`), member('carol', 'owner')));
    await assertFails(setDoc(doc(as('mallory'), `groups/${OTHER_GROUP}/members/carol`), member('carol', 'member')));
  });

  it('アプリから owner に上がれない（自分でも、owner が相手を上げることも）', async () => {
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}/members/bob`), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}/members/bob`), { role: 'owner' }));
    await assertFails(setDoc(doc(as('bob'), `groups/${GROUP}/members/bob`), { uid: 'bob', role: 'owner', joinedAt: serverTimestamp(), displayName: 'bob' }));
  });

  it('memberships（1人1つのわが家の記録）は、本人もアプリから読み書きできない', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'memberships/bob'), { groupID: GROUP, joinedAt: Timestamp.now() });
    });
    await assertFails(getDoc(doc(as('bob'), 'memberships/bob')));
    await assertFails(setDoc(doc(as('bob'), 'memberships/bob'), { groupID: OTHER_GROUP }));
    await assertFails(deleteDoc(doc(as('bob'), 'memberships/bob')));
    await assertFails(setDoc(doc(as('carol'), 'memberships/carol'), { groupID: GROUP }));
    await assertFails(getDocs(collection(as('alice'), 'memberships')));
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), 'memberships/bob')));
  });

  it('招待（取り消しの記録を含む）はアプリから読めず、取り消しも書けない', async () => {
    await assertFails(getDoc(doc(as('alice'), 'invites/hash-1')));
    await assertFails(updateDoc(doc(as('alice'), 'invites/hash-1'), { revokedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('alice'), 'invites/hash-new'), {
      groupID: GROUP, createdBy: 'alice', expiresAt: Timestamp.now(), usedAt: null, usedBy: null, revokedAt: null,
    }));
  });
});

// MARK: - 共有 ToDo・買い物（2026-10-28 Build 7）。docs/SHARED_TODO_SHOPPING_FOUNDATION.md

describe('共有 ToDo・買い物（Build 7）', () => {
  /** わが家の設定（sharedKinds）を、サーバーが変えたのと同じように書く */
  async function setSharedKinds(kinds) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: kinds });
    });
  }

  it('新しく作れるのは 予定・ToDo・買い物だけ（家事は作れない。予定は Build 14 から、設定でオンのときだけ）', async () => {
    const db = as('bob');
    await setSharedKinds(['event', 'todo', 'chore', 'shopping']);
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/k-todo`), sharedItem('bob')));
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/k-shop`), { ...sharedItem('bob'), kind: 'shopping' }));
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/k-event`), { ...sharedItem('bob'), kind: 'event' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/k-chore`), { ...sharedItem('bob'), kind: 'chore' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/k-money`), { ...sharedItem('bob'), kind: 'money' }));
  });

  it('schemaVersion は 1 が必須で、あとから変えられない', async () => {
    const db = as('bob');
    const { schemaVersion, ...withoutVersion } = sharedItem('bob');
    assert.equal(schemaVersion, 1);
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/v0`), withoutVersion));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/v2`), { ...sharedItem('bob'), schemaVersion: 2 }));
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), { schemaVersion: 2, updatedBy: 'bob', updatedAt: serverTimestamp() }));
  });

  it('種類（kind）はあとから変えられない', async () => {
    const db = as('bob');
    await assertFails(updateDoc(doc(db, `groups/${GROUP}/items/item-1`), { kind: 'shopping', updatedBy: 'bob', updatedAt: serverTimestamp() }));
  });

  it('わが家の設定でオフの種類は、新しく作れない（オンに戻せば作れる）', async () => {
    const db = as('bob');
    await setSharedKinds(['shopping']);
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/off-1`), sharedItem('bob')));
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/on-1`), { ...sharedItem('bob'), kind: 'shopping' }));
    await setSharedKinds(['todo', 'shopping']);
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/off-1`), sharedItem('bob')));
  });

  it('テスト10：種類をオフにしても、すでにある共有項目は残り、完了・編集・削除できる', async () => {
    await setSharedKinds(['shopping']);
    const alice = as('alice');
    const ref = doc(alice, `groups/${GROUP}/items/item-1`);
    const before = await getDoc(ref);
    assert.equal(before.exists(), true);
    await assertSucceeds(updateDoc(ref, { isCompleted: true, updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { title: '歯医者に電話', updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(ref));
  });

  it('テスト4：2人のあいだで追加・編集・完了・未完了・削除が反映される', async () => {
    const alice = as('alice');
    const bob = as('bob');
    const path = `groups/${GROUP}/items/shared-1`;
    await assertSucceeds(setDoc(doc(bob, path), { ...sharedItem('bob'), kind: 'shopping', title: '牛乳を買う' }));
    assert.equal((await getDoc(doc(alice, path))).data().title, '牛乳を買う');
    await assertSucceeds(updateDoc(doc(alice, path), { title: '低脂肪牛乳を買う', updatedBy: 'alice', updatedAt: serverTimestamp() }));
    assert.equal((await getDoc(doc(bob, path))).data().title, '低脂肪牛乳を買う');
    await assertSucceeds(updateDoc(doc(alice, path), { isCompleted: true, updatedBy: 'alice', updatedAt: serverTimestamp() }));
    assert.equal((await getDoc(doc(bob, path))).data().isCompleted, true);
    await assertSucceeds(updateDoc(doc(bob, path), { isCompleted: false, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    const reopened = (await getDoc(doc(alice, path))).data();
    assert.equal(reopened.isCompleted, false);
    assert.equal(reopened.updatedBy, 'bob');
    assert.equal(reopened.createdBy, 'bob', '作成者は変わらない');
    await assertSucceeds(deleteDoc(doc(alice, path)));
    assert.equal((await getDoc(doc(bob, path))).exists(), false);
  });

  it('テスト9：同じ ID の作成をくり返しても、2件目はできない（上書きで作成日時を変えられない）', async () => {
    const db = as('bob');
    const path = `groups/${GROUP}/items/same-id`;
    await assertSucceeds(setDoc(doc(db, path), sharedItem('bob')));
    await assertFails(setDoc(doc(db, path), sharedItem('bob')));
    const all = await getDocs(collection(db, `groups/${GROUP}/items`));
    assert.equal(all.docs.filter((d) => d.id === 'same-id').length, 1);
  });

  it('テスト5・6：サインインしていない人・メンバーでない人は、作成も読み取りもできない。ほかのわが家は読めない', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, `groups/${GROUP}/items/anon`), sharedItem('anon')));
    await assertFails(getDocs(collection(anon, `groups/${GROUP}/items`)));
    const mallory = as('mallory');
    await assertFails(setDoc(doc(mallory, `groups/${GROUP}/items/m1`), sharedItem('mallory')));
    await assertFails(getDocs(collection(mallory, `groups/${GROUP}/items`)));
    await assertFails(getDocs(collection(as('bob'), `groups/${OTHER_GROUP}/items`)));
    await assertFails(getDocs(collectionGroup(as('bob'), 'items')));
  });

  it('退出（サーバーがメンバー文書を外した）あとは、読めず書けない', async () => {
    await removeMemberAsServer('bob');
    const bob = as('bob');
    await assertFails(getDocs(collection(bob, `groups/${GROUP}/items`)));
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/after-leave`), sharedItem('bob')));
    await assertFails(updateDoc(doc(bob, `groups/${GROUP}/items/item-1`), { isCompleted: true, updatedBy: 'bob', updatedAt: serverTimestamp() }));
  });

  it('アプリから共有する種類（sharedKinds）は変えられない（updateHousehold だけ）', async () => {
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}`), { sharedKinds: ['todo'], updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}`), { sharedKinds: ['todo', 'shopping', 'money'], updatedAt: serverTimestamp() }));
  });

  it('アプリからわが家（グループ）を消せない（deleteHousehold だけ）', async () => {
    await assertFails(deleteDoc(doc(as('alice'), `groups/${GROUP}`)));
  });
});

// MARK: - 共有の支出（2026-11-01 Build 13）。docs/BUILD_13_SHARED_HOUSEHOLD_BUDGET_AND_EVENT_DELETE.md

describe('Build 13：共有の支出（groups/{groupID}/expenses）', () => {
  const ID1 = 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F';
  const ID2 = '0F8FAD5B-D9CB-469F-A165-70867728950E';
  const ID3 = '7C9E6679-7425-40DE-944B-E07FC1F90AE7';

  async function setSharedKinds(kinds) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: kinds });
    });
  }

  /** 決まった形の共有の支出（作成時は createdAt・updatedAt にサーバーの時刻） */
  function expense(uid, overrides = {}) {
    return {
      schemaVersion: 1,
      title: 'スーパー',
      amount: 3520,
      category: 'food',
      date: Timestamp.fromDate(new Date('2026-11-01T00:00:00+09:00')),
      createdBy: uid,
      updatedBy: uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  const path = (id) => `groups/${GROUP}/expenses/${id}`;

  beforeEach(async () => {
    await setSharedKinds(['todo', 'shopping', 'money']);
  });

  it('オーナーとパートナーは、作成・読み取り・更新・削除ができる（双方向）', async () => {
    const alice = as('alice');
    const bob = as('bob');
    await assertSucceeds(setDoc(doc(alice, path(ID1)), expense('alice')));
    await assertSucceeds(setDoc(doc(bob, path(ID2)), expense('bob', { title: 'ランチ', amount: 1200, category: 'diningOut' })));
    assert.equal((await getDoc(doc(bob, path(ID1)))).data().amount, 3520);
    assert.equal((await getDocs(collection(alice, `groups/${GROUP}/expenses`))).size, 2);
    await assertSucceeds(updateDoc(doc(bob, path(ID1)), { title: 'スーパー（まとめ買い）', amount: 4980, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    const changed = (await getDoc(doc(alice, path(ID1)))).data();
    assert.equal(changed.amount, 4980);
    assert.equal(changed.updatedBy, 'bob');
    assert.equal(changed.createdBy, 'alice', '作成者は変わらない');
    await assertSucceeds(updateDoc(doc(alice, path(ID2)), { category: 'food', date: Timestamp.now(), updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(alice, path(ID2))));
    await assertSucceeds(deleteDoc(doc(bob, path(ID1))));
    assert.equal((await getDocs(collection(alice, `groups/${GROUP}/expenses`))).size, 0);
  });

  it('サインインしていない人・メンバーでない人は、読めず、作れず、変えられず、消せない', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), path(ID1)), expense('alice')));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, path(ID1))));
    await assertFails(getDocs(collection(anon, `groups/${GROUP}/expenses`)));
    await assertFails(setDoc(doc(anon, path(ID2)), expense('anon')));
    const mallory = as('mallory');
    await assertFails(getDoc(doc(mallory, path(ID1))));
    await assertFails(getDocs(collection(mallory, `groups/${GROUP}/expenses`)));
    await assertFails(setDoc(doc(mallory, path(ID2)), expense('mallory')));
    await assertFails(updateDoc(doc(mallory, path(ID1)), { amount: 1, updatedBy: 'mallory', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(mallory, path(ID1))));
    // ほかのわが家・グループをまたいだ検索もできない
    await assertFails(getDocs(collection(as('bob'), `groups/${OTHER_GROUP}/expenses`)));
    await assertFails(getDocs(collectionGroup(as('bob'), 'expenses')));
  });

  it('退出（サーバーがメンバー文書を外した）あとは、読めず書けない', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), path(ID1)), expense('bob')));
    await removeMemberAsServer('bob');
    const bob = as('bob');
    await assertFails(getDoc(doc(bob, path(ID1))));
    await assertFails(updateDoc(doc(bob, path(ID1)), { amount: 1, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(bob, path(ID1))));
    await assertFails(setDoc(doc(bob, path(ID2)), expense('bob')));
  });

  it('家計簿（money）がオフなら新しく作れない。オフのあとも、すでにある支出は変更・削除できる', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), path(ID1)), expense('alice')));
    await setSharedKinds(['todo', 'shopping']);
    await assertFails(setDoc(doc(as('bob'), path(ID2)), expense('bob')));
    await assertSucceeds(updateDoc(doc(as('bob'), path(ID1)), { amount: 3000, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(as('alice'), path(ID1))));
    await setSharedKinds(['money']);
    await assertSucceeds(setDoc(doc(as('bob'), path(ID2)), expense('bob')));
  });

  it('金額は 1〜999,999,999 の整数だけ', async () => {
    const db = as('bob');
    for (const [i, amount] of [0, -1, 1000000000, 12.5, '1200', null, true].entries()) {
      await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { amount })), `amount ${i}`);
    }
    await assertSucceeds(setDoc(doc(db, path(ID1)), expense('bob', { amount: 1 })));
    await assertSucceeds(setDoc(doc(db, path(ID2)), expense('bob', { amount: 999999999 })));
    await assertFails(updateDoc(doc(db, path(ID1)), { amount: 0, updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, path(ID1)), { amount: 1000000000, updatedBy: 'bob', updatedAt: serverTimestamp() }));
  });

  it('カテゴリーは決まった6つだけ。タイトルは 1〜200 文字。日付は Timestamp', async () => {
    const db = as('bob');
    for (const category of ['food', 'dailyGoods', 'diningOut', 'transport', 'subscription', 'other']) {
      await assertSucceeds(setDoc(doc(db, path(ID1)), expense('bob', { category })), category);
      await testEnv.withSecurityRulesDisabled(async (context) => deleteDoc(doc(context.firestore(), path(ID1))));
    }
    for (const category of ['medical', 'Food', '', null]) {
      await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { category })), String(category));
    }
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { title: '' })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { title: 'あ'.repeat(201) })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { title: 1200 })));
    await assertSucceeds(setDoc(doc(db, path(ID1)), expense('bob', { title: 'あ'.repeat(200) })));
    for (const date of ['2026-11-01', 1793500000, null]) {
      await assertFails(setDoc(doc(db, path(ID2)), expense('bob', { date })), String(date));
    }
  });

  it('作成者・更新者は操作した本人。作成日時・更新日時はサーバーの時刻。schemaVersion は 1', async () => {
    const db = as('bob');
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { createdBy: 'alice' })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { updatedBy: 'alice' })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('mallory')));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { createdAt: Timestamp.now() })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { updatedAt: Timestamp.now() })));
    await assertFails(setDoc(doc(db, path(ID1)), expense('bob', { schemaVersion: 2 })));
    const { schemaVersion, ...withoutVersion } = expense('bob');
    assert.equal(schemaVersion, 1);
    await assertFails(setDoc(doc(db, path(ID1)), withoutVersion));
    await assertSucceeds(setDoc(doc(db, path(ID1)), expense('bob')));
    await assertFails(updateDoc(doc(db, path(ID1)), { amount: 10, updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, path(ID1)), { amount: 10, updatedBy: 'bob', updatedAt: Timestamp.now() }));
  });

  it('作成の情報（作成者・作成日時・schemaVersion）は、あとから改ざんできない', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), path(ID1)), expense('bob')));
    const alice = as('alice');
    await assertFails(updateDoc(doc(alice, path(ID1)), { createdBy: 'alice', updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice, path(ID1)), { createdAt: serverTimestamp(), updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice, path(ID1)), { createdAt: Timestamp.now(), updatedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice, path(ID1)), { schemaVersion: 2, updatedBy: 'alice', updatedAt: serverTimestamp() }));
    // 同じ ID の作り直し（上書き）でも、作成の情報は変えられない
    await assertFails(setDoc(doc(alice, path(ID1)), expense('alice')));
  });

  it('決まっていない項目（レシート・メモ・予算・メール・端末・持ち主の印）を足せない', async () => {
    const db = as('bob');
    for (const extra of [
      { receiptImage: 'data' }, { receiptURL: 'https://example.com/r.jpg' }, { memo: '個人のメモ' }, { budget: 100000 },
      { email: 'a@example.com' }, { deviceID: 'install-1' }, { ownership: 'personal' }, { kind: 'todo' },
    ]) {
      await assertFails(setDoc(doc(db, path(ID1)), expense('bob', extra)), JSON.stringify(extra));
    }
    await assertSucceeds(setDoc(doc(db, path(ID1)), expense('bob')));
    await assertFails(updateDoc(doc(db, path(ID1)), { memo: 'メモ', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, path(ID1)), { receiptImage: 'x', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    // 支出の下にさらに置くこともできない（レシートの場所を作れない）
    await assertFails(setDoc(doc(db, `${path(ID1)}/receipts/r1`), { image: 'x' }));
  });

  it('文書の ID は支出の UUID だけ（自動の ID・決まっていない形は拒否）', async () => {
    const db = as('bob');
    for (const id of ['expense-1', 'abc', '12345678-1234-1234-1234-12345678901']) {
      await assertFails(setDoc(doc(db, `groups/${GROUP}/expenses/${id}`), expense('bob')), id);
    }
    await assertSucceeds(setDoc(doc(db, path(ID3.toLowerCase())), expense('bob')));
  });

  it('共有 ToDo・買い物の権限は変わらない（支出の形では items に書けない。items の形では expenses に書けない）', async () => {
    const bob = as('bob');
    await assertSucceeds(setDoc(doc(bob, `groups/${GROUP}/items/after-expense`), sharedItem('bob')));
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/money-1`), expense('bob')));
    await assertFails(setDoc(doc(bob, path(ID1)), sharedItem('bob')));
    await assertFails(setDoc(doc(as('mallory'), `groups/${GROUP}/items/m-x`), sharedItem('mallory')));
    // 家計簿をオンにしても、items に money の種類は作れない
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/k-money-2`), { ...sharedItem('bob'), kind: 'money' }));
    // アプリから sharedKinds は変えられない（家計簿のオン・オフも updateHousehold だけ）
    await assertFails(updateDoc(doc(as('alice'), `groups/${GROUP}`), { sharedKinds: ['money'], updatedAt: serverTimestamp() }));
  });
});

// MARK: - 共有の通知の端末（2026-10-28 Build 8）。docs/SHARED_PUSH_NOTIFICATIONS.md

describe('共有の通知の端末（Build 8）', () => {
  const DEVICE_ID = '6F1C2B7E-3D4A-4C5B-9E8F-0A1B2C3D4E5F';
  const device = (overrides = {}) => ({
    fcmToken: 'fcm-token_abc:DEF-123', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true,
    showsPreview: false, updatedAt: serverTimestamp(), ...overrides,
  });

  it('自分の端末だけ作成・更新（トークンの更新・項目名の表示の切り替え）・削除できる', async () => {
    const ref = doc(as('alice'), `users/alice/devices/${DEVICE_ID}`);
    await assertSucceeds(setDoc(ref, device()));
    await assertSucceeds(setDoc(ref, device({ fcmToken: 'fcm-token-new' })));
    await assertSucceeds(setDoc(ref, device({ showsPreview: true })));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(deleteDoc(ref));
  });

  it('他人の端末は読めない・書けない・消せない', async () => {
    await assertFails(setDoc(doc(as('bob'), `users/alice/devices/${DEVICE_ID}`), device()));
    await assertFails(getDoc(doc(as('alice'), 'users/bob/devices/device-1')));
    await assertFails(updateDoc(doc(as('alice'), 'users/bob/devices/device-1'), { showsPreview: true, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(as('alice'), 'users/bob/devices/device-1')));
    await assertFails(getDocs(collection(as('alice'), 'users/bob/devices')));
  });

  it('サインインしていなければ、作成・読み取り・削除できない', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, `users/alice/devices/${DEVICE_ID}`), device()));
    await assertFails(getDoc(doc(anon, 'users/bob/devices/device-1')));
    await assertFails(deleteDoc(doc(anon, 'users/bob/devices/device-1')));
  });

  it('決まっていない項目（UID・メール・項目名・端末の名前など）を足せない', async () => {
    const db = as('alice');
    for (const [key, value] of [['uid', 'alice'], ['email', 'a@example.com'], ['itemTitle', '洗剤'], ['deviceName', 'iPhone'], ['advertisingID', 'x']]) {
      await assertFails(setDoc(doc(db, `users/alice/devices/${DEVICE_ID}`), device({ [key]: value })), key);
    }
  });

  it('型・長さ・形が正しくなければ拒否（トークン・設定・端末・時刻・端末 ID）', async () => {
    const db = as('alice');
    const ref = doc(db, `users/alice/devices/${DEVICE_ID}`);
    await assertFails(setDoc(ref, device({ fcmToken: '' })));
    await assertFails(setDoc(ref, device({ fcmToken: 'a'.repeat(4097) })));
    await assertFails(setDoc(ref, device({ fcmToken: 'token with space' })));
    await assertFails(setDoc(ref, device({ fcmToken: 123 })));
    await assertFails(setDoc(ref, device({ platform: 'android' })));
    await assertFails(setDoc(ref, device({ notificationsEnabled: 'yes' })));
    await assertFails(setDoc(ref, device({ sharedUpdatesEnabled: 1 })));
    await assertFails(setDoc(ref, device({ showsPreview: 'true' })));
    await assertFails(setDoc(ref, device({ updatedAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')) })));
    const { fcmToken, ...withoutToken } = device();
    assert.equal(typeof fcmToken, 'string');
    await assertFails(setDoc(ref, withoutToken));
    await assertFails(setDoc(doc(db, `users/alice/devices/${'x'.repeat(129)}`), device()));
    await assertFails(setDoc(doc(db, 'users/alice/devices/bad id'), device()));
  });

  it('端末の情報からは、共有項目・メンバーの権限は広がらない', async () => {
    await assertSucceeds(setDoc(doc(as('mallory'), `users/mallory/devices/${DEVICE_ID}`), device()));
    await assertFails(getDocs(collection(as('mallory'), `groups/${GROUP}/items`)));
    await assertFails(getDocs(collectionGroup(as('mallory'), 'devices')));
  });
});

// MARK: - Build 9（2026-10-28）：オーナー・パートナーの両方が共有 ToDo・買い物を作成・更新できる。docs/PARTNER_SHARED_ITEM_SYNC_FIX.md

describe('Build 9：オーナーとパートナーの共有項目の権限', () => {
  const item = (uid, kind = 'todo') => ({ ...sharedItem(uid), kind, title: kind === 'todo' ? '書類を出す' : '洗剤を買う' });

  for (const [who, role] of [['alice', 'owner'], ['bob', 'member']]) {
    it(`${role}（${who}）は、自分を作成者・更新者にした ToDo・買い物を作成・更新できる`, async () => {
      const db = as(who);
      for (const kind of ['todo', 'shopping']) {
        const path = `groups/${GROUP}/items/${role}-${kind}`;
        await assertSucceeds(setDoc(doc(db, path), item(who, kind)));
        await assertSucceeds(updateDoc(doc(db, path), { title: `${kind}（変更）`, updatedBy: who, updatedAt: serverTimestamp() }));
        await assertSucceeds(updateDoc(doc(db, path), { isCompleted: true, updatedBy: who, updatedAt: serverTimestamp() }));
      }
    });

    it(`${role}（${who}）は、相手が作った共有項目を更新できる（更新者は自分）`, async () => {
      const other = who === 'alice' ? 'bob' : 'alice';
      const path = `groups/${GROUP}/items/by-${other}`;
      await assertSucceeds(setDoc(doc(as(other), path), item(other, 'shopping')));
      await assertSucceeds(updateDoc(doc(as(who), path), { title: '低脂肪牛乳を買う', updatedBy: who, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as(who), path), { title: 'x', updatedBy: other, updatedAt: serverTimestamp() }), '更新者を相手にできない');
    });

    it(`${role}（${who}）は、作成者・更新者を別人の UID にできない`, async () => {
      const db = as(who);
      const other = who === 'alice' ? 'bob' : 'alice';
      await assertFails(setDoc(doc(db, `groups/${GROUP}/items/${role}-spoof-1`), { ...item(who), createdBy: other }));
      await assertFails(setDoc(doc(db, `groups/${GROUP}/items/${role}-spoof-2`), { ...item(who), updatedBy: other }));
      await assertFails(setDoc(doc(db, `groups/${GROUP}/items/${role}-spoof-3`), item('mallory')));
    });
  }

  it('メンバーでない人・サインインしていない人は作成・更新できない', async () => {
    await assertFails(setDoc(doc(as('mallory'), `groups/${GROUP}/items/m-1`), item('mallory')));
    await assertFails(updateDoc(doc(as('mallory'), `groups/${GROUP}/items/item-1`), { title: 'x', updatedBy: 'mallory', updatedAt: serverTimestamp() }));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, `groups/${GROUP}/items/anon-9`), item('anon')));
  });

  it('通知の端末を登録したあとも、共有項目の権限は変わらない（パートナーは作成でき、メンバーでない人はできない）', async () => {
    const device = { fcmToken: 'fcm-token-bob', platform: 'ios', notificationsEnabled: true, sharedUpdatesEnabled: true, showsPreview: true, updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(as('bob'), 'users/bob/devices/install-bob'), device));
    await assertSucceeds(setDoc(doc(as('alice'), 'users/alice/devices/install-alice'), { ...device, fcmToken: 'fcm-token-alice' }));
    await assertSucceeds(setDoc(doc(as('bob'), `groups/${GROUP}/items/after-device`), item('bob', 'shopping')));
    await assertSucceeds(getDocs(collection(as('alice'), `groups/${GROUP}/items`)));
    await assertFails(setDoc(doc(as('mallory'), `groups/${GROUP}/items/after-device-m`), item('mallory')));
  });

  it('断られた書き込みは保存されない（通知の処理は動かない）', async () => {
    await assertFails(setDoc(doc(as('mallory'), `groups/${GROUP}/items/rejected-1`), item('mallory')));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      assert.equal((await getDoc(doc(context.firestore(), `groups/${GROUP}/items/rejected-1`))).exists(), false);
    });
  });
});

// MARK: - 共有の予定（2026-11-01 Build 14）。docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md

describe('Build 14：カレンダーから共有する予定（groups/{groupID}/items の kind: event）', () => {
  const EVENT_ID = '0B6A3C1E-7F52-4C1D-9C77-2E0D8A7B5F11';
  const eventPath = (id = EVENT_ID) => `groups/${GROUP}/items/${id}`;

  /** カレンダーの「予定を追加」で送る形（アプリの SharedItemPayload.createFields と同じ項目） */
  function sharedEvent(uid, time = serverTimestamp()) {
    return {
      schemaVersion: 1,
      title: '歯医者',
      kind: 'event',
      date: Timestamp.fromDate(new Date('2026-11-05T10:30:00+09:00')),
      hasTime: true,
      isCompleted: false,
      assigneeUID: null,
      createdBy: uid,
      updatedBy: uid,
      createdAt: time,
      updatedAt: time,
    };
  }

  async function setSharedKinds(kinds) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: kinds });
    });
  }

  it('予定がオフ（はじめの設定：ToDo・買い物だけ）なら、予定を新しく共有できない。ToDo・買い物は作れる', async () => {
    const bob = as('bob');
    await assertFails(setDoc(doc(bob, eventPath()), sharedEvent('bob')));
    await assertSucceeds(setDoc(doc(bob, `groups/${GROUP}/items/todo-while-event-off`), sharedItem('bob')));
  });

  it('予定がオンなら、オーナーもパートナーも予定を作れる。終日の予定も作れる', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    await assertSucceeds(setDoc(doc(as('alice'), eventPath()), sharedEvent('alice')));
    const allDay = { ...sharedEvent('bob'), hasTime: false, date: Timestamp.fromDate(new Date('2026-11-06T00:00:00+09:00')) };
    await assertSucceeds(setDoc(doc(as('bob'), eventPath('1C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F')), allDay));
  });

  it('作った予定は相手にも見え、相手も削除できる', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    await assertSucceeds(setDoc(doc(as('alice'), eventPath()), sharedEvent('alice')));
    const seen = await getDoc(doc(as('bob'), eventPath()));
    assert.equal(seen.data().title, '歯医者');
    assert.equal(seen.data().kind, 'event');
    await assertSucceeds(deleteDoc(doc(as('bob'), eventPath())));
    assert.equal((await getDoc(doc(as('alice'), eventPath()))).exists(), false);
  });

  it('予定をオフにしたあとも、すでにある共有の予定は残り、削除できる（新しくは作れない）', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    await assertSucceeds(setDoc(doc(as('alice'), eventPath()), sharedEvent('alice')));
    await setSharedKinds(['todo', 'shopping']);
    assert.equal((await getDoc(doc(as('bob'), eventPath()))).exists(), true, 'オフにしても勝手に消えない');
    await assertFails(setDoc(doc(as('bob'), eventPath('2D3E4F5A-6B7C-4D8E-9F0A-1B2C3D4E5F60')), sharedEvent('bob')));
    await assertSucceeds(deleteDoc(doc(as('bob'), eventPath())));
  });

  it('作成者・更新者は本人、作成日時・更新日時はサーバーの時刻（端末の時刻・他人の UID は拒否）', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    const bob = as('bob');
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), createdBy: 'alice' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), updatedBy: 'alice' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), createdAt: Timestamp.now() }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), updatedAt: Timestamp.now() }));
    await assertSucceeds(setDoc(doc(bob, eventPath()), sharedEvent('bob')));
  });

  it('形を厳しく確かめる（タイトル 1〜200 文字・日付は Timestamp・終日／時刻は bool・schemaVersion 1）', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    const bob = as('bob');
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), title: '' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), title: 'あ'.repeat(201) }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), date: '2026-11-05' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), hasTime: 'true' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), schemaVersion: 2 }));
    const { date, ...withoutDate } = sharedEvent('bob');
    assert.ok(date);
    await assertFails(setDoc(doc(bob, eventPath()), withoutDate));
    await assertSucceeds(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), title: 'あ'.repeat(200) }));
  });

  it('予定は、完了済み・担当あり・あとで／もうやらないの印つきでは作れない', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    const bob = as('bob');
    const later = Timestamp.fromDate(new Date('2026-11-07T00:00:00+09:00'));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), isCompleted: true }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), assigneeUID: 'alice' }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), deferredTo: later }));
    await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), droppedAt: later }));
    await assertSucceeds(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), deferredTo: null, droppedAt: null }));
  });

  it('メモ・場所・メールアドレス・端末・通知トークン・外部カレンダーの情報は書けない', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    const bob = as('bob');
    const extras = [
      { memo: '個人のメモ' }, { note: 'メモ' }, { location: '駅前クリニック' }, { email: 'bob@example.com' },
      { deviceID: 'device-1' }, { fcmToken: 'token' }, { calendarIdentifier: 'ek-1' }, { externalID: 'x' },
      { ownership: 'personal' }, { softTime: 'morning' },
    ];
    for (const extra of extras) {
      await assertFails(setDoc(doc(bob, eventPath()), { ...sharedEvent('bob'), ...extra }), JSON.stringify(Object.keys(extra)));
    }
  });

  it('同じ UUID の作成をくり返しても、2件目はできない（重ならない）', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    const bob = as('bob');
    await assertSucceeds(setDoc(doc(bob, eventPath()), sharedEvent('bob')));
    await assertFails(setDoc(doc(bob, eventPath()), sharedEvent('bob')));
    const all = await getDocs(collection(bob, `groups/${GROUP}/items`));
    assert.equal(all.docs.filter((d) => d.id === EVENT_ID).length, 1);
  });

  it('メンバーでない人・サインインしていない人は、予定を読めず、作れず、消せない', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    await assertSucceeds(setDoc(doc(as('alice'), eventPath()), sharedEvent('alice')));
    const mallory = as('mallory');
    await assertFails(getDoc(doc(mallory, eventPath())));
    await assertFails(setDoc(doc(mallory, eventPath('3E4F5A6B-7C8D-4E9F-8A0B-1C2D3E4F5A6B')), sharedEvent('mallory')));
    await assertFails(deleteDoc(doc(mallory, eventPath())));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, eventPath())));
    await assertFails(setDoc(doc(anon, eventPath('4F5A6B7C-8D9E-4F0A-9B1C-2D3E4F5A6B7C')), sharedEvent('anon')));
    await assertFails(deleteDoc(doc(anon, eventPath())));
    assert.equal((await getDoc(doc(as('alice'), eventPath()))).exists(), true);
  });

  it('退出した人は、予定を読めず、作れず、消せない', async () => {
    await setSharedKinds(['event', 'todo', 'shopping']);
    await assertSucceeds(setDoc(doc(as('alice'), eventPath()), sharedEvent('alice')));
    await removeMemberAsServer('bob');
    const bob = as('bob');
    await assertFails(getDoc(doc(bob, eventPath())));
    await assertFails(setDoc(doc(bob, eventPath('5A6B7C8D-9E0F-4A1B-8C2D-3E4F5A6B7C8D')), sharedEvent('bob')));
    await assertFails(deleteDoc(doc(bob, eventPath())));
  });

  it('予定の種類はあとから変えられない。ToDo・買い物・家計簿の権限は緩まない（家事・支出は items に作れない）', async () => {
    await setSharedKinds(['event', 'todo', 'chore', 'shopping', 'money']);
    const bob = as('bob');
    await assertSucceeds(setDoc(doc(bob, eventPath()), sharedEvent('bob')));
    await assertFails(updateDoc(doc(bob, eventPath()), { kind: 'todo', updatedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/chore-1`), { ...sharedItem('bob'), kind: 'chore' }));
    await assertFails(setDoc(doc(bob, `groups/${GROUP}/items/money-1`), { ...sharedItem('bob'), kind: 'money' }));
    // ToDo の作成の決まりは変わらない（完了済み・担当ありでも ToDo なら作れる。これまでどおり）
    await assertSucceeds(setDoc(doc(bob, `groups/${GROUP}/items/todo-done`), { ...sharedItem('bob'), isCompleted: true, assigneeUID: 'alice' }));
  });
});

// MARK: - Build 21：共有の支出の商品明細（2026-11-08）。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md

describe('Build 21：共有の支出の商品明細（groups/{groupID}/expenseLineItems）', () => {
  const ID1 = 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F';
  const ID2 = '0F8FAD5B-D9CB-469F-A165-70867728950E';
  const ITEM1 = '7C9E6679-7425-40DE-944B-E07FC1F90AE7';
  const ITEM2 = '16FD2706-8BAF-433B-82EB-8C7FADA847DA';
  const TAB = '\t';
  const row = (...parts) => parts.join(TAB);
  /** アプリが作る1件（明細ID・商品名・数量・単価・金額） */
  const milk = row(ITEM1, '牛乳', '', '', '198');
  const tissue = row(ITEM2, 'ティッシュ', '2', '250', '500');
  const lineItems = (rows = [milk, tissue], overrides = {}) => ({ schemaVersion: 1, rows, ...overrides });
  const expensePath = (id) => `groups/${GROUP}/expenses/${id}`;
  const itemsPath = (id) => `groups/${GROUP}/expenseLineItems/${id}`;
  /** n 件の正しい行（明細ID は件ごとに変える） */
  const manyRows = (n) => Array.from({ length: n }, (_, i) => row(`00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, `商品${i + 1}`, '', '', String(i)));

  function expense(uid, overrides = {}) {
    return {
      schemaVersion: 1, title: 'スーパー', amount: 698, category: 'food',
      date: Timestamp.fromDate(new Date('2026-11-08T00:00:00+09:00')),
      createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
    };
  }

  /** 支出と商品明細を同じ書き込みで作る（アプリの「わが家で共有」の保存・自分だけからの変更と同じ） */
  async function createWithItems(db, uid, id = ID1, rows = [milk, tissue]) {
    const batch = writeBatch(db);
    batch.set(doc(db, expensePath(id)), expense(uid));
    batch.set(doc(db, itemsPath(id)), lineItems(rows));
    return batch.commit();
  }

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: ['todo', 'shopping', 'money'] });
    });
  });

  it('テスト10：メンバーは支出と一緒に明細を作れ、オーナーとパートナーの両方が読める（50件まで）', async () => {
    await assertSucceeds(createWithItems(as('alice'), 'alice'));
    const read = await getDoc(doc(as('bob'), itemsPath(ID1)));
    assert.deepEqual(read.data().rows, [milk, tissue]);
    assert.equal((await getDocs(collection(as('alice'), `groups/${GROUP}/expenseLineItems`))).size, 1);
    // パートナーが作った支出の明細もオーナーが読める。50件ちょうどまで置ける
    await assertSucceeds(createWithItems(as('bob'), 'bob', ID2, manyRows(50)));
    assert.equal((await getDoc(doc(as('alice'), itemsPath(ID2)))).data().rows.length, 50);
  });

  it('テスト11：サインインしていない人・メンバーでない人・退出した人は、読めず、作れず、変えられず、消せない', async () => {
    await assertSucceeds(createWithItems(as('alice'), 'alice'));
    const anon = testEnv.unauthenticatedContext().firestore();
    const mallory = as('mallory');
    for (const db of [anon, mallory]) {
      await assertFails(getDoc(doc(db, itemsPath(ID1))));
      await assertFails(getDocs(collection(db, `groups/${GROUP}/expenseLineItems`)));
      await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems([milk])));
      await assertFails(deleteDoc(doc(db, itemsPath(ID1))));
    }
    await assertFails(getDocs(collectionGroup(as('bob'), 'expenseLineItems')));
    await assertFails(getDocs(collection(as('bob'), `groups/${OTHER_GROUP}/expenseLineItems`)));
    await removeMemberAsServer('bob');
    await assertFails(getDoc(doc(as('bob'), itemsPath(ID1))));
    await assertFails(setDoc(doc(as('bob'), itemsPath(ID1)), lineItems([milk])));
    await assertFails(deleteDoc(doc(as('bob'), itemsPath(ID1))));
  });

  it('支出が無いところには明細を作れない（明細だけが残らない）。文書の ID は支出の UUID だけ', async () => {
    await assertFails(setDoc(doc(as('alice'), itemsPath(ID1)), lineItems()));
    for (const id of ['expense-1', 'abc']) {
      await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/expenseLineItems/${id}`), lineItems()), id);
    }
    // 支出のあとなら作れる（別々の書き込みでも、同じ書き込みでも）
    await assertSucceeds(setDoc(doc(as('alice'), expensePath(ID1)), expense('alice')));
    await assertSucceeds(setDoc(doc(as('bob'), itemsPath(ID1)), lineItems()));
    // 支出の下（サブコレクション）には置けない（これまでどおり）
    await assertFails(setDoc(doc(as('bob'), `${expensePath(ID1)}/lineItems/x`), lineItems()));
  });

  it('テスト3・12：決まっていない項目・51件・0件・形の違う行は拒否', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), expensePath(ID1)), expense('alice')));
    const db = as('bob');
    for (const extra of [{ ocrText: '全文' }, { receiptImage: 'x' }, { candidates: ['¥698'] }, { confidence: 0.9 }, { createdBy: 'bob' }, { email: 'a@example.com' }]) {
      await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems([milk], extra)), JSON.stringify(extra));
    }
    await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems(manyRows(51))), '51件');
    await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems([])), '0件');
    await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems([milk], { schemaVersion: 2 })), 'schemaVersion');
    await assertFails(setDoc(doc(db, itemsPath(ID1)), { schemaVersion: 1 }), 'rows が無い');
    await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems('牛乳')), 'rows がリストでない');
    for (const bad of [
      row(ITEM1, '', '', '', '198'),
      row(ITEM1, 'あ'.repeat(81), '', '', '198'),
      row(ITEM1, '牛乳', '0', '', '198'),
      row(ITEM1, '牛乳', '-1', '', '198'),
      row(ITEM1, '牛乳', '', '-1', '198'),
      row(ITEM1, '牛乳', '', '', '1000000000'),
      row(ITEM1, '牛乳', '', '', ''),
      row(ITEM1, '牛乳', '', '', '198', 'メモ'),
      row('item-1', '牛乳', '', '', '198'),
      { name: '牛乳', amount: 198 },
    ]) {
      // 50件の中の最後（50件目）に1件だけ混ぜても拒否する
      await assertFails(setDoc(doc(db, itemsPath(ID1)), lineItems([...manyRows(49), bad])), JSON.stringify(bad));
    }
    await assertSucceeds(setDoc(doc(db, itemsPath(ID1)), lineItems([milk, row(ITEM2, 'あ'.repeat(80), '1.5', '0', '0')])));
  });

  it('テスト13：明細が残っているあいだは支出を消せない。明細を先に消すか、同じ書き込みで消せば消せる', async () => {
    await assertSucceeds(createWithItems(as('alice'), 'alice'));
    // 古いアプリ（Build 20）と同じ「支出だけを消す」は断られる（明細だけが残らない）
    await assertFails(deleteDoc(doc(as('bob'), expensePath(ID1))));
    assert.equal((await getDoc(doc(as('bob'), expensePath(ID1)))).exists(), true);
    // 明細を先に消してから支出を消す（アプリの順番）
    await assertSucceeds(deleteDoc(doc(as('bob'), itemsPath(ID1))));
    await assertSucceeds(deleteDoc(doc(as('bob'), expensePath(ID1))));
    // 同じ書き込みで両方を消す
    await assertSucceeds(createWithItems(as('alice'), 'alice', ID2));
    // as() は呼ぶたびに別の Firestore を作るため、1つの書き込み（batch）の参照は同じ Firestore から作る
    const aliceDb = as('alice');
    const batch = writeBatch(aliceDb);
    batch.delete(doc(aliceDb, itemsPath(ID2)));
    batch.delete(doc(aliceDb, expensePath(ID2)));
    await assertSucceeds(batch.commit());
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      assert.equal((await getDocs(collection(db, `groups/${GROUP}/expenseLineItems`))).size, 0, '明細だけが残らない');
      assert.equal((await getDocs(collection(db, `groups/${GROUP}/expenses`))).size, 0);
    });
  });

  it('テスト15・16・17：同じ支出の明細は文書1つ（くり返しても重ならない）。修正・1件の削除・全部の削除ができる', async () => {
    await assertSucceeds(createWithItems(as('alice'), 'alice'));
    await assertSucceeds(setDoc(doc(as('alice'), itemsPath(ID1)), lineItems()));
    await assertSucceeds(setDoc(doc(as('alice'), itemsPath(ID1)), lineItems()));
    assert.equal((await getDocs(collection(as('bob'), `groups/${GROUP}/expenseLineItems`))).size, 1);
    // パートナーが1件を直す・1件を消す
    await assertSucceeds(setDoc(doc(as('bob'), itemsPath(ID1)), lineItems([row(ITEM1, '低脂肪牛乳', '1', '200', '200'), tissue])));
    await assertSucceeds(setDoc(doc(as('bob'), itemsPath(ID1)), lineItems([tissue])));
    assert.deepEqual((await getDoc(doc(as('alice'), itemsPath(ID1)))).data().rows, [tissue]);
    // 最後の1件を消す＝明細の文書を消す
    await assertSucceeds(deleteDoc(doc(as('alice'), itemsPath(ID1))));
    // 共有から自分だけへ：同じ書き込みで、明細と支出を消す（端末へは先に保存している）
    await assertSucceeds(createWithItems(as('bob'), 'bob', ID2));
    // 1つの書き込み（batch）の参照は同じ Firestore から作る（as() は呼ぶたびに別の Firestore）
    const bobDb = as('bob');
    const batch = writeBatch(bobDb);
    batch.delete(doc(bobDb, itemsPath(ID2)));
    batch.delete(doc(bobDb, expensePath(ID2)));
    await assertSucceeds(batch.commit());
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      assert.equal((await getDoc(doc(db, itemsPath(ID2)))).exists(), false, '明細だけが残らない');
      assert.equal((await getDoc(doc(db, expensePath(ID2)))).exists(), false);
    });
  });

  it('支出そのものの決まりは変わらない（9項目だけ・明細の項目を支出に足せない）', async () => {
    await assertFails(setDoc(doc(as('alice'), expensePath(ID1)), expense('alice', { rows: [milk] })));
    await assertFails(setDoc(doc(as('alice'), expensePath(ID1)), expense('alice', { lineItems: [milk] })));
    await assertSucceeds(setDoc(doc(as('alice'), expensePath(ID1)), expense('alice')));
    // 明細の無い支出は、これまでどおりメンバーが消せる
    await assertSucceeds(deleteDoc(doc(as('bob'), expensePath(ID1))));
  });
});

describe('Build 24：わが家の月の予算（groups/{groupID}/monthlyBudgets）', () => {
  const MONTH = '2026-11';
  const budgetPath = (key = MONTH, group = GROUP) => `groups/${group}/monthlyBudgets/${key}`;
  /** アプリ（SharedMonthlyBudgetPayload）が作る形。変えた人は本人・変えた日時はサーバーの時刻 */
  function budget(uid, overrides = {}, key = MONTH) {
    return {
      schemaVersion: 1, monthKey: key, totalAmount: 120000, categoryAmounts: { food: 40000, dailyGoods: 0 },
      updatedBy: uid, updatedAt: serverTimestamp(), ...overrides,
    };
  }

  async function setMoney(on) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: on ? ['todo', 'shopping', 'money'] : ['todo', 'shopping'] });
    });
  }

  beforeEach(async () => {
    await setMoney(true);
  });

  it('テスト3・4：オーナーが保存した予算をパートナーが読める。パートナーも変えられる（変えた人は本人）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice')));
    const read = await getDoc(doc(as('bob'), budgetPath()));
    assert.equal(read.data().totalAmount, 120000);
    assert.deepEqual(read.data().categoryAmounts, { food: 40000, dailyGoods: 0 });
    await assertSucceeds(setDoc(doc(as('bob'), budgetPath()), budget('bob', { totalAmount: 150000 })));
    assert.equal((await getDoc(doc(as('alice'), budgetPath()))).data().totalAmount, 150000);
    assert.equal((await getDocs(collection(as('alice'), `groups/${GROUP}/monthlyBudgets`))).size, 1);
    // 別人を「変えた人」にできない
    await assertFails(setDoc(doc(as('bob'), budgetPath()), budget('alice')));
    // 変えた日時は端末の時刻にできない
    await assertFails(setDoc(doc(as('bob'), budgetPath()), budget('bob', { updatedAt: Timestamp.now() })));
  });

  it('テスト5・39：サインインしていない人・メンバーでない人・退出した人は、読めず、作れず、変えられず、消せない', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice')));
    const anon = testEnv.unauthenticatedContext().firestore();
    for (const db of [anon, as('mallory')]) {
      await assertFails(getDoc(doc(db, budgetPath())));
      await assertFails(getDocs(collection(db, `groups/${GROUP}/monthlyBudgets`)));
      await assertFails(setDoc(doc(db, budgetPath()), budget('mallory')));
      await assertFails(deleteDoc(doc(db, budgetPath())));
    }
    await removeMemberAsServer('bob');
    await assertFails(getDoc(doc(as('bob'), budgetPath())));
    await assertFails(getDocs(collection(as('bob'), `groups/${GROUP}/monthlyBudgets`)));
    await assertFails(setDoc(doc(as('bob'), budgetPath()), budget('bob')));
    await assertFails(deleteDoc(doc(as('bob'), budgetPath())));
  });

  it('テスト6：ほかのわが家の予算は読めず、書けない（まとめての読み取りもできない）', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), budgetPath(MONTH, OTHER_GROUP)), { ...budget('mallory'), updatedAt: Timestamp.now() });
    });
    await assertFails(getDoc(doc(as('alice'), budgetPath(MONTH, OTHER_GROUP))));
    await assertFails(getDocs(collection(as('alice'), `groups/${OTHER_GROUP}/monthlyBudgets`)));
    await assertFails(setDoc(doc(as('alice'), budgetPath(MONTH, OTHER_GROUP)), budget('alice')));
    await assertFails(getDocs(collectionGroup(as('alice'), 'monthlyBudgets')));
  });

  it('テスト7：月のキーの形（YYYY-MM・2000〜2099年）と、文書の ID と monthKey が同じこと', async () => {
    for (const key of ['2026-13', '2026-00', '2026-1', '1999-12', '2100-01', 'abcd-ef', '2026-11-01']) {
      await assertFails(setDoc(doc(as('alice'), budgetPath(key)), budget('alice', {}, key)));
    }
    await assertFails(setDoc(doc(as('alice'), budgetPath('2026-12')), budget('alice', {}, '2026-11')), '文書の ID と違う月');
    for (const key of ['2026-01', '2026-12', '2028-02', '2000-01', '2099-12']) {
      await assertSucceeds(setDoc(doc(as('alice'), budgetPath(key)), budget('alice', {}, key)));
    }
  });

  it('テスト8・9：金額の下限・上限。負の数・小数・文字は拒否（未設定と 0 円は別）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice', { totalAmount: 1, categoryAmounts: {} })));
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice', { totalAmount: 999999999, categoryAmounts: { food: 999999999 } })));
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice', { categoryAmounts: { food: 0 } })), 'カテゴリーは 0 円も設定できる');
    for (const totalAmount of [0, -1, 1000000000, 1.5, '120000', null]) {
      await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { totalAmount, categoryAmounts: {} })), `月の予算 ${totalAmount}`);
    }
    for (const amount of [-1, 1000000000, 1.5, '1000', null, true]) {
      await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { categoryAmounts: { food: amount } })), `カテゴリー ${amount}`);
    }
    await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { categoryAmounts: [40000] })), 'カテゴリーは map だけ');
  });

  it('テスト10・11：決まっていない項目・決まっていないカテゴリーは拒否。項目が足りなくても拒否', async () => {
    for (const extra of [{ createdAt: serverTimestamp() }, { createdBy: 'alice' }, { email: 'a@example.com' }, { personalBudget: 1000 }, { memo: 'メモ' }]) {
      await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', extra)), Object.keys(extra)[0]);
    }
    for (const missing of ['schemaVersion', 'monthKey', 'totalAmount', 'categoryAmounts', 'updatedBy', 'updatedAt']) {
      const data = budget('alice');
      delete data[missing];
      await assertFails(setDoc(doc(as('alice'), budgetPath()), data), missing);
    }
    await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { schemaVersion: 2 })));
    await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { categoryAmounts: { travel: 1000 } })), '決まっていないカテゴリー');
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice', {
      categoryAmounts: { food: 1, dailyGoods: 1, diningOut: 1, transport: 1, subscription: 1, other: 1 },
    })), '6つのカテゴリーすべて');
  });

  it('テスト12：カテゴリーの予算の合計は月の予算以下（同じなら通る・超えれば拒否）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice', { totalAmount: 100000, categoryAmounts: { food: 60000, other: 40000 } })));
    await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', { totalAmount: 100000, categoryAmounts: { food: 60000, other: 40001 } })));
    await assertFails(setDoc(doc(as('alice'), budgetPath()), budget('alice', {
      totalAmount: 999999999,
      categoryAmounts: { food: 999999999, dailyGoods: 999999999, diningOut: 999999999, transport: 999999999, subscription: 999999999, other: 999999999 },
    })), '大きな合計でも数えられる（あふれない）');
  });

  it('テスト14・家計簿オフ：家計簿がオフなら新しく作れない。すでにある予算は変えられ、解除できる（共有の支出と同じ）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), budgetPath()), budget('alice')));
    await setMoney(false);
    await assertFails(setDoc(doc(as('alice'), budgetPath('2026-12')), budget('alice', {}, '2026-12')), '新しい月は作れない');
    await assertSucceeds(setDoc(doc(as('bob'), budgetPath()), budget('bob', { totalAmount: 90000, categoryAmounts: {} })));
    await assertSucceeds(deleteDoc(doc(as('bob'), budgetPath())));
    assert.equal((await getDoc(doc(as('alice'), budgetPath()))).exists(), false);
  });

  it('予算の決まりは、ほかの場所の権限を広げない（支出・明細に予算の形を書けない）', async () => {
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/expenses/E621E1F8-C36C-495A-93FC-0C247A3E6E5F`), budget('alice')));
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/expenseLineItems/E621E1F8-C36C-495A-93FC-0C247A3E6E5F`), budget('alice')));
    await assertFails(setDoc(doc(as('alice'), `users/alice/monthlyBudgets/${MONTH}`), budget('alice')), '自分だけの予算の置き場所は無い');
  });
});

describe('Build 25：わが家で共有の定期支出（groups/{groupID}/recurringExpenses・recurringExpenseOccurrences）', () => {
  const TEMPLATE = 'D3B07384-D113-4EC5-A2A8-1A0F8E2B5C11';
  const EXPENSE_A = '0F8FAD5B-D9CB-469F-A165-70867728950E';
  const EXPENSE_B = '7C9E6679-7425-40DE-944B-E07FC1F90AE7';
  const MONTH = '2026-11';
  const templatePath = (id = TEMPLATE, group = GROUP) => `groups/${group}/recurringExpenses/${id}`;
  const occurrencePath = (month = MONTH, id = TEMPLATE, group = GROUP) => `groups/${group}/recurringExpenseOccurrences/${id}_${month}`;
  const expensePath = (id, group = GROUP) => `groups/${group}/expenses/${id}`;

  /** アプリ（SharedRecurringExpensePayload）が作る形：11項目。作成者・変えた人は本人・日時はサーバーの時刻 */
  function template(uid, overrides = {}) {
    return {
      schemaVersion: 1, title: '家賃', expectedAmount: 85000, category: 'other', dueDay: 27, startMonthKey: MONTH, isActive: true,
      createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
    };
  }

  /** 設定を変えるときに送る項目（作成者・作成日時・schemaVersion は送らない） */
  function templateUpdate(uid, overrides = {}) {
    return {
      title: '家賃', expectedAmount: 86000, category: 'other', dueDay: 27, startMonthKey: MONTH, isActive: true,
      updatedBy: uid, updatedAt: serverTimestamp(), ...overrides,
    };
  }

  /** 月ごとの状態：7項目 */
  function occurrence(uid, status, expenseID, overrides = {}, month = MONTH) {
    return {
      schemaVersion: 1, templateID: TEMPLATE, monthKey: month, status, expenseID, processedBy: uid, processedAt: serverTimestamp(), ...overrides,
    };
  }

  function expense(uid, overrides = {}) {
    return {
      schemaVersion: 1, title: '家賃', amount: 85000, category: 'other',
      date: Timestamp.fromDate(new Date('2026-11-27T00:00:00+09:00')),
      createdBy: uid, updatedBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
    };
  }

  /** アプリの「今月分を追加」と同じ：共有の支出と「追加済み」を1回の書き込みで */
  function addThisMonth(db, uid, expenseID, month = MONTH) {
    const batch = writeBatch(db);
    batch.set(doc(db, expensePath(expenseID)), expense(uid));
    batch.set(doc(db, occurrencePath(month)), occurrence(uid, 'created', expenseID, {}, month));
    return batch.commit();
  }

  async function setMoney(on) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `groups/${GROUP}`), { sharedKinds: on ? ['todo', 'shopping', 'money'] : ['todo', 'shopping'] });
    });
  }

  async function count(path) {
    let size = 0;
    await testEnv.withSecurityRulesDisabled(async (context) => {
      size = (await getDocs(collection(context.firestore(), path))).size;
    });
    return size;
  }

  beforeEach(async () => {
    await setMoney(true);
  });

  it('テスト3・4：オーナーが作った設定をパートナーが読め、編集・停止・再開できる（作成者・作成日時は変えられない）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    const read = await getDoc(doc(as('bob'), templatePath()));
    assert.equal(read.data().title, '家賃');
    assert.equal(read.data().expectedAmount, 85000);
    assert.deepEqual(Object.keys(read.data()).sort(), [
      'category', 'createdAt', 'createdBy', 'dueDay', 'expectedAmount', 'isActive', 'schemaVersion', 'startMonthKey', 'title', 'updatedAt', 'updatedBy',
    ], '11項目だけ');
    await assertSucceeds(updateDoc(doc(as('bob'), templatePath()), templateUpdate('bob')));
    await assertSucceeds(updateDoc(doc(as('bob'), templatePath()), templateUpdate('bob', { isActive: false })), '停止');
    await assertSucceeds(updateDoc(doc(as('alice'), templatePath()), templateUpdate('alice', { isActive: true, startMonthKey: '2027-01' })), '再開');
    await assertFails(updateDoc(doc(as('bob'), templatePath()), { ...templateUpdate('bob'), createdBy: 'bob' }), '作成者は変えられない');
    await assertFails(updateDoc(doc(as('bob'), templatePath()), { ...templateUpdate('bob'), createdAt: serverTimestamp() }), '作成日時は変えられない');
    await assertFails(updateDoc(doc(as('bob'), templatePath()), { ...templateUpdate('bob'), schemaVersion: 2 }));
    await assertFails(updateDoc(doc(as('bob'), templatePath()), templateUpdate('alice')), '変えた人は本人');
    await assertFails(updateDoc(doc(as('bob'), templatePath()), templateUpdate('bob', { updatedAt: Timestamp.now() })), '端末の時刻は使えない');
    await assertFails(deleteDoc(doc(as('alice'), templatePath())), 'Build 25 では全部を消さない（停止だけ）');
  });

  it('テスト3：作成者・作成日時は本人・サーバーの時刻。文書の ID は UUID。決まった11項目だけ', async () => {
    await assertFails(setDoc(doc(as('alice'), templatePath()), template('bob')), '作成者は本人');
    await assertFails(setDoc(doc(as('alice'), templatePath()), template('alice', { createdAt: Timestamp.now() })));
    await assertFails(setDoc(doc(as('alice'), templatePath('rent')), template('alice')), '文書の ID は UUID');
    await assertFails(setDoc(doc(as('alice'), templatePath()), template('alice', { memo: '大家さん' })), '決まっていない項目');
    await assertFails(setDoc(doc(as('alice'), templatePath()), template('alice', { email: 'a@example.com' })));
    const missing = template('alice');
    delete missing.isActive;
    await assertFails(setDoc(doc(as('alice'), templatePath()), missing), '足りない項目');
    await assertFails(setDoc(doc(as('alice'), templatePath()), template('alice', { schemaVersion: 2 })));
  });

  it('テスト7・8・10：名前1〜80文字・改行なし、金額1〜999,999,999の整数、カテゴリー6つ、支払日1〜31、開始月2000-01〜2099-12', async () => {
    const id = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
    let n = 0;
    const ok = (overrides, note) => assertSucceeds(setDoc(doc(as('alice'), templatePath(id(++n))), template('alice', overrides)), note);
    const ng = (overrides, note) => assertFails(setDoc(doc(as('alice'), templatePath(id(++n))), template('alice', overrides)), note);
    await ok({ title: 'あ'.repeat(80) }, '80文字');
    await ok({ title: '👨‍👩‍👧 サブスク' }, '絵文字');
    await ng({ title: '' }, '空');
    await ng({ title: 'あ'.repeat(81) }, '81文字');
    await ng({ title: '家賃\n駐車場' }, '改行');
    await ng({ title: '家賃\t' }, '制御文字');
    await ng({ title: 85000 }, '文字ではない');
    await ok({ expectedAmount: 1 });
    await ok({ expectedAmount: 999999999 });
    await ng({ expectedAmount: 0 }, '0円');
    await ng({ expectedAmount: -1 }, '負');
    await ng({ expectedAmount: 1000000000 }, '上限超え');
    await ng({ expectedAmount: 1.5 }, '小数');
    await ng({ expectedAmount: '85000' }, '文字');
    await ok({ category: 'subscription' });
    await ng({ category: 'rent' }, '決まっていないカテゴリー');
    await ok({ dueDay: 1 });
    await ok({ dueDay: 31 });
    await ng({ dueDay: 0 });
    await ng({ dueDay: 32 });
    await ng({ dueDay: 27.5 });
    await ok({ startMonthKey: '2000-01' });
    await ok({ startMonthKey: '2099-12' });
    await ng({ startMonthKey: '1999-12' });
    await ng({ startMonthKey: '2100-01' });
    await ng({ startMonthKey: '2026-13' });
    await ng({ startMonthKey: '2026-1' });
    await ng({ isActive: 'true' }, '真偽値ではない');
  });

  it('テスト5・6：わが家に入っていない人・サインインしていない人・別のわが家の人は読み書きできない', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await assertSucceeds(addThisMonth(as('alice'), 'alice', EXPENSE_A));
    for (const db of [as('mallory'), testEnv.unauthenticatedContext().firestore()]) {
      await assertFails(getDoc(doc(db, templatePath())));
      await assertFails(getDocs(collection(db, `groups/${GROUP}/recurringExpenses`)));
      await assertFails(getDoc(doc(db, occurrencePath())));
      await assertFails(getDocs(collection(db, `groups/${GROUP}/recurringExpenseOccurrences`)));
      await assertFails(updateDoc(doc(db, templatePath()), templateUpdate('mallory')));
      await assertFails(setDoc(doc(db, occurrencePath('2026-12')), occurrence('mallory', 'skipped', null, {}, '2026-12')));
    }
    await assertFails(setDoc(doc(as('mallory'), templatePath(TEMPLATE, GROUP)), template('mallory')));
    await assertFails(getDocs(collectionGroup(as('alice'), 'recurringExpenses')));
    await assertFails(getDocs(collectionGroup(as('alice'), 'recurringExpenseOccurrences')));
    await assertFails(getDocs(collection(as('alice'), `groups/${OTHER_GROUP}/recurringExpenses`)));
    await assertFails(setDoc(doc(as('alice'), templatePath(TEMPLATE, OTHER_GROUP)), template('alice')), '別のわが家');
    // 退出した人（メンバー文書が無い）
    await removeMemberAsServer('bob');
    await assertFails(getDoc(doc(as('bob'), templatePath())));
    await assertFails(updateDoc(doc(as('bob'), templatePath()), templateUpdate('bob')));
  });

  it('家計簿がオフ：新しく作れない。すでにある設定は変えられる。「今月分を追加」は支出を作れないので断られる', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await setMoney(false);
    await assertFails(setDoc(doc(as('alice'), templatePath('00000000-0000-4000-8000-000000000001')), template('alice')), '新しく作れない');
    await assertSucceeds(updateDoc(doc(as('bob'), templatePath()), templateUpdate('bob', { isActive: false })));
    await assertFails(addThisMonth(as('alice'), 'alice', EXPENSE_A));
    assert.equal(await count(`groups/${GROUP}/expenses`), 0, '支出も作られない');
  });

  it('テスト22：「今月分を追加」は、共有の支出と「追加済み」を同じ書き込みで作る（片方だけは作れない）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    // 状態だけ（支出なし）は断られる
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'created', EXPENSE_A)), '支出を作らずに「追加済み」だけは置けない');
    // すでにある支出を「追加済み」にすることもできない（同じ書き込みで新しく作る支出だけ）
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), expensePath(EXPENSE_B)), expense('alice', { createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
    });
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'created', EXPENSE_B)), 'すでにある支出');
    // 一緒なら通る
    await assertSucceeds(addThisMonth(as('alice'), 'alice', EXPENSE_A));
    const read = (await getDoc(doc(as('bob'), occurrencePath()))).data();
    assert.equal(read.status, 'created');
    assert.equal(read.expenseID, EXPENSE_A);
    assert.deepEqual(Object.keys(read).sort(), ['expenseID', 'monthKey', 'processedAt', 'processedBy', 'schemaVersion', 'status', 'templateID'], '7項目だけ');
    assert.ok((await getDoc(doc(as('bob'), expensePath(EXPENSE_A)))).exists(), 'パートナーにも支出が見える');
  });

  it('テスト21：2台で同時に「今月分を追加」しても、支出も「追加済み」も1件だけ（2回目は全部が断られる）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await assertSucceeds(addThisMonth(as('alice'), 'alice', EXPENSE_A));
    await assertFails(addThisMonth(as('bob'), 'bob', EXPENSE_B), 'パートナーの2回目');
    await assertFails(addThisMonth(as('alice'), 'alice', EXPENSE_B), '同じ人の2回目（別の支出 ID）');
    assert.equal(await count(`groups/${GROUP}/expenses`), 1, '支出は1件だけ');
    assert.equal(await count(`groups/${GROUP}/recurringExpenseOccurrences`), 1);
    assert.equal((await getDoc(doc(as('bob'), expensePath(EXPENSE_B)))).exists(), false, '断られた書き込みの支出は残らない');
    // 「今月は追加しない」で上書きもできない
    await assertFails(setDoc(doc(as('bob'), occurrencePath()), occurrence('bob', 'skipped', null)));
  });

  it('テスト27・28：「追加済み」は変更も削除もできない。支出を消しても「追加済み」は残る（候補が戻らない）', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await assertSucceeds(addThisMonth(as('alice'), 'alice', EXPENSE_A));
    await assertFails(updateDoc(doc(as('alice'), occurrencePath()), { status: 'skipped', expenseID: null, processedBy: 'alice', processedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('bob'), occurrencePath()), { expenseID: EXPENSE_B, processedBy: 'bob', processedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(as('alice'), occurrencePath())), '追加済みは消せない');
    await assertFails(deleteDoc(doc(as('bob'), occurrencePath())));
    await assertSucceeds(deleteDoc(doc(as('bob'), expensePath(EXPENSE_A))), '支出は消せる');
    assert.equal((await getDoc(doc(as('alice'), occurrencePath()))).data().status, 'created', '追加済みのまま');
  });

  it('テスト25・26：「今月は追加しない」は支出を作らず、メンバーなら未確認に戻せる（消せる）。変更はできない', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await assertSucceeds(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'skipped', null)));
    assert.equal(await count(`groups/${GROUP}/expenses`), 0);
    await assertFails(setDoc(doc(as('bob'), occurrencePath()), occurrence('bob', 'skipped', null)), '上書き（変更）はできない');
    await assertSucceeds(deleteDoc(doc(as('bob'), occurrencePath())), 'パートナーも未確認に戻せる');
    assert.equal((await getDoc(doc(as('alice'), occurrencePath()))).exists(), false);
    // 戻したあとは「今月分を追加」できる
    await assertSucceeds(addThisMonth(as('bob'), 'bob', EXPENSE_A));
  });

  it('月ごとの状態の形：文書の ID は設定の ID と月・設定がある・処理した人は本人・日時はサーバー・skipped は null・created は UUID', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), templatePath()), template('alice')));
    await assertFails(setDoc(doc(as('alice'), occurrencePath('2026-12')), occurrence('alice', 'skipped', null)), '文書の ID と月が合わない');
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/recurringExpenseOccurrences/other_${MONTH}`), occurrence('alice', 'skipped', null)), '文書の ID と設定が合わない');
    await assertFails(setDoc(doc(as('alice'), occurrencePath(MONTH, '00000000-0000-4000-8000-000000000009')),
      occurrence('alice', 'skipped', null, { templateID: '00000000-0000-4000-8000-000000000009' })), '設定が無い');
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('bob', 'skipped', null)), '処理した人は本人');
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'skipped', null, { processedAt: Timestamp.now() })));
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'skipped', EXPENSE_A)), 'skipped は支出の ID を持たない');
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'paused', null)), '決まっていない状態');
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'skipped', null, { amount: 85000 })), '決まっていない項目');
    await assertFails(setDoc(doc(as('alice'), occurrencePath()), occurrence('alice', 'skipped', null, { schemaVersion: 2 })));
    const batch = writeBatch(as('alice'));
    batch.set(doc(as('alice'), expensePath('not-a-uuid')), expense('alice'));
    batch.set(doc(as('alice'), occurrencePath()), occurrence('alice', 'created', 'not-a-uuid'));
    await assertFails(batch.commit(), 'created の expenseID は UUID');
  });

  it('定期支出の決まりは、ほかの場所の権限を広げない（支出・予算・自分の場所に定期支出の形を書けない）', async () => {
    await assertFails(setDoc(doc(as('alice'), expensePath(EXPENSE_A)), template('alice')));
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/monthlyBudgets/${MONTH}`), template('alice')));
    await assertFails(setDoc(doc(as('alice'), `users/alice/recurringExpenses/${TEMPLATE}`), template('alice')), '自分だけの定期支出の置き場所は無い');
    await assertFails(setDoc(doc(as('alice'), `groups/${GROUP}/notificationLog/${TEMPLATE}`), template('alice')));
  });
});
