'use strict';

/**
 * 同じグループ・同じ項目への通知を、30秒以内はまとめる（仕様 6）。
 * 最後に送った時刻から 30 秒たっていなければ送らない。
 * あわせて APNs の collapse id に項目 ID を使い、端末側でも同じ項目の通知を1つにまとめる。
 */
const COLLAPSE_WINDOW_MS = 30 * 1000;

/**
 * @param {number|null} lastSentAtMs 最後に送った時刻（ミリ秒。送ったことが無ければ null）
 * @param {number} nowMs いまの時刻（ミリ秒）
 */
function shouldSend(lastSentAtMs, nowMs, windowMs = COLLAPSE_WINDOW_MS) {
  if (lastSentAtMs === null || lastSentAtMs === undefined) return true;
  return nowMs - lastSentAtMs >= windowMs;
}

/** collapse id（APNs は 64 バイトまで） */
function collapseID(groupID, itemID) {
  return `${groupID}:${itemID}`.slice(0, 64);
}

module.exports = { COLLAPSE_WINDOW_MS, shouldSend, collapseID };
