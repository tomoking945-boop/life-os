'use strict';

/**
 * わが家の決まりごと（src/household.js）の単体テスト。firebase・ネットワークを使わない。
 * 実際の Firestore での動きは test/emulator/functions.test.js。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  SHARED_SPACE_KINDS, SYNC_SUPPORTED_KINDS, DEFAULT_SHARED_SPACE_KINDS, MAX_MEMBERS, DEFAULT_GROUP_NAME,
  validateSharedKinds, validateGroupName, planSharedKindsUpdate, buildHouseholdSummary, buildInvitePreview, pickActiveInvite,
} = require('../../src/household');
const { isActiveInvite } = require('../../src/invites');

describe('共有する種類', () => {
  it('決まった7種類（英語の固定の値）。はじめは ToDo と買い物', () => {
    assert.deepEqual(SHARED_SPACE_KINDS, ['event', 'todo', 'chore', 'shopping', 'money', 'warranty', 'list']);
    assert.deepEqual(DEFAULT_SHARED_SPACE_KINDS, ['todo', 'shopping']);
    assert.equal(Object.isFrozen(SHARED_SPACE_KINDS), true);
  });

  it('1種類以上・決まった値だけ・重複なし。保存は決まった並び', () => {
    assert.deepEqual(validateSharedKinds(['shopping', 'todo']), { ok: true, kinds: ['todo', 'shopping'] });
    assert.deepEqual(validateSharedKinds([...SHARED_SPACE_KINDS].reverse()).kinds, SHARED_SPACE_KINDS);
    for (const bad of [[], ['payment'], ['habit'], ['todo', 'todo'], ['TODO'], [''], [1], 'todo', null, undefined, {},
      [...SHARED_SPACE_KINDS, 'todo']]) {
      assert.deepEqual(validateSharedKinds(bad), { ok: false, code: 'invalid-kinds' }, JSON.stringify(bad));
    }
  });

  it('共有項目（items）の4種類は、共有する種類の値と同じ', () => {
    const { SHARED_KINDS } = require('../../src/notificationPolicy');
    for (const kind of SHARED_KINDS) assert.ok(SHARED_SPACE_KINDS.includes(kind), kind);
  });
});

describe('わが家の名前', () => {
  it('前後の空白を除く。空・51文字以上・改行などは不可', () => {
    assert.equal(DEFAULT_GROUP_NAME, 'わが家');
    assert.deepEqual(validateGroupName(' わが家 '), { ok: true, name: 'わが家' });
    assert.equal(validateGroupName('あ'.repeat(50)).ok, true);
    for (const bad of ['', '   ', 'あ'.repeat(51), 'わが\n家', 'a\tb', null, 5]) {
      assert.deepEqual(validateGroupName(bad), { ok: false, code: 'invalid-name' }, JSON.stringify(bad));
    }
  });
});

describe('アプリに返す内容', () => {
  const group = { name: '池上家', createdBy: 'uid-owner', sharedKinds: ['shopping', 'todo'] };
  const members = [
    { uid: 'uid-partner', role: 'member', joinedAt: 2000 },
    { uid: 'uid-owner', role: 'owner', joinedAt: 1000 },
  ];

  it('オーナーが見ると：オーナーが先・自分の印・有効な招待の期限。UID は入らない', () => {
    const summary = buildHouseholdSummary(group, members, 'uid-owner', { expiresAt: 5000, createdBy: 'uid-owner' }, 'group-1');
    assert.deepEqual(summary, {
      groupID: 'group-1',
      name: '池上家',
      sharedKinds: ['todo', 'shopping'],
      isOwner: true,
      members: [{ role: 'owner', isSelf: true, joinedAt: 1000 }, { role: 'member', isSelf: false, joinedAt: 2000 }],
      maxMembers: MAX_MEMBERS,
      activeInvite: { expiresAt: 5000 },
    });
    assert.ok(!JSON.stringify(summary).includes('uid-'));
  });

  it('パートナーが見ると：招待は見せない', () => {
    const summary = buildHouseholdSummary(group, members, 'uid-partner', { expiresAt: 5000 });
    assert.equal(summary.isOwner, false);
    assert.equal(summary.activeInvite, null);
    assert.deepEqual(summary.members.map((m) => m.isSelf), [false, true]);
  });

  it('招待の Preview は、グループ名・共有する種類・期限だけ（招待した人・UID は入らない）', () => {
    const preview = buildInvitePreview(group, { groupID: 'g', createdBy: 'uid-owner', expiresAt: { seconds: 10, nanoseconds: 0 } });
    assert.deepEqual(preview, { groupName: '池上家', sharedKinds: ['todo', 'shopping'], expiresAt: 10000 });
  });

  it('有効な招待は、いちばん新しい未使用・未取り消し・期限内のもの', () => {
    const now = 10_000;
    const invites = [
      { createdAt: 1, expiresAt: 20_000, usedAt: null, revokedAt: null },
      { createdAt: 3, expiresAt: 20_000, usedAt: null, revokedAt: 5 },
      { createdAt: 2, expiresAt: 20_000, usedAt: null, revokedAt: null },
      { createdAt: 4, expiresAt: 9_000, usedAt: null, revokedAt: null },
    ];
    assert.equal(pickActiveInvite(invites, now, isActiveInvite).createdAt, 2);
    assert.equal(pickActiveInvite([], now, isActiveInvite), null);
  });
});

describe('ログ・保存に出さないもの', () => {
  const root = path.join(__dirname, '../..');
  const store = fs.readFileSync(path.join(root, 'src/householdStore.js'), 'utf8');
  const index = fs.readFileSync(path.join(root, 'index.js'), 'utf8');

  it('わが家の処理の中ではログを出さない。Function のエラーのログは Function 名とエラーの種類だけ', () => {
    assert.doesNotMatch(store, /console\.|logger\./);
    const start = index.indexOf('async function runHousehold(');
    const block = index.slice(start, index.indexOf('\n}\n', start));
    const logs = block.match(/logger\.\w+\([^)]*\)/g) || [];
    assert.deepEqual(logs, ["logger.error('household function failed', { function: name, code })"]);
    for (const word of ['uid', 'token', 'request.data', 'error.message']) {
      assert.equal(logs.join('').includes(word), false, word);
    }
  });

  it('招待トークンは、ハッシュを文書 ID にして保存し、トークンそのものは書かない', () => {
    assert.match(store, /db\.doc\(`invites\/\$\{hashToken\(token\)\}`\)/);
    const createBlock = store.slice(store.indexOf('transaction.create(inviteRef, {'), store.indexOf('});', store.indexOf('transaction.create(inviteRef, {')));
    assert.equal(/\btoken\b/.test(createBlock.replace('inviteRef', '')), false);
  });

  it('アプリへ返すエラーは、決まった理由（reason）だけ', () => {
    assert.match(index, /new HttpsError\(HOUSEHOLD_FAILURES\[error\.reason\], 'わが家の操作ができませんでした。', \{ reason: error\.reason \}\)/);
    assert.match(index, /new HttpsError\('internal', 'わが家の操作ができませんでした。', \{ reason: 'internal' \}\)/);
  });
});

describe('わが家の設定：共有する種類の変更（2026-10-28）', () => {
  it('いま同期できるのは ToDo・買い物だけ', () => {
    assert.deepEqual(SYNC_SUPPORTED_KINDS, ['todo', 'shopping']);
    assert.equal(Object.isFrozen(SYNC_SUPPORTED_KINDS), true);
    for (const kind of SYNC_SUPPORTED_KINDS) assert.ok(SHARED_SPACE_KINDS.includes(kind));
  });

  it('ToDo・買い物だけを切り替え、保存されている「今後対応」の種類は消さない', () => {
    assert.deepEqual(planSharedKindsUpdate(['todo', 'shopping'], ['shopping']), { ok: true, kinds: ['shopping'] });
    assert.deepEqual(planSharedKindsUpdate(['todo'], ['todo', 'shopping']), { ok: true, kinds: ['todo', 'shopping'] });
    assert.deepEqual(planSharedKindsUpdate(['event', 'money', 'todo'], []), { ok: true, kinds: ['event', 'money'] }, '今後対応の種類は残す');
    assert.deepEqual(planSharedKindsUpdate(['warranty', 'list'], ['shopping']), { ok: true, kinds: ['shopping', 'warranty', 'list'] });
  });

  it('今後対応の種類・知らない値・重複は送れない。1つも残らない変更は不可', () => {
    for (const bad of [['event'], ['money'], ['todo', 'todo'], ['TODO'], 'todo', null, undefined, [1]]) {
      assert.deepEqual(planSharedKindsUpdate(['todo'], bad), { ok: false, code: 'invalid-kinds' }, JSON.stringify(bad));
    }
    assert.deepEqual(planSharedKindsUpdate(['todo', 'shopping'], []), { ok: false, code: 'invalid-kinds' });
    assert.deepEqual(planSharedKindsUpdate(undefined, []), { ok: false, code: 'invalid-kinds' });
    // 保存されている知らない値は数えない
    assert.deepEqual(planSharedKindsUpdate(['unknown'], []), { ok: false, code: 'invalid-kinds' });
  });
});
