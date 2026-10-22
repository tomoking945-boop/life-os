'use strict';

const { toMillis } = require('./timestamps');

/**
 * 「わが家」（生活グループ）の決まりごと（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）。
 * firebase-admin に依存しない（単体テストでそのまま確かめる）。
 *
 * - 1人が参加できる「わが家」は1つ
 * - 最大2人（オーナー＋パートナー）
 * - 招待を作る・取り消すのはオーナーだけ
 * - 共有する種類は、下の決まった英語の値だけ（アプリの SharedSpaceKind と同じ。テストで一致を確かめる）
 */

/**
 * 共有する種類（保存する値）。並びは画面の並びと同じ
 * - event：予定、todo：ToDo、chore：家事、shopping：買い物（共有項目 items の kind と同じ値）
 * - money：家計簿、warranty：保証書、list：リスト・メモ
 */
const SHARED_SPACE_KINDS = Object.freeze(['event', 'todo', 'chore', 'shopping', 'money', 'warranty', 'list']);

/** はじめに選んでおく種類 */
const DEFAULT_SHARED_SPACE_KINDS = Object.freeze(['todo', 'shopping']);

/** 1つのわが家の人数の上限（オーナー＋パートナー） */
const MAX_MEMBERS = 2;

/** わが家の名前の初期値と、長さの上限（Security Rules の groups の name と同じ 50 文字） */
const DEFAULT_GROUP_NAME = 'わが家';
const MAX_GROUP_NAME_LENGTH = 50;

const HouseholdError = Object.freeze({
  invalidKinds: 'invalid-kinds',
  invalidName: 'invalid-name',
  alreadyInHousehold: 'already-in-household',
  noHousehold: 'no-household',
  notOwner: 'not-owner',
  householdFull: 'household-full',
});

/**
 * 共有する種類を確かめる。1〜7種類・決まった値だけ・重複なし。保存するときは決まった並びにそろえる
 * @returns {{ok: true, kinds: string[]} | {ok: false, code: string}}
 */
function validateSharedKinds(value) {
  const invalid = { ok: false, code: HouseholdError.invalidKinds };
  if (!Array.isArray(value)) return invalid;
  if (value.length === 0 || value.length > SHARED_SPACE_KINDS.length) return invalid;
  if (!value.every((kind) => typeof kind === 'string' && SHARED_SPACE_KINDS.includes(kind))) return invalid;
  if (new Set(value).size !== value.length) return invalid;
  return { ok: true, kinds: SHARED_SPACE_KINDS.filter((kind) => value.includes(kind)) };
}

/**
 * わが家の名前を確かめる（前後の空白を除く。空・長すぎる・制御文字は不可）
 * @returns {{ok: true, name: string} | {ok: false, code: string}}
 */
function validateGroupName(value) {
  const invalid = { ok: false, code: HouseholdError.invalidName };
  if (typeof value !== 'string') return invalid;
  const name = value.trim();
  if (name.length === 0) return invalid;
  if (Array.from(name).length > MAX_GROUP_NAME_LENGTH) return invalid;
  // 改行・タブなどの制御文字は使わない
  if (/[\u0000-\u001F\u007F]/.test(name)) return invalid;
  return { ok: true, name };
}

/** 役割の並び（オーナーが先） */
function roleOrder(role) {
  return role === 'owner' ? 0 : 1;
}

/**
 * アプリに返すわが家の情報。UID・メール・トークンは入れない（自分かどうかと役割だけ）
 * @param {{name: string, sharedKinds?: string[]}} group
 * @param {{uid: string, role: string, joinedAt?: unknown}[]} members
 * @param {string} viewerUID 見ている人
 * @param {{expiresAt: unknown}|null} activeInvite 有効な招待（オーナーにだけ返す）
 */
function buildHouseholdSummary(group, members, viewerUID, activeInvite) {
  const viewer = members.find((member) => member.uid === viewerUID);
  const isOwner = Boolean(viewer && viewer.role === 'owner');
  const kinds = Array.isArray(group.sharedKinds) ? SHARED_SPACE_KINDS.filter((kind) => group.sharedKinds.includes(kind)) : [];
  const list = members
    .map((member) => ({
      role: member.role === 'owner' ? 'owner' : 'member',
      isSelf: member.uid === viewerUID,
      joinedAt: toMillis(member.joinedAt),
    }))
    .sort((a, b) => roleOrder(a.role) - roleOrder(b.role) || (a.joinedAt || 0) - (b.joinedAt || 0));
  return {
    name: typeof group.name === 'string' ? group.name : DEFAULT_GROUP_NAME,
    sharedKinds: kinds,
    isOwner,
    members: list,
    maxMembers: MAX_MEMBERS,
    activeInvite: isOwner && activeInvite ? { expiresAt: toMillis(activeInvite.expiresAt) } : null,
  };
}

/**
 * 参加の前に見せる招待の内容。グループ名・共有する種類・期限だけ（招待した人の情報・UID は入れない）
 */
function buildInvitePreview(group, invite) {
  return {
    groupName: typeof group.name === 'string' ? group.name : DEFAULT_GROUP_NAME,
    sharedKinds: Array.isArray(group.sharedKinds) ? SHARED_SPACE_KINDS.filter((kind) => group.sharedKinds.includes(kind)) : [],
    expiresAt: toMillis(invite.expiresAt),
  };
}

/** 招待の一覧から、いま有効な招待（いちばん新しいもの）を選ぶ */
function pickActiveInvite(invites, nowMs, isActive) {
  return invites
    .filter((invite) => isActive(invite, nowMs))
    .sort((a, b) => (toMillis(b.createdAt) || 0) - (toMillis(a.createdAt) || 0))[0] || null;
}

module.exports = {
  SHARED_SPACE_KINDS,
  DEFAULT_SHARED_SPACE_KINDS,
  MAX_MEMBERS,
  DEFAULT_GROUP_NAME,
  MAX_GROUP_NAME_LENGTH,
  HouseholdError,
  validateSharedKinds,
  validateGroupName,
  buildHouseholdSummary,
  buildInvitePreview,
  pickActiveInvite,
};
