'use strict';

/**
 * Build 24（2026-11-10）：わが家の月の予算（groups/{groupID}/monthlyBudgets/{YYYY-MM}）。
 * docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md
 *
 * Emulator を使わずに確かめられること：
 * - ルールの形（決まった6項目・月のキーの形・決まったカテゴリー・金額の範囲・カテゴリーの合計・本人・サーバーの時刻・家計簿のオン）
 * - 月のキーの正規表現（ルールの文字列を取り出し、JavaScript の正規表現で正しいキー・正しくないキーを確かめる）
 * - アプリ（Swift の SharedMonthlyBudgetPayload）と同じ見本の形
 * - Functions は予算を扱わない（わが家ごと消すときだけ recursiveDelete で消える。通知も作らない）
 * ルールの動きそのものは test/emulator/rules.test.js、削除は test/emulator/accountDeletion.test.js で確かめる。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const read = (relative) => fs.readFileSync(path.join(__dirname, relative), 'utf8');
const rules = read('../../../../firestore.rules');
const index = read('../../index.js');
const householdStore = read('../../src/householdStore.js');
const cleanupRunner = read('../../src/accountCleanupRunner.js');
const notificationPolicy = read('../../src/notificationPolicy.js');

const block = rules.slice(rules.indexOf('match /monthlyBudgets/{monthKey}'), rules.indexOf('// accountDeletions'));
const CATEGORIES = ['food', 'dailyGoods', 'diningOut', 'transport', 'subscription', 'other'];
const FIELDS = ['schemaVersion', 'monthKey', 'totalAmount', 'categoryAmounts', 'updatedBy', 'updatedAt'];

/** アプリ（Swift の SharedMonthlyBudgetPayload.fields）が作る見本。updatedBy・updatedAt は Firestore の窓口が入れる */
const GOLDEN = { schemaVersion: 1, monthKey: '2026-11', totalAmount: 120000, categoryAmounts: { food: 40000, dailyGoods: 0 } };

function monthKeyPattern() {
  const fn = block.slice(block.indexOf('function validMonthKey'), block.indexOf('function budgetSharingIsOn'));
  const found = fn.match(/monthKey\.matches\('([^']+)'\)/);
  assert.ok(found, '月のキーの正規表現が見つかる');
  return new RegExp(found[1]);
}

describe('Build 24：わが家の月の予算のルール（形）', () => {
  it('場所はわが家の下の monthlyBudgets（月ごとに文書1つ）。共有の支出・明細の決まりの外に置く', () => {
    assert.ok(block.length > 0);
    assert.ok(rules.indexOf('match /monthlyBudgets/{monthKey}') > rules.indexOf('// notificationLog など'), '支出・明細のブロックとは別');
    assert.ok(rules.indexOf('match /monthlyBudgets/{monthKey}') > rules.indexOf('match /groups/{groupID}'));
    // 支出・明細の決まりには、予算の項目が入っていない
    const expenses = rules.slice(rules.indexOf('match /expenses/{expenseID}'), rules.indexOf('// notificationLog など'));
    for (const word of ['budget', 'totalAmount', 'categoryAmounts']) assert.ok(!expenses.includes(word), word);
  });

  it('決まった6項目だけ（すべて必須）。schemaVersion は 1。月のキーは文書の ID と同じ', () => {
    const list = FIELDS.map((f) => `'${f}'`).join(', ');
    assert.ok(block.includes(`data.keys().hasOnly([${list}])`));
    assert.ok(block.includes(`data.keys().hasAll([${list}])`));
    assert.match(block, /data\.schemaVersion == 1/);
    assert.match(block, /data\.monthKey == monthKey/);
    assert.deepEqual(Object.keys(GOLDEN).concat(['updatedBy', 'updatedAt']), FIELDS, 'アプリの見本と同じ項目');
  });

  it('月の予算は 1〜999,999,999 の整数。カテゴリーは 0〜999,999,999 の整数で、決まったカテゴリーだけ', () => {
    assert.match(block, /data\.totalAmount is int/);
    assert.match(block, /data\.totalAmount >= 1/);
    assert.match(block, /data\.totalAmount <= 999999999/);
    assert.match(block, /data\.categoryAmounts is map/);
    assert.ok(block.includes(`data.categoryAmounts.keys().hasOnly([${CATEGORIES.map((c) => `'${c}'`).join(', ')}])`));
    assert.match(block, /amounts\[category\] is int && amounts\[category\] >= 0 && amounts\[category\] <= 999999999/);
    const checked = [...block.matchAll(/&& validCategoryAmount\(data\.categoryAmounts, '([A-Za-z]+)'\)/g)].map((m) => m[1]);
    assert.deepEqual(checked, CATEGORIES, '6つのカテゴリーを1回ずつ確かめる');
    // 支出のカテゴリーと同じ
    const expenseCategories = rules.match(/data\.category in \[([^\]]+)\]/)[1];
    assert.equal(expenseCategories, CATEGORIES.map((c) => `'${c}'`).join(', '));
  });

  it('カテゴリーの合計は月の予算以下（6つすべてを足す）', () => {
    const sum = block.slice(block.indexOf("&& data.categoryAmounts.get('food', 0)"), block.indexOf('<= data.totalAmount'));
    const added = [...sum.matchAll(/data\.categoryAmounts\.get\('([A-Za-z]+)', 0\)/g)].map((m) => m[1]);
    assert.deepEqual(added, CATEGORIES);
    assert.match(block, /<= data\.totalAmount/);
  });

  it('変えた人は本人・変えた日時はサーバーの時刻。作成者・メール・端末・UID の一覧などは無い', () => {
    assert.match(block, /data\.updatedBy == request\.auth\.uid/);
    assert.match(block, /data\.updatedAt == request\.time/);
    for (const word of ['createdBy', 'email', 'displayName', 'device', 'token', 'memo', 'receipt', 'personal']) {
      assert.ok(!block.includes(`'${word}'`), word);
    }
  });

  it('読み書きはメンバーだけ。新しく作れるのは家計簿がオンのときだけ。変更・解除はオフのあとも', () => {
    assert.match(block, /allow read: if isMember\(groupID\);/);
    assert.match(block, /allow create: if isMember\(groupID\)\s*&& validMonthKey\(\)\s*&& validMonthlyBudget\(request\.resource\.data\)\s*&& budgetSharingIsOn\(\);/);
    assert.match(block, /allow update: if isMember\(groupID\)\s*&& validMonthKey\(\)\s*&& validMonthlyBudget\(request\.resource\.data\);/);
    assert.match(block, /allow delete: if isMember\(groupID\);/);
    assert.match(block, /'money' in get\(\/databases\/\$\(database\)\/documents\/groups\/\$\(groupID\)\)\.data\.get\('sharedKinds', \[\]\)/);
  });
});

describe('Build 24：月のキー（YYYY-MM）', () => {
  const pattern = monthKeyPattern();

  it('2000年1月〜2099年12月の YYYY-MM だけ', () => {
    for (const key of ['2026-11', '2026-01', '2026-12', '2000-01', '2099-12', '2028-02', GOLDEN.monthKey]) {
      assert.ok(pattern.test(key), key);
    }
  });

  it('形の違うキー・範囲外の月・年は拒否', () => {
    for (const key of ['2026-13', '2026-00', '2026-1', '26-11', '1999-12', '2100-01', '2026/11', '2026-11-01', 'abcd-ef', '', ' 2026-11', '2026-11 ']) {
      assert.ok(!pattern.test(key), JSON.stringify(key));
    }
  });
});

describe('Build 24：Functions と予算', () => {
  it('通知の Function は共有 ToDo・買い物（items）だけを見る。予算の変更では通知しない', () => {
    const triggers = index.match(/onDocument\w+\('([^']+)'/g) || [];
    assert.deepEqual(triggers, ["onDocumentWritten('groups/{groupID}/items/{itemID}'"]);
    assert.ok(!index.includes('monthlyBudgets'));
    assert.ok(!notificationPolicy.includes('monthlyBudgets'));
  });

  it('退出・アカウント削除の整理は予算に触れない（わが家ごと消すときだけ recursiveDelete で消える）', () => {
    assert.ok(!householdStore.includes('monthlyBudgets'));
    assert.ok(!cleanupRunner.includes('monthlyBudgets'));
    assert.match(householdStore, /recursiveDelete\(db\.doc\(`groups\/\$\{groupID\}`\)\)/);
    assert.match(cleanupRunner, /recursiveDelete\(groupRef\)/);
  });
});
