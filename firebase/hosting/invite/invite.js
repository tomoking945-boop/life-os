/*
 * くらしOS への招待の案内ページ（2026-10-28。docs/INVITE_OPEN_BUTTON_FIX.md）
 *
 * Universal Link でアプリが開かず、このページがブラウザに出たときに、
 * 利用者が「くらしOSで開く」を押したときだけ、くらしOS専用の URL Scheme でアプリを開く。
 *
 * - ページを開いただけでは、アプリを開かない（自動で移動しない）
 * - トークンは、このページのアドレスの ?token= だけから読む。形（43文字・英数字と - _）が正しいときだけ使う
 * - アプリと同じ確かめ方：? のあとは token=<43文字> の1つだけ（% での書き換え・ほかの項目・重複は不可）
 * - アプリへ渡すときは encodeURIComponent でエンコードする
 * - トークンは画面・ログ（console）に出さない。どこにも送らない・保存しない
 *
 * ブラウザでは window.KurashiInvite、テスト（Node）では module.exports として使う。
 */
(function (global) {
  'use strict';

  var APP_SCHEME = 'com.tomoking945boop.lifeos';
  var TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

  /** アドレスの ? 以降から、正しい形のトークンだけを取り出す（無い・正しくなければ null） */
  function readToken(search) {
    if (typeof search !== 'string' || search.length > 256) return null;
    var query = search.charAt(0) === '?' ? search.slice(1) : search;
    var parts = query.split('&');
    if (parts.length !== 1) return null;
    var prefix = 'token=';
    if (parts[0].indexOf(prefix) !== 0) return null;
    var token = parts[0].slice(prefix.length);
    return TOKEN_PATTERN.test(token) ? token : null;
  }

  /** アプリを開く URL（くらしOS専用の URL Scheme）。トークンが正しくなければ null */
  function buildAppURL(token) {
    if (typeof token !== 'string' || !TOKEN_PATTERN.test(token)) return null;
    return APP_SCHEME + '://invite?token=' + encodeURIComponent(token);
  }

  /**
   * ボタンを準備する。正しいトークンがあるときだけボタンを押せるようにし、押したときだけアプリを開く
   * @param {Document} doc
   * @param {{search: string, href: string}} location
   */
  function setUp(doc, location) {
    var button = doc.getElementById('open-app');
    var invalid = doc.getElementById('invalid-link');
    if (!button || !invalid) return;
    var url = buildAppURL(readToken(location.search));
    if (!url) {
      button.disabled = true;
      button.setAttribute('aria-disabled', 'true');
      invalid.hidden = false;
      return;
    }
    button.disabled = false;
    button.removeAttribute('aria-disabled');
    invalid.hidden = true;
    button.addEventListener('click', function () {
      location.href = url;
    });
  }

  var api = { APP_SCHEME: APP_SCHEME, TOKEN_PATTERN: TOKEN_PATTERN, readToken: readToken, buildAppURL: buildAppURL, setUp: setUp };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    global.KurashiInvite = api;
    if (global.document) {
      global.document.addEventListener('DOMContentLoaded', function () {
        setUp(global.document, global.location);
      });
    }
  }
})(typeof window !== 'undefined' ? window : this);
