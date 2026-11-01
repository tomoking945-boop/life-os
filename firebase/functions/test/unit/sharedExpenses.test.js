'use strict';

/**
 * Build 13（2026-11-01）：共有の支出（groups/{groupID}/expenses）。docs/BUILD_13_SHARED_HOUSEHOLD_BUDGET_AND_EVENT_DELETE.md
 * Emulator を使わずに確かめられること（ソースと決まりごと）。ルールの動きそのものは test/emulator/rules.test.js で確かめる。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { SHARED_SPACE_KINDS, SYNC_SUPPORTED_KINDS, planSharedKindsUpdate } = require('../../src/household');

const read = (relative) => fs.readFileSync(path.join(__dirname, relative), 'utf8');
const index = read('../../index.js');
const householdStore = read('../../src/householdStore.js');
const cleanupRunner = read('../../src/accountCleanupRunner.js');
const rules = read('../../../../firestore.rules');

describe('Build 13：共有の支出と Functions', () => {
  it('家計簿（money）は同期できる種類。保存済みの将来用の種類（家事・保証書・リスト）は消さない', () => {
    assert.ok(SYNC_SUPPORTED_KINDS.includes('money'));
    assert.ok(SHARED_SPACE_KINDS.includes('money'));
    const planned = planSharedKindsUpdate(['chore', 'warranty', 'list'], ['money']);
    assert.deepEqual(planned, { ok: true, kinds: ['chore', 'money', 'warranty', 'list'] });
    // Build 14：予定（event）は同期できる種類になった。オンのまま送れば残り、送らなければオフになる
    assert.deepEqual(planSharedKindsUpdate(['event', 'chore', 'warranty', 'list'], ['event', 'money']), { ok: true, kinds: ['event', 'chore', 'money', 'warranty', 'list'] });
    assert.deepEqual(planSharedKindsUpdate(['event', 'chore', 'warranty', 'list'], ['money']), { ok: true, kinds: ['chore', 'money', 'warranty', 'list'] });
  });

  it('通知の Function は共有 ToDo・買い物（items）だけを見る。共有の支出（expenses）では動かない', () => {
    const triggers = index.match(/onDocumentWritten\('([^']+)'/g) || [];
    assert.deepEqual(triggers, ["onDocumentWritten('groups/{groupID}/items/{itemID}'"]);
    assert.ok(!index.includes('expenses'), 'index.js は expenses を扱わない');
    assert.ok(!read('../../src/notificationPolicy.js').includes('expenses'));
  });

  it('わが家の削除・アカウント削除は、わが家の下を丸ごと消す（共有の支出も残らない）', () => {
    assert.match(householdStore, /recursiveDelete\(db\.doc\(`groups\/\$\{groupID\}`\)\)/);
    assert.match(cleanupRunner, /recursiveDelete\(groupRef\)/);
  });

  it('退出・種類の変更・アカウント削除の整理は、共有の支出を消さない・別の場所へ写さない', () => {
    assert.ok(!householdStore.includes('expenses'), 'householdStore.js は expenses に触れない');
    assert.ok(!cleanupRunner.includes('expenses'), 'accountCleanupRunner.js は expenses に触れない（わが家ごと消すときだけ recursiveDelete で消える）');
  });

  it('ルール：expenses はメンバーだけ・家計簿がオンのときだけ作成・決まった項目だけ', () => {
    const block = rules.slice(rules.indexOf('match /expenses/{expenseID}'), rules.indexOf('// notificationLog など'));
    assert.ok(block.length > 0);
    assert.match(block, /keys\(\)\.hasOnly\(\[\s*'schemaVersion', 'title', 'amount', 'category', 'date', 'createdBy', 'updatedBy', 'createdAt', 'updatedAt'\s*\]\)/);
    assert.match(block, /'money' in get\(/);
    assert.match(block, /allow read: if isMember\(groupID\);/);
    assert.match(block, /allow delete: if isMember\(groupID\);/);
    assert.match(block, /data\.amount <= 999999999/);
    for (const word of ['receipt', 'memo', 'budget', 'email']) assert.ok(!block.includes(word), word);
  });
});
