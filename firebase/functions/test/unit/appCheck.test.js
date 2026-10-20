'use strict';

/**
 * 招待の Callable Function が App Check を必須にしていることを、index.js の中身で確かめる（2026-10-20 監査）。
 * firebase なしで動く。実際に断られることは Functions Emulator のテスト（test/emulator/functions.test.js）で確かめる。
 */

const fs = require('node:fs');
const path = require('node:path');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.join(__dirname, '../../index.js'), 'utf8');

describe('招待の App Check', () => {
  it('createInvite と acceptInvite は enforceAppCheck: true で作られている', () => {
    for (const name of ['createInvite', 'acceptInvite']) {
      const pattern = new RegExp(`exports\\.${name} = onCall\\(\\{ enforceAppCheck: true \\}, async \\(request\\) => \\{`);
      assert.match(source, pattern, `${name} に enforceAppCheck: true が無い`);
    }
    // App Check を必須にしない Callable を増やさない
    const callables = source.match(/onCall\(/g) || [];
    const enforced = source.match(/onCall\(\{ enforceAppCheck: true \}/g) || [];
    assert.equal(callables.length, 2);
    assert.equal(enforced.length, callables.length);
  });

  it('App Check があってもサインインの確認（requireUID）は省かない', () => {
    for (const name of ['createInvite', 'acceptInvite']) {
      const start = source.indexOf(`exports.${name} =`);
      const body = source.slice(start, start + 200);
      assert.match(body, /const uid = requireUID\(request\);/, `${name} がサインインを確かめていない`);
    }
  });

  it('onSharedItemWritten は Firestore のトリガー（Callable ではない）', () => {
    assert.match(source, /exports\.onSharedItemWritten = onDocumentWritten\(/);
  });
});
