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
  ownInvite: 'own-invite',
  alreadyMember: 'already-member',
});

/**
 * 招待を受け入れてよいか（トランザクションの中で、読み取った招待に対して使う）
 * @param {object|null} invite `invites/{tokenHash}` の内容
 * @param {string} uid 受け入れる人
 * @param {number} nowMs いまの時刻
 * @param {{isAlreadyMember?: boolean}} [state]
 * @returns {{ok: true} | {ok: false, code: string}}
 */
function validateInviteForAccept(invite, uid, nowMs, state = {}) {
  if (!invite) return { ok: false, code: InviteError.notFound };
  if (invite.usedAt !== null && invite.usedAt !== undefined) return { ok: false, code: InviteError.alreadyUsed };
  const expiresAt = toMillisLocal(invite.expiresAt);
  if (expiresAt === null || nowMs >= expiresAt) return { ok: false, code: InviteError.expired };
  if (invite.createdBy === uid) return { ok: false, code: InviteError.ownInvite };
  if (state.isAlreadyMember) return { ok: false, code: InviteError.alreadyMember };
  return { ok: true };
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
  sanitizeDisplayName,
};
