# 確定済みの変更の統合（2026-10-17）

基準：main の commit `7dc777d`（保証書管理 MVP。池上さんの Mac でビルド成功・207件中206件成功・失敗0件・実機専用1件スキップ）
作業用ブランチ：`integrate-confirmed-changes`（**Mac でテストが成功するまで main に入れない**）

**2026-10-17 池上さんの Mac で確認済み**（commit `a673373`）：ビルド成功、アセットカタログの警告なし、テスト221件で失敗0件（実機専用のファイル保護テスト1件のみスキップ）、シミュレーターへのインストール・起動、アプリアイコンの表示。同日 main に取り込み（main = `a673373`）。サーバーの単体テスト（Node）20件はこの環境で成功。

## 実施内容

| # | 指示 | 対応 |
| --- | --- | --- |
| 1 | 表示名を「くらしOS」（Debug／Release） | `INFOPLIST_KEY_CFBundleDisplayName = "くらしOS"`（2か所） |
| 2 | 画面の「生活OS」「LifeOS」を「くらしOS」に | オンボーディング、Premium、なんでも追加、Inbox、整理、提案カード、共有の始め方、招待文、カメラの案内、保証書の書き出し文、サーバーの通知タイトル、招待ページ。Swift の型名・プロジェクト名・内部ファイル名（保存先の `LifeOS` フォルダなど）は変えていない |
| 3 | Bundle Identifier | アプリ `com.tomoking945boop.lifeos`、テスト `com.tomoking945boop.lifeos.tests`（Debug／Release）。招待リンク用ファイル（AASA）の ID も変更（Team ID は TODO のまま） |
| 4 | アプリアイコン | 池上さんの確定アイコン `kurashi-os-app-icon-1024.png`（1024×1024・PNG・透過なし）を `AppIcon.appiconset` に追加し、`Contents.json` の universal・iOS・1024×1024 に設定（2026-10-17 追記）。画像は作り直していない |
| 5 | なんでも追加のキーボード | スクロールで閉じる（`.scrollDismissesKeyboard(.immediately)`）、入力欄・ボタン以外の余白を触ると閉じる（背景にだけ置くのでボタン操作を妨げない）、キーボードの上の「完了」 |
| 6 | 統合通知スケジューラー | 時刻つき予定の10分前（直近40件）、当日の未完了タスク20時に1件、保証書18件と合わせて最大59件。起動時・予定やタスクや保証書の変更時・プランや通知設定の変更時に予約し直す。通知設定の画面を開いたとき、許可が未確認ならお願いする |
| 7 | 通知設定の説明 | 「時刻のある予定の10分前」「その日のやることが残っていたら20時に1回」「この iPhone の中で予約」。許可されていないときは「設定を開く」 |
| 8 | 共有の更新 | 本物のメンバー同期ができるまで無効のまま（変更なし。テストを追加） |
| 9 | 生活グループ名の例 | はじめての設定の例を「例：わが家」に。テスト・サーバーのテストの「池上家」も置き換え |

## 新しい解釈

- タスクの通知から除くもの：習慣・予定・完了済み・もうやらない（指示どおり）に加えて、**パートナー担当のやること**（自分の端末で自分に知らせる通知のため）。
- 20時を過ぎてからアプリを開いたときは、**明日のやること**を明日の20時に予約する（アプリを開かない日も知らせるため）。
- 予定を「あとで」で動かしたときは、動かした先の時刻の10分前。
- 通知の本文：予定は「10:30 歯医者（10分後）」、タスクは「まだ終わっていないやることが2件あります」（項目名は出さない）。

## 注意：Bundle Identifier を変えると

iPhone から見ると **別のアプリ** になります。

- シミュレーター・実機に入っている今までの「生活OS」（`com.example.LifeOS`）は、そのまま残ります。
- 新しい「くらしOS」は、空のデータとはじめての設定から始まります。今までのアプリに保存したデータは、新しいアプリへは自動で移りません（保存データを消したわけではありません）。
- 確認が終わって不要になったら、古い「生活OS」はホーム画面から長押しで削除できます（**削除すると、そのアプリのデータは消えます**）。

## 変更ファイル

- `LifeOS.xcodeproj/project.pbxproj`：表示名・Bundle Identifier
- `LifeOS/Core/Notifications/LifeNotificationService.swift`：予定・タスクの通知、許可の状態
- `LifeOS/App/MainTabView.swift`：予定・タスクの変更でも予約し直す
- `LifeOS/Features/Profile/NotificationSettingsView.swift`：説明・許可のお願い・設定を開く
- `LifeOS/Features/QuickAdd/QuickAddSheet.swift`：キーボード
- 表示名：`Onboarding/OnboardingView.swift`・`OnboardingViewModel.swift`・`Premium/PremiumViewModel.swift`・`Inbox/InboxView.swift`・`Inbox/TidyUpView.swift`・`Sharing/SharedStarterView.swift`・`DesignSystem/Components/LifeInsightCard.swift`・`Core/Utilities/InviteMessage.swift`・`Core/Utilities/WarrantyExporter.swift`・`Documents/Warranty/WarrantyCameraView.swift`
- サーバー：`firebase/functions/src/notificationPolicy.js`、`firebase/hosting/invite/index.html`、`firebase/hosting/.well-known/apple-app-site-association`、テスト2ファイル
- テスト：`LifeOSTests/ConfirmedChangesTests.swift`（新規14件）、`LifeOSTests/OnboardingTests.swift`（文言と例の名前）
- docs：本書、`FIREBASE_SETUP.md`（B-1 は決定済み）、`WARRANTY_MANAGEMENT_REPORT.md`（Mac の結果）、`WARRANTY_MANUAL_CHECK.md`、`AFTER_CALM_FUTURE.md`、`README.md`

## テスト

| テスト | 件数 | 結果 |
| --- | --- | --- |
| XCTest（これまでの207件＋新規14件） | 221件 | 2026-10-17 池上さんの Mac：失敗0件（実機専用1件スキップ） |
| サーバーの単体テスト（Node） | 20件 | この環境で実行：すべて成功 |

新規テスト：予定がちょうど10分前、あとで動かした予定、時刻なし・過ぎた・完了・もうやらない予定は通知しない、予定は40件まで、未完了タスクが20時に1件（習慣・予定・完了・もうやらない・パートナー担当を除く）、すべて終わっていれば通知なし、20時以降は明日の分、設定 OFF なら予約しない、保証書・予定・タスクの合計59件、アプリの状態から予約し直す、表示名と Bundle Identifier、画面の名前、生活グループ名の例、共有の更新は無効のまま。
