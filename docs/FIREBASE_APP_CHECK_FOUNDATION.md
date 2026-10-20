# Firebase App Check の基礎

作業用ブランチ：`firebase-app-check-foundation`（main `0d72eda` から作成。**main にはまだ入れていない**）

## 目的

Firebase への通信が、本物の「くらしOS」アプリから送られたものかを Firebase が確かめられるようにする。
今回は **App Check のトークンがきちんと届くところまで**。Firebase Console の「強制適用（Enforce）」は、実機での確認が終わるまでオンにしない。

## App Attest を選んだ理由

- Apple が用意している仕組みで、iPhone の中の安全な部分（Secure Enclave）を使って「本物のアプリ・本物の端末か」を確かめる
- くらしOS の最低対応は iOS 17 のため、App Attest の仕組み（iOS 14 以降）は必ず使える
- Firebase Console には App Attest を登録済み（DeviceCheck は登録していないため、代わりの仕組みには使わない）
- App Attest を使えない環境（シミュレーターなど）では、トークンが取れないだけでアプリは止まらない。強制適用がオフのあいだは、既存の機能にも影響しない

## Debug と Release の違い

| ビルド | App Check の仕組み | 使う場面 |
| --- | --- | --- |
| Debug（Xcode の ▶・⌘U） | `AppCheckDebugProvider` | 開発中。Xcode のログに出る Debug Token を、必要なときだけ利用者が Firebase Console に登録する |
| Release（Archive・TestFlight・App Store） | `AppAttestProvider` | 本番。App Attest でトークンを取る |

entitlements の `com.apple.developer.devicecheck.appattest-environment` は、Debug・Release とも `production`（Firebase App Check が受け付ける本番の環境）。

## 起動の順番（`LifeOS/Core/Auth/FirebaseBootstrap.swift`）

1. すでに Firebase を設定済みなら何もしない
2. テスト中は何もしない（テストでネットワークを使わない）
3. `GoogleService-Info.plist` が無い・壊れている・別のアプリ用なら、何もしない（アプリは普通に起動し、共有用アカウントの画面にだけ案内が出る）
4. **App Check の Provider Factory を設定する**（`AppCheck.setAppCheckProviderFactory`）
5. **Firebase を設定する**（`FirebaseApp.configure`）
6. Firebase Authentication（Appleでサインイン）は、このあと使うときに初めて動く

App Check は必ず Firebase の設定より前、Authentication より前に設定される（テストで順番を確認）。

## 追加・変更したファイル

- 新規
  - `LifeOS/Core/Auth/FirebaseBootstrap.swift`：起動の順番、Debug／Release の仕組みの選び方、App Check の Provider Factory（`FirebaseAuthBackend.swift` から起動の部分を移した）
  - `LifeOSTests/AppCheckTests.swift`（11件）
  - 本書
- 変更
  - `LifeOS.xcodeproj/project.pbxproj`：既存の Firebase パッケージ（12 系のまま）に `FirebaseAppCheck` を追加。アプリのターゲットだけ。FirebaseCore・FirebaseAuth・FirebaseFirestore はそのまま。Analytics・Crashlytics・Messaging は追加しない
  - `LifeOS.entitlements`：`com.apple.developer.devicecheck.appattest-environment` = `production` を追加（Sign in with Apple はそのまま）
  - `LifeOS/Core/Auth/FirebaseAuthBackend.swift`：起動の部分を `FirebaseBootstrap.swift` へ移しただけ（Authentication の動きは変えていない）
  - `LifeOS/App/LifeOSApp.swift`：起動時の呼び出しの条件に App Check を追加
  - `.gitignore`：Debug Token をファイルに保存しないための注意と除外
  - `README.md`：本書へのリンク

変えていないもの：Appleでサインイン・サインアウト・アカウント削除の動き、Firestore のルール、Firestore への書き込み（無し）、端末内のデータ、通知、アイコン、Bundle Identifier、Version 1.0／Build 3、`GoogleService-Info.plist`、App Store Connect・TestFlight、Firebase Console の強制適用。

## 外部へ送られる情報

- App Check：Apple の App Attest が作る「本物のアプリ・端末か」の証明（アプリの ID・端末の中で作られた鍵の証明など）を Apple と Firebase に送り、Firebase から App Check トークンを受け取る。Debug ビルドでは、Debug Provider のトークンを Firebase に送る
- 以後の Firebase への通信（いまは Authentication だけ）に App Check トークンが付く
- **生活データ（予定・やること・リスト・お金・習慣・保証書・写真など）は、まだ送らない**。Firestore には何も書き込まない

## Debug Provider の扱い

- Debug Token は **コード・設定ファイル・Scheme の環境変数・説明文書に書かない**（テストで、ソースと Scheme に `FIRAAppCheckDebugToken` が無いことを確認）
- 必要なときだけ：Xcode で Debug ビルドを動かす → Xcode のログ（下の「デバッグエリア」）に出る `App Check debug token: …` の値を、利用者が自分で Firebase Console → App Check → アプリ → 「Debug Token を管理」に登録する
- いまは強制適用がオフなので、Debug Token を登録しなくてもアプリはこれまでどおり使える

## 強制適用をまだオンにしない理由

強制適用をオンにすると、App Check のトークンが無い通信は Firebase に断られる。本物のアプリからトークンが届いていることを確かめる前にオンにすると、サインインできなくなるおそれがあるため、先に指標で確かめる。

## Xcode でのテスト手順

1. GitHub でブランチ `firebase-app-check-foundation` を選び、ZIP でダウンロードして Xcode で開く。Firebase の部品（FirebaseAppCheck が増えた）の読み込みが終わるまで待つ
2. Signing & Capabilities で自分の Team を選ぶ。**「App Attest」と「Sign in with Apple」の2つ**があることを確かめる（App Attest が赤い表示なら、自動の署名が Apple Developer の App ID に App Attest を追加するまで待つか、表示に従う。Team の変更は GitHub に送らない）
3. ⌘U でテスト（256件の予定：これまでの245件＋11件。失敗0件）
4. Edit Scheme で Run を Release にして ⌘B（確かめたら Debug に戻す）

## 実機・TestFlight での確認手順

1. Debug（Xcode の ▶ で実機）：起動して、Xcode のログに `App Check debug token` が出ることを確かめる。今日・カレンダー・やること・リスト・お金・なんでも追加・保証書・通知がこれまでどおり使えること、共有用アカウントでサインイン・サインアウトできることを確かめる
2. Release（Archive → TestFlight。Build 番号は別の作業で上げる）：TestFlight 版を起動して、同じ機能を確かめ、Appleでサインインする

## Firebase Console で成功を判断する方法

Firebase Console → プロジェクト `kurashi-os-production` → 左のメニュー「App Check」→「API」タブ → **Authentication**（Identity Platform）の指標を開く。

- 「確認済みのリクエスト（Verified requests）」が増えていれば、本物のアプリからトークンが届いている
- 「確認されていないリクエスト」「古いクライアント」が多いあいだは、強制適用をオンにしない

## 強制適用をオンにするための成功条件

- TestFlight 版（App Attest）で、Authentication の指標の「確認済み」がほぼすべてになっている
- 実機でサインイン・サインアウト・アカウント削除がこれまでどおりできる
- 内部テスターの端末がすべて、App Check に対応したビルドになっている（古いビルドは強制適用で使えなくなる）
- Firestore の強制適用は、Firestore を使い始める段階で別に判断する

## 元に戻す方法

- コード：この変更を main に入れたあとで戻すときは、取り込みの commit を `git revert` する。または `LifeOS.xcodeproj` から `FirebaseAppCheck` を外し、`FirebaseBootstrap.swift` の `installAppCheckProviderFactory` の呼び出しをやめる（App Check が無くても Authentication は強制適用がオフなら動く）
- entitlements：`com.apple.developer.devicecheck.appattest-environment` の行を消す
- Firebase Console：強制適用をオンにしたあとで問題が出たら、App Check → API → Authentication の「強制適用」をオフに戻す（すぐに反映される）

## テストの結果

2026-10-20 池上さんの Mac で確認済み（下の「確認結果」）。テストの件数・スキップ数は未報告（256件の想定）。

新規テスト（11件・ネットワークなし）：
- App Check の Provider Factory が Firebase の設定より前に設定される
- Debug は Debug Provider、Release は App Attest
- 設定ファイルが無い・使えない・設定に失敗しても止まらない
- テスト中・設定済みのときは何もしない
- このビルド（Debug）では Debug Provider が選ばれる
- Firebase に接続していなくても、今までの機能が使える
- アプリのソースに Firestore を使う処理（`import FirebaseFirestore`・書き込み）が無い
- ソースと Scheme に Debug Token が無い

## 確認結果（2026-10-20 池上さん・commit `6a9d422`）

| 項目 | 結果 |
| --- | --- |
| Xcode のテスト | 完了（件数・スキップ数は未報告） |
| Release ビルド | 成功 |
| 実機の Debug 版 | 起動成功 |
| Debug Token | 池上さんが Firebase Console に登録済み（値はどこにも記録しない） |
| Firebase App Check → Authentication | 「確認済みのリクエスト」2件を確認 |
| App Check の強制適用 | 適用していない（オフのまま） |
| Firestore への書き込み | 追加していない |

次は TestFlight ビルド4（Release・App Attest）で、TestFlight 版からも「確認済み」のリクエストが届くかを確かめる（[TESTFLIGHT_BUILD_4.md](TESTFLIGHT_BUILD_4.md)）。

## TestFlight ビルド4での確認結果（2026-10-20 池上さん・commit `62d6b36`）

Release（App Attest）でも、本物のアプリからトークンが届いていることを確認した。アプリのコードと設定は `62d6b36` から変えていない。

| 項目 | 結果 |
| --- | --- |
| Build 4 の Xcode テスト | 完了 |
| Release ビルド | 成功 |
| Version 1.0／Build 4 の Archive | 成功 |
| App Store Connect へのアップロード | 成功 |
| TestFlight への追加・iPhone への導入 | 完了 |
| TestFlight 版の起動 | 成功 |
| Appleでサインイン | 成功 |
| Firebase App Check → Authentication | TestFlight 版を操作したあと「確認済みのリクエスト」が増えた |
| Release 版の App Attest | 正常に動作 |
| App Check の強制適用 | 適用していない（オフのまま） |
| Firestore への生活データの送信 | 追加なし |
| App Store への審査提出・公開 | していない |

強制適用をオンにするかは、[強制適用をオンにするための成功条件](#強制適用をオンにするための成功条件) を満たしてから別に判断する。同日 main に取り込み。
