# 生活OS v2 改修の報告

仕様：[LIFE_OS_V2_SPEC.md](LIFE_OS_V2_SPEC.md)／詳しい解釈と決定事項：[IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md)

2026-10-02〜03 に6回に分けて実装しました。各回ごとに Mac の Xcode でビルドと Simulator 確認を行っています（第6回は確認待ち）。
外部サービス（Firebase・OpenAI API・StoreKit・AdMob など）には一切接続していません。

## 1. 変更したファイル

- `LifeOS.xcodeproj/project.pbxproj`（Unit Test ターゲット追加）
- App：`AppState.swift`、`MainTabView.swift`
- Core/Models：`LifeItem.swift`、`Expense.swift`
- Core/Store：`LifeStore.swift`
- Core/Utilities：`LifeFormatters.swift`
- DesignSystem：`LifeColors.swift`、`LifeTypography.swift`、`LifeSpacing.swift`、`LifeRadius.swift`、`LifeTaskRow.swift`
- Features：Today（`TodayView`・`TodayViewModel`）、Calendar（`CalendarView`・`CalendarViewModel`）、Tasks（`TasksView`・`TasksViewModel`）、Lists（`ListsViewModel`）、Money（`MoneyViewModel`）、QuickAdd（`QuickAddSheet`・`QuickAddViewModel`・`QuickAddConfirmView`）、Profile（`DeveloperSettingsView`・`GroupSettingsView`・`MembersView`）、Premium（`PremiumView`・`PremiumViewModel`）
- Mock：`MockData.swift`
- `README.md`、`docs/IMPLEMENTATION_NOTES.md`

## 2. 新規作成したファイル

- Core/Models：`InboxItem`、`PostponeOption`、`LifeMemory`、`ChoreAutopilot`、`UsageStyle`、`FrequentPurchase`、`MealPlan`
- Core/Utilities：`InboxClassifier`、`TodayFocusSelector`、`LifeMemoryEvaluator`、`InviteMessage`、`ShoppingCategorizer`
- Core/Repositories：`Repositories.swift`
- DesignSystem：`LifeCategoryColors`、`LifeThemes`、`LifeHeroCard`（`LifeHeroCard`・`LifeEditorialCard`・`LifeCategoryDot`・`LifeLeafOrnament`）
- Features/Inbox：`InboxView`・`InboxViewModel`・`TidyUpView`・`TidyUpViewModel`
- Features/Today：`PostponeSheet`
- Features/LifeMemory：`LifeMemoryView`
- Features/Sharing：`SharingFlowView`・`WelcomeView`・`SharedStarterView`
- Features/Shopping：`ShoppingSection`・`ShoppingViewModel`・`MealPlanView`
- LifeOSTests：`LifeOSTests.swift`・`TestSupport.swift`
- `LifeOS.xcodeproj/xcshareddata/xcschemes/LifeOS.xcscheme`
- docs：`LIFE_OS_V2_SPEC.md`、`REPOSITORY_DESIGN.md`、`V2_REPORT.md`

## 3. 実装した新機能

| 仕様 | 機能 | 入口 |
| --- | --- | --- |
| 1 | おまかせInbox（とりあえず保存・未整理件数・分類候補） | なんでも追加の「とりあえず保存」、今日画面の Inbox |
| 2 | おまかせ整理（全部OK・修正・スキップ・後で） | Inbox の「まとめて整理」 |
| 3 | 今日これだけ（最大3件・あと◯件・完了で下へ） | 今日画面 |
| 4 | 未完了救済（今日に表示・今週に回す・あとで・もうやらない） | 今日画面「昨日残ったもの」 |
| 5 | あとで（今日の夜・明日・週末・来週の Bottom Sheet） | 今日・やること のタスク行の時計ボタン |
| 6 | 暮らしメモリー（5例・買い物に追加・土曜日に追加・今回はスキップ） | 今日画面、すべて見る |
| 7 | 家事オートパイロット（今日の余力 3段階・所要時間・チェック） | 今日画面「今日の余力」 |
| 8 | 一人モード／家族・パートナーモード | 開発用設定 |
| 9 | 1タップ家族招待 Mock（LINEで共有・リンクをコピー・わが家へようこそ） | 予定の「パートナーと共有」、招待カード、生活グループ |
| 10 | 共有スターター（ゴミの日・よく買うもの・今月の共通予定） | わが家へようこそ →「わが家を始める」 |
| 11 | 買い物の強化（自動カテゴリー・よく買うもの・再購入候補・ワンタップ追加・お店モード） | やること →「買い物」 |
| 12 | 献立 → 買い物 Mock | 買い物 →「今週の献立から作る」 |
| 13 | 習慣（habit） | 今日画面「習慣」 |
| 20 | LifeOS Themes プレビュー | Premium 画面「自分らしい生活OSに」 |
| 22 | Repository Protocol | `Core/Repositories` |
| 24 | Unit Test | ⌘U |

## 4. UIデザイン変更内容（Editorial Living）

- カテゴリー色（Mist Blue・Sage・Terracotta・Warm Gold・Lavender Gray・Forest Gray）を追加。ドット・細い線・淡い背景のみに使用し、文字色は従来どおり。
- 日付・挨拶・大見出し・キャッチコピー・番号を `.serif`。外部フォントなし。
- 今日画面を作り直し：英語のセリフ体の日付、Deep Forest のヒーロー（ごく弱いグラデーション＋抽象的な葉）、番号付きの「今日これだけ」、紙色の NEXT、カテゴリー色の淡い背景のカード。白いカードの繰り返しをやめた。
- キャッチコピーを「今日も、無理なく。」に変更。
- Motion：完了で記号の切り替え → 取り消し線 → フェード → 下へ移動。3件完了で「今日の大事なこと、完了。」。Reduce Motion のときはアニメーションなし。
- 赤字・警告色は使っていない（未完了・習慣も責めない表示）。

## 5. Model 変更内容

- `LifeItemKind` に `habit`（習慣・`leaf`）。
- `LifeItem` に `deferredTo`（表示先の日時）と `droppedAt`（もうやらない）を追加。元の `date` は書き換えない。表示は `displayDate`。
- 新規：`InboxItem`（`postponedUntil`）、`InboxSuggestion`、`PostponeOption`、`LifeMemory`（`MemoryRule`・`MemoryAction`）、`EnergyLevel`・`ChoreTemplate`・`AutopilotDay`、`UsageStyle`、`FrequentPurchase`・`ShoppingCategory`、`MealPlanDay`、`LifeTheme`。
- `AppState` に `usageStyle`・`partnerJoined`・`effectiveScope`。
- 保存：追加した項目はすべて Optional で保存データに追加し、以前の保存データもそのまま読める。

## 6. TODO（主なもの）

- 「今週に回す」「週末」「来週」の曜日の決め方（現状：今週の土曜／次の土曜／次の月曜）
- 暮らしメモリーの「今回はスキップ」（現状：周期を数え直す）、周期の学習、メモリーの追加・編集
- 習慣のくり返し設定
- 今日これだけ の本格的な選定（期限・優先度・余力など）
- 一人／共有の初回オンボーディング
- Premium 画面の機能一覧に v2 の Premium 候補を反映するか
- テーマを実際にアプリへ適用する仕組み
- 残りの ViewModel の Repository 経由への切り替え
- 広告カードの位置、ダークモード配色

## 7. 未実装の外部サービス

Firebase／Firestore／Firebase Storage／OpenAI API（AI 分類・AI 自然文検索）／StoreKit／AdMob／Push 通知／WidgetKit／Apple Calendar 同期／位置情報／OCR（レシート）／Universal Links／招待のバックエンド。すべて Mock または UI のみ。

## 8. Unit Test 結果

テストは `LifeOSTests` に 11 グループ・38 件。第6回のファイルを入れたあと、Xcode で ⌘U を実行して確認する（この報告の作成時点では未実行）。

## 9. Xcode Build 結果

第1〜5回：Mac の Xcode でビルド成功を確認済み。第6回：確認待ち。

## 10. Simulator 確認結果

第1〜5回：各回の確認項目を Simulator で確認済み（既存の5タブ・すべて/自分/共有・QuickAdd・Profile・PhotosPicker・保存・Free/Premium・Money・Lists・Calendar も動作）。第6回は画面の変更なし。

## 11. Firebase 導入前に直すべき点

[REPOSITORY_DESIGN.md](REPOSITORY_DESIGN.md) の「Firebase 導入前に決める・直すこと」を参照。特に重要なのは次の4つ。

1. Mock の現在時刻（9:10 固定）を `Date()` に戻す
2. 担当者（me / partner / either）をユーザー ID に置き換え、生活グループ ID を各データに持たせる
3. 保存の非同期化と失敗時の扱い
4. 開発用設定を本番で隠す

## 12. 次の推奨実装順

1. 残りの ViewModel を Repository 経由に切り替える（画面の動きは変えない）
2. Mock の現在時刻を実時刻に切り替え、時間帯の挨拶を入れる
3. 習慣のくり返し・暮らしメモリーの編集など、ローカルだけで完結する未決事項を決める
4. Apple Sign In と Firebase（Auth → Firestore の LifeItem から）を接続
5. 家族招待のバックエンドと Universal Links
6. StoreKit（Premium）、その後 AdMob
