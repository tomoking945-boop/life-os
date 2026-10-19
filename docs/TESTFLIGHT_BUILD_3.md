# TestFlight ビルド3（内部テスト用）

作業用ブランチ：`prepare-testflight-3`（main `a2c630a` から作成。**main にはまだ入れていない**）

## 設定（`LifeOS.xcodeproj/project.pbxproj`）

| 項目 | 値 | 対象 |
| --- | --- | --- |
| Version（`MARKETING_VERSION`） | 1.0（変更なし） | アプリ・テスト（Debug／Release） |
| Build（`CURRENT_PROJECT_VERSION`） | 2 → **3** | アプリ・テスト（Debug／Release） |
| Bundle Identifier | アプリ `com.tomoking945boop.lifeos`、テスト `com.tomoking945boop.lifeos.tests`（変更なし） | |
| 暗号化の申告（`ITSAppUsesNonExemptEncryption`） | NO（変更なし） | アプリ（Debug／Release） |

変えたのは Build 番号だけ。Firebase・Appleでサインイン・Firestore のルール・アイコン・通知・ほかの機能は変えていない。Apple の Team・証明書・`.p8` の秘密鍵は GitHub に保存していない（`DEVELOPMENT_TEAM` は未設定のまま）。

## ビルド3に入る内容（ビルド2との違い）

- パートナー共有の土台：Firebase への接続と「Appleでサインイン」（プロフィール →「共有用アカウント」）。サインイン・サインアウト・アカウント削除。生活データは送らず、Firestore にも書き込まない（[FIREBASE_APPLE_AUTH_FOUNDATION.md](FIREBASE_APPLE_AUTH_FOUNDATION.md)）
- アカウント削除ボタンが反応しない不具合の修正
- 新しいアプリアイコン（`kurashi-os-app-icon-v2.png`）

## 確認済みのこと（main `a2c630a` の内容。2026-10-19 池上さんの Mac・iPhone）

- Xcode の自動テスト：Test Succeeded、失敗0件（総数は245件の想定。正確な件数・スキップ数は未報告）
- Release ビルド：成功。AppIcon の警告なし
- 新しいアイコンがホーム画面に表示される
- Appleでサインイン → Firebase Authentication に利用者が作られる
- 削除の確認で「やめる」・Apple の再認証の途中キャンセルでは、何も消えない
- アカウント削除：処理中の表示 → Apple の再認証 → 連携の解除 → Firebase の利用者の削除まで成功。端末内のデータは残る
- Firestore に生活データは作られていない

ビルド3の設定（Build 番号の変更）そのもののビルド・テストは、この環境に Xcode が無いため未実行（Mac で確認する）。

## Archive の手順（Mac）

1. GitHub でブランチ `prepare-testflight-3` を選び、ZIP でダウンロードして Xcode で開く（Firebase の部品の読み込みが終わるまで待つ）
2. Signing & Capabilities で自分の Team を選ぶ。「Sign in with Apple」があることを確かめる（この変更は GitHub に送らない）
3. ⌘U でテスト（失敗0件を確認）
4. 上の端末の選択を「Any iOS Device (arm64)」にする
5. メニューの Product → Archive
6. Organizer が開いたら、いちばん上の Archive が Version 1.0・Build 3 であることを確かめる
7. 「Distribute App」→ TestFlight 向け（「TestFlight Internal Only」など）→ Upload
8. App Store Connect の TestFlight に 1.0 (3) が出て処理が終わったら、内部テスターに追加する
9. 問題がなければ、このブランチを main に入れる

App Store への審査提出・公開はしない。
