# Premium「大切な書類」保証書管理 MVP：実装の報告

正本の仕様：[WARRANTY_MANAGEMENT_MVP_SPEC.md](WARRANTY_MANAGEMENT_MVP_SPEC.md)
確認の手順：[WARRANTY_MANUAL_CHECK.md](WARRANTY_MANUAL_CHECK.md)

実装日：2026-10-13。この環境には Xcode が無いため、**ビルドとテストはまだ実行していない**（コードの読み合わせのみ）。

## 決定（2026-10-13 池上さん）

- 仕様書の「予定10分前と当日20時の通知は実装済み」は、GitHub の main にはありませんでした。
  - 今回作ったのは **保証書の通知だけ** です。
  - 合計59件に収める統合スケジューラーを作り、予定（40件）とタスク（1件）の枠は空けてあります。
  - 予定・タスクの通知は、後から足せる形にしてあります（`LifeNotificationService.swift` の TODO）。

## 作成した機能

| spec | 内容 |
| --- | --- |
| 3 | 「リスト」の上に「大切な書類　Premium」の入口。保証書の件数と、次の期限（例：次の期限：冷蔵庫　あと28日）を表示 |
| 3 | Free：説明と Premium 案内（見本データは出さない）／Premium：一覧・検索・＋で登録／Premium 終了後：閲覧・写真表示・書き出し・削除だけ |
| 3 | 一覧は「期限が近い」「保証期間中」「期限終了」の順。検索の対象は製品名・メーカー・型番・購入店・保管場所 |
| 4 | 写真の追加：カメラで撮る（AVFoundation）／写真から選ぶ（PhotosPicker）／あとで追加。最大10枚、HEIC・JPEG・PNG、1枚25MBまで |
| 4 | 原本のまま保存（再圧縮しない）。同じ画像は SHA-256 で見つけて確認を出す。キャンセルしても空の保証書を作らない |
| 4 | Apple Vision（VNRecognizeTextRequest・日本語と英語・端末内）で文字を読み取り、候補を作る |
| 4 | 読み取り結果の確認：「確認が必要」の印、ほかの候補の選択、入力済みの項目は上書きしない、「候補を反映」を押すまで反映しない |
| 5 | 入力項目：製品名（必須）・カテゴリー・メーカー・型番・製造番号・購入店・購入日・保証期間（日／か月／年）・保証終了日・保管場所・メモ・写真・所有範囲・通知 |
| 5 | 保証終了日は購入日＋保証期間から計算し、根拠（購入日 2026/10/13 ＋ 1年）を表示。直接修正もできる。応当日が無いときは月末 |
| 7 | 写真の保存先：Application Support/LifeOS/WarrantyDocuments/{documentID}/{attachmentID}.拡張子。ファイル保護 `.complete` |
| 8 | 30日前・7日前・当日の 9:00 に通知。通知文に製造番号・保管場所を出さない |
| 8 | 統合スケジューラー：保証書は期限が近い6件×3通知＝18件まで、合計59件以内。起動時・追加・編集・削除・通知設定やプランの変更時に予約し直す |
| 9 | 「今日」画面：保証終了まで30日以内の保証書があるときだけ、Warm Gold の小さな案内（最も近い1件・購入店と保証書を確認・すべて見る） |
| 10 | Premium の機能一覧に「大切な書類（保証書の管理）」を追加。通知設定に「保証書の期限」を追加 |

## 変更ファイル一覧

**新規**
- `LifeOS/Core/Models/Warranty.swift`
  - 保証書、写真、カテゴリー、保証期間、読み取り候補のモデル。
- `LifeOS/Core/Utilities/WarrantyExpiration.swift`
  - 期限の計算、状態、一覧のまとまり、Free / Premium / 終了後の可否。
- `LifeOS/Core/Utilities/WarrantyAttachmentStorage.swift`
  - 原本の保存、一時フォルダ、ロールバック、孤立ファイルの掃除、SHA-256。
- `LifeOS/Core/Utilities/WarrantyFieldExtractor.swift`
  - 読み取った文字から候補を作る（純粋な計算）。
- `LifeOS/Core/Utilities/WarrantyTextRecognizer.swift`
  - Apple Vision による端末内の文字認識。
- `LifeOS/Core/Utilities/WarrantyExporter.swift`
  - 書き出しと、位置情報を除いたコピー。
- `LifeOS/Core/Notifications/LifeNotificationService.swift`
  - 統合通知スケジューラー。
- `LifeOS/Features/Documents/Warranty/` の各ファイル
  - `WarrantyListView`：一覧・Free の説明・Premium 終了後の案内・プレビュー用データ。
  - `WarrantyDetailView`：詳細・書き出し・削除。
  - `WarrantyEditorView` と `WarrantyEditorViewModel`：登録・編集。
  - `WarrantyDraft`：入力内容と候補の反映。
  - `WarrantyProposalReviewView`：読み取り結果の確認。
  - `WarrantyPhotoViews`：写真の表示と拡大。
  - `WarrantyCameraView`：カメラ。
  - `WarrantyEntryViews`：リストの入口と今日画面の案内。
- `LifeOSTests/WarrantyTests.swift`（38件）
- docs：`WARRANTY_MANAGEMENT_MVP_SPEC.md`（受け取った仕様書をそのまま）、`WARRANTY_MANUAL_CHECK.md`、本書

**変更**
- `LifeOS/Core/Store/LifeStore.swift`
  - 保証書と写真の情報を保存。Snapshot には Optional で追加。
  - 追加・更新・削除・写真の削除。起動時に孤立ファイルを掃除。
- `LifeOS/Core/Repositories/Repositories.swift`：`WarrantyRepository`
- `LifeOS/Core/Utilities/LocalStorage.swift`：保存先の土台を写真の保存でも使えるようにした（`rootDirectory`）
- `LifeOS/Core/Models/UserProfile.swift`
  - 通知設定に `warrantyReminders` を Optional で追加。以前の保存データもそのまま読めます。
- `LifeOS/App/MainTabView.swift`：通知を予約し直すきっかけ
- `LifeOS/App/LifeOSApp.swift`：書き出しの一時ファイルの掃除
- `LifeOS/Features/Lists/ListsView.swift`：大切な書類の入口
- `LifeOS/Features/Today/TodayView.swift`：期限30日以内の案内
- `LifeOS/Features/Premium/PremiumViewModel.swift`：機能一覧
- `LifeOS/Features/Profile/NotificationSettingsView.swift`：「保証書の期限」の切り替え
- `LifeOS.xcodeproj/project.pbxproj`：カメラの使用目的の説明（`NSCameraUsageDescription`）

## 保存場所とプライバシー保護

- **保存場所**
  - 保証書の情報は、これまでと同じ端末内の JSON（`life-store.json`）に保存します。
  - 写真は `Application Support/LifeOS/WarrantyDocuments/` に保存します。
  - どちらもアプリ専用の領域です。
- **原本のまま**
  - カメラが作ったデータ（`fileDataRepresentation`）や、選んだ写真のデータ（`preferredItemEncoding: .current`）を、そのまま書き込み・移動します。
  - JPEG への作り直しはしません。テストでは、保存前後のバイトが同じことを確認しています。
- **ファイル名**
  - UUID と拡張子だけです。製品名・メーカー名・製造番号は使いません。
- **ファイル保護**
  - 写真・フォルダ・書き出しの一時ファイルは `.complete` にしています。端末のロック中は読み出せません。
- **外部へ送らない**
  - 通信の仕組み（URLSession など）は使っていません。
  - 文字の読み取りは端末内の Vision で行います。読み取った文字は確認画面に出すだけで、保存しません（全文の検索用の保存はしない）。
  - テストで、登録・読み取り・閲覧・書き出し・通知予約のあいだ URLSession の通信が0件であることを確認しています。ただし、URLSession 以外の通信までは見ていません。
- **通知**
  - 本文は「冷蔵庫の保証終了まであと30日です」の形だけです。製造番号・保管場所・写真の内容は出しません。
- **所有範囲**
  - 初期値は「自分」です。「共有」を選ぶと、写真の枚数と共有の対象になる項目名を確認します。
  - いまは同期していないため、相手の端末には送られません。パートナー共有の同期の対象（予定・ToDo・家事・買い物）にも、保証書は入っていません。
- **位置情報**
  - 原本には写真の位置情報が残ります（spec 7）。
  - 書き出すときに「位置情報を除いて書き出す」か「原本のまま」かを選べます。
  - 除くときは、まず画像を作り直さずに情報だけを除きます。それができない形式（HEIC など）は、画質を最高にして作り直したコピーを作ります。保存している原本は変えません。
- **はじめての登録**
  - 「アプリを削除すると、保証書のデータと写真も消えます」と表示します。

## 既存機能への影響

- 5タブ・既存のリスト・今日画面の並びは変えていません。
  - リストの一番上と、今日画面の Inbox とお金の間に、小さなセクションを足しただけです。
  - 今日画面のセクションは、30日以内の保証書があるときだけ出ます。
- **既存の保存データ**
  - 保証書の項目は Optional で追加したので、以前のデータは保証書が空の状態で読み込まれます（テストあり）。
  - 開発用の「データを初期化」でも、保証書は消しません。
- **通知**
  - アプリが管理する通知（識別子が `lifeos.` で始まるもの）だけを入れ替えます。ほかの通知は消しません。
  - これまで実際の通知は無かったため、消える既存の通知はありません。
- **通知設定の画面**
  - 注記を「保証書の期限は実際にお知らせします。そのほかは試作版のため送られません」に変えました。
- **追加・変更していないもの**
  - Firebase・外部 AI・StoreKit・契約書・PDF・パートナーの Push 通知は、追加していません。
  - パートナー共有の第1段階のコードも変えていません。

## 新しい解釈・TODO

- **新しい解釈**
  - Premium 終了後かどうかは、Free で保存済みの保証書があるかで決めます（解約時にデータは消さないため）。
  - 保証終了日が無い保証書は、一覧の最後に「終了日 未入力」としてまとめます。
  - 保証期間の単位は「日／か月／年」、1〜120 です。
  - HEIC には HEIF も含めます。
  - 写真を1枚ずつ消す操作は、Premium 終了後もできます（容量を空けるため。削除の一種として扱いました）。
  - 製造番号は検索の対象に入れていません（spec 3 の対象に無いため）。
  - 読み取りは、新しく追加した写真（無ければ保存済みの写真）で行います。
  - 当日の通知が 9:00 を過ぎてから保存された場合、その日の通知は予約しません。
  - 写真の「元のファイル名」は、写真アプリから取れないため「選んだ写真.heic」「撮影した写真.heic」にしています。
- **TODO**
  - 予定・タスクの通知を作るときは、統合スケジューラーの `events`・`tasks` に渡します。
  - 契約書と PDF は第2段階です。
  - 書き出しの一時ファイルは端末の一時フォルダに作り、共有シートを閉じたときと起動時に消します。
  - 写真は、iPhone のバックアップ（iCloud バックアップなど）の対象になります。仕様にバックアップの指定が無いため、対象外にはしていません。

## テスト

| テスト | 件数 | 結果 |
| --- | --- | --- |
| 新規 XCTest（WarrantyTests.swift） | 38件 | **未実行**（この環境に Xcode が無いため） |
| 既存 XCTest | 169件 | **未実行**（同上） |
| 実機の確認（カメラ・実際の通知・ロック中の保護・VoiceOver・文字サイズ・ダークモード） | — | 手順書 [WARRANTY_MANUAL_CHECK.md](WARRANTY_MANUAL_CHECK.md) |

新規テストの内容：
- 期限：1年、90日、うるう日、月末、状態と一覧の順、検索
- 保存：古いデータから空で読める、追加・編集・削除のあと再起動しても残る、製品名だけで保存、自分／共有、10枚を超えると何も保存しない
- 写真：再圧縮しない、UUID のファイル名、途中で失敗しても孤立ファイルなし、保存失敗時はデータも変えない、孤立ファイルの掃除、25MB と形式、同じ写真の確認、キャンセル、1枚削除
- プラン：Free は作れない、Premium は作れる、終了後も閲覧・書き出し・削除ができる
- 通知：9:00・30日前・7日前・当日、過去は予約しない、終了日なし・終了済み・OFF は予約しない、本文に製造番号・保管場所なし、6件18通知、既存通知と合わせて59件、Premium 終了・設定 OFF、`lifeos.` だけ入れ替え・削除した保証書の通知が残らない、許可が無いときは予約しない
- 読み取り：見出しのある項目、令和・全角、保証期限の行、複数の候補・低い信頼度・見出しの無い日付は確認が必要、候補なし
- 承認制：反映するまで入らない、入力済みを上書きしない、手入力だけで保存
- プライバシー：通信0件、書き出しで位置情報を除ける、書き出す文字
