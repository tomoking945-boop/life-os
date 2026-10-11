'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { shouldSend, collapseID, COLLAPSE_WINDOW_MS } = require('../../src/throttle');

test('初めては送る', () => {
  assert.equal(shouldSend(null, 1000), true);
});

test('30秒以内の同じ項目はまとめる（送らない）', () => {
  assert.equal(COLLAPSE_WINDOW_MS, 30000);
  assert.equal(shouldSend(0, 29999), false);
  assert.equal(shouldSend(0, 30000), true);
});

test('collapse id は 64 文字まで', () => {
  assert.equal(collapseID('g1', 'i1'), 'g1:i1');
  assert.equal(collapseID('g'.repeat(40), 'i'.repeat(40)).length, 64);
});
