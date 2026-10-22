'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  generateToken, isValidTokenFormat, hashToken, buildInviteURL,
  validateInviteForAccept, sanitizeDisplayName, INVITE_TTL_MS, TOKEN_LENGTH,
  isActiveInvite, isRevocableInvite,
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

test('取り消し・同じ人の2回目・満員・別のわが家・グループが無い（2026-10-22）', () => {
  const now = Date.parse('2026-10-22T12:00:00Z');
  const invite = { groupID: 'g', createdBy: 'alice', expiresAt: new Date(now + INVITE_TTL_MS), usedAt: null, usedBy: null, revokedAt: null };
  const room = { memberCount: 1, maxMembers: 2, groupExists: true };
  assert.deepEqual(validateInviteForAccept(invite, 'bob', now, room), { ok: true });
  assert.equal(validateInviteForAccept({ ...invite, revokedAt: new Date(now) }, 'bob', now, room).code, 'revoked');
  assert.equal(validateInviteForAccept(invite, 'bob', now, { ...room, memberCount: 2 }).code, 'household-full');
  assert.equal(validateInviteForAccept(invite, 'bob', now, { ...room, inOtherHousehold: true }).code, 'already-in-household');
  assert.equal(validateInviteForAccept(invite, 'bob', now, { ...room, groupExists: false }).code, 'not-found');
  // 同じ人がこの招待で参加済み（同じ参加が2回届いた）→ 成功（何も書かない）。期限が過ぎていても同じ
  const used = { ...invite, usedAt: new Date(now), usedBy: 'bob' };
  assert.deepEqual(validateInviteForAccept(used, 'bob', now + INVITE_TTL_MS * 2, { ...room, memberCount: 2, isAlreadyMember: true }), { ok: true, alreadyJoined: true });
  // 別の人には使用済み
  assert.equal(validateInviteForAccept(used, 'carol', now, room).code, 'already-used');
  // 取り消しは、使用済み・期限切れより先に伝える
  assert.equal(validateInviteForAccept({ ...invite, revokedAt: new Date(now), expiresAt: new Date(now - 1) }, 'bob', now, room).code, 'revoked');
});

test('有効な招待・取り消せる招待', () => {
  const now = Date.parse('2026-10-22T12:00:00Z');
  const invite = { expiresAt: new Date(now + 1000), usedAt: null, revokedAt: null };
  assert.equal(isActiveInvite(invite, now), true);
  assert.equal(isActiveInvite({ ...invite, expiresAt: new Date(now) }, now), false);
  assert.equal(isActiveInvite({ ...invite, usedAt: new Date(now) }, now), false);
  assert.equal(isActiveInvite({ ...invite, revokedAt: new Date(now) }, now), false);
  assert.equal(isActiveInvite(null, now), false);
  assert.equal(isRevocableInvite(invite), true);
  assert.equal(isRevocableInvite({ ...invite, expiresAt: new Date(now - 1) }), true, '期限切れも閉じる');
  assert.equal(isRevocableInvite({ ...invite, usedAt: new Date(now) }), false);
  assert.equal(isRevocableInvite({ ...invite, revokedAt: new Date(now) }), false);
});
