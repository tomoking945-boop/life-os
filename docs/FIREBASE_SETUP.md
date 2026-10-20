# パートナー共有・通知：Apple / Firebase の設定手順（はじめての人向け）

正本の仕様：[PARTNER_NOTIFICATIONS_IMPLEMENTATION.md](PARTNER_NOTIFICATIONS_IMPLEMENTATION.md)
実装の報告：[PARTNER_NOTIFICATIONS_REPORT.md](PARTNER_NOTIFICATIONS_REPORT.md)

この手順書は2つに分かれています。

- **A. Mac でサーバー側の自動テストを動かす**：アカウント登録なしで、いますぐできます（お金もかかりません）。
- **B. 本物の共有・通知のための設定**：第2段階（iPhone アプリを Firebase につなぐ作業）の前に必要です。

> 大切：次のファイルは **絶対に GitHub に入れない** でください（`.gitignore` で除外済みですが、念のため）。
> - `AuthKey_XXXXXXXXXX.p8`（Apple の秘密鍵：Sign in with Apple・APNs）
> - サービスアカウントの鍵（`〜firebase-adminsdk〜.json`）
>
> 画面の名前やボタンの位置は、Apple・Google の変更で少し違うことがあります。見つからないときは、近い名前を探してください。

---

## A. Mac でサーバー側の自動テストを動かす

Firebase Emulator（Mac の中だけで動く、Firebase のまね）を使います。本物の Firebase にはつながりません。

### A-1. Node.js 20 を入れる

1. ブラウザで https://nodejs.org/ を開きます。
2. 「LTS」の **20** 系（または 22 系）のインストーラー（macOS 用 .pkg）をダウンロードして、ダブルクリックで入れます。
3. 「ターミナル」アプリ（アプリケーション → ユーティリティ）を開き、次を入力して Enter：
   ```
   node -v
   ```
   `v20.…` や `v22.…` と出れば OK です。

### A-2. Java を入れる（Firestore Emulator に必要）

1. https://adoptium.net/ を開き、「Temurin 21 (LTS)」の macOS 用 .pkg をダウンロードして入れます。
2. ターミナルで確認：
   ```
   java -version
   ```
   `21` などの数字が出れば OK です。

### A-3. テストの準備（初回だけ）

ターミナルで、life-os のフォルダに移動します（場所は人によって違います。例：書類フォルダにある場合）。

```
cd ~/Documents/life-os/firebase/functions
npm install
```

数分かかります。最後に `added … packages` と出れば OK です（`warn` は気にしなくて大丈夫です。`ERR!` が出たら、その文を教えてください）。

### A-4. テストを動かす

```
npm test
```

3種類のテストが順番に動きます。

| 名前 | 確かめること |
| --- | --- |
| `test:unit` | 通知を送るかの判定・本人を除く・通知 OFF を除く・30秒以内はまとめる・招待トークン |
| `test:rules` | メンバーでない人は読み書きできない・共有項目だけ書ける・役割を上げられない・サインインしていない人は書けない・ルールに無い場所や項目は拒否（[監査](FIRESTORE_SHARING_RULES_AUDIT.md)） |
| `test:functions` | 招待の期限と一度きり・App Check の情報が無い招待の呼び出しを断る・通知が届く端末の選び方・使えないトークンの削除 |

最後に `# fail 0` と出れば、すべて成功です。失敗したときは、出てきた文をそのまま送ってください。

---

## B. 本物の共有・通知のための設定

### 必要なもの（仕様 13）

- Apple Developer Program の登録（年会費があります）
- Google アカウント（Firebase 用）
- iPhone 2台と、テスト用の別の Apple Account

### B-1. アプリの ID（Bundle Identifier）

決定済み（2026-10-17）：アプリは `com.tomoking945boop.lifeos`、テストは `com.tomoking945boop.lifeos.tests`。プロジェクトの設定に反映済みです。B-2 以降では、この ID を使います。

### B-2. Apple Developer で App ID を作る

1. https://developer.apple.com/account を開き、サインインします。
2. 「Certificates, Identifiers & Profiles」→「Identifiers」→「＋」。
3. 「App IDs」→「App」を選んで Continue。
4. Description に `くらしOS`、Bundle ID に `com.tomoking945boop.lifeos` を入れます（Explicit）。
5. 下の Capabilities で、次の3つにチェックを入れます。
   - **Sign in with Apple**
   - **Push Notifications**
   - **Associated Domains**
6. Continue → Register。
7. 画面右上などに出ている **Team ID**（10文字の英数字）をメモします。

### B-3. APNs の鍵（.p8）を作る

1. 同じ画面の「Keys」→「＋」。
2. Key Name に `LifeOS Push` と入れ、**Apple Push Notifications service (APNs)** にチェック → Continue → Register。
3. 「Download」で `AuthKey_XXXXXXXXXX.p8` を保存します。**ダウンロードは1回だけ** です。安全な場所に保管し、GitHub やチャットには送らないでください。
4. **Key ID**（10文字）をメモします。

### B-4. Firebase プロジェクトを作る

1. https://console.firebase.google.com/ を開き、Google アカウントでサインイン。
2. 「プロジェクトを作成」→ 名前（例：`lifeos`）を入れて進めます。Google アナリティクスは **オフ** で大丈夫です。
3. できたら、プロジェクトの設定（歯車）で **プロジェクト ID**（例：`lifeos-1a2b3`）をメモします。

### B-5. 料金プランを Blaze にする（Cloud Functions に必要）

1. 左下の「アップグレード」→ **Blaze（従量課金）** を選び、支払い方法を登録します。
2. 予算のアラートを設定します（例：月 500 円）。少人数で使う範囲では、無料枠に収まることが多いですが、必ず確認してください。

### B-6. iPhone アプリを登録して、設定ファイルを受け取る

1. プロジェクトのトップで「アプリを追加」→ **iOS** のマーク。
2. Apple バンドル ID に `com.tomoking945boop.lifeos` を入れて「アプリを登録」。
3. `GoogleService-Info.plist` をダウンロードします。
4. 2026-10-19 決定：`GoogleService-Info.plist` は秘密ではない設定の識別子のため、`LifeOS/GoogleService-Info.plist` としてリポジトリに入れました（[FIREBASE_APPLE_AUTH_FOUNDATION.md](FIREBASE_APPLE_AUTH_FOUNDATION.md)）。
5. 「Firebase SDK の追加」などの次の画面は「次へ」で飛ばしてかまいません（第2段階でこちらが行います）。

### B-7. APNs の鍵を Firebase に登録する

1. プロジェクトの設定 →「Cloud Messaging」タブ。
2. 「Apple アプリの構成」→「APNs 認証キー」の「アップロード」。
3. B-3 の `.p8` ファイル、Key ID、Team ID を入れてアップロード。

### B-8. ログイン方法で Apple を有効にする

1. 左のメニュー「構築」→「Authentication」→「始める」。
2. 「Sign-in method」→「Apple」→ **有効にする** → 保存。
   （iPhone アプリだけで使うので、サービス ID などの欄は空のままで大丈夫です）

### B-9. Firestore を作る

1. 「構築」→「Firestore Database」→「データベースを作成」。
2. 場所は **asia-northeast1（東京）** を選びます（Cloud Functions と同じ地域）。
3. 「本番環境モード」で作成します（ルールはあとで、このリポジトリの `firestore.rules` を送ります）。

### B-10. 招待リンク用のドメイン（Hosting）を準備する

招待リンク `https://<プロジェクト ID>.web.app/invite?token=…` を iPhone アプリで開けるようにします。

1. 「構築」→「Hosting」→「始める」（画面の手順は途中まででかまいません）。
2. `firebase/hosting/.well-known/apple-app-site-association` は `A8D9YY866R.com.tomoking945boop.lifeos`（Team ID と Bundle ID。どちらも公開してよい識別情報）に書き換え済みです（2026-10-20）。Hosting へはまだ送っていません。

### B-11. サーバー側を送る（デプロイ）

A の準備（Node.js）ができていれば、ターミナルで：

```
cd ~/Documents/life-os
cp .firebaserc.example .firebaserc
```

`.firebaserc` をテキストエディットで開き、`ここに Firebase のプロジェクト ID` を B-4 のプロジェクト ID に書き換えて保存します。続けて：

```
firebase/functions/node_modules/.bin/firebase login
firebase/functions/node_modules/.bin/firebase deploy --only firestore,functions,hosting
```

（`firebase/functions/node_modules/.bin/firebase` は、A-3 の `npm install` で入った Firebase のコマンドです）

ブラウザが開いたら、Firebase と同じ Google アカウントでログインします。最後に `Deploy complete!` と出れば成功です。

### B-12. Xcode の設定（第2段階でいっしょに行います）

次の作業は、iPhone アプリ側のコードと同時に行うので、第2段階でお知らせします（いまは不要です）。

- Firebase のライブラリを追加（File → Add Package Dependencies…）
- Signing & Capabilities に Sign in with Apple・Push Notifications・Background Modes（Remote notifications）・Associated Domains（`applinks:<プロジェクト ID>.web.app`）を追加
- `GoogleService-Info.plist`：2026-10-19 にリポジトリへ追加済み

---

## 第2段階に進むときに教えてほしいこと

1. Team ID（B-2。秘密の情報ではありません）
2. Firebase のプロジェクト ID（B-4）
3. A-4 のテスト結果（`# fail 0` かどうか）

鍵ファイル（.p8）の中身は送らないでください。
