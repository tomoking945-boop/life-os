# TestFlight ビルド4（App Check・内部テスト用）

作業用ブランチ：`firebase-app-check-foundation`（**main にはまだ入れていない**。main は `0d72eda`）

## 設定（`LifeOS.xcodeproj/project.pbxproj`）

| 項目 | 値 | 対象 |
| --- | --- | --- |
| Version（`MARKETING_VERSION`） | 1.0（変更なし） | アプリ・テスト（Debug／Release） |
| Build（`CURRENT_PROJECT_VERSION`） | 3 → **4** | アプリ・テスト（Debug／Release） |
| Bundle Identifier | アプリ `com.tomoking945boop.lifeos`、テスト `com.tomoking945boop.lifeos.tests`（変更なし） | |
| 暗号化の申告（`ITSAppUsesNonExemptEncryption`） | NO（変更なし） | アプリ（Debug／Release） |

ビルド4のための変更は Build 番号だけ。App Check・Firebase・Appleでサインインのプログラム、Firestore のルール、アイコン、通知は変えていない。Apple の Team・証明書・秘密鍵・Debug Token は GitHub に保存していない。

## ビルド3との違い

- Firebase App Check（Release は App Attest、Debug は Debug Provider）。Firebase の設定より前に App Check を設定する（[FIREBASE_APP_CHECK_FOUNDATION.md](FIREBASE_APP_CHECK_FOUNDATION.md)）
- entitlements に App Attest（production）
- App Check の強制適用はオフのまま。生活データは送らず、Firestore にも書き込まない

## 確認済みのこと（2026-10-20 池上さん・commit `6a9d422`・Build 3 の設定のとき）

- Xcode のテスト：完了（件数・スキップ数は未報告）
- Release ビルド：成功
- 実機の Debug 版：起動成功。Debug Token を Firebase Console に登録し、App Check → Authentication で「確認済みのリクエスト」2件
- App Check の強制適用：オフのまま
- Firestore への書き込み：無し

Build 4 の設定そのもののビルド・テストは、この環境に Xcode が無いため未実行（Mac で確認する）。

## Archive の手順（Mac）

1. GitHub でブランチ `firebase-app-check-foundation` を選び、ZIP でダウンロードして Xcode で開く（Firebase の部品の読み込みが終わるまで待つ）
2. Signing & Capabilities で自分の Team を選び、「App Attest」と「Sign in with Apple」があることを確かめる（この変更は GitHub に送らない）
3. ⌘U でテスト（失敗0件を確認）
4. 上の端末の選択を「Any iOS Device (arm64)」にする
5. メニューの Product → Archive（Archive は Release なので App Attest を使う）
6. Organizer で、いちばん上の Archive が Version 1.0・Build 4 であることを確かめる
7. 「Distribute App」→ TestFlight 向け（「TestFlight Internal Only」など）→ Upload（Firebase の部品の dSYM の警告が出ても、ビルド3と同じくアップロードは続けてよい）
8. App Store Connect の TestFlight で 1.0 (4) の処理が終わったら、内部テスターに追加する

## TestFlight 版で確かめること

1. TestFlight から 1.0 (4) を入れて起動する
2. 今日・カレンダー・やること・リスト・お金・なんでも追加・保証書・通知が今までどおり使える
3. プロフィール → 共有用アカウント → Appleでサインイン（成功すること）
4. 数分おいてから Firebase Console → App Check →「API」→ Authentication を開き、「確認済みのリクエスト」が増えていることを確かめる（TestFlight 版は App Attest でトークンを取る。Debug Token は使わない）
5. 強制適用はまだオンにしない（[FIREBASE_APP_CHECK_FOUNDATION.md](FIREBASE_APP_CHECK_FOUNDATION.md) の「強制適用をオンにするための成功条件」を満たしてから判断する）

App Store への審査提出・公開はしない。問題がなければ、このブランチを main に入れる。
