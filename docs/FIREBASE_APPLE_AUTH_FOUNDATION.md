# パートナー共有の土台：Firebase 接続と「Appleでサインイン」

作業用ブランチ：`firebase-apple-auth-foundation`（main `aaa663e` から作成。**main にはまだ入れていない**）
目的：パートナー共有を使う人を安全に見分けられるようにする。**今回は認証まで**。生活データの同期・共有・Firestore への保存はしない。

## 実装したこと

| # | 内容 |
| --- | --- |
| 2・3 | Mac の Downloads にあった `GoogleService-Info.plist`（同じ内容の2つのうち、元の方）を確認し、`LifeOS/GoogleService-Info.plist` としてアプリにだけ追加（PROJECT_ID `kurashi-os-production`・BUNDLE_ID `com.tomoking945boop.lifeos`・Analytics オフ）。テストのフォルダには入れていない |
| 4 | Swift Package Manager で公式の Firebase Apple SDK（`https://github.com/firebase/firebase-ios-sdk`）を追加。製品は **FirebaseCore・FirebaseAuth・FirebaseFirestore** の3つだけ（Analytics・Crashlytics・Messaging は追加しない）。アプリのターゲットだけにつなぐ |
| 5 | 起動時に `FirebaseBootstrap.configureIfPossible()`：設定ファイルが無い・壊れている・別のアプリ用なら設定しない（アプリは止まらない）。テスト中は接続しない |
| 6 | `LifeOS.entitlements`（`com.apple.developer.applesignin` = Default）を作り、アプリの Debug／Release の `CODE_SIGN_ENTITLEMENTS` に設定 |
| 7 | AuthenticationServices でサインインの画面を出す。nonce を安全な乱数で作り、Apple には SHA-256、Firebase には元の文字列を渡して照合。名前とメールアドレスは求めない（requestedScopes は空） |
| 8 | `AuthService`：Firebase 未接続・サインアウト中・処理中・サインイン済み・エラーの5つの状態。画面は Firebase SDK を直接使わず、`AuthBackend`（Firebase）と `AppleSignInProviding`（Apple の画面）の窓口だけを使う |
| 9 | プロフィール →「わが家」→ **共有用アカウント**：Appleでサインイン、サインイン状態、サインアウト、アカウント削除、「共有を有効にするまで、予定やタスクなどの生活データは送信されません」の説明 |
| 10 | アカウント削除：確認の画面 → Apple でもう一度確かめる → Firebase で再認証 → authorization code で Apple のトークンを失効 → Firebase の利用者を削除。途中でやめたら何も消さない。失効に失敗したら削除しない |
| 11 | Firestore は使わない（読み込みも書き込みもしない。FirebaseFirestore は追加しただけで、どこからも呼んでいない） |
| 12・13 | サインインしなくても、今までの機能はすべてそのまま。Firebase が使えないときは「共有用アカウント」の画面にだけ案内を出す |
| 14 | `.gitignore` に `*.p8`・`AuthKey_*.p8`・`*.p12`・`*.pem`・`*.key`・`*.mobileprovision` を追加。**Apple の .p8 秘密鍵には一切アクセスしていない**（読み取り・コピー・追加なし） |
| 16 | Firestore のルールは変えていない。共有のデータの形・招待コード・同期・遠隔通知は作っていない |

## GoogleService-Info.plist について

- Firebase の公式の説明では、`GoogleService-Info.plist` の中身（API キー・プロジェクト ID など）は **秘密ではない設定の識別子** で、アプリに入れて配るものです。2026-10-19、池上さんの決定でリポジトリに入れました。
- **データを守るのは、この設定ファイルを隠すことではありません。** 次の3つで守ります。
  - Firebase Authentication（サインインした本人だけ）
  - Firestore Security Rules（いまは全部の読み書きを拒否。共有を作るときにメンバーだけ読み書きできるルールにする）
  - App Check（今後設定する。本物のくらしOSアプリからの通信だけを受け付ける）

## 外部へ送られる情報

- サインインのとき：Apple が発行する ID トークン（Apple があなたを見分ける番号を含む）と nonce を、Apple と Firebase Authentication に送る。名前とメールアドレスは Apple に求めていないため、送られない
- Firebase Authentication に記録されるもの：Firebase の利用者 ID と、Apple との連携の情報
- アカウント削除のとき：authorization code を Firebase 経由で Apple に送り、連携を解除する
- **送らないもの**：予定・タスク・リスト・メモ・お金・習慣・保証書・写真などの生活データ。Firestore には何も書き込まない
- Firebase SDK は、動作に必要な最小限の情報（SDK の種類・バージョンなど）をリクエストに含めることがある（Firebase の仕様）

## 変更したファイル

- 新規：`LifeOS/Core/Auth/AuthModels.swift`、`AuthService.swift`、`FirebaseAuthBackend.swift`、`AppleSignInCoordinator.swift`、`LifeOS/Features/Profile/PartnerAccountView.swift`、`LifeOS/GoogleService-Info.plist`、`LifeOS.entitlements`、`LifeOSTests/AuthServiceTests.swift`、本書
- 変更：`LifeOS.xcodeproj/project.pbxproj`（Firebase のパッケージ・entitlements）、`LifeOS/App/LifeOSApp.swift`（起動時の設定）、`LifeOS/Features/Profile/ProfileView.swift`（共有用アカウントの行）、`.gitignore`、`docs/FIREBASE_SETUP.md`、`README.md`

## Firebase の依存関係

- パッケージ：`firebase-ios-sdk`。指定は「12.0.0 以上、13 未満」（Up to Next Major）。2026-10-19 時点で 12 系の最新は **12.19.2**
- 13.0.1 も出ているが、大きな変更が入った版のため、今回は動作をよく知る 12 系にした（13 への更新は別の作業で確かめる）
- `Package.resolved`（実際に使う版の記録）は、Mac の Xcode が初めてパッケージを読み込んだときに作られる

## テスト

この環境には Xcode が無いため、**ビルドとテストはまだ実行していない**（コードの読み合わせのみ）。

| テスト | 件数 | 結果 |
| --- | --- | --- |
| XCTest（これまでの223件＋新規22件。下の修正で5件増えた） | 245件 | 未実行（Mac で実行が必要） |

新規テスト（実際のネットワーク・Firebase・Apple の画面は使わない）：
- 状態：最初の状態、Firebase 未設定で何も起きない、設定ファイルの無いバンドルでは設定しない・テスト中は接続しない
- サインイン：Apple には nonce の SHA-256・Firebase には元の nonce、やめたらエラーにしない、失敗はエラーになり閉じられる、エラーの中身は画面に出さない
- サインアウト：成功、失敗してもサインイン済みのまま
- 削除：確認しないと削除しない、再認証→失効→削除の順、再認証をやめたら何も消さない、authorization code が無ければ止まる、失効に失敗したら削除しない
- nonce：毎回ちがう・SHA-256 の値、利用者 ID の一部だけを表示
- ローカルの機能はサインインに関係なく使える

## 手動での確認（Mac・iPhone）

1. GitHub でブランチ `firebase-apple-auth-foundation` を選び、ZIP でダウンロードして Xcode で開く
2. はじめて開くと、Xcode が Firebase のパッケージを読み込む（画面の左下や上に「Fetching」「Resolving」と出る。数分かかる）。終わるまで待つ
3. Signing & Capabilities で自分の Team を選ぶ（この変更は GitHub に送らない）。「Sign in with Apple」が並んでいることを確かめる
4. ⌘B でビルド、⌘U でテスト（240件の予定。失敗0件、実機専用1件スキップの予定）
5. Product → Scheme → Edit Scheme → Run を Release にして ⌘B（確かめたら Debug に戻す）
6. iPhone の実機（またはApple Account でサインインしたシミュレーター）で起動 → 今日 → 右上のプロフィール →「共有用アカウント」
7. 「Appleでサインイン」→ Face ID など → 「Appleでサインイン済み」と番号の一部が出る
8. Firebase コンソール → Authentication → ユーザー に、プロバイダが Apple の利用者が1人増えていることを確かめる
9. 「サインアウト」→「サインインしていません」に戻る
10. もう一度サインイン →「アカウントを削除」→ 確認 →「アカウントを削除」→ もう一度 Apple で確かめる →「サインインしていません」に戻り、Firebase コンソールの利用者が消えていることを確かめる
11. 機内モードで「Appleでサインイン」→ 通信できないという案内が出て、アプリのほかの画面は普通に使えることを確かめる
12. Firestore コンソールに、何もデータが増えていないことを確かめる

## 既知の制約・次の段階

- Firestore のルールは全部拒否のまま。共有のデータの形・招待・同期・通知は次の段階
- App Check は未設定（次の段階で設定する）
- Apple 側でくらしOSとの連携を解除されたときの検知（credential state の確認）は、まだしていない
- Xcode のテストのターゲットから Firebase のモジュールが見つからない、というエラーが出る場合がある（Firebase を Swift Package で入れたアプリでたまに起きる）。出たら、エラーの文を送ってください。テストのターゲットの設定で直します

## 修正：アカウント削除ボタンが反応しない（2026-10-19）

### 原因（池上さんの確認）

- `PartnerAccountView` の確認画面（`confirmationDialog`）が閉じると、表示状態をつないでいた Binding の setter から `cancelAccountDeletion()` が先に呼ばれていた
- そのあとで「アカウントを削除」のボタンの処理（Task）から `confirmAccountDeletion()` が呼ばれる
- `confirmAccountDeletion()` の最初の `guard isConfirmingDeletion else { return }` で、すでに確認の状態が消えているため、削除が何もせず終わっていた
- SwiftUI の「確認画面が閉じる処理」と「ボタンの処理」の順番に左右される不具合だった

### 修正

- 確認画面の表示状態は `PartnerAccountView` の `@State`（画面の中だけ）にした。`AuthService` からは確認の状態をなくした（`requestAccountDeletion`・`cancelAccountDeletion`・`confirmAccountDeletion`・`isConfirmingDeletion` を削除）
- 削除の処理は `AuthService.deleteAccount()`。確認画面の表示状態には関係なく、確定のボタンからだけ呼ぶ
- 実行のときに、サインイン済みで処理中でないことを改めて確かめる（`case .signedIn` のときだけ動く）
- 最初の await の前に「削除しています…」（処理中）にするので、2回押しても2回目は何もしない。削除ボタンは `canDeleteAccount` が false のあいだ押せない
- 「やめる」・確認画面を閉じたときは何も呼ばないので、Apple の再認証・トークンの失効・Firebase の利用者の削除は一切行わない
- 確定したときだけ、Apple の再認証 → トークンの失効 → Firebase の利用者の削除を、それぞれ1回行う
- キャンセル（サインイン済みのまま）、Apple の失敗・トークン不足・失効の失敗・Firebase の削除の失敗（案内を出し、閉じるとサインイン済みに戻る）
- Firestore・既存のデータ・GoogleService-Info.plist・Apple の設定は変えていない

### 追加したテスト

- 確認画面が先に閉じても、確定すれば削除が1回ずつ行われる（不具合の再現）
- 確認画面でやめた・閉じたときは、何も削除しない
- 2回続けて押しても1回だけ
- 削除中は処理中の表示で、削除ボタンは押せない
- Apple の再認証の失敗、Firebase の削除の失敗、サインインしていないときに何もしない

### 結果

この環境には Xcode が無いため、ビルドとテストはまだ実行していない（Mac で確認が必要。245件の予定）。
