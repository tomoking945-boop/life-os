# Build 12：新しいアプリアイコン・カレンダーから予定を追加・なんでも追加で先の予定

2026-11-01。ブランチ `build12-calendar-event-and-icon`（`fix-build9-performance-and-todo-consistency` の `cba1c62` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer の変更はしていません。

## 始める前の状態

| 確認 | 状態 |
| --- | --- |
| main | `ba6bd4c`（Build 9 の記録まで）。Build 10・11 の安定化は、まだ main に入っていない |
| 安定化の作業ブランチ | `fix-build9-performance-and-todo-consistency`：`c0abc92`（Build 11 として確認済み）→ `cba1c62`（Build 11 の結果の記録） |
| Build 11 の2台の実機確認 | 完了（重さ・クラッシュの解消、共有の通知が正常。docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md に記録） |

Build 12 は、安定化（Build 10・11）の上に作っています。

## 1. アプリアイコン（家＋チェック）

- 新しい画像：`LifeOS/Assets.xcassets/AppIcon.appiconset/kurashi-os-app-icon-house-check-v3.png`
  - 1024×1024、PNG、RGB（アルファの無い画像。透明部分なし）。四隅もクリーム色（角丸を付けていない。角丸は iPhone 側が付ける）
  - 背景は前と同じクリーム色（四隅の色：前 RGB(251,244,233)、新 RGB(253,247,236)）
  - 絵（家とチェック）の範囲は x 185〜828、y 165〜820。中心は (506, 492) で、画像の中心 (512, 512) とほぼ同じ
  - 池上さんの Mac の素材と、1バイトずつ同じファイル（画像を作り直していない）
- `Contents.json` は新しい画像だけを指す（1024×1024・universal・iOS）
- 前のアイコン（v2）は消さずに `docs/app-icon/kurashi-os-app-icon-v2.png` へ移した（アイコンのフォルダーに残すと、Xcode が「どこにも割り当てていない画像」の警告を出すため）
- アイコンの設定（`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`）は変えていない

## 2. カレンダーで選んだ日から予定を追加

- 日付を選ぶと、その日の見出しの下に「＋ 予定を追加」ボタンが出る（`CalendarView.swift`）
- 押すと「予定を追加」のシート（`CalendarEventSheet.swift`）
  - タイトル（必須）、日付（選んだ日が初期値）、終日（初期値オン）、時刻（終日をオフにしたとき。初期値 10:00）
  - 保存先はいつも「自分だけ」（予定の共有はまだしない。シートにも書いてある）
- 保存すると、これまでと同じ `LifeItem(kind: .event)`（自分・担当は自分）として保存し、その日を選んだまま、その月を表示する。一覧にすぐ出る
- 「共有」だけを表示していたときは、追加した自分の予定が見えるよう「すべて」に戻す
- タイトルが空（空白だけも含む）なら「保存」を押せない。保存もしない
- 「なんでも追加」のボタンは、そのまま残している

## 3. なんでも追加で1週間より先の予定

### 読める書き方（`DateReader.swift`）

| 入力 | 結果（2026年11月1日に入力した場合） |
| --- | --- |
| `12月25日 19時 美容院` | 予定「美容院」2026/12/25 19:00 |
| `2027年3月10日 10時 病院` | 予定「病院」2027/3/10 10:00 |
| `来月15日 歯医者` | 予定「歯医者」2026/12/15（終日） |

- 年が無いとき：今年のその日がもう過ぎていれば、次の年（今日は過ぎていない扱い）。12月の「来月」は翌年の1月
- 存在しない日付（`2月30日`・`4月31日`・`13月5日`・うるう年でない年の `2月29日`・30日までの月の `来月31日` など）は、別の日（3月2日など）にずらさない。日付を決めずに「日付を確認」とし、そのままは保存しない
  - 「提案どおり追加」：保存せずに「詳しく整える」の確認画面を開く。日付を選ぶまで「追加」を押せない
  - 「種類を決めて追加」の予定：保存せず「日付を確かめてください」と知らせる（入力は消さない）
- 日付や時刻があって、ほかの手がかり（買う・払う・掃除 など）が無ければ「予定」。手がかりがあれば、これまでどおりの分類（「12月25日 プレゼントを買う」は買い物）
- アプリ独自の「1週間先まで」などの上限は無い

### 「詳しく整える」の日付

- 予定と「日付を確認」の項目に、日付を選ぶ DatePicker を出す。翌月・翌年など先の日付も選べる（上限なし）
- 時刻のある予定は、時刻をそのままにして日付だけ変える
- 確認画面の補足は、今年なら `12/25（金）`、ほかの年なら `2027/3/10（水）`（年の取り違えを防ぐ）

### 変えていないもの

- ToDo・買い物・支出・家事・支払予定の分類（日付が無い入力の結果は、前とまったく同じ。テストで確かめている）
- 保存先の初期値は「自分」。自動の分類は共有を選ばない
- おまかせ Inbox は日付を読まない（これまでどおり）
- 個人データの保存形式：`InboxSuggestion` に省略できる項目（`specificDate`・`dateProblem`）を足しただけ。前の保存データ（この項目が無いもの）もそのまま読める（テストで確認）。`LifeItem` の形は変えていない

## 変えていないもの（全体）

- Firebase Functions・Firestore ルール・索引・Hosting、共有 ToDo・買い物のデータ形式
- 通知の登録・保存の調整（`SharedPushNotifications.swift`）、Firestore の片付け（`FirestoreLocalCacheRepair.swift`）
- Bundle Identifier・Version（1.0）・Associated Domains・App Check・Sign in with Apple・`ITSAppUsesNonExemptEncryption = NO`

## Build

- **12**（アプリとテスト、Debug と Release の4か所）。Build 11 の番号は池上さんの Mac で付けたもので、リポジトリは 10 のままだったため、10 → 12 にした

## 変更したファイル

| ファイル | 内容 |
| --- | --- |
| `LifeOS/Assets.xcassets/AppIcon.appiconset/Contents.json`・`kurashi-os-app-icon-house-check-v3.png` | 新しいアイコン |
| `docs/app-icon/kurashi-os-app-icon-v2.png` | 前のアイコン（移しただけ） |
| `LifeOS/Features/Calendar/CalendarView.swift`・`CalendarViewModel.swift`・`CalendarEventSheet.swift`（新規） | 選んだ日から予定を追加 |
| `LifeOS/Core/Utilities/DateReader.swift`（新規） | 日付の読み取り |
| `LifeOS/Core/Utilities/InboxClassifier.swift`・`LifeInterpreter.swift` | なんでも追加のときだけ日付を読む |
| `LifeOS/Core/Models/InboxItem.swift` | 文の中の日付・日付の確認 |
| `LifeOS/Core/Utilities/LifeFormatters.swift` | 年つきの日付 |
| `LifeOS/Features/QuickAdd/QuickAddViewModel.swift`・`QuickAddConfirmView.swift`・`QuickAddSheet.swift` | 日付の DatePicker・確認・知らせ |
| `LifeOS.xcodeproj/project.pbxproj` | Build 12 |
| `LifeOSTests/Build12CalendarEventTests.swift`（新規） | テスト17件 |

## テスト

### 追加したテスト（`LifeOSTests/Build12CalendarEventTests.swift`。17件）

| 確かめること | テスト |
| --- | --- |
| アイコンが 1024×1024・アルファなし、Contents.json が新しい画像を指す、前のアイコンを残している | `testAppIconIs1024OpaqueAndReferenced` |
| 選んだ日から終日の予定を追加し、一覧にすぐ出る（自分だけ） | `testAddAllDayEventFromSelectedDay` |
| 時刻つきの予定を追加 | `testAddTimedEvent` |
| タイトルが空なら保存しない | `testEmptyTitleIsNotSaved` |
| 翌月・翌年・うるう日・月末 | `testFarAndEdgeDates` |
| 「共有」だけの表示でも、追加した予定がすぐ見える | `testSharedScopeShowsNewPersonalEvent` |
| 「今日」と「カレンダー」で同じ日に出る | `testSavedEventAppearsOnSameDayInTodayAndCalendar` |
| 例の3つの書き方を読む | `testReadsRequestedExamples` |
| 年が無いときの年またぎ | `testYearOmittedRollsOverToNextYear` |
| うるう日・月末・存在しない日付 | `testLeapDaysMonthEndsAndInvalidDates` |
| なんでも追加：例の3つを予定として追加（自分） | `testRequestedExamplesAreAddedAsEvents` |
| なんでも追加：8日後・3か月後・翌年 | `testEightDaysThreeMonthsAndNextYear` |
| 存在しない日付は確認画面で日付を選ぶまで保存しない | `testInvalidDateIsConfirmedBeforeSaving` |
| 「種類を決めて追加」の予定も日付を読み、存在しない日付は保存しない | `testQuickAddEventTypeReadsDates` |
| 「詳しく整える」の日付は2030年も選べ、時刻はそのまま | `testRefineDatePickerHasNoUpperLimit` |
| ToDo・買い物・支出・家事の分類が変わらない、共有を選ばない | `testExistingCategoriesAreUnchanged` |
| おまかせ Inbox は変わらない、前の保存データを読める | `testInboxUnchangedAndOldSuggestionsDecode` |

既存のテストは削除・スキップ・必ず成功する形にはしていません。

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 74 | 実行した（Node 22） | **74件成功・失敗0・スキップ0** |
| Rules Emulator・Functions Emulator・アカウント削除 | 70・43・20 | 実行できなかった（変更なし） | 未実行 |
| Swift（Xcode） | **441**（424＋17） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

### Mac での1回目の結果（2026-11-01 12:05、池上さん）

- ビルド：成功（警告3件。中身は未報告）
- テスト：**1件失敗** `AppCheckTests.testAppSourceDoesNotUseFirestore`
  - 原因：Build 10 の `c0abc92` で足した `FirestoreLocalCacheRepair.swift`（端末の中の Firestore の片付け）が、「Firestore を使ってよいファイル」の一覧に入っていなかった。`c0abc92` のときに、このテストを直し忘れていた（Build 12 の変更が原因ではない）
  - 直し方：テストの一覧に片付けのファイルを足し、そのファイルには、ほかの窓口より厳しい確かめを足した（書き込み・サーバーへの問い合わせ・見張り・`collection(`・`document(`・ログを使わない、読むのは `collectionGroup("items")` を端末の中だけで1回、止める・消すの手順があること）。片付けの処理そのものは変えていない
  - 失敗したテストを消す・飛ばす・必ず成功させる変更はしていない

### Mac・実機での確認結果（2026-11-01 12:21、池上さんの報告。`dabf78e`）

| 確認 | 結果 |
| --- | --- |
| Xcode のテスト | **成功・失敗0件**（実行件数・スキップ数：未報告） |
| Release ビルド | **成功** |
| iPhone へ、既存のアプリを消さずに上書きでインストール | **成功** |
| 新しい「家＋チェック」のアイコン | **表示を確認** |
| カレンダーからの予定の追加 | **確認** |
| 追加した予定が選んだ日に出る | **確認** |
| なんでも追加で翌月・翌年の予定を登録 | **確認** |
| アプリの重さ・クラッシュ | **問題なし** |
| 既存の通知 | **問題なし** |
| サーバーのテスト（単体 74 以外の Rules・Functions・アカウント削除） | 未報告（Build 12 ではサーバーを変えていない） |
| 1回目の警告3件の中身 | 未報告 |

- Firebase への公開・TestFlight へのアップロードはしていない

## Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 74・Rules 70・Functions 43・アカウント削除 20）
2. Xcode で ⌘U（**441件の予定**・失敗0件）、Release ビルド
3. シミュレーターまたは実機で
   1. ホーム画面のアイコンが、クリーム色の背景に家とチェックで、真ん中に見える（小さい表示：設定アプリの通知の一覧・Spotlight でも）
   2. カレンダーで来月の日を選ぶ →「予定を追加」→ タイトルを入れて保存 → その日の一覧にすぐ出る。終日をオフにして時刻を選んだ予定も同じ
   3. タイトルを空のままにすると「保存」を押せない
   4. なんでも追加に `12月25日 19時 美容院`・`2027年3月10日 10時 病院`・`来月15日 歯医者` を入れて「提案どおり追加」→ カレンダーのその日に出る。その日の「今日」にも出る
   5. `2月30日 歯医者` →「提案どおり追加」で確認画面が開き、日付を選ぶまで追加できない
   6. 共有 ToDo・買い物の追加・通知（2台）が、Build 11 と同じように動く

## 問題があったときの戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アイコンだけ戻すときは、`docs/app-icon/kurashi-os-app-icon-v2.png` をアイコンのフォルダーへ戻し、`Contents.json` の名前を戻す
- サーバーは変えていないので、戻す作業は無い
