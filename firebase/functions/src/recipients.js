'use strict';

/**
 * 通知の宛先を選ぶ（仕様 5・6）。
 * - 操作した本人（の、すべての端末）には送らない
 * - 通知を許可していない端末・「共有の更新」を切っている端末には送らない
 * - 同じトークンは1回だけ
 */

/**
 * @param {{memberUIDs: string[], actorUID: string, devicesByUID: Object<string, Array<{id: string, fcmToken: string, notificationsEnabled?: boolean, sharedUpdatesEnabled?: boolean, showsPreview?: boolean}>>}} input
 * @returns {Array<{uid: string, deviceID: string, token: string, showsPreview: boolean}>}
 */
function selectRecipients({ memberUIDs, actorUID, devicesByUID }) {
  const seen = new Set();
  const result = [];
  for (const uid of memberUIDs || []) {
    if (!uid || uid === actorUID) continue;
    for (const device of (devicesByUID && devicesByUID[uid]) || []) {
      if (!device || typeof device.fcmToken !== 'string' || !device.fcmToken) continue;
      if (device.notificationsEnabled !== true || device.sharedUpdatesEnabled !== true) continue;
      if (seen.has(device.fcmToken)) continue;
      seen.add(device.fcmToken);
      result.push({ uid, deviceID: device.id, token: device.fcmToken, showsPreview: device.showsPreview === true });
    }
  }
  return result;
}

/** 送信結果がこれらのエラーなら、そのトークンはもう使えない（アプリ削除・ログアウトなど） */
const INVALID_TOKEN_CODES = Object.freeze([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * 送信結果から、削除する端末を選ぶ
 * @param {Array<{uid: string, deviceID: string}>} recipients 送った順
 * @param {Array<{success: boolean, error?: {code?: string}}>} responses recipients と同じ順
 */
function devicesToRemove(recipients, responses) {
  const removals = [];
  (responses || []).forEach((response, index) => {
    const code = response && response.error && response.error.code;
    if (response && !response.success && INVALID_TOKEN_CODES.includes(code) && recipients[index]) {
      removals.push({ uid: recipients[index].uid, deviceID: recipients[index].deviceID });
    }
  });
  return removals;
}

module.exports = { selectRecipients, devicesToRemove, INVALID_TOKEN_CODES };
