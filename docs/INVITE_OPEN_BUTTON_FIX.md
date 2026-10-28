# 招待リンクが案内ページのままになる問題の対策（Build 6）

作業用ブランチ：`fix-invite-open-button`（`prepare-testflight-5` の `c9e9936` から作成。**main にはまだ入れていない**）

**Hosting・Functions・Firestore へは何も送っていない。Firebase Console・Apple Developer も変えていない。**

## 起きていること

TestFlight Build 5 で、メモなどから招待リンク（`https://kurashi-os-production.web.app/invite?token=…`）をタップすると、くらしOSではなくブラウザが開き、「くらしOS への招待」の案内ページが出たままになることがある。案内ページにはアプリへ進むボタンが無かった。

## 原因（考えられること）

Universal Links（リンクからアプリを開く仕組み）は、iPhone（iOS）が「開くかどうか」を決めるため、アプリの側からは確実にはできない。次のようなときは、アプリではなくブラウザが開く。

- 一度でもそのドメインのリンクを **「Safariで開く」** にすると（リンクの長押し、またはアプリが開いたあと右上の「kurashi-os-production.web.app」を押すなど）、iPhone がそれを覚えて、以後もブラウザで開く
- ブラウザのアドレス欄に直接入力した・同じドメインのページの中のリンクを押した
- アプリを入れた直後などで、iPhone がまだ AASA（`/.well-known/apple-app-site-association`）を Apple から受け取れていない
- アプリのビルドに Associated Domains が入っていない（Build 4 まで）

今回の症状がどれに当たるかは、この作業環境からは確かめられない。どの場合でも利用者が自分でアプリへ進めるよう、**案内ページのボタン** と **アプリの中の貼り付け** の2つを用意した。

（すぐに試せること：メモのリンクを **長押し** して「くらしOSで開く」を選ぶ。Safari で案内ページが出たときは、ページを下に引くと上に出る「開く」を押す。どちらかで一度アプリが開くと、iPhone がまたアプリで開くように覚え直すことがある）

## 作ったもの

### 1. くらしOS専用の URL Scheme

- 名前：**`com.tomoking945boop.lifeos`**（形：`com.tomoking945boop.lifeos://invite?token=<43文字>`）
- ほかのアプリと重なりにくいよう、Apple の推奨どおり Bundle ID と同じ名前にした（`kurashios` のような短い名前は、ほかのアプリと重なるおそれがある）
- `LifeOS-Info.plist`（新規）に1つだけ書き、**アプリのターゲットの Debug・Release だけ** で使う（`INFOPLIST_FILE`）。テストのターゲットには付けない。そのほかの Info.plist の設定は、これまでどおり Xcode が作る
- Associated Domains（`applinks:kurashi-os-production.web.app`）と Universal Links は変えていない

### 2. 受け取り（`LifeOS/Core/Sharing/SharedLinks.swift`・`InviteLinkCoordinator.swift`）

- Universal Link と URL Scheme の両方を、同じ `InviteLink` の判定に通す。URL Scheme だからといって確かめ方を省かない
  - スキームが `com.tomoking945boop.lifeos`、ホストが `invite`、パスが空
  - `?` のあとが `token=<43文字>` の1つだけ（空・重複・ほかの項目・`#`・`%` での書き換え・ユーザー名・ポート番号は不可）
- 受け取っただけでは、サインイン・参加・Firestore への書き込みはしない。必ず「わが家への招待を受け取りました」の確認画面から
- 同じ招待は、Universal Link と URL Scheme のどちらから何度届いても、起動中は1回だけ表示する
- 不正なリンクは「この招待リンクは使用できません」の案内だけ。重複の履歴には残さない
- 期限切れ・使用済みかどうかは、これまでどおり「招待を確認」のあとにサーバーへ確かめ、参加はしない

### 3. 案内ページの「くらしOSで開く」ボタン（`firebase/hosting/invite/`）

- `index.html`：これまでの説明とクリーム色のデザインはそのままに、主ボタン「くらしOSで開く」と、その下に「開かない場合は、TestFlightから最新版のくらしOSをインストールし、アプリ内の「招待リンクを入力」をお使いください。」を追加
- `invite.js`（新規）：
  - アドレスの `?token=` だけを読む。アプリと同じ確かめ方（43文字・英数字と `-` `_`・ほかの項目なし）
  - 正しいときだけ `com.tomoking945boop.lifeos://invite?token=…` を組み立てる（トークンは `encodeURIComponent` でエンコード）
  - **ボタンを押したときだけ** アプリを開く。ページを開いただけでは開かない（自動で移動しない）
  - トークンが無い・正しくないときは、ボタンを押せなくして「招待リンクが正しくありません」を出す
  - トークンは画面・ログに出さず、どこにも送らない・保存しない。外部のスクリプト（分析など）は読み込まない。`referrer` も送らない
- ボタンを押すと、Safari が「このページを“くらしOS”で開きますか？」と確かめてから、くらしOSが開く（iOS の標準の動き）

### 4. アプリの中の代わりの入り口「招待リンクを入力」（`LifeOS/Features/Sharing/InviteLinkEntryView.swift`）

- 場所：プロフィール →「共有用アカウント」
  - サインインしていないとき：「Appleでサインイン」の下
  - サインイン済みで、わが家に参加していないとき：「わが家を作る」の下
  - わが家に参加済みの人には出さない
- 利用者が欄をタップして、自分で貼り付ける。**クリップボードは自動で読まない**
- `https://kurashi-os-production.web.app/invite?token=…` と `com.tomoking945boop.lifeos://invite?token=…` の両方を受け付け、同じ `InviteLink` の判定を通す（前後の空白・改行は除く）
- 正しければ「わが家への招待を受け取りました」の確認画面へ進む。**貼り付けただけでは参加しない**
- 自分で入力したときは、前に「あとで」で閉じた同じ招待でも、もう一度確認画面を出す（表示中の同じ招待は重ねない）
- 正しくないときは、入力欄の下に「招待リンクが正しくありません」（トークンの中身は出さない）
- 入力欄は保存しない（画面を離れると消える）。アプリの切り替え画面などでは隠す（`privacySensitive`）

## ボタンと貼り付けを両方用意する理由

- **ボタン**：案内ページが出てしまった人が、その場で1回押すだけで進める。いちばん手軽
- **貼り付け**：ボタンでも開かない場合（古いビルド・ブラウザの設定・メッセージアプリの中のブラウザなど）でも、アプリの中から確実に進める
- どちらも、最後は同じ確認画面・同じサーバーの確かめ（期限・使用済み・取り消し・満員・自分の招待）を通るので、入り口が増えても参加の決まりは変わらない

## 送られる情報

**新しく送る情報は無い。**

- 案内ページは、トークンをどこにも送らない（アプリを開く URL の中に入れて、iPhone の中でアプリへ渡すだけ）
- アプリは、これまでどおり「招待を確認」→ サインイン → 「参加する」のときだけ、トークンを Cloud Functions（App Check・サインイン必須）へ送る
- 貼り付けた文字は、端末の中でだけ確かめ、保存しない

## セキュリティ上の扱い

- URL Scheme は、iOS の仕組み上、ほかのアプリが同じ名前を名乗ることを完全には防げない。そのため：
  - Bundle ID と同じ、重なりにくい名前にした
  - アプリを開くのは、利用者がボタンを押したときだけ（Safari も確かめる）
  - 招待は24時間・1回だけ。参加には、本物のくらしOS（**App Check**）からの呼び出しと **Appleでのサインイン** と **「参加する」** が必要。ほかのアプリがトークンを受け取っても、サーバーは本物のくらしOS以外からの呼び出しを断る
  - オーナーは、知らない人が参加したらメンバーの画面で分かり、招待はいつでも取り消せる
- 受け取ったリンク・貼り付けた文字は、Universal Link と同じ判定を必ず通す
- トークン・招待のリンクは、画面・ログ・UserDefaults・分析・クラッシュログに書かない（テストでソースを確かめる）

## テスト

### 追加・変更したテスト

- Swift（`LifeOSTests/InviteLinkTests.swift`・`HouseholdTests.swift`）：301件 → **312件**
  - URL Scheme を受け付ける／URL Scheme でもトークンなし・形・長さ・別のスキーム・別ホスト・別のパス・ほかの項目を断る／貼り付けた文字も同じ判定
  - Universal Link と URL Scheme で同じ確認画面／両方から届いても1回だけ／不正な URL Scheme は覚えない／受け取っただけではサインイン・Preview・参加を呼ばない
  - 「招待リンクを入力」：不正なら入力欄で知らせて覚えない・表示中の同じ招待は重ねない・「あとで」のあとでも自分で入力すれば出す・トークンを残さない
  - 設定：URL Scheme は `LifeOS-Info.plist` に1つだけ・アプリの Debug／Release だけ・案内ページと同じ名前。入力画面がクリップボードを読まない
- サーバーの単体テスト（`firebase/functions/test/unit/hostingInvitePage.test.js`、新規6件）：60件 → **66件**
  - 正しいトークンだけを読む／URL Scheme の URL をエンコードして組み立てる・形が違えば組み立てない／正しいときだけボタンを押せて、押したときだけ開く（読み込んだだけでは開かない）／不正ならボタンを押せず「招待リンクが正しくありません」／文言・デザインが残っている／トークンを画面・ログに出さない・外部のスクリプトを読まない・自動で移動しない

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 66 | 実行した（Node 22） | 66件成功・失敗0・スキップ0 |
| Rules Emulator | 44 | 実行できなかった（変更なし） | 未実行 |
| Functions Emulator | 49 | 実行できなかった（変更なし） | 未実行 |
| Swift（Xcode） | 312 | 実行できなかった（Xcode が無い） | **未実行・未確認**（ビルドも未確認） |
| Release ビルド | — | 実行できなかった | **未確認** |

## Mac での確認方法

1. GitHub でブランチ `fix-invite-open-button` を選び、ZIP でダウンロードして展開する
2. `firebase/functions` で `npm install`、`npm test`（目安：単体 66・Rules 44・Functions 29・アカウント削除 20、すべて `# fail 0`）
3. `LifeOS.xcodeproj` を開き、Signing & Capabilities で自分の Team を選ぶ（Associated Domains・Sign in with Apple・App Attest がそのままあること）
4. TARGETS の LifeOS →「Info」タブの「URL Types」に `com.tomoking945boop.lifeos` が1つあることを確かめる
5. ⌘U でテスト（**312件の予定**・失敗0件）
6. Edit Scheme で Run を Release にして ⌘B（確かめたら Debug に戻す）

## Hosting だけを公開する手順（池上さんの許可のあとで行う）

公開されるファイル（`firebase/hosting`）：

- `/invite/index.html`（変更：ボタンと案内を追加）
- `/invite/invite.js`（新規）
- `/.well-known/apple-app-site-association`（変更なし）

Mac で、展開したフォルダの一番上（`firebase.json` があるところ）で：

```
firebase/functions/node_modules/.bin/firebase hosting:sites:list --project kurashi-os-production
firebase/functions/node_modules/.bin/firebase deploy --only hosting --project kurashi-os-production
```

- 1行目は確かめるだけ（サイト名が `kurashi-os-production` であること）
- **`--only hosting` を必ず付ける**（Functions・Firestore のルール・索引は送らない）
- 確認：パソコンのブラウザで `https://kurashi-os-production.web.app/invite?token=` のあとに適当な文字を付けて開き、ボタンが押せず「招待リンクが正しくありません」が出ること。`https://kurashi-os-production.web.app/.well-known/apple-app-site-association` がこれまでどおり開くこと
- 戻すとき：Firebase Console → Hosting → リリースの履歴 → 前のリリースの「ロールバック」

## Build 6

| 項目 | 値 |
| --- | --- |
| Version | 1.0（変更なし） |
| Build | 5 → **6**（アプリ・テストの Debug／Release の4か所） |
| `ITSAppUsesNonExemptEncryption` | NO（変更なし） |

Archive の手順は [TESTFLIGHT_BUILD_5.md](TESTFLIGHT_BUILD_5.md) と同じ（Organizer で Version 1.0・Build 6 を確かめる）。

### Build 6 の実機での確認

2台の iPhone・別々の Apple ID（A：オーナー、B：パートナー）。どちらも TestFlight から 1.0 (6) を入れる。Hosting を公開してから行う。

1. 既存の機能（今日・カレンダー・やること・リスト・お金・保証書・通知）がこれまでどおり使える
2. A：わが家を作り、「パートナーを招待」→「共有」で B に送る
3. B：リンクをタップ
   - くらしOSが開いたら → 「わが家への招待を受け取りました」（これまでどおり）
   - 案内ページが開いたら → 「くらしOSで開く」を押す →「“くらしOS”で開きますか？」→「開く」→ 同じ確認画面が出る。ページを開いただけではアプリが開かないこと
4. B：案内ページの末尾を消したリンク（トークンが足りない）を開くと、ボタンが押せず「招待リンクが正しくありません」
5. B：くらしOS → プロフィール → 共有用アカウント →「招待リンクを入力」→ 欄をタップしてリンクを貼り付け →「招待を確認」→ 同じ確認画面。貼り付けただけでは参加しないこと。クリップボードを勝手に読まないこと
6. B：「招待を確認」→（サインイン）→「参加する」→「わが家に参加しました」。A の画面でパートナーが参加済みになる
7. B が同じリンクをボタン・貼り付けで何度開いても、参加し直しにならない（使用済み・すでに参加の案内）
8. 参加済みの B の画面には「招待リンクを入力」が出ないこと

### Build 6 の確認結果（2026-10-28、池上さんの報告）

| 項目 | 結果 |
| --- | --- |
| Hosting | 2026-10-28 に3ファイルを公開（案内ページの「くらしOSで開く」ボタン） |
| Xcode のテスト | 成功・**失敗0件**（実行件数・スキップ数は報告なし。ここには推測で書かない） |
| Release ビルド | 成功 |
| 別の Apple ID での確認 | Appleでサインイン、招待の確認、わが家への参加まで成功 |
| TestFlight | Build 6 を外部テスト中 |

次の Build 7（わが家の管理・共有 ToDo・買い物）は [SHARED_TODO_SHOPPING_FOUNDATION.md](SHARED_TODO_SHOPPING_FOUNDATION.md)。

## 元に戻す方法

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- main に入れたあとで戻すときは、取り込みの commit を `git revert` する。または：
  - `LifeOS-Info.plist` と、`project.pbxproj` の `INFOPLIST_FILE = "LifeOS-Info.plist";` の2行を消す（URL Scheme が無くなる）
  - `InviteLinkEntryView.swift` と、共有用アカウント・わが家の画面の「招待リンクを入力」を消す
  - `firebase/hosting/invite/index.html` を前に戻し、`invite.js` を消して Hosting を送り直す（またはロールバック）

## 変えていないもの

Appleでサインイン、App Check、Universal Links・Associated Domains、招待の作成・取り消し・Preview・参加、アカウント削除のあとの整理、Firestore のルール・索引、Functions、AASA、アイコン、通知、端末の中のデータ、Version 1.0、Bundle Identifier。
