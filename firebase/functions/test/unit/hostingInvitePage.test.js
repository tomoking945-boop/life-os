'use strict';

/**
 * 招待の案内ページ（firebase/hosting/invite）の「くらしOSで開く」ボタンのテスト（2026-10-28。docs/INVITE_OPEN_BUTTON_FIX.md）
 * ブラウザ・ネットワークを使わない（ページの仕組み invite.js を Node で直接動かす）。
 */

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const hostingDir = path.join(__dirname, '../../../hosting');
const page = require(path.join(hostingDir, 'invite/invite.js'));
const html = fs.readFileSync(path.join(hostingDir, 'invite/index.html'), 'utf8');
const script = fs.readFileSync(path.join(hostingDir, 'invite/invite.js'), 'utf8');

const newToken = () => crypto.randomBytes(32).toString('base64url');

/** ボタンと案内だけを持つ、小さなページのまね */
function fakePage(search) {
  const listeners = [];
  const button = {
    disabled: true,
    attributes: { 'aria-disabled': 'true' },
    setAttribute(name, value) { this.attributes[name] = value; },
    removeAttribute(name) { delete this.attributes[name]; },
    addEventListener(type, handler) { listeners.push({ type, handler }); },
  };
  const invalid = { hidden: true };
  const doc = { getElementById: (id) => ({ 'open-app': button, 'invalid-link': invalid }[id] || null) };
  const location = { search, href: `https://kurashi-os-production.web.app/invite${search}` };
  return { doc, location, button, invalid, listeners };
}

describe('招待の案内ページ：トークンの読み取り', () => {
  it('正しい形のトークンだけを読む（アプリの InviteLink と同じ確かめ方）', () => {
    const token = newToken();
    assert.equal(page.readToken(`?token=${token}`), token);
    for (const search of [
      '', '?', '?token=', '?token', `?Token=${token}`, `?token=${token.slice(0, 42)}`, `?token=${token}A`,
      `?token=${token.slice(0, 42)}+`, `?token=${token.slice(0, 42)}/`, `?token=${token.slice(0, 40)}%41`,
      `?token=${token}&token=${token}`, `?token=${token}&x=1`, `?x=1&token=${token}`, `?token=${'a'.repeat(300)}`,
      null, undefined, 5,
    ]) {
      assert.equal(page.readToken(search), null, String(search));
    }
  });
});

describe('招待の案内ページ：アプリを開く URL', () => {
  it('くらしOS専用の URL Scheme で、トークンを URL エンコードして組み立てる', () => {
    const token = newToken();
    assert.equal(page.APP_SCHEME, 'com.tomoking945boop.lifeos');
    assert.equal(page.buildAppURL(token), `com.tomoking945boop.lifeos://invite?token=${encodeURIComponent(token)}`);
    assert.match(script, /:\/\/invite\?token=' \+ encodeURIComponent\(token\)/, 'encodeURIComponent でエンコードする');
    // 形が正しくないものは組み立てない（エンコードで逃がさない）
    for (const bad of ['', 'short', `${token.slice(0, 42)}&`, `${token.slice(0, 42)}#`, '../'.repeat(15), null]) {
      assert.equal(page.buildAppURL(bad), null, String(bad));
    }
  });
});

describe('招待の案内ページ：ボタン', () => {
  it('正しいトークンのときだけ押せる。押したときだけアプリを開く（読み込んだだけでは開かない）', () => {
    const token = newToken();
    const p = fakePage(`?token=${token}`);
    const before = p.location.href;
    page.setUp(p.doc, p.location);
    assert.equal(p.button.disabled, false);
    assert.equal(p.button.attributes['aria-disabled'], undefined);
    assert.equal(p.invalid.hidden, true);
    assert.equal(p.location.href, before, '読み込んだだけでは移動しない');
    assert.equal(p.listeners.length, 1);
    p.listeners[0].handler();
    assert.equal(p.location.href, `com.tomoking945boop.lifeos://invite?token=${token}`);
  });

  it('トークンが無い・正しくないときは、ボタンを押せなくして「招待リンクが正しくありません」を出す', () => {
    for (const search of ['', '?token=short', `?token=${newToken()}&x=1`]) {
      const p = fakePage(search);
      page.setUp(p.doc, p.location);
      assert.equal(p.button.disabled, true, search);
      assert.equal(p.button.attributes['aria-disabled'], 'true');
      assert.equal(p.invalid.hidden, false);
      assert.equal(p.listeners.length, 0, '押しても何もしない');
    }
  });
});

describe('招待の案内ページ：中身', () => {
  it('ボタン・案内・説明の文言があり、はじめはボタンを押せない', () => {
    assert.match(html, /<button id="open-app" class="open" type="button" disabled aria-disabled="true">くらしOSで開く<\/button>/);
    assert.match(html, /<p id="invalid-link" class="invalid" role="alert" hidden>招待リンクが正しくありません<\/p>/);
    assert.ok(html.includes('開かない場合は、TestFlightから最新版のくらしOSをインストールし、アプリ内の「招待リンクを入力」をお使いください。'));
    assert.ok(html.includes('このリンクは、くらしOS のアプリで開くと参加できます。'), 'これまでの説明は残す');
    assert.ok(html.includes('background: #F6F4EF'), 'これまでのクリーム色のデザインは残す');
  });

  it('トークンを画面・ログに出さない。外部の仕組みを読み込まない。自動では移動しない', () => {
    assert.match(html, /<script src="\/invite\/invite\.js"><\/script>/);
    assert.equal((html.match(/<script/g) || []).length, 1, 'ほかのスクリプト（分析など）を読み込まない');
    assert.ok(html.includes('<meta name="referrer" content="no-referrer">'));
    assert.doesNotMatch(script, /console\.|innerHTML|textContent|document\.write|localStorage|sessionStorage|fetch\(|XMLHttpRequest|sendBeacon/);
    assert.doesNotMatch(html, /https?:\/\/(?!kurashi-os-production)/, '外部のアドレスを書かない');
    // location.href の書き換えは、ボタンを押したときの1か所だけ
    assert.equal((script.match(/location\.href = /g) || []).length, 1);
    assert.match(script, /addEventListener\('click', function \(\) \{\n\s+location\.href = url;/);
  });
});
