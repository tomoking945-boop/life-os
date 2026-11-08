'use strict';

/**
 * Build 21（2026-11-08）：共有の支出の商品明細（groups/{groupID}/expenseLineItems/{expenseID}）。
 * docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md
 *
 * Emulator を使わずに確かめられること：
 * - ルールの形（決まった2項目・最大50件・50件分の1件ごとの確認・支出があるときだけ・支出の削除の条件）
 * - 1件ごとの正規表現（ルールの文字列を取り出し、JavaScript の正規表現に読み替えて、正しい行・正しくない行で確かめる）
 * - アプリ（Swift）と同じ見本の行（LifeOSTests/Build21ReceiptLineItemHistoryTests.swift と同じ文字列）
 * - Functions は商品明細を扱わない（わが家ごと消すときだけ recursiveDelete で消える）
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

const block = rules.slice(rules.indexOf('match /expenseLineItems/{expenseID}'), rules.indexOf('// notificationLog など'));
const expenseBlock = rules.slice(rules.indexOf('match /expenses/{expenseID}'), rules.indexOf('match /expenseLineItems/{expenseID}'));

/** ルールの1件の正規表現（RE2）を取り出し、JavaScript の正規表現にする（[[:cntrl:]] は ASCII の制御文字） */
function rowPattern() {
  const fn = block.slice(block.indexOf('function lineItemRow'), block.indexOf('function validLineItems'));
  const found = fn.match(/\.matches\('([^']+)'\)/);
  assert.ok(found, '1件の正規表現が見つかる');
  const source = found[1]
    .replaceAll('[^[:cntrl:]]', '[^\\u0000-\\u001F\\u007F]')
    .replaceAll('[[:cntrl:]]', '[\\u0000-\\u001F\\u007F]');
  return new RegExp(source, 'u');
}

const ID1 = 'E621E1F8-C36C-495A-93FC-0C247A3E6E5F';
const ID2 = '0F8FAD5B-D9CB-469F-A165-70867728950E';
const ID3 = '7C9E6679-7425-40DE-944B-E07FC1F90AE7';
const ID4 = '16FD2706-8BAF-433B-82EB-8C7FADA847DA';
const TAB = '\t';
const row = (...parts) => parts.join(TAB);

/** アプリ（Swift の SharedExpenseLineItemsPayload）が作る見本の行。Swift のテストでも同じ文字列を確かめる */
const GOLDEN = [
  row(ID1, '牛乳', '', '', '198'),
  row(ID2, 'ティッシュ', '2', '250', '500'),
  row(ID3, '量り売りのお米', '1.5', '400', '600'),
  row(ID4, 'おまけ', '', '', '0'),
];

describe('Build 21：商品明細のルール（形）', () => {
  it('決まった2項目（schemaVersion・rows）だけ。schemaVersion は 1。明細は1〜50件', () => {
    assert.ok(block.length > 0);
    assert.match(block, /data\.keys\(\)\.hasOnly\(\['schemaVersion', 'rows'\]\)/);
    assert.match(block, /data\.keys\(\)\.hasAll\(\['schemaVersion', 'rows'\]\)/);
    assert.match(block, /data\.schemaVersion == 1/);
    assert.match(block, /data\.rows is list/);
    assert.match(block, /data\.rows\.size\(\) >= 1/);
    assert.match(block, /data\.rows\.size\(\) <= 50/);
  });

  it('50件分すべての行を1件ずつ確かめる（0〜49 を1回ずつ。抜けも重なりもない）', () => {
    const indexes = [...block.matchAll(/&& lineItemRow\(data\.rows, (\d+)\)/g)].map((m) => Number(m[1]));
    assert.deepEqual(indexes, Array.from({ length: 50 }, (_, i) => i));
    assert.match(block, /return rows\.size\(\) <= index\s*\|\| rows\[index\]\.matches\(/);
  });

  it('読み書きはメンバーだけ。文書の ID は支出の UUID。その支出があるときだけ置ける（明細だけを作れない）', () => {
    assert.match(block, /allow read: if isMember\(groupID\);/);
    assert.match(block, /allow create, update: if isMember\(groupID\)\s*&& expenseID\.matches\('\^\[0-9A-Fa-f\]\{8\}-/);
    assert.match(block, /&& existsAfter\(\/databases\/\$\(database\)\/documents\/groups\/\$\(groupID\)\/expenses\/\$\(expenseID\)\)/);
    assert.match(block, /&& validLineItems\(request\.resource\.data\);/);
    assert.match(block, /allow delete: if isMember\(groupID\);/);
  });

  it('共有の支出は、商品明細が残っているあいだは消せない（明細だけが残らない）', () => {
    assert.match(expenseBlock, /allow delete: if isMember\(groupID\)\s*&& !existsAfter\(\/databases\/\$\(database\)\/documents\/groups\/\$\(groupID\)\/expenseLineItems\/\$\(expenseID\)\);/);
    // 支出そのものの形（9項目）は変えていない
    assert.match(expenseBlock, /keys\(\)\.hasOnly\(\[\s*'schemaVersion', 'title', 'amount', 'category', 'date', 'createdBy', 'updatedBy', 'createdAt', 'updatedAt'\s*\]\)/);
  });

  it('商品明細に、レシートの写真・全文・候補・信頼度・位置・メール・端末・トークンの項目は無い', () => {
    for (const word of ['image', 'photo', 'ocr', 'fullText', 'candidate', 'confidence', 'boundingBox', 'email', 'device', 'token', 'createdBy', 'updatedBy']) {
      assert.ok(!block.includes(`'${word}'`), word);
    }
  });
});

describe('Build 21：商品明細の1件の形（正規表現）', () => {
  const pattern = rowPattern();

  it('アプリが作る見本の行はすべて通る（明細ID・商品名・数量・単価・金額）', () => {
    for (const value of GOLDEN) assert.ok(pattern.test(value), JSON.stringify(value));
    // 小文字の UUID・80文字ちょうどの商品名・上限の金額・小数3桁の数量も通る
    assert.ok(pattern.test(row(ID1.toLowerCase(), 'あ'.repeat(80), '9999.999', '999999999', '999999999')));
    assert.ok(pattern.test(row(ID1, '😀'.repeat(80), '0.001', '0', '0')), '絵文字も1文字として数える');
  });

  it('商品名：空・81文字以上・制御文字（タブ・改行）入りは拒否', () => {
    assert.ok(!pattern.test(row(ID1, '', '', '', '198')), '空');
    assert.ok(!pattern.test(row(ID1, 'あ'.repeat(81), '', '', '198')), '81文字');
    assert.ok(!pattern.test(row(ID1, '牛\n乳', '', '', '198')), '改行');
    assert.ok(!pattern.test(row(ID1, '牛\u0001乳', '', '', '198')), '制御文字');
  });

  it('数量：0・負・10000 以上・小数4桁以上・数字でないものは拒否（空は「分からない」として通る）', () => {
    for (const quantity of ['0', '0.0', '0.000', '-1', '10000', '1.2345', '1,5', 'abc', '01', '.5', '1.', ' 2']) {
      assert.ok(!pattern.test(row(ID2, 'ティッシュ', quantity, '250', '500')), `数量 ${JSON.stringify(quantity)}`);
    }
    for (const quantity of ['', '1', '2', '1.5', '0.25', '9999']) {
      assert.ok(pattern.test(row(ID2, 'ティッシュ', quantity, '250', '500')), `数量 ${JSON.stringify(quantity)}`);
    }
  });

  it('単価・金額：0〜999,999,999 の整数だけ（負・小数・10桁・先頭の0・カンマ・円は拒否）。金額は必須', () => {
    for (const value of ['-1', '1.5', '1000000000', '01', '1,000', '198円', '¥198', 'abc']) {
      assert.ok(!pattern.test(row(ID2, 'ティッシュ', '2', value, '500')), `単価 ${value}`);
      assert.ok(!pattern.test(row(ID2, 'ティッシュ', '2', '250', value)), `金額 ${value}`);
    }
    assert.ok(!pattern.test(row(ID2, 'ティッシュ', '2', '250', '')), '金額が空');
    assert.ok(pattern.test(row(ID2, 'ティッシュ', '2', '', '500')), '単価は空でもよい');
  });

  it('明細ID が UUID でない・項目が多い／少ない行は拒否', () => {
    for (const id of ['', 'item-1', '12345678-1234-1234-1234-12345678901', `${ID1}x`]) {
      assert.ok(!pattern.test(row(id, '牛乳', '', '', '198')), id);
    }
    assert.ok(!pattern.test(row(ID1, '牛乳', '', '', '198', 'memo')), '6つ目の項目');
    assert.ok(!pattern.test(row(ID1, '牛乳', '', '198')), '項目が足りない');
    assert.ok(!pattern.test(JSON.stringify({ id: ID1, name: '牛乳', amount: 198 })), '別の形（JSON）');
  });
});

describe('Build 21：Functions と商品明細', () => {
  it('通知の Function は共有 ToDo・買い物（items）だけを見る。商品明細では動かない', () => {
    const triggers = index.match(/onDocument\w+\('([^']+)'/g) || [];
    assert.deepEqual(triggers, ["onDocumentWritten('groups/{groupID}/items/{itemID}'"]);
    assert.ok(!index.includes('expenseLineItems'));
  });

  it('退出・アカウント削除の整理は、商品明細に触れない（わが家ごと消すときだけ recursiveDelete で消える）', () => {
    assert.ok(!householdStore.includes('expenseLineItems'));
    assert.ok(!cleanupRunner.includes('expenseLineItems'));
    assert.match(householdStore, /recursiveDelete\(db\.doc\(`groups\/\$\{groupID\}`\)\)/);
    assert.match(cleanupRunner, /recursiveDelete\(groupRef\)/);
  });
});
