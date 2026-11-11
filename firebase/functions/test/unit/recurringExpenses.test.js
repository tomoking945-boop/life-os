'use strict';

/**
 * Build 25（2026-11-11）：わが家で共有の定期支出。docs/BUILD_25_RECURRING_EXPENSES.md
 * - 設定：groups/{groupID}/recurringExpenses/{templateID}（決まった11項目）
 * - 月ごとの状態：groups/{groupID}/recurringExpenseOccurrences/{templateID}_{YYYY-MM}（決まった7項目）
 *
 * Emulator を使わずに確かめられること：
 * - ルールの形（決まった項目・名前・金額・カテゴリー・支払日・開始月・本人・サーバーの時刻・家計簿のオン）
 * - 「追加済み」は新しい共有の支出と同じ書き込みでだけ作れて、変更・削除できない。「今月は追加しない」だけ消せる
 * - 名前・月のキー・UUID の正規表現（ルールの文字列を取り出し、JavaScript の正規表現で確かめる）
 * - アプリ（Swift の SharedRecurringExpensePayload）と同じ見本の形
 * - Functions は定期支出を扱わない（通知しない。わが家ごと消すときだけ recursiveDelete で消える）
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
const swiftPayload = read('../../../../LifeOS/Core/Sharing/SharedRecurringExpenses.swift');

const templateBlock = rules.slice(rules.indexOf('match /recurringExpenses/{templateID}'), rules.indexOf('match /recurringExpenseOccurrences/{occurrenceID}'));
const occurrenceBlock = rules.slice(rules.indexOf('match /recurringExpenseOccurrences/{occurrenceID}'), rules.indexOf('match /monthlyBudgets/{monthKey}'));

const TEMPLATE_FIELDS = [
  'schemaVersion', 'title', 'expectedAmount', 'category', 'dueDay', 'startMonthKey', 'isActive',
  'createdBy', 'updatedBy', 'createdAt', 'updatedAt',
];
const OCCURRENCE_FIELDS = ['schemaVersion', 'templateID', 'monthKey', 'status', 'expenseID', 'processedBy', 'processedAt'];
const CATEGORIES = ['food', 'dailyGoods', 'diningOut', 'transport', 'subscription', 'other'];

/** アプリが作る見本（作成者・日時は Firestore の窓口が入れる） */
const GOLDEN_TEMPLATE = {
  schemaVersion: 1, title: '家賃', expectedAmount: 85000, category: 'other', dueDay: 27, startMonthKey: '2026-11', isActive: true,
  createdBy: 'uid', updatedBy: 'uid', createdAt: 'serverTime', updatedAt: 'serverTime',
};
const GOLDEN_OCCURRENCE = {
  schemaVersion: 1, templateID: 'D3B07384-D113-4EC5-A2A8-1A0F8E2B5C11', monthKey: '2026-11', status: 'created',
  expenseID: '0F8FAD5B-D9CB-469F-A165-70867728950E', processedBy: 'uid', processedAt: 'serverTime',
};

/** ルールの文字列の中の matches('...') を取り出して、JavaScript の正規表現にする（[[:cntrl:]] は ASCII の制御文字） */
function pattern(block, field) {
  const escaped = field.replace('.', '\\.');
  const found = block.match(new RegExp(`${escaped}\\.matches\\('([^']+)'\\)`));
  assert.ok(found, `${field} の正規表現が見つかる`);
  return new RegExp(found[1].replace(/\[:cntrl:\]/g, '\\x00-\\x1F\\x7F'), 'u');
}

describe('Build 25：定期支出の設定のルール（形）', () => {
  it('場所はわが家の下（recurringExpenses）。支出・明細の決まりの外で、月の予算より前に置く', () => {
    assert.ok(templateBlock.length > 0 && occurrenceBlock.length > 0);
    assert.ok(rules.indexOf('match /recurringExpenses/{templateID}') > rules.indexOf('// notificationLog など'));
    assert.ok(rules.indexOf('match /recurringExpenses/{templateID}') > rules.indexOf('match /groups/{groupID}'));
    assert.ok(rules.indexOf('match /recurringExpenseOccurrences/{occurrenceID}') < rules.indexOf('match /monthlyBudgets/{monthKey}'));
    const expenses = rules.slice(rules.indexOf('match /expenses/{expenseID}'), rules.indexOf('// notificationLog など'));
    for (const word of ['recurring', 'expectedAmount', 'dueDay', 'occurrence']) assert.ok(!expenses.includes(word), word);
  });

  it('決まった11項目だけ（すべて必須）。schemaVersion は 1。アプリの見本と同じ項目', () => {
    const list = TEMPLATE_FIELDS.map((f) => `'${f}'`).join(', ');
    const compact = templateBlock.replace(/\s+/g, ' ');
    assert.ok(compact.includes(`data.keys().hasOnly([ ${list} ])`), 'hasOnly');
    assert.ok(compact.includes(`data.keys().hasAll([ ${list} ])`), 'hasAll');
    assert.match(templateBlock, /data\.schemaVersion == 1/);
    assert.deepEqual(Object.keys(GOLDEN_TEMPLATE), TEMPLATE_FIELDS);
    for (const field of TEMPLATE_FIELDS) assert.ok(swiftPayload.includes(`"${field}"`), `Swift にも ${field}`);
  });

  it('名前は1〜80文字で制御文字・改行なし', () => {
    const title = pattern(templateBlock, 'data.title');
    for (const ok of ['家賃', 'あ'.repeat(80), 'Netflix', '👨‍👩‍👧 サブスク', GOLDEN_TEMPLATE.title]) assert.ok(title.test(ok), ok);
    for (const ng of ['', 'あ'.repeat(81), '家賃\n駐車場', '家賃\r', 'タブ\t', '\u0000', '\u007F']) assert.ok(!title.test(ng), JSON.stringify(ng));
  });

  it('目安金額は 1〜999,999,999 の整数・カテゴリーは6つ・支払日は 1〜31 の整数・停止は真偽値', () => {
    assert.match(templateBlock, /data\.expectedAmount is int/);
    assert.match(templateBlock, /data\.expectedAmount >= 1/);
    assert.match(templateBlock, /data\.expectedAmount <= 999999999/);
    assert.ok(templateBlock.includes(`data.category in [${CATEGORIES.map((c) => `'${c}'`).join(', ')}]`));
    assert.match(templateBlock, /data\.dueDay is int/);
    assert.match(templateBlock, /data\.dueDay >= 1/);
    assert.match(templateBlock, /data\.dueDay <= 31/);
    assert.match(templateBlock, /data\.isActive is bool/);
  });

  it('開始月は 2000-01〜2099-12 の YYYY-MM', () => {
    const month = pattern(templateBlock, 'data.startMonthKey');
    for (const ok of ['2026-11', '2000-01', '2099-12', '2028-02']) assert.ok(month.test(ok), ok);
    for (const ng of ['2026-13', '2026-00', '2026-1', '1999-12', '2100-01', '2026/11', '', '2026-11 ']) assert.ok(!month.test(ng), JSON.stringify(ng));
  });

  it('作成者は本人・作成日時はサーバー。変えた人は本人・変えた日時はサーバー。作成者・作成日時・schemaVersion は変えられない', () => {
    assert.match(templateBlock, /data\.updatedBy == request\.auth\.uid/);
    assert.match(templateBlock, /data\.updatedAt == request\.time/);
    assert.match(templateBlock, /allow create: if isMember\(groupID\)[\s\S]*?&& recurringSharingIsOn\(\)\s*&& request\.resource\.data\.createdBy == request\.auth\.uid\s*&& request\.resource\.data\.createdAt == request\.time;/);
    assert.match(templateBlock, /allow update: if isMember\(groupID\)\s*&& validRecurringTemplate\(request\.resource\.data\)\s*&& request\.resource\.data\.createdBy == resource\.data\.createdBy\s*&& request\.resource\.data\.createdAt == resource\.data\.createdAt\s*&& request\.resource\.data\.schemaVersion == resource\.data\.schemaVersion;/);
  });

  it('読み書きはメンバーだけ。作るのは家計簿がオンのときだけ（変更はオフのあとも）。消せない（停止だけ）', () => {
    assert.match(templateBlock, /allow read: if isMember\(groupID\);/);
    assert.match(templateBlock, /allow delete: if false;/);
    assert.match(templateBlock, /'money' in get\(\/databases\/\$\(database\)\/documents\/groups\/\$\(groupID\)\)\.data\.get\('sharedKinds', \[\]\)/);
    assert.ok(!/allow update:[^;]*recurringSharingIsOn/.test(templateBlock), '変更は家計簿のオン・オフに関係ない');
  });

  it('メール・表示名・端末・トークン・メモ・レシートの項目は無い', () => {
    for (const word of ['email', 'displayName', 'device', 'token', 'memo', 'receipt', 'personal', 'lineItems']) {
      assert.ok(!templateBlock.includes(`'${word}'`), word);
      assert.ok(!occurrenceBlock.includes(`'${word}'`), word);
    }
  });
});

describe('Build 25：定期支出の月ごとの状態のルール（重複を防ぐ）', () => {
  it('決まった7項目だけ（すべて必須）。schemaVersion は 1。アプリの見本と同じ項目', () => {
    const list = OCCURRENCE_FIELDS.map((f) => `'${f}'`).join(', ');
    assert.ok(occurrenceBlock.includes(`data.keys().hasOnly([${list}])`));
    assert.ok(occurrenceBlock.includes(`data.keys().hasAll([${list}])`));
    assert.match(occurrenceBlock, /data\.schemaVersion == 1/);
    assert.deepEqual(Object.keys(GOLDEN_OCCURRENCE), OCCURRENCE_FIELDS);
    for (const field of OCCURRENCE_FIELDS) assert.ok(swiftPayload.includes(`"${field}"`), `Swift にも ${field}`);
  });

  it('文書の ID は設定の ID と月（{templateID}_{YYYY-MM}）。設定がある月だけ。処理した人は本人・日時はサーバー', () => {
    assert.match(occurrenceBlock, /occurrenceID == data\.templateID \+ '_' \+ data\.monthKey/);
    assert.match(occurrenceBlock, /exists\(\/databases\/\$\(database\)\/documents\/groups\/\$\(groupID\)\/recurringExpenses\/\$\(data\.templateID\)\)/);
    assert.match(occurrenceBlock, /data\.processedBy == request\.auth\.uid/);
    assert.match(occurrenceBlock, /data\.processedAt == request\.time/);
    assert.match(occurrenceBlock, /data\.status in \['created', 'skipped'\]/);
    const uuid = pattern(occurrenceBlock, 'data.templateID');
    assert.ok(uuid.test(GOLDEN_OCCURRENCE.templateID));
    assert.ok(!uuid.test('rent'));
    const month = pattern(occurrenceBlock, 'data.monthKey');
    assert.ok(month.test(GOLDEN_OCCURRENCE.monthKey));
    assert.ok(!month.test('2026-13'));
  });

  it('追加済み（created）は、新しい共有の支出をこの書き込みで作るときだけ（前には無く、後にある。作成者は本人）', () => {
    assert.match(occurrenceBlock, /data\.status == 'created'/);
    assert.match(occurrenceBlock, /data\.expenseID is string/);
    assert.match(occurrenceBlock, /!exists\(expensePath\(data\.expenseID\)\)/);
    assert.match(occurrenceBlock, /existsAfter\(expensePath\(data\.expenseID\)\)/);
    assert.match(occurrenceBlock, /getAfter\(expensePath\(data\.expenseID\)\)\.data\.createdBy == request\.auth\.uid/);
    const uuid = pattern(occurrenceBlock, 'data.expenseID');
    assert.ok(uuid.test(GOLDEN_OCCURRENCE.expenseID));
    assert.ok(!uuid.test('not-a-uuid'));
  });

  it('今月は追加しない（skipped）は支出の ID が null。変更はできない。消せるのは skipped だけ（追加済みは消せない）', () => {
    assert.match(occurrenceBlock, /request\.resource\.data\.status == 'skipped' && request\.resource\.data\.expenseID == null/);
    assert.match(occurrenceBlock, /allow update: if false;/);
    assert.match(occurrenceBlock, /allow delete: if isMember\(groupID\)\s*&& resource\.data\.status == 'skipped';/);
    assert.match(occurrenceBlock, /allow read: if isMember\(groupID\);/);
    assert.match(occurrenceBlock, /allow create: if isMember\(groupID\)/);
  });

  it('既存の支出のルールは緩めていない（作成は家計簿がオンのとき・本人・サーバーの時刻のまま）', () => {
    const expenses = rules.slice(rules.indexOf('match /expenses/{expenseID}'), rules.indexOf('match /expenseLineItems/{expenseID}'));
    assert.match(expenses, /allow create: if isMember\(groupID\)[\s\S]*?&& moneyIsEnabled\(\)\s*&& request\.resource\.data\.createdBy == request\.auth\.uid\s*&& request\.resource\.data\.createdAt == request\.time;/);
  });
});

describe('Build 25：Functions と定期支出', () => {
  it('通知の Function は共有 ToDo・買い物（items）だけを見る。定期支出では通知しない', () => {
    const triggers = index.match(/onDocument\w+\('([^']+)'/g) || [];
    assert.deepEqual(triggers, ["onDocumentWritten('groups/{groupID}/items/{itemID}'"]);
    for (const source of [index, notificationPolicy]) {
      assert.ok(!source.includes('recurringExpenses'));
      assert.ok(!source.includes('recurringExpenseOccurrences'));
    }
  });

  it('退出・アカウント削除の整理は定期支出に触れない（わが家ごと消すときだけ recursiveDelete で消える）', () => {
    for (const source of [householdStore, cleanupRunner]) {
      assert.ok(!source.includes('recurringExpense'));
    }
    assert.match(householdStore, /recursiveDelete\(db\.doc\(`groups\/\$\{groupID\}`\)\)/);
    assert.match(cleanupRunner, /recursiveDelete\(groupRef\)/);
  });
});
