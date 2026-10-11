'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  generateToken, isValidTokenFormat, hashToken, buildInviteURL,
  validateInviteForAccept, sanitizeDisplayName, INVITE_TTL_MS, TOKEN_LENGTH,
} = require('../../src/invites');

test('トークンは 43 文字の base64url で、毎回ちがう', () => {
  const a = generateToken();
  const b = generateToken();
  assert.equal(a.length, TOKEN_LENGTH);
  assert.ok(isValidTokenFormat(a));
  assert.notEqual(a, b);
  assert.equal(isValidTokenFormat('short'), false);
  assert.equal(isValidTokenFormat(`${a.slice(0, 42)}/`), false);
  assert.equal(isValidTokenFormat(undefined), false);
});

test('保存するのはハッシュだけ（生のトークンと同じにならない）', () => {
  const token = generateToken();
  const hash = hashToken(token);
  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.notEqual(hash, token);
  assert.equal(hashToken(token), hash);
});

test('招待の URL', () => {
  assert.equal(buildInviteURL('https://example.web.app/', 'abc'), 'https://example.web.app/invite?token=abc');
});

test('期限は 24 時間・一度だけ・自分の招待は使えない・すでにメンバーなら使えない', () => {
  const now = Date.parse('2026-10-11T12:00:00Z');
  const invite = { groupID: 'g', createdBy: 'alice', expiresAt: new Date(now + INVITE_TTL_MS), usedAt: null, usedBy: null };
  assert.equal(INVITE_TTL_MS, 86400000);
  assert.deepEqual(validateInviteForAccept(invite, 'bob', now), { ok: true });
  assert.equal(validateInviteForAccept(null, 'bob', now).code, 'not-found');
  assert.equal(validateInviteForAccept(invite, 'bob', now + INVITE_TTL_MS).code, 'expired');
  assert.equal(validateInviteForAccept({ ...invite, usedAt: new Date(now), usedBy: 'carol' }, 'bob', now).code, 'already-used');
  assert.equal(validateInviteForAccept(invite, 'alice', now).code, 'own-invite');
  assert.equal(validateInviteForAccept(invite, 'bob', now, { isAlreadyMember: true }).code, 'already-member');
  assert.equal(validateInviteForAccept({ ...invite, expiresAt: { seconds: (now - 1) / 1000, nanoseconds: 0 } }, 'bob', now).code, 'expired');
});

test('表示名の整え', () => {
  assert.equal(sanitizeDisplayName('  池上 '), '池上');
  assert.equal(sanitizeDisplayName(''), 'メンバー');
  assert.equal(sanitizeDisplayName(null), 'メンバー');
  assert.equal(Array.from(sanitizeDisplayName('あ'.repeat(60))).length, 40);
});
