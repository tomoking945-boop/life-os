'use strict';

const crypto = require('node:crypto');

/**
 * 招待（仕様 4・8）：期限つき（24時間）・一度だけ使える招待トークン。
 * 生のトークンは Firestore に保存せず、SHA-256 のハッシュだけを `invites/{tokenHash}` に保存する。
 */
const INVITE_TTL_MS = 24 * 60 * 60 * 1000;
/** 32 バイトの乱数を base64url にした長さ */
const TOKEN_LENGTH = 43;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/** 新しい招待トークン（推測できない 256 ビットの乱数） */
function generateToken(randomBytes = crypto.randomBytes) {
  return randomBytes(32).toString('base64url');
}

function isValidTokenFormat(token) {
  return typeof token === 'string' && TOKEN_PATTERN.test(token);
}

/** トークンのハッシュ（保存用・照合用） */
function hashToken(token) {
  return crypto.createHash('sha256').update(token, 'utf8').digest('hex');
}

/** 招待の URL（Universal Link）。トークンは URL の中だけにあり、サーバーには残らない */
function buildInviteURL(baseURL, token) {
  const base = String(baseURL || '').replace(/\/+$/, '');
  return `${base}/invite?token=${encodeURIComponent(token)}`;
}

const InviteError = Object.freeze({
  notFound: 'not-found',
  expired: 'expired',
  alreadyUsed: 'already-used',
  revoked: 'revoked',
  ownInvite: 'own-invite',
  alreadyMember: 'already-member',
  alreadyInHousehold: 'already-in-household',
  householdFull: 'household-full',
});

/**
 * 招待を受け入れてよいか（参加の前の確認・参加のトランザクションの中で、読み取った招待に対して使う）
 * docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md
 *
 * 順番：
 *   1. 招待が無い → not-found
 *   2. 同じ人がこの招待で参加済み（同じ参加の処理が2回届いた）→ ok（alreadyJoined。何も書かない）
 *   3. 取り消し済み → revoked、使用済み → already-used、期限切れ → expired
 *   4. 自分で作った招待 → own-invite
 *   5. グループがもう無い → not-found
 *   6. すでにこのグループのメンバー → already-member、別のわが家に参加中 → already-in-household
 *   7. 満員 → household-full
 *
 * @param {object|null} invite `invites/{tokenHash}` の内容
 * @param {string} uid 受け入れる人
 * @param {number} nowMs いまの時刻
 * @param {{isAlreadyMember?: boolean, inOtherHousehold?: boolean, groupExists?: boolean,
 *          memberCount?: number, maxMembers?: number}} [state]
 * @returns {{ok: true, alreadyJoined?: boolean} | {ok: false, code: string}}
 */
function validateInviteForAccept(invite, uid, nowMs, state = {}) {
  if (!invite) return { ok: false, code: InviteError.notFound };
  if (invite.usedBy === uid && state.isAlreadyMember) return { ok: true, alreadyJoined: true };
  if (invite.revokedAt !== null && invite.revokedAt !== undefined) return { ok: false, code: InviteError.revoked };
  if (invite.usedAt !== null && invite.usedAt !== undefined) return { ok: false, code: InviteError.alreadyUsed };
  const expiresAt = toMillisLocal(invite.expiresAt);
  if (expiresAt === null || nowMs >= expiresAt) return { ok: false, code: InviteError.expired };
  if (invite.createdBy === uid) return { ok: false, code: InviteError.ownInvite };
  if (state.groupExists === false) return { ok: false, code: InviteError.notFound };
  if (state.isAlreadyMember) return { ok: false, code: InviteError.alreadyMember };
  if (state.inOtherHousehold) return { ok: false, code: InviteError.alreadyInHousehold };
  if (typeof state.memberCount === 'number' && typeof state.maxMembers === 'number' && state.memberCount >= state.maxMembers) {
    return { ok: false, code: InviteError.householdFull };
  }
  return { ok: true };
}

/** 未使用・未取り消し・期限内の招待か */
function isActiveInvite(invite, nowMs) {
  if (!invite) return false;
  if (invite.usedAt !== null && invite.usedAt !== undefined) return false;
  if (invite.revokedAt !== null && invite.revokedAt !== undefined) return false;
  const expiresAt = toMillisLocal(invite.expiresAt);
  return expiresAt !== null && nowMs < expiresAt;
}

/** 取り消してよい招待か（未使用・未取り消し。期限切れも含めて閉じる） */
function isRevocableInvite(invite) {
  if (!invite) return false;
  const used = invite.usedAt !== null && invite.usedAt !== undefined;
  const revoked = invite.revokedAt !== null && invite.revokedAt !== undefined;
  return !used && !revoked;
}

function toMillisLocal(value) {
  return require('./timestamps').toMillis(value);
}

/** 表示名の整え（空なら「メンバー」、長すぎるものは切る） */
function sanitizeDisplayName(value) {
  const name = typeof value === 'string' ? value.trim() : '';
  if (!name) return 'メンバー';
  return Array.from(name).slice(0, 40).join('');
}

module.exports = {
  INVITE_TTL_MS,
  TOKEN_LENGTH,
  InviteError,
  generateToken,
  isValidTokenFormat,
  hashToken,
  buildInviteURL,
  validateInviteForAccept,
  isActiveInvite,
  isRevocableInvite,
  sanitizeDisplayName,
};
