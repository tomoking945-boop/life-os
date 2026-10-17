# TestFlight ビルド1（内部テスト用）

作業用ブランチ：`prepare-testflight-1`（main `cdbd1d5` から作成。**main にはまだ入れていない**）
目的：App Store Connect に作成済みの「くらしOS」iOS 1.0 へ、最初の内部テスト用ビルドをアップロードできる状態にする。

## 変更したこと（`LifeOS.xcodeproj/project.pbxproj` のみ）

| 項目 | 変更前 | 変更後 | 対象 |
| --- | --- | --- | --- |
| Version（`MARKETING_VERSION`） | 0.1 | **1.0** | アプリ・テスト（Debug／Release） |
| Build（`CURRENT_PROJECT_VERSION`） | 1 | 1（変更なし） | アプリ・テスト（Debug／Release） |
| 暗号化の申告（`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`） | なし | **NO** | アプリ（Debug／Release） |

暗号化の申告を NO にした理由：
- アプリは独自の暗号化を使っていない。
- CryptoKit は、保証書の写真が重複していないかを確かめる SHA-256 ハッシュにだけ使っている。
- アプリは外部と通信しない（Firebase は未接続）。

## 変更していないこと

- Bundle Identifier：アプリ `com.tomoking945boop.lifeos`、テスト `com.tomoking945boop.lifeos.tests`
- 表示名「くらしOS」、アプリアイコン、通知、保証書管理、そのほかのコード（テスト221件に影響するコードの変更なし）
- Apple の Team ID・証明書・署名の設定は GitHub に保存していない（`DEVELOPMENT_TEAM` は未設定のまま。Archive のときに Mac の Xcode で選ぶ）

## まだ行っていないこと

- ビルドとテスト：この環境に Xcode が無いため **未実行**（Mac での確認が必要）
- Archive と App Store Connect へのアップロード：行っていない（池上さんが Mac で行う）
- App Store への審査提出・公開：行わない（TestFlight の内部テスト用）

## 次の手順（Mac）

1. このブランチを Xcode で開き、⌘U でテストが221件・失敗0件（実機専用1件スキップ）かを確認する
2. Signing & Capabilities で自分の Team を選ぶ（この変更は GitHub に送らない）
3. 端末の選択を「Any iOS Device」にして、Product → Archive
4. Organizer で「Distribute App」→「TestFlight Internal Only」または「App Store Connect」→ Upload
5. App Store Connect の TestFlight にビルド 1.0 (1) が出たら、内部テスターに追加する
6. 問題がなければ、このブランチを main に入れる
