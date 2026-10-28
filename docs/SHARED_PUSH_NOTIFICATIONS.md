# 共有 ToDo・買い物のプッシュ通知（Build 8）

2026-10-28。ブランチ `firebase-shared-notifications`（main の `319ce63` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

Build 7 では、共有 ToDo・買い物の同期はできましたが、アプリを開いていない相手へ知らせるための「端末の登録」がありませんでした（[SHARED_TODO_SHOPPING_FOUNDATION.md](SHARED_TODO_SHOPPING_FOUNDATION.md)）。Build 8 で、利用者が選んだときだけ端末を登録し、パートナーの追加・変更を通知できるようにしました。

## 書き始める前に確かめたこと

- 通知を送るのは、公開済みの Cloud Function `onSharedItemWritten`（共有項目の書き込みで動く）
- 宛先は `users/{uid}/devices/{deviceID}`。Function が使う項目は `fcmToken`・`notificationsEnabled`・`sharedUpdatesEnabled`・`showsPreview`（Security Rules も同じ項目だけを許す）。**この形をそのまま使う**（移行は不要）
- 宛先はわが家のいまのメンバーだけ（`groups/{groupID}/members`）。退出した人は含まれない
- アカウント削除のあとの整理は `users/{uid}` を下の `devices` ごと消す（`accountCleanupRunner.js`。アカウント削除のテストで、devices が残らないことを確かめている）
- ローカル通知（予定・やること・保証書）は `LifeNotificationService`。許可は通知の設定の画面・保証書の保存のときに求める（起動時ではない）
- Firebase の起動の順番は `LifeOSApp` の init（App Check → Firebase）。今回も変えない

## 通知の流れ

1. 利用者が「共有用アカウント → わが家 → わが家の設定 → 共有の通知を受け取る」をオンにする（初期値はオフ）
2. サインインしていて、わが家に参加しているときだけ進む。iPhone の通知の許可がまだなら、**このときだけ** iOS の許可画面を出す
3. 許可されたら、APNs（Apple の通知の仕組み）に登録し、Firebase Cloud Messaging のトークンを受け取る
4. 自分の `users/{uid}/devices/{deviceID}` に、通知に必要な最小限の情報を保存する
5. パートナーが共有の ToDo・買い物を追加・名前を変更すると、`onSharedItemWritten` が、操作した本人を除くメンバーの端末へ送る
6. 通知をタップすると、くらしOSが開き、ToDo なら「やること」の「今日」、買い物なら「買い物」を開く（項目は変えない）

## 保存する情報（Firestore：自分の `users/{uid}/devices/{deviceID}`）

| 項目 | 内容 |
| --- | --- |
| 文書の ID（`deviceID`） | アプリを入れるたびに作るランダムな ID（UUID）。広告の識別子・端末固有の番号は使わない |
| `fcmToken` | 通知用のトークン（画面・ログに出さない） |
| `platform` | `ios` |
| `notificationsEnabled`・`sharedUpdatesEnabled` | `true`（オフにしたら文書ごと消すため、残っている文書はいつも `true`） |
| `showsPreview` | 通知に項目名を表示するか（初期値 `false`） |
| `updatedAt` | サーバーの時刻 |

端末の名前・メール・UID（文書の中）・項目名・広告の識別子は保存しません。
端末の中には `shared-push.json`（受け取る・項目名を表示する・端末の ID）だけを保存します（外部へは送りません。`life-store.json` の形は変えていません）。

## 外部へ送る情報

- Firebase へ：上の端末の文書だけ（自分の場所だけ。Security Rules で確かめる）
- 通知の中身（Apple・Firebase 経由でパートナーの iPhone へ）：
  - 文面：内容を出さないとき「わが家のToDoが更新されました」「わが家の買い物が更新されました」／出すとき「「洗剤を買う」が追加されました」「「書類を出す」に変更されました」（項目名だけ・40文字まで・改行なし）
  - タップしたときに使う情報：わが家の文書の ID・項目の文書の ID・通知の種類・ToDo か買い物か（UID・項目名は入れない）

## 通知する操作・しない操作

| 操作 | 通知 |
| --- | --- |
| パートナーが共有の ToDo・買い物を追加 | する |
| パートナーが共有の ToDo・買い物の名前を変更 | する |
| 完了・未完了に戻す | しない（初期値。Function の設定で変えられるが、いまは使わない） |
| 削除・あとで・もうやらない・日付の変更 | しない |
| 自分の操作 | しない（本人のすべての端末と、本人の端末と同じトークンを除く） |
| 自分だけ（個人）の項目 | しない（Firestore に無いので、通知の処理が動かない） |
| 予定・家事（Build 7 から新しく作れない） | しない |
| 「共有の通知を受け取る」がオフの端末・登録していない端末 | 送らない |
| わが家を退出した人 | 送らない（宛先はいまのメンバーだけ） |
| 同じ項目への30秒以内の2回目 | 送らない（通知の記録で1回にまとめる） |

## プライバシーの設定

- **共有の通知を受け取る**（初期値オフ）：オンにしたときだけ許可を求め、端末を登録する。オフにすると端末の文書を消し、トークンも無効にする
- **通知に項目名を表示する**（初期値オフ）：受け取るがオフのときは押せない。オフのときは種類（ToDo／買い物）だけ。オンでも名前だけを出す（金額・メモ・日付は出さない）
- iPhone の設定で通知が許可されていないときは、理由と「設定を開く」を出す
- 通知の設定の画面にあった「共有の更新」（以前から押せなかった切り替え）は、「わが家の設定で」という案内に置き換えた

## サインアウト・アカウント削除・わが家の退出

- サインアウト：先に端末の文書を消し、トークンを無効にしてからサインアウトする。通信できないときは3秒だけ待ってサインアウトを続ける（ほかの機能を止めない）
- アカウント削除：サーバーの整理が `users/{uid}` を丸ごと消す（端末の文書も残らない）。アプリでもトークンを無効にする
- わが家を退出・削除したとき：端末の文書を消す（「受け取る」の設定は端末に残し、また参加したら登録し直す）。退出した人には、そのわが家の通知は送られない

## セキュリティ

- Firestore のルール（`users/{uid}/devices/{deviceID}`）：本人だけ読み書き・削除。決まった項目だけ。トークンは1〜4096文字で決まった文字だけ、`platform` は `ios`、設定は true/false、更新日時はサーバーの時刻、端末の ID は決まった文字・128文字まで。サインインしていなければ拒否。共有項目・メンバーの権限は変えていない
- Function：操作した本人・本人と同じトークンを除く。通知 OFF の端末を除く。内容は既定で出さない。使えなくなったトークンの端末の文書は消す
- Functions の再試行：通知の記録に出来事の ID（`lastEventID`）を残し、同じ出来事では2回送らない。記録を先に書いてから送る（失敗したときは送り直さない＝重複より取りこぼしを選ぶ）。この Function は自動の再試行を使っていない
- アプリ：トークン・UID・項目名をログに出さない（ソースの確認のテストあり）。Firebase の製品は Messaging だけを足した（Analytics・Crashlytics などは入れない）
- Info.plist：`FirebaseMessagingAutoInitEnabled = NO`（オンにするまでトークンを作らない）、`FirebaseAppDelegateProxyEnabled = NO`（アプリの処理を自動で置き換えさせない）
- entitlements：`aps-environment`（Push Notifications）をアプリにだけ追加。テストのターゲットには付けない。Background Modes（裏での通知の処理）は使わないので足していない

## APNs 認証キーの手作業（池上さん本人が行う）

Firebase から iPhone へ通知を届けるには、**Firebase Cloud Messaging に Apple の APNs 認証キー（`.p8`）を登録する必要があります**。すでに登録してあるかどうかは、ここからは分かりません（推測しません）。Firebase Console で確かめてください。

- `.p8` はコード・GitHub に入れません。Claude は `.p8` に触れません。登録は池上さんが Firebase Console で行います
- `.p8` は Apple Developer で作るときに **1回だけ** ダウンロードできます。安全な場所に保管してください

### 確かめる場所

| 情報 | 場所 |
| --- | --- |
| 登録済みか | Firebase Console → 歯車（プロジェクトの設定）→「Cloud Messaging」タブ →「Apple アプリの構成」→ APNs 認証キー |
| Key ID | Apple Developer → Certificates, Identifiers & Profiles →「Keys」→ 作ったキー（APNs が有効なもの）を開く → Key ID（10文字） |
| Team ID | Apple Developer →「Membership details」の Team ID（10文字） |
| Bundle ID | Xcode → TARGETS の LifeOS →「General」→ Bundle Identifier（`com.tomoking945boop.lifeos`）。Firebase Console の iOS アプリの設定と同じであること |

### 登録の手順（まだ登録していなかったとき）

1. Apple Developer →「Keys」→「＋」→ 名前を付け、「Apple Push Notifications service (APNs)」にチェック → 作成 →「Download」で `.p8` を保存（Key ID を控える）
2. Firebase Console →「Cloud Messaging」タブ →「Apple アプリの構成」→ APNs 認証キーの「アップロード」→ `.p8` を選び、Key ID と Team ID を入れる
3. Xcode → Signing & Capabilities に「Push Notifications」が出ていることを確かめる（entitlements に入れてあるので、自動の署名で App ID にも有効になる）

### Sandbox／Production と TestFlight

- Xcode から iPhone に入れたアプリ（Debug）は、APNs の **Sandbox（開発用）** を使う
- TestFlight・App Store のアプリは **Production（本番用）** を使う（書き出すときに Xcode が entitlements を `production` にする）
- APNs 認証キー（`.p8`）は、1つで Sandbox と Production の両方に使える。証明書（`.p12`）方式のように2つ用意する必要はない
- シミュレーターでは、本物のプッシュ通知は受け取れない（実機で確かめる）

## テスト

### 追加・変更したテスト

- サーバーの単体テスト：73件 → **74件**
  - 通知の決まり・文面を Build 8 の仕様に合わせて書き直した8件（予定・家事は通知しない、名前の変更を通知、「わが家のToDoが更新されました」、項目名だけ・40文字まで）
  - 本人と同じトークンを除く1件を追加
- Functions Emulator：37件 → **41件**
  - 通知の見本を ToDo に変更し、文面・データの期待を Build 8 に合わせた（既存の6件）
  - 追加4件：項目名の表示のオン・オフ、予定・家事は通知しない・名前の変更は通知、退出した人・本人と同じトークンには送らない、再試行のための出来事の ID
- Rules Emulator：55件 → **61件**（端末の文書：自分だけ、他人・未サインインを拒否、決まっていない項目、型・長さ・形、権限が広がらない）
- アカウント削除：20件（変更なし。devices が残らないことを確かめるテストが既にある）
- Swift：357件 → **377件**（`SharedPushNotificationTests.swift`）。
  - 変更：`InviteLinkTests` の entitlements・Info.plist の項目の一覧（`aps-environment`、Firebase Messaging の2つを追加）
  - 変更：`NoFirestoreWritesTests`（Firestore を使ってよいファイルに端末の窓口を追加し、使う場所と項目を確かめる）

| 求められた確認 | テスト |
| --- | --- |
| 起動時に許可を求めない | Swift `testDefaultsAreOffAndNothingIsRequested`・`testNoPermissionRequestAtLaunch` |
| オンにしたときだけ許可を求める | Swift `testTurningOnRequestsPermissionAndRegisters`・`testAlreadyAuthorized` |
| 許可・拒否・未決定の表示 | Swift `testDeniedPermission` ほか |
| トークンの取得・更新・削除 | Swift `testTokenRefreshOverwrites`・`testWaitsForAPNsToken`・`testTurningOffRemovesDevice` |
| サインアウトのときの安全な解除 | Swift `testSignOutRemovesDeviceSafely` |
| 内容の表示の設定 | Swift `testShowsTitleSetting`、単体・Functions の文面のテスト |
| 項目名をログに出さない | Swift `testNoLoggingOrDeviceIdentifiers` |
| 通知タップの画面の移動・対象が無くても落ちない | Swift `SharedPushRouteTests` |
| 既存の共有同期・ローカル通知 | 既存の Swift テスト（変更なし）・ローカル通知はアプリを開いているときは出さないまま（`testForegroundPresentation`） |
| 送信者を除く・パートナーだけ・通知 OFF を除く | 単体 `recipients.test.js`・Functions |
| 30秒の重複の抑え | 単体・Functions |
| 個人項目は対象外 | 単体 |
| 無効なトークン | Functions「使えなくなったトークンの端末は削除される」 |
| 再試行の安全 | Functions「同じ出来事が2回届いても」 |
| Rules：自分の端末だけ・他人・未認証・不正な形を拒否 | Rules「共有の通知の端末（Build 8）」 |

### 結果（作業環境での実行。commit `7557637` 時点の記録）

この表は commit を作った時点の記録です。Mac での結果は、下の「Mac での確認結果」を見てください。

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 74 | 実行した（Node 22） | **74件成功・失敗0・スキップ0** |
| Rules Emulator | 61 | 実行できなかった（Emulator が無い） | 未実行 |
| Functions Emulator | 41 | 実行できなかった | 未実行 |
| アカウント削除 | 20 | 実行できなかった | 未実行 |
| Swift（Xcode） | 377 | 実行できなかった（Xcode が無い） | **未実行・未確認**（ビルドも未確認。全 Swift ファイルの簡易の字句チェックだけ実行） |
| Release ビルド | — | 実行できなかった | **未確認** |

## Mac での確認

1. GitHub でブランチ `firebase-shared-notifications` を選び、ZIP でダウンロードして展開する
2. `firebase/functions` で `npm install`、`npm test`（目安：単体 74・Rules 61・Functions 41・アカウント削除 20、すべて `# fail 0`）
3. `LifeOS.xcodeproj` を開く。**初回は Firebase のパッケージ（Messaging と、それが使う部品）の読み込みに時間がかかる**
4. Signing & Capabilities で自分の Team を選び、「Push Notifications」「Associated Domains」「Sign in with Apple」「App Attest」があることを確かめる
5. ⌘U でテスト（**377件の予定**・失敗0件）
6. Edit Scheme で Run を Release にして ⌘B（確かめたら Debug に戻す）

## Mac での確認結果（2026-10-28、池上さんの報告）

確認した commit：`7557637`

| テスト | 件数 | 失敗 | スキップ | 結果 |
| --- | --- | --- | --- | --- |
| サーバーの単体テスト | 74 | 0 | 0 | 成功 |
| Firestore Rules | 61 | 0 | 0 | 成功 |
| Functions | 41 | 0 | 0 | 成功 |
| アカウント削除 | 20 | 0 | 0 | 成功 |
| サーバーの合計 | 196 | 0 | 0 | 成功 |
| Xcode のテスト | 未報告 | 0 | 未報告 | Test Succeeded |
| Release ビルド | — | — | — | 成功 |

## APNs 認証キー

Firebase Console の Cloud Messaging に、開発用・本番環境用の APNs 認証キーを **登録済み**（池上さん本人が登録。2026-10-28）。
キーの中身・ファイル・識別子などの秘密の情報は、この文書にもリポジトリにも書きません。

## Firebase Messaging の最終の設定の監査（2026-10-28、commit `7557637` のソースで確認）

ソースと設定ファイルを読んで確かめました（実機での通信の確認ではありません）。問題は見つからず、**コードは変えていません**。

| # | 確かめたこと | 結果 |
| --- | --- | --- |
| 1 | 起動時に通知用のトークンが自動で作られない・Firebase へ送られない | OK。起動時に動くのは、Messaging の窓口（`FirebaseMessagingTokenProvider`）の作成と受け取り先の設定だけ。トークンの取得（`token()`）・APNs への登録・端末の文書の保存は、`register()` の中だけで、`register()` は「受け取る」がオンのときだけ動く。トークンが届いても、条件（サインイン・わが家に参加・受け取るがオン・許可済み）を満たさなければ保存しない |
| 2 | `LifeOS-Info.plist` の `FirebaseMessagingAutoInitEnabled = NO` が真偽値 | OK。`<false/>`（真偽値）。文字列ではない。Swift のテスト（`testAppURLSchemeIsRegisteredOnce`）も Bool の false を確かめている |
| 3 | 「共有の通知を受け取る」を利用者がオンにしたあとだけ、自動の開始（`isAutoInitEnabled = true`）になる | OK。true にするのは `register()` だけ。「受け取る」が true になるのは `setReceives(true)`（画面の切り替え）で、許可を得たあとだけ |
| 4 | 通知をオフにしたときのトークン・端末の文書 | OK。「受け取る」を false にして保存し、端末の文書を消し（決まった時間だけ待つ）、自動の開始を false にし、トークンを無効にする（`deleteToken`）。サインアウト・わが家の退出／削除でも、端末の文書を消し、自動の開始を false にする |
| 5 | `FirebaseAppDelegateProxyEnabled` | `NO`（真偽値の false。自動の置き換え＝swizzling は使わない）。APNs のトークンは `AppDelegate` の `didRegisterForRemoteNotificationsWithDeviceToken` から `Messaging.messaging().apnsToken` へ明示的に渡している。自動の置き換えが無いので、二重の処理・競合は無い |
| 6 | Debug・Release の両方で Push Notifications と正しい entitlements | OK。アプリの Debug・Release とも `CODE_SIGN_ENTITLEMENTS = LifeOS.entitlements`。その中に `aps-environment = development`（TestFlight・App Store 用の書き出しで Xcode が production にする）。Associated Domains・Sign in with Apple・App Attest もそのまま。Bundle ID は Debug・Release とも同じ |
| 7 | テストのターゲットに Push Notifications・アプリの Info.plist が入っていない | OK。テストの Debug・Release には `CODE_SIGN_ENTITLEMENTS`・`INFOPLIST_FILE` が無い。テストのターゲットの Frameworks・パッケージも空（FirebaseMessaging はアプリのターゲットだけ） |
| 8 | トークン・UID・項目名をログに出すコードが無い | OK。アプリのソース全体に `print`・`debugPrint`・`dump`・`NSLog`・`os_log`・`Logger`・Analytics・Crashlytics の呼び出しは無い。Swift のソースの確認テスト（`testNoLoggingOrDeviceIdentifiers` など）も同じことを確かめている |

再テスト：コードを変えていないので、Xcode のテストと Release ビルドのやり直しは不要（この記録は文書だけの変更）。

## 2台の iPhone での確認（A：オーナー、B：パートナー。別々の Apple ID）

公開（下の順番）・APNs 認証キーの登録・Build 8 の配布のあとで行います。

1. 起動しただけでは、通知の許可画面が出ないこと
2. A・B：わが家の設定 →「共有の通知を受け取る」をオン → 許可画面 →「許可」。「通知に項目名を表示する」は押せるようになる（オフのまま）
3. B がアプリを閉じた状態で、A が「わが家で共有」の ToDo を追加 → B に「わが家のToDoが更新されました」。A には届かない
4. B が「通知に項目名を表示する」をオン → A が共有の買い物「洗剤を買う」を追加 → B に「「洗剤を買う」が追加されました」
5. A が名前を変える → B に届く。30秒以内に何度変えても1回だけ
6. A が完了・削除・「自分だけ」の項目を追加 → B に届かない
7. B が通知をタップ → くらしOSの「やること」（ToDo）・「買い物」が開く。削除済みの項目の通知でも落ちない
8. B がアプリを開いているときに届いた共有の通知はバナーで出る。予定・やることのローカル通知はこれまでどおり
9. B が「共有の通知を受け取る」をオフ → A が追加しても B に届かない
10. B が iPhone の設定で通知をオフ → わが家の設定に理由と「設定を開く」が出る
11. B がサインアウト → A が追加しても B に届かない。B が再びサインインすると、「受け取る」の設定のまま自動で登録し直される
12. B が退出 → A が追加しても B に届かない

## 公開の順番（池上さんの許可のあとで行う）

この作業では何も公開していません。行うときは、必ず `--only` を付けます（`firebase deploy` だけは使わない）。

1. Mac で全部のテストが通ることを確かめる
2. Firebase Console で APNs 認証キーが登録されていることを確かめる（無ければ上の手順で池上さんが登録）
3. `firebase deploy --only firestore:rules`（端末の文書の確認を少し厳しくした。Build 7 以前のアプリは端末を登録しないので影響しない）
4. `firebase deploy --only functions`（`onSharedItemWritten` の文面・種類・本人のトークンを除く・出来事の ID。ほかの Function の動きは変わらない）
5. 索引・Hosting は変更なし（公開しない）
6. Build 8 を Archive して TestFlight へ

## 元に戻す方法

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- main に入れたあとで戻すときは、取り込みの commit を `git revert` する
- 公開したあとで戻すとき：
  - Functions：前の `index.js`・`src/` で `--only functions` を公開し直す（通知の文面が前の形に戻る）
  - ルール：前の `firestore.rules` で `--only firestore:rules` を公開し直す
  - アプリ：TestFlight で Build 7 を配る
- 利用者の端末の文書を消すとき：アプリで「共有の通知を受け取る」をオフにする（Firebase Console からも消せる）

## 残る制約・次の段階

- 通知するのは、追加と名前の変更だけ（完了・削除は通知しない）
- 通知をタップしたとき、その項目そのものまでは移動しない（「やること」「買い物」を開くまで）
- 通信できないままサインアウトすると、端末の文書が残ることがある（トークンを無効にするので、送ってもサーバーが失敗を受け取り、文書を消す）。メンバーでなくなれば送られない
- アプリのアイコンの数字（バッジ）は扱わない
- シミュレーターでは本物の通知を確かめられない
- APNs 認証キーの登録は Firebase Console での手作業（登録するまで通知は届かない）
- 以前の端末の中の「共有の更新」の設定の値は使わない（保存の形を変えないため値は残す）
