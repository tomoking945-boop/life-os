# 招待リンクの土台（Associated Domains と受け取り）

作業用ブランチ：`firebase-invite-link-foundation`（main `12a0fa4` から作成。**main にはまだ入れていない**）

**Firebase（Firestore・Functions・Hosting）へは何も送っていない。Firebase Console・Apple Developer の画面も変えていない。**

## 何を実装したか

くらしOSの招待リンクを iPhone で開いたとき、アプリがリンクを受け取り、確認の画面へ安全に案内する **土台だけ** を作りました。

- **Associated Domains**（`LifeOS.entitlements`）：招待リンクのドメインを、このアプリで開くリンクとして登録
- **招待リンクの判定**（`LifeOS/Core/Sharing/SharedLinks.swift` の `InviteLink`）：決まった形のリンクだけを招待として受け付ける
- **受け取り**（`LifeOS/App/LifeOSApp.swift`）：SwiftUI の標準の受け取り方（`onOpenURL` と `onContinueUserActivity`）。アプリが終了している・バックグラウンド・起動中のどれから開いても届く
- **流れの管理**（`LifeOS/Core/Sharing/InviteLinkCoordinator.swift`）：確認画面を出す・重複を防ぐ・「あとで」で捨てる
- **確認画面**（`LifeOS/Features/Sharing/InviteLinkSheet.swift`）と、共有用アカウントの画面の案内（`PartnerAccountView.swift`）

**リンクを開いただけでは、招待への参加・Firestore への書き込み・サインイン・端末内のデータの変更はしません。**

## ドメインと招待リンクの形

| 項目 | 値 |
| --- | --- |
| ドメイン | `kurashi-os-production.web.app`（Firebase Hosting の既定のドメイン） |
| 招待リンクの形 | `https://kurashi-os-production.web.app/invite?token=<43文字>` |
| トークンの形 | 32バイトの乱数を base64url にした43文字（英数字・`-`・`_`） |
| Associated Domains | `applinks:kurashi-os-production.web.app` だけ（ワイルドカードなし・`firebaseapp.com` は入れない） |
| AASA の許可 | `A8D9YY866R.com.tomoking945boop.lifeos`、パス `/invite`、`token` 付き |

（実際のトークンは本書にも、ソースにも、設定にも書いていない）

### どこから確かめたか（推測で作っていない）

- 招待を作る Function（`firebase/functions/index.js` の `inviteBaseURL`）：`INVITE_BASE_URL` が無ければ `https://<プロジェクト ID>.web.app`。本番用の `INVITE_BASE_URL` の設定は無い（`.env.demo-lifeos` はテスト専用）
- リンクの組み立て（`src/invites.js` の `buildInviteURL`）：`<土台>/invite?token=<トークン>`、トークンは `^[A-Za-z0-9_-]{43}$`
- プロジェクト ID（`LifeOS/GoogleService-Info.plist`）：`kurashi-os-production`
- AASA（`firebase/hosting/.well-known/apple-app-site-association`）：`appIDs` が `A8D9YY866R.com.tomoking945boop.lifeos`、`/invite` と `token`
- Hosting（`firebase.json`）：公開フォルダは `firebase/hosting`、AASA は `application/json` で配信、`/invite` はアプリが無い人向けの案内ページ

**サーバーが作るリンクと AASA が許可するリンクは一致しており、直す必要はなかった**（テストで、サーバーのコード・プロジェクト ID・AASA・entitlements の4つが同じドメインとパスを使っていることを確かめる）。

注意：Firebase Hosting の既定のサイト名はふつうプロジェクト ID と同じだが、実際に `kurashi-os-production.web.app` になっているかは、Hosting を始めるとき（[FIREBASE_SETUP.md](FIREBASE_SETUP.md) の B-10）に Firebase Console → Hosting の画面で確かめる。違っていたら、Functions の `INVITE_BASE_URL`・AASA の配信先・entitlements・`InviteLink.host` を合わせて直す。

### 受け付けるリンク・断るリンク

受け付けるのは、次をすべて満たすリンクだけ：

- `https`（大文字・小文字は区別しない）
- ホストが `kurashi-os-production.web.app`（大文字・小文字は区別しない）
- パスが `/invite`
- `?` のあとが `token=<43文字>` の1つだけ

断るもの（例）：`http`、別ドメイン（`firebaseapp.com` を含む）、似たドメイン（`…web.app.evil.example`、`evil-…`、`sub.…`、文字の入れ替え、末尾の点）、ユーザー名・パスワード・ポート番号付き、別のパス（`/invite/`、`/Invite`、`/invites`、`%` での書き換えなど）、トークンなし・空・重複・ほかの項目付き・`#` 付き、不正な文字（`+` `/` `=` `.` `%` 日本語など）、42文字・44文字、長すぎるリンク（256文字より長い）。

## 画面の動き

1. 有効な招待リンクを開く → 「招待」の画面（下から出る画面）
   - 「わが家への招待を受け取りました」
   - 「参加する前に、共有される内容を確認してください」
   - 「このリンクを開いただけでは、参加もサインインもしません。…」
   - ボタン：「招待を確認」「あとで」
2. 「あとで」・下へ引いて閉じる → 何も変えずに閉じる。持っていた招待は捨てる
3. 「招待を確認」 → 同じ画面の中で「共有用アカウント」へ進み、「招待への参加は、次のアップデートで使えるようになります」の案内を出す。持っていた招待はここで捨てる（参加の処理がまだ無いため）。サインインしていなくても、自動でサインインの画面は出ない（ふだんの「Appleでサインイン」のボタンはある）。右上の「閉じる」で閉じる
4. **同じリンクは、アプリを開いているあいだ1回だけ**。表示中に同じリンクが届いても（起動の仕方によって2回届くことがある）2枚目を出さず、「あとで」・閉じる・「招待を確認」のあとに同じリンクが届いても出さない。別の正しい招待リンクは出す（表示中なら新しいほうに置き換える）。アプリを起動し直すと、同じリンクをまた受け取れる
   - 重複を見分けるために覚えるのは、トークンそのものではなく、**起動ごとに作る秘密の鍵で計算した印（HMAC-SHA256）だけ**。元のトークンには戻せず、メモリの中だけで持ち、保存しない。不正なリンクは覚えない
5. はじめての設定の途中に届いたら、設定が終わってから出す。「なんでも追加」を開いているときは、閉じてから出す
6. 不正なリンク → 「この招待リンクは使用できません」「リンクが正しくありません。招待した人に、もう一度送ってもらってください。」の案内だけ（トークンや詳しい理由は出さない）。確認画面を出しているときや、はじめての設定の途中は出さない。予定・ToDo・通知などには影響しない

## 外部へ送る情報

**今回の変更で、新しく外部へ送る情報は無い。**

- アプリは招待リンクを受け取っても、どこにも送らない（Firebase・Apple・分析のどれにも送らない）
- トークンは、画面・ログ・エラー文・端末の保存（UserDefaults など）に出さない。アプリを開いているあいだのメモリだけで持ち、「あとで」「閉じる」「招待を確認」で捨てる
- Associated Domains を入れると、iPhone（iOS）が、アプリを入れたときなどに Apple を通して `https://kurashi-os-production.web.app/.well-known/apple-app-site-association` を取りに行く（iOS の標準の動き。くらしOSの利用者の情報は含まれない）

## まだ実装していないこと（次の段階）

- **招待への参加**（`acceptInvite` を呼ぶ）、**招待の作成**（`createInvite` を呼ぶ）
- **グループの同期**（Firestore の読み書き）
- 招待の画面で「共有される内容」（共有される種類・共有されない個人の項目）を詳しく見せる説明
- App Check の使い捨てトークン（`consumeAppCheckToken`）
- Firestore・Functions・Hosting の deploy

## Hosting を deploy するまで、実機では動かない

Universal Links は、iPhone が **本番の Hosting から AASA ファイルを取得できたとき** だけ動きます。
Hosting はまだ deploy していないので、**今は実機で招待リンクをタップしても、アプリではなく Safari が開きます**（ページはまだ無い）。
シミュレーター・テストでは、リンクの判定と画面の流れだけを確かめられます。

## Xcode で Associated Domains を確かめる場所

1. Xcode で `LifeOS.xcodeproj` を開く
2. 左の一覧でいちばん上の「LifeOS」→ TARGETS の「LifeOS」→「Signing & Capabilities」
3. 「All」を選んだ状態で、次の3つがあることを確かめる
   - **Associated Domains**：`applinks:kurashi-os-production.web.app` の1行だけ
   - **Sign in with Apple**
   - **App Attest**
4. 自動の署名（Automatically manage signing）が、Apple Developer の App ID に Associated Domains を追加することがある（App Attest のときと同じ）。赤い表示が出たら、表示に従うか、少し待ってからもう一度ビルドする。Team の変更は GitHub に送らない

Debug と Release は同じ `LifeOS.entitlements` を使う（テストで確認）。

## Mac でのテスト方法

1. GitHub でブランチ `firebase-invite-link-foundation` を選び、ZIP でダウンロードして Xcode で開く
2. Signing & Capabilities で自分の Team を選び、上の3つを確かめる
3. ⌘U でテスト。**281件の予定**（これまでの256件 − 移した1件 ＋ 新しい26件）。失敗0件を確かめる
4. Edit Scheme で Run を Release にして ⌘B（確かめたら Debug に戻す）

新しいテスト（`LifeOSTests/InviteLinkTests.swift`、26件・ネットワークなし）：

- 判定：正しいリンクだけ受け付ける／`http` を断る／別ドメイン・似たドメイン・ユーザー名やポート付きを断る／別のパスを断る／トークンなし・空・重複・ほかの項目・`#` を断る／不正な文字・長さを断る／文字にしてもトークンが出ない
- 流れ：有効なリンクで確認画面／表示中の同じリンクを重ねない／「あとで」・閉じるのあとも同じリンクを出さない／「招待を確認」のあとも同じリンクを出さない／別の正しいリンクは出す／新しく作ると覚えている招待は空（起動し直すとまた受け取れる）／不正なリンクは覚えない／覚えている中身にトークンが無い／表示中に別のリンクで置き換える／「あとで」・閉じるでトークンを捨てる／「招待を確認」で共有用アカウントへ進みトークンを捨てる／「招待を確認」でもサインインを始めない／不正なリンクでも既存の機能が使える／確認画面の表示中に不正なリンクが来ても重ねない
- 設定：Associated Domains が招待のドメインだけ／App Attest と Sign in with Apple が残っている／Debug と Release が同じ entitlements・独自の URL スキームなし／ドメインがサーバー・プロジェクト ID・AASA と一致／ソースや設定に招待トークンが無く、招待の処理がログ・保存をしない

前の `PartnerSharingTests.swift` の招待リンクのテスト（ドメインを確かめていなかった、例のドメインを使っていた）は、上の新しいテストに置き換えた。

サーバー側（`firebase/functions`）は変えていないので、`npm test`（115件）はやり直さなくてよい（念のため実行してもよい）。

## 実機での確認方法

**Hosting を deploy する前（いま）**：

1. Xcode の ▶ で実機に入れて起動し、今日・カレンダー・やること・リスト・お金・なんでも追加・保証書・通知・共有用アカウントがこれまでどおり使えることを確かめる
2. （任意）メモアプリに `https://kurashi-os-production.web.app/invite?token=` で始まる偽のリンクを書いてタップしても、Safari が開くだけでアプリには影響しない

**Hosting を deploy したあと（次の段階）**：

1. メモアプリなどに、Functions が作った本物の招待リンクを貼ってタップする（Safari のアドレス欄に直接入力すると Universal Links は動かない）
2. アプリが終了している・バックグラウンド・起動中のそれぞれで、「わが家への招待を受け取りました」が1回だけ出ること
3. 「あとで」で閉じ、何も変わっていないこと。「招待を確認」で共有用アカウントの画面と案内が出て、サインインが勝手に始まらないこと

## 成功条件

- Xcode のテスト 281件・失敗0件
- Release ビルドが成功する
- Signing & Capabilities に Associated Domains（招待のドメインだけ）・Sign in with Apple・App Attest がある
- 実機で既存の機能がこれまでどおり使える
- （Hosting の deploy 後）本物の招待リンクで確認画面が1回だけ出て、「あとで」で何も変わらない

## 元に戻す方法

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- main に入れたあとで戻すときは、取り込みの commit を `git revert` する。または：
  - `LifeOS.entitlements` から `com.apple.developer.associated-domains` の部分を消す
  - `LifeOSApp.swift` の `onOpenURL`・`onContinueUserActivity`・招待の `sheet`・`alert` を消す
  - 新しいファイル（`InviteLinkCoordinator.swift`・`InviteLinkSheet.swift`・`InviteLinkTests.swift`）を消す
- 端末内のデータの形は変えていないので、戻してもデータには影響しない

## 変えていないもの

Firestore のルール、Functions（招待・通知・アカウント削除の整理）、Hosting のファイル、`GoogleService-Info.plist`、Appleでサインイン・アカウント削除の動き、App Check、通知、アイコン、Bundle Identifier、Team、Version 1.0／Build 4、端末内のデータの形。

## 次の段階で必要なこと（招待への参加・グループの同期）

1. Hosting の deploy（AASA と案内ページ）と、実機での Universal Links の確認
2. 招待を作る画面（`createInvite` を呼び、リンクを共有シートで送る）
3. 「招待を確認」から、サインイン → 共有される内容の説明 → 参加（`acceptInvite`）。そのときはトークンを捨てずに、参加の処理に渡す
4. 参加のあとのグループの同期（Firestore の読み書き）と、Firestore の App Check 強制適用の判断
5. App Check の使い捨てトークン（`consumeAppCheckToken`）
6. ほかの入力画面（保証書の編集など）を開いているあいだに招待リンクが届いたときの出し方（いまは「なんでも追加」だけを考えている）

## 修正（2026-10-21）：同じリンクの重複表示

池上さんの Mac で `InviteLinkTests.testSameLinkIsNotPresentedTwice()` が失敗（3件）。

- 原因：重複の判定を「最初に受け取ってから3秒以内」で行っていたため、表示中に時間がたってから・「あとで」のあとに同じリンクが届くと、新しい招待として扱って確認画面を出し直していた。テストも「時間がたてば出し直す」前提で書いていて、仕様（起動中は1回だけ）と合っていなかった
- 修正：時間の判定をやめ、アプリの起動中に受け取った招待の印（起動ごとの鍵で計算した HMAC-SHA256。元のトークンには戻せない）をメモリに覚え、同じ印のリンクは出さないようにした。不正なリンクは覚えない。アプリを起動し直すと空になる
- テスト：失敗したテストを、表示中・「あとで」と閉じる・「招待を確認」のあと・別のリンク・起動し直し・不正なリンク・覚えている中身の7件に分けて書き直した（20件 → 26件）
- 変えていないもの：招待リンクの判定、Associated Domains、App Attest、Sign in with Apple、トークンを捨てるタイミング（「あとで」・閉じる・「招待を確認」）
