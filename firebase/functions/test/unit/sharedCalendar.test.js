'use strict';

/**
 * Build 14（2026-11-01）：カレンダーから作る予定の共有（groups/{groupID}/items の kind: 'event'）。
 * docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md
 * Emulator を使わずに確かめられること（決まりごととソース）。ルールの動きそのものは test/emulator/rules.test.js で確かめる。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  SHARED_SPACE_KINDS, SYNC_SUPPORTED_KINDS, DEFAULT_SHARED_SPACE_KINDS, planSharedKindsUpdate,
} = require('../../src/household');
const { decide, NOTIFY_KINDS } = require('../../src/notificationPolicy');

const read = (relative) => fs.readFileSync(path.join(__dirname, relative), 'utf8');
const index = read('../../index.js');
const rules = read('../../../../firestore.rules');

const event = {
  schemaVersion: 1,
  title: '歯医者',
  kind: 'event',
  date: new Date('2026-11-05T10:30:00+09:00'),
  hasTime: true,
  assigneeUID: null,
  isCompleted: false,
  createdBy: 'alice',
  updatedBy: 'alice',
};

describe('Build 14：予定の共有（わが家の設定）', () => {
  it('予定（event）は同期できる種類。はじめに選んでおく種類は ToDo・買い物のまま（予定を自動でオンにしない）', () => {
    assert.ok(SYNC_SUPPORTED_KINDS.includes('event'));
    assert.ok(SHARED_SPACE_KINDS.includes('event'));
    assert.deepEqual(DEFAULT_SHARED_SPACE_KINDS, ['todo', 'shopping']);
    assert.ok(!DEFAULT_SHARED_SPACE_KINDS.includes('event'));
  });

  it('予定をオン・オフできる（ほかの種類は変えない）', () => {
    assert.deepEqual(planSharedKindsUpdate(['todo', 'shopping'], ['event', 'todo', 'shopping']), { ok: true, kinds: ['event', 'todo', 'shopping'] });
    assert.deepEqual(planSharedKindsUpdate(['event', 'todo', 'shopping', 'money'], ['todo', 'shopping', 'money']), { ok: true, kinds: ['todo', 'shopping', 'money'] }, '予定だけをオフ');
    assert.deepEqual(planSharedKindsUpdate(['todo'], ['event']), { ok: true, kinds: ['event'] }, '予定だけでもよい');
    assert.deepEqual(planSharedKindsUpdate(['event', 'chore', 'warranty'], ['todo']), { ok: true, kinds: ['todo', 'chore', 'warranty'] }, '今後対応の種類は残す');
  });
});

describe('Build 14：予定はプッシュ通知しない（ToDo・買い物の通知は変えない）', () => {
  it('通知する種類は ToDo・買い物だけのまま', () => {
    assert.deepEqual(NOTIFY_KINDS, ['todo', 'shopping']);
    assert.ok(!NOTIFY_KINDS.includes('event'));
  });

  it('共有の予定の追加・名前の変更・日時の変更・削除では通知しない', () => {
    assert.equal(decide(null, event).notify, false);
    assert.equal(decide(event, { ...event, title: '歯医者（再診）', updatedBy: 'bob' }).notify, false);
    assert.equal(decide(event, { ...event, date: new Date('2026-11-06T10:30:00+09:00'), updatedBy: 'bob' }).notify, false);
    assert.equal(decide(event, null).notify, false);
    assert.equal(decide(null, event, { notifyCompletion: true }).notify, false);
  });

  it('ToDo・買い物の通知はこれまでどおり', () => {
    assert.equal(decide(null, { ...event, kind: 'todo' }).type, 'taskAdded');
    assert.equal(decide(null, { ...event, kind: 'shopping' }).type, 'taskAdded');
  });

  it('Functions の通知のきっかけは、これまでどおり共有項目（items）の1つだけ', () => {
    const triggers = index.match(/onDocumentWritten\('([^']+)'/g) || [];
    assert.deepEqual(triggers, ["onDocumentWritten('groups/{groupID}/items/{itemID}'"]);
  });
});

describe('Build 14：ルール（共有項目 items）', () => {
  const block = rules.slice(rules.indexOf('match /items/{itemID}'), rules.indexOf('match /expenses/{expenseID}'));

  it('新しく作れるのは 予定・ToDo・買い物。家事は作れない。わが家の設定でオンの種類だけ', () => {
    assert.ok(block.length > 0);
    assert.match(block, /request\.resource\.data\.kind in \['event', 'todo', 'shopping'\]/);
    assert.match(block, /&& kindIsEnabled\(request\.resource\.data\.kind\)/);
    assert.match(block, /&& validNewEvent\(request\.resource\.data\)/);
    assert.ok(!/kind in \['event', 'todo', 'chore', 'shopping'\]\s*\n\s*&& kindIsEnabled/.test(block), '作成で家事を許さない');
  });

  it('作成者・作成日時・更新者・更新日時は本人とサーバーの時刻', () => {
    assert.match(block, /request\.resource\.data\.createdBy == request\.auth\.uid/);
    assert.match(block, /request\.resource\.data\.createdAt == request\.time/);
    assert.match(block, /data\.updatedBy == request\.auth\.uid/);
    assert.match(block, /data\.updatedAt == request\.time/);
  });

  it('予定は、完了なし・担当なし・あとで／もうやらないの印なしでだけ作れる', () => {
    const fn = block.slice(block.indexOf('function validNewEvent'), block.indexOf('allow read'));
    assert.match(fn, /data\.kind != 'event'/);
    assert.match(fn, /data\.isCompleted == false/);
    assert.match(fn, /data\.get\('assigneeUID', null\) == null/);
    assert.match(fn, /data\.get\('deferredTo', null\) == null/);
    assert.match(fn, /data\.get\('droppedAt', null\) == null/);
  });

  it('決まった項目だけ（メモ・場所・メールアドレス・端末・トークン・外部カレンダーの項目は書けない）', () => {
    assert.match(block, /keys\(\)\.hasOnly\(\[\s*'schemaVersion', 'title', 'kind', 'date', 'hasTime', 'assigneeUID', 'isCompleted',\s*'deferredTo', 'droppedAt', 'createdBy', 'updatedBy', 'createdAt', 'updatedAt'\s*\]\)/);
    for (const word of ['memo', 'note', 'location', 'email', 'device', 'token', 'calendarIdentifier', 'externalID']) {
      assert.ok(!block.includes(`'${word}'`), word);
    }
  });

  it('読む・消すのはメンバーだけ。予定をオフにしたあとも消せる（削除は種類の設定を見ない）', () => {
    assert.match(block, /allow read: if isMember\(groupID\);/);
    assert.match(block, /allow delete: if isMember\(groupID\);/);
  });
});
