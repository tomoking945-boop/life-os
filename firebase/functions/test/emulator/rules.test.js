'use strict';

/**
 * Firestore Security Rules のテスト（仕様 11「Rules Emulator」）。
 * Firestore Emulator が必要：firebase/functions で `npm run test:rules`（手順は docs/FIREBASE_SETUP.md）
 * 2026-10-20 の監査で追加したテストは、下の「監査（2026-10-20）」の各 describe（docs/FIRESTORE_SHARING_RULES_AUDIT.md）
 */

const fs = require('node:fs');
const path = require('node:path');
const { before, after, beforeEach, describe, it } = require('node:test');
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
    await setDoc(doc(db, `groups/${GROUP}`), { name: 'わが家', createdBy: 'alice', createdAt: now, updatedAt: now });
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

  it('自分は退出できるが、ほかの人は外せない', async () => {
    await assertFails(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/alice`)));
    await assertSucceeds(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/bob`)));
    // 退出したあとは読めない
    await assertFails(getDoc(doc(as('bob'), `groups/${GROUP}/items/item-1`)));
  });

  it('グループの名前だけ変えられる（作成者は変えられない）', async () => {
    await assertSucceeds(updateDoc(doc(as('bob'), `groups/${GROUP}`), { name: 'わが家（新）', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('bob'), `groups/${GROUP}`), { createdBy: 'bob', updatedAt: serverTimestamp() }));
  });
});

describe('生活グループを作る', () => {
  it('同じ書き込みで自分を owner にすれば作れる', async () => {
    const db = as('carol');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/group-c'), { name: 'carol の家', createdBy: 'carol', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    batch.set(doc(db, 'groups/group-c/members/carol'), { uid: 'carol', role: 'owner', joinedAt: serverTimestamp(), displayName: 'carol' });
    await assertSucceeds(batch.commit());
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
    await assertSucceeds(deleteDoc(doc(bob, `groups/${GROUP}/members/bob`)));
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
    await assertSucceeds(deleteDoc(doc(alice, `groups/${GROUP}/members/alice`)));
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
    await assertSucceeds(deleteDoc(doc(as('bob'), `groups/${GROUP}/members/bob`)));
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

  it('グループを作るとき、自分の UID を uid に入れれば作れる', async () => {
    const db = as('carol');
    await assertSucceeds(createGroupBatch(db, 'carol', {
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
