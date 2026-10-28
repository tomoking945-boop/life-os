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

  it('新しく作れるのは ToDo・買い物だけ（予定・家事は Build 7 では作れない）', async () => {
    const db = as('bob');
    await setSharedKinds(['event', 'todo', 'chore', 'shopping']);
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/k-todo`), sharedItem('bob')));
    await assertSucceeds(setDoc(doc(db, `groups/${GROUP}/items/k-shop`), { ...sharedItem('bob'), kind: 'shopping' }));
    await assertFails(setDoc(doc(db, `groups/${GROUP}/items/k-event`), { ...sharedItem('bob'), kind: 'event' }));
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
