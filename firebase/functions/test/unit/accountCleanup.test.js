'use strict';

/**
 * アカウント削除のあとの整理：何をするかを決める部分（src/accountCleanup.js）の単体テスト。
 * firebase・ネットワークを使わない。実際の Firestore での動きは test/emulator/accountDeletion.test.js。
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  GroupAction, compareUID, chooseSuccessor, planGroupCleanup, mergeGroupIDs, isValidUID, emptySummary,
} = require('../../src/accountCleanup');

const at = (ms) => ({ toMillis: () => ms });
const EXISTS = { groupExists: true };
const member = (uid, role, joinedMs) => ({ uid, role, joinedAt: joinedMs === undefined ? undefined : at(joinedMs) });

describe('生活グループごとの整理の決め方', () => {
  it('一般メンバーが削除され、ほかの人がいる：本人だけ外す', () => {
    const plan = planGroupCleanup('m', [member('o', 'owner', 0), member('m', 'member', 10), member('p', 'member', 20)], EXISTS);
    assert.deepEqual(plan, { action: GroupAction.removeMember });
  });

  it('owner が削除され、ほかの人がいる：ほかの人に owner を引き継ぐ', () => {
    const plan = planGroupCleanup('o', [member('o', 'owner', 0), member('p', 'member', 10)], EXISTS);
    assert.deepEqual(plan, { action: GroupAction.transferOwnership, newOwnerUID: 'p' });
  });

  it('複数人いるときは、参加がいちばん古い人', () => {
    const members = [member('o', 'owner', 0), member('a', 'member', 300), member('b', 'member', 100), member('c', 'member', 200)];
    assert.equal(planGroupCleanup('o', members, EXISTS).newOwnerUID, 'b');
  });

  it('参加の時刻が同じなら UID の文字順（並べ方を変えても同じ結果）', () => {
    const members = [member('o', 'owner', 0), member('zed', 'member', 50), member('amy', 'member', 50), member('bob', 'member', 50)];
    assert.equal(planGroupCleanup('o', members, EXISTS).newOwnerUID, 'amy');
    assert.equal(planGroupCleanup('o', [...members].reverse(), EXISTS).newOwnerUID, 'amy');
    // 大文字は小文字より先（言語の設定に左右されない文字の並び）
    assert.equal(chooseSuccessor([member('b', 'member', 1), member('B', 'member', 1)]), 'B');
  });

  it('参加の時刻が無い人は最後に回す', () => {
    assert.equal(chooseSuccessor([member('a', 'member'), member('z', 'member', 999)]), 'z');
    assert.equal(chooseSuccessor([member('b', 'member'), member('a', 'member')]), 'a');
    assert.equal(chooseSuccessor([]), null);
  });

  it('Firestore の Timestamp のほか、{seconds} や数値の時刻でも比べられる', () => {
    const list = [
      { uid: 'x', joinedAt: { seconds: 20, nanoseconds: 0 } },
      { uid: 'y', joinedAt: 10_000 },
      { uid: 'z', joinedAt: new Date(30_000) },
    ];
    assert.equal(chooseSuccessor(list), 'y');
  });

  it('owner しかいない：グループを丸ごと消す', () => {
    assert.deepEqual(planGroupCleanup('o', [member('o', 'owner', 0)], EXISTS), { action: GroupAction.deleteGroup });
  });

  it('最後の一人が一般メンバーでも、誰も残らないならグループを消す（誰も読めないグループを残さない）', () => {
    assert.deepEqual(planGroupCleanup('m', [member('m', 'member', 0)], EXISTS), { action: GroupAction.deleteGroup });
  });

  it('ほかにも owner がいる：引き継がず、本人だけ外す', () => {
    const plan = planGroupCleanup('o', [member('o', 'owner', 0), member('o2', 'owner', 5), member('p', 'member', 1)], EXISTS);
    assert.deepEqual(plan, { action: GroupAction.removeMember });
  });

  it('本人がもういない（前回の実行で済んだ）：何もしない', () => {
    assert.deepEqual(planGroupCleanup('m', [member('o', 'owner', 0)], EXISTS), { action: GroupAction.nothing });
  });

  it('本人もほかの人もいない（前回、グループを消す途中で止まった）：グループを消す', () => {
    assert.deepEqual(planGroupCleanup('m', [], EXISTS), { action: GroupAction.deleteGroup });
    assert.deepEqual(planGroupCleanup('m', undefined, EXISTS), { action: GroupAction.deleteGroup });
  });

  it('入力を変えない', () => {
    const members = [member('o', 'owner', 0), member('b', 'member', 2), member('a', 'member', 2)];
    const copy = JSON.stringify(members.map((m) => m.uid));
    planGroupCleanup('o', members, EXISTS);
    assert.equal(JSON.stringify(members.map((m) => m.uid)), copy);
  });
});

describe('グループの文書がもう無いとき（途中まで削除されたグループ）', () => {
  const GONE = { groupExists: false };

  it('削除された人とパートナーが残っていても、丸ごと消す（引き継がない）', () => {
    const members = [member('o', 'owner', 0), member('p', 'member', 10)];
    assert.deepEqual(planGroupCleanup('o', members, GONE), { action: GroupAction.deleteGroup });
    assert.deepEqual(planGroupCleanup('p', members, GONE), { action: GroupAction.deleteGroup });
  });

  it('削除された人はもういなくて、パートナーだけ残っていても、丸ごと消す', () => {
    assert.deepEqual(planGroupCleanup('o', [member('p', 'member', 10)], GONE), { action: GroupAction.deleteGroup });
    assert.deepEqual(planGroupCleanup('o', [member('p', 'owner', 10)], GONE), { action: GroupAction.deleteGroup });
  });

  it('メンバーが誰もいなくても、丸ごと消す', () => {
    assert.deepEqual(planGroupCleanup('o', [], GONE), { action: GroupAction.deleteGroup });
  });

  it('グループの文書が在るかを必ず指定する（指定し忘れで引き継ぎを選ばない）', () => {
    assert.throws(() => planGroupCleanup('o', [member('o', 'owner', 0), member('p', 'member', 1)]), /groupExists/);
    assert.throws(() => planGroupCleanup('o', [], {}), /groupExists/);
  });
});

describe('整理するグループの一覧・UID', () => {
  it('重複を除いて並べる。おかしな ID は使わない', () => {
    assert.deepEqual(mergeGroupIDs(['g2', 'g1'], ['g1', 'g3'], null, ['a/b', '', 5]), ['g1', 'g2', 'g3']);
    assert.deepEqual(mergeGroupIDs(), []);
  });

  it('UID はパスに入れられる形だけ', () => {
    assert.equal(isValidUID('AbC123_-x'), true);
    for (const bad of ['', 'a/b', '..', null, undefined, 5, 'x'.repeat(129)]) assert.equal(isValidUID(bad), false, String(bad));
  });

  it('UID の比べ方は文字の並び', () => {
    assert.equal(compareUID('a', 'b'), -1);
    assert.equal(compareUID('b', 'a'), 1);
    assert.equal(compareUID('a', 'a'), 0);
  });

  it('ログ用の集計は件数だけ', () => {
    const summary = emptySummary();
    for (const value of Object.values(summary)) assert.equal(typeof value, 'number');
  });
});
