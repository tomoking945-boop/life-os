'use strict';

/**
 * 削除トリガーの作り方を index.js の中身で確かめる（firebase なしで動く）。
 * 実際に動くことは test/emulator/accountDeletion.test.js（Auth Emulator で利用者を削除）で確かめる。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.join(__dirname, '../../index.js'), 'utf8');
const runner = fs.readFileSync(path.join(__dirname, '../../src/accountCleanupRunner.js'), 'utf8');

function triggerBlock() {
  const start = source.indexOf('exports.onAuthUserDeleted =');
  assert.ok(start >= 0, 'onAuthUserDeleted が無い');
  return source.slice(start);
}

describe('アカウント削除のトリガー', () => {
  it('安定版（第1世代）の Authentication 削除トリガーを使う。プレビュー版や blocking 関数は使わない', () => {
    assert.match(source, /require\('firebase-functions\/v1'\)/);
    const block = triggerBlock();
    assert.match(block, /\.auth\.user\(\)\s*\.onDelete\(/);
    assert.match(block, /\.region\(REGION\)/);
    assert.match(block, /failurePolicy: true/, '失敗したらやり直す');
    assert.doesNotMatch(source, /v2\/identity|beforeUserDeleted|\/beta|alpha/);
  });

  it('ログに個人の情報（メール・Apple の情報・端末トークン・名前・電話）を出さない', () => {
    const block = triggerBlock();
    for (const word of ['email', 'providerData', 'phoneNumber', 'displayName', 'fcmToken', 'photoURL']) {
      assert.equal(block.includes(word), false, word);
    }
    assert.doesNotMatch(runner, /console\.|logger\./, '整理の処理の中ではログを出さない（件数だけを返す）');
  });

  it('失敗を握りつぶさず、エラーにしてやり直してもらう', () => {
    assert.match(triggerBlock(), /throw new Error\(/);
  });

  it('acceptInvite が作るメンバー文書に uid を入れる', () => {
    assert.match(source, /transaction\.set\(memberRef, \{ uid, role: 'member'/);
  });
});
