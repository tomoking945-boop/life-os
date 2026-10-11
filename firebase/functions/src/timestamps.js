'use strict';

/**
 * Firestore の Timestamp・Date・{seconds, nanoseconds}・数値（ミリ秒）を、ミリ秒の数値にそろえる。
 * 無い（null / undefined）ときは null。
 * firebase-admin に依存しない（単体テストをどこでも動かせるようにするため）。
 */
function toMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.seconds === 'number') {
    return value.seconds * 1000 + Math.floor((value.nanoseconds || 0) / 1e6);
  }
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000 + Math.floor((value._nanoseconds || 0) / 1e6);
  }
  return null;
}

module.exports = { toMillis };
