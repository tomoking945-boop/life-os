# Build 24：月の予算・カテゴリー別の予算・今日画面の MONEY

2026-11-10。ブランチ `build24-monthly-budget-and-category-summary`（`origin/main` の `edccbb4` から）。main には入れていません。
Firebase（Firestore のルール・索引・Functions・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `edccbb4`（予定どおり。Build 23 と、その実機での確認結果の記録） |
| ブランチ | `build24-monthly-budget-and-category-summary` を `origin/main` から作成 |
| commit していない変更・送っていない変更・stash | なし（上書きしていない） |

**Build 16 は欠番** です（`docs/BUILD_17_EVENT_DESTINATION_SWITCH.md`）。Build 17〜23 に続き、今回は Build 24 です。Version は 1.0、`ITSAppUsesNonExemptEncryption = NO` のままです。

## 何を作ったか

1. **月の予算**：「お金」の画面の上に予算のカード。表示している月の予算を設定・変更・解除できる。
   予算・使った金額・残り・使用割合・残りの日数・「1日あたりの目安」を出す。予算が無ければ「今月の予算を設定」
2. **自分だけの予算と、わが家の共有予算を分ける**：「自分」は自分だけの予算、「共有」はわが家の予算、「すべて」は2枚のカードを別々に出す（足して1つにしない）
3. **月ごとの予算**：月の切り替え（前の月・次の月・今月に戻る）。過去の月の予算は残り、翌月へ自動でコピーしない（「前月の予算をコピー」を押したときだけ欄に入れる）
4. **カテゴリー別の予算**：今までの6つのカテゴリーだけ。任意（未設定のカテゴリーは使った金額だけ）。予算・使った金額・残り・使用割合を縦の一覧で
5. **今日画面の MONEY**：「お金」の画面と同じ数え方にした（以前は見本の固定値）。タップで「お金」の画面を開く

外部の AI による予測・お金の助言・銀行やカードとの連携・予算の変更の通知は作っていません。

## 自分だけ／わが家で共有の保存先

| | 自分だけの予算 | わが家の共有予算 |
| --- | --- | --- |
| 保存先 | この iPhone の中（life-store.json の `monthlyBudgets`） | Firestore の `groups/{groupID}/monthlyBudgets/{YYYY-MM}` |
| 送るか | **送らない**（Firestore に置き場所も無い） | わが家のメンバーだけが読み書き |
| 数える支出 | 自分だけの支出だけ | 共有の支出だけ |
| 変えられる人 | 本人 | オーナーとパートナーのどちらも |
| 家計簿の共有がオフのとき | 関係なし | 新しい月の予算は作れない。すでにある予算は変更・解除できる（共有の支出と同じ） |

- わが家の予算は端末には保存しません（起動中だけ持ち、Firestore から読み直す）
- 変えた人の UID・メールアドレスは、画面にもログにも出しません

### Firestore へ送る情報（わが家の共有予算だけ）

| 項目 | 内容 |
| --- | --- |
| `schemaVersion` | 1 |
| `monthKey` | `YYYY-MM`（文書の ID と同じ） |
| `totalAmount` | 月の予算（1〜999,999,999 の整数） |
| `categoryAmounts` | 設定したカテゴリーだけ（`food`・`dailyGoods`・`diningOut`・`transport`・`subscription`・`other`。0〜999,999,999 の整数） |
| `updatedBy` | 変えた本人の UID（ルールで本人だけ） |
| `updatedAt` | サーバーの時刻 |

`createdAt` は入れていません。予算は「今の値」だけを使い、作った日時は画面にも集計にも使わないためです。

### 送らない・保存しない情報

- 自分だけの予算（端末の中だけ）
- 支出の名前・金額（予算の文書には入れない）
- 検索語・見た履歴・お金の助言のためのデータ（作っていない）
- レシートの写真・読み取った全文
- 商品名・予算・金額を含むログ（新しく足したファイルに `print`・`Logger` などは無い）
- Analytics・Crashlytics・外部の AI・銀行の API は足していない

## 月とカテゴリーの集計

- 月のキーは `YYYY-MM`。予算を保存できるのは 2000年1月〜2099年12月（ルールと同じ）
- 支出は **支出の日付** の月で数えます（作った日・直した日では数えない）。日付は端末の暦（日本語・グレゴリオ暦・端末のタイムゾーン）で月に分けます
- 月末・年末年始（12月31日は12月、1月1日は1月）・うるう年（2028年2月は29日）も、端末の暦で決めます
- 自分だけの予算は自分だけの支出、わが家の予算は共有の支出だけを数えます。自分だけ⇔共有を変えている途中も、同じ支出は1回だけ数えます
- カテゴリーごと：予算があるか、使った金額があるカテゴリーだけを、決まった順（食費・日用品・外食・交通・サブスク・その他）で出します
- 支出のカテゴリーを変える・支出を消す・自分だけ⇔共有を変えると、すぐに集計が変わります（集計を保存せず、毎回今の支出から数えるため）

### 表示する値

| 値 | 計算 |
| --- | --- |
| 使った金額 | その月の支出の合計（あふれない足し算） |
| 残り | 予算 − 使った金額 |
| 予算を上回ったとき | 「予算を¥2,500上回っています」（責める言葉・強い警告・強い赤は使わない。細い線は 100% で止める） |
| 使用割合 | 使った金額 ÷ 予算（予算は1円以上なので 0 で割らない） |
| 残りの日数 | 今月は今日を含む（11月10日なら21日）。過ぎた月は 0日、先の月はその月の日数 |
| 1日あたりの目安 | 残り ÷ 残りの日数（1円未満は切り捨て）。残りが無い・日数が 0 のときは出さない。「残りの予算を日数で割った参考の値」と書き、使い方のおすすめ・お金の助言にはしない |

### 金額の決まり

| | 月の予算 | カテゴリーの予算 |
| --- | --- | --- |
| 範囲 | 1〜999,999,999 円 | 0〜999,999,999 円 |
| 空 | 保存しない（「月の予算を入れてください」） | 未設定（0円とは別） |
| 拒否 | 負の数・小数・文字・上限超え | 同じ |
| 合計 | — | カテゴリーの予算の合計は月の予算以下（超えたら保存せず「カテゴリーの予算の合計（¥…）が、月の予算（¥…）を超えています…」） |

全角の数字・カンマ・「円」「¥」は読みます（「１２０，０００円」→ 120,000円）。10桁以上は数に直す前に断るので、あふれません。

## 今日画面との連携

| 今日画面の範囲 | 出すもの |
| --- | --- |
| 自分 | 今日・今月の自分だけの支出。予算があれば「予算 残り ¥…」と細い線 |
| 共有 | 今日・今月の共有の支出。わが家の予算があれば「予算 残り ¥…」と細い線 |
| すべて | 今日・今月の支出の合計と、「自分 残り ¥…・共有 予算未設定」のように分けた1行（足して「総予算」にしない。細い線は出さない） |
| 一人で使う設定 | 自分だけ |

- 「お金」の画面のカードと同じ計算（`MonthlyBudgetCalculator`）を使うので、値は同じです
- 以前の見本の固定値（今月 ¥82,450・予算 ¥120,000）は使いません
- MONEY の部分をタップすると「お金」の画面を開きます。予算の一言は1行です

## 以前のデータとの互換性

- 以前の保存データには予算の項目が無いので、どの月も「未設定」から始まります（支出はそのまま）
- 以前の「予算」の値（Build 13〜23。設定の画面は無く、見本の値か 0円）は、月の予算にしません（`MoneyViewModel.budget` として残し、画面には出さない）
- 壊れた予算の記録（読めない月・正しくない金額・形の違う記録）は飛ばし、ファイル全体は読めるようにしています（支出・明細を失わない）
- 共有の支出・明細の形は変えていません

## Rules・Functions・Indexes の変更

| | 変更 |
| --- | --- |
| Firestore のルール | **追加**：`groups/{groupID}/monthlyBudgets/{monthKey}` |
| 索引（Indexes） | 変更なし（月ごとの文書を読むだけで、新しい問い合わせは無い） |
| Functions | 変更なし（わが家の削除・最後のメンバーのアカウント削除は、今までどおり `recursiveDelete` でわが家の下を丸ごと消すため、予算も残らない。予算では通知しない） |
| Hosting | 変更なし |

### ルール（`firestore.rules`）

- 読める・作れる・変えられる・消せるのは、わが家のメンバーだけ（サインインしていない人・メンバーでない人・退出した人・ほかのわが家の人は拒否）
- 新しく作れるのは、わが家の設定で「家計簿」がオンのときだけ。変更・解除はオフのあとも（共有の支出と同じ）
- 決まった6項目だけ（足りない・多いものは拒否）。`schemaVersion` は 1。`monthKey` は文書の ID と同じ
- 月のキーは `^20[0-9]{2}-(0[1-9]|1[0-2])$`
- 月の予算は 1〜999,999,999 の整数、カテゴリーは決まった6つだけ・0〜999,999,999 の整数、カテゴリーの合計は月の予算以下
- `updatedBy` は本人の UID、`updatedAt` はサーバーの時刻
- 共有の支出・明細のルールは変えていません（予算のルールは別の場所に書いた）

## Firebase の公開が必要か・公開順序

**Firestore のルールの公開が必要です**（索引・Functions・Hosting は不要）。

1. Mac でテスト（下の「Mac での次の手順」）がすべて成功
2. **Firestore のルールだけを公開**：`firebase deploy --only firestore:rules`（`firebase deploy` だけのコマンドは使わない）
3. そのあとで Build 24 を TestFlight へアップロード

ルールを公開する前に Build 24 を使うと、わが家の共有予算の保存はルールに断られ（元の予算に戻り、「わが家の予算を保存できませんでした」と出る）、自分だけの予算・支出は今までどおり使えます。
Build 23 以前のアプリは予算の場所を読み書きしないので、ルールを先に公開しても影響はありません。

## 元に戻す方法

- アプリ：Build 23 に戻すと、予算のカードと今日画面の新しい表示が無くなります（端末の `monthlyBudgets` は読まずに残るだけ。支出・明細はそのまま）
- ルール：`monthlyBudgets` の部分を消したルールを公開し直すと、わが家の予算は読み書きできなくなります（文書は残る。消すときは Firebase Console から。わが家の削除では今までどおり消える）
- Functions・索引は変えていないので、戻す作業はありません

## 変更ファイル

| ファイル | 内容 |
| --- | --- |
| `LifeOS/Core/Models/MonthlyBudgetPlan.swift` | 新規。月のキー・予算・入力の決まり・集計（残り・割合・日数・目安・カテゴリー別）・端末の記録 |
| `LifeOS/Core/Sharing/SharedMonthlyBudgets.swift` | 新規。わが家の予算の送る形・読む形・保存先の窓口 |
| `LifeOS/Core/Sharing/FirestoreSharedMonthlyBudgetsBackend.swift` | 新規。Firestore の `monthlyBudgets` だけを読み書きする |
| `LifeOS/Core/Sharing/SharedExpenses.swift` | わが家の予算の見張り（常に1つ）・保存・断られたときに元に戻す |
| `LifeOS/Core/Store/LifeStore.swift`・`LifeOS/Core/Repositories/Repositories.swift` | 自分だけの予算（端末に保存）・わが家の予算（起動中だけ） |
| `LifeOS/Features/Money/MoneyViewModel.swift` | 表示している月・予算のカード・入力・保存・解除 |
| `LifeOS/Features/Money/MoneyView.swift` | 月の切り替えと予算のカード（以前の「今月の支出・予算・残り」の表示を置き換え）。カテゴリーの合計はカードに |
| `LifeOS/Features/Money/MonthlyBudgetViews.swift` | 新規。予算のカード・入力の画面 |
| `LifeOS/Features/Today/TodayViewModel.swift`・`TodayView.swift` | MONEY を「お金」の画面と同じ数え方に。タップで「お金」の画面 |
| `firestore.rules` | `monthlyBudgets` のルールを追加 |
| `LifeOS.xcodeproj/project.pbxproj` | Build 番号 23 → 24（4か所） |
| `LifeOSTests/Build24MonthlyBudgetAndCategorySummaryTests.swift` | 新規。テスト1〜45 |
| `LifeOSTests/Build23ExpenseSearchAndPriceHistoryTests.swift` | Build 番号の確認を「23 以上」に |
| `LifeOSTests/Build10StabilityTests.swift`・`LifeOSTests/AppCheckTests.swift` | 新しい Firestore の窓口（`FirestoreSharedMonthlyBudgetsBackend.swift`）を、見張り・Firestore を使ってよいファイルに足し、使うコレクション・書く項目を確かめる |
| `firebase/functions/test/unit/monthlyBudgets.test.js` | 新規。ルールの形・月のキー・Functions が予算に触れないこと |
| `firebase/functions/test/emulator/rules.test.js`・`accountDeletion.test.js`・`functions.test.js` | 予算のルール・削除・通知なしのテストを追加 |
| `README.md`・この文書 | 文書 |

### 既存のテストで変えたところ（削除・スキップ・常に成功する形にはしていない）

- `Build23ExpenseSearchAndPriceHistoryTests.testBuildNumberIs23`：「4か所がそろっていて 23 以上」に（今までの Build と同じ扱い）
- `Build10StabilityTests.testOnlyServiceOwnsListener`：見張りを持ってよい窓口に `FirestoreSharedMonthlyBudgetsBackend.swift` を足した（Build 13・21 と同じ扱い。画面は見張りを持たないことは変わらず確かめる）
- `AppCheckTests`（Firestore を使ってよいファイル）：同じく足し、使うコレクションが `groups`・`monthlyBudgets` だけ・書く項目・ログなしを新しく確かめる
- Build 13 の「予算は端末の設定」（`MoneyViewModel.budget`）のテストは変えていません（以前の値として残している）

## テスト件数と結果

### 件数（変更前 → 変更後）

| テスト | 変更前 | 変更後 |
| --- | --- | --- |
| サーバーの単体テスト | 103 | **113**（＋10） |
| Rules Emulator | 100 | **109**（＋9。予定の数） |
| Functions Emulator | 47 | **48**（＋1。予定の数） |
| アカウント削除 | 30 | **34**（＋4。予定の数） |
| サーバーの合計 | 280 | **304**（予定の数） |
| Swift（Xcode） | 744（Build 23 時点の予定の数。Mac での実行件数は未報告） | **782**（＋38。予定の数） |

### 指示のテスト1〜45 と、確かめている場所

| 指示 | Swift（`Build24...Tests`） | サーバー |
| --- | --- | --- |
| 1 個人の月予算を保存 | `testPersonalBudgetIsSaved` | — |
| 2 個人予算を送らない | `testPersonalBudgetIsNotSent` | Rules（自分だけの置き場所が無い） |
| 3 共有予算を保存 | `testHouseholdBudgetIsSavedWithFixedFields` | Rules「テスト3・4」 |
| 4 パートナー側に反映 | `testPartnerSeesAndEditsHouseholdBudget` | Rules「テスト3・4」 |
| 5 非メンバー・未認証を拒否 | `testNonMemberAndSignedOutCannotUseHouseholdBudget` | Rules「テスト5・39」 |
| 6 ほかのわが家を拒否 | `testOtherHouseholdBudgetsAreSeparate` | Rules「テスト6」 |
| 7 月キー | `testMonthKeys` | Rules「テスト7」、unit |
| 8 下限・上限 | `testAmountBounds` | Rules「テスト8・9」、unit |
| 9 負数・小数・文字 | `testNegativeDecimalAndTextAreRejected` | Rules「テスト8・9」 |
| 10 不要なフィールド | `testHouseholdBudgetIsSavedWithFixedFields` | Rules「テスト10・11」、unit |
| 11 決まったカテゴリー | `testOnlyKnownCategories` | Rules「テスト10・11」、unit |
| 12 カテゴリー合計 ≤ 月予算 | `testCategoryTotalMustNotExceedTotal` | Rules「テスト12」、unit |
| 13 予算未設定 | `testUnsetBudget` | — |
| 14 予算解除 | `testRemovingBudgets` | Rules「テスト14」 |
| 15 過去月 | `testPastMonthsAndNoAutomaticCopy` | — |
| 16 月末・年末年始 | `testMonthEndAndNewYear` | — |
| 17 うるう年 | `testLeapYear` | — |
| 18 支出日で集計・19 作成日では集計しない | `testCountsByExpenseDateNotCreationDate` | — |
| 20 自分だけ・21 共有・22 すべてで混ぜない | `testScopesAreNotMixed` | — |
| 23 カテゴリー別 | `testCategoryLines` | — |
| 24 カテゴリー変更・25 支出削除 | `testCategoryChangeAndDeletion` | — |
| 26 自分だけ⇔共有・27 重複しない | `testDestinationChangeMovesWithoutDuplicates` | — |
| 28 残額・29 超過・30 使用割合 | `testRemainingOverAndRatio` | — |
| 31 残り日数・32 1日あたりの目安 | `testDaysRemainingAndDailyAllowance` | — |
| 33 0除算なし | `testNoDivisionByZero` | — |
| 34 オーバーフローなし | `testNoOverflow` | Rules「テスト12」（大きな合計） |
| 35 今日画面との一致 | `testTodayMatchesMoneyScreen` | — |
| 36 MONEY タップ | `testTappingMoneyOpensMoneyTab` | — |
| 37 わが家削除 | `testHouseholdRemovalClearsSharedBudgetsOnly` | アカウント削除「テスト37」 |
| 38 アカウント削除 | `testHouseholdRemovalClearsSharedBudgetsOnly` | アカウント削除「テスト38」2件 |
| 39 退出後は読めない | `testNonMemberAndSignedOutCannotUseHouseholdBudget` | Rules「テスト5・39」 |
| 40 ログに出さない | `testNoLoggingOrAnalytics` | Functions（予算で通知しない） |
| 41 Build 23 の検索 | `testBuild23SearchStillWorks`（と Build 23 のテストすべて） | — |
| 42 Build 21 の商品明細 | `testBuild21LineItemsStillWork`（と Build 21 のテストすべて） | — |
| 43 レシート・保証書 OCR | `testReceiptAndWarrantyOCRStillWork` | — |
| 44 Build 番号・45 Version・暗号化 | `testBuildNumberIs24` | — |

ほかに、わが家の予算の保存が断られたら元に戻すこと・家計簿オフのあとの扱い・以前のデータと壊れた記録・見張りが1つだけ・VoiceOver とキーボード（Build 22 と同じ閉じ方）も確かめています。

### 結果（この作業環境）

| テスト | 結果 |
| --- | --- |
| サーバーの単体テスト | **113件成功・失敗0・スキップ0** |
| Rules Emulator・Functions Emulator・アカウント削除 | **未実行**（この作業環境では Firestore Emulator を取得できない）。JavaScript の書き方の確認（`node --check`）だけ実行：問題なし |
| Swift（Xcode） | **未実行**（この作業環境に Xcode が無い）。全 Swift ファイルの簡易の字句チェック（かっこ・文字列・コメントの対応）だけ実行：問題なし |

### Mac での最初の確認と修正（2026-11-10、池上さんの報告。`76d1d2f`）

- Xcode でコンパイルエラー：`MonthlyBudgetPlan.swift` の `Type 'BudgetAmountProblem' does not conform to protocol 'Error'`
- 原因：`BudgetAmountInput.parse` は `Result<Int?, BudgetAmountProblem>` を返しますが、Swift の `Result` の失敗側の型は `Error` に準拠していなければなりません。`BudgetAmountProblem` は `Equatable` だけでした（この作業環境には Xcode が無く、組み立てで確かめられなかったため見落としました）
- 修正：`enum BudgetAmountProblem: Error, Equatable` にしました（型の宣言だけ。値・日本語の理由・アプリの動作・データの形・Rules・Functions は変えていません）
- 同じ原因の箇所：Build 24 で新しく足した `Result` は、`BudgetAmountInput.parse`（直した）と `MonthlyBudgetDraft.validated`（失敗側の `BudgetInputError` は、もともと `Error` に準拠）の2つだけでした。ほかに同じ原因の箇所はありません
- 念のための書き換え：端末の予算の記録を読む部分（`MonthlyBudgetRecords` の月のキー）の `init?(intValue: Int) { nil }` を、意味が同じ `init?(intValue: Int) { return nil }` にしました（Swift の版によって省略の書き方が通らないことがあるため。動作は同じ）
- テスト：変えていません（削除・スキップ・弱める変更なし）
- Build 番号は24、Version は1.0のまま
- 修正のあとの Mac での結果：**未報告**

### 2回目のXcode確認で見つかったテストコードのコンパイルエラー（2026-11-10、池上さんの報告。`b028532`）

- 修正の commit：`7da3728`（池上さんが Mac から送った commit。この記録の見出しは、そのあとの文書だけの commit で整えた）
- Xcode のテストを組み立てると、`Build24MonthlyBudgetAndCategorySummaryTests.swift` の `testScopesAreNotMixed` で `Errors thrown from here are not handled` が1件出ました
- 原因：テスト内で `try build24Source(...)` を使っていましたが、テスト関数の宣言に `throws` がありませんでした
- 修正：`func testScopesAreNotMixed() throws` に変更しました。確かめる内容、アプリ本体、データの形、Rules、Functions は変えていません
- 同じテストファイルを確認し、`try` を使っているのに `throws` がないテストは、ほかにありませんでした
  （テスト関数ごとに `try`・`throws` の有無を機械的に調べた。ほかのテストファイルでは `WarrantyTests.testSizeAndTypeLimits` だけが当てはまったが、
  `try` は `XCTAssertNoThrow(...)`・`XCTAssertThrowsError(...)` の中にあり、`throws` は要らない正しい書き方）
- アプリのコード・テストの中身（確かめる内容）は変えていません。テストの削除・スキップ・弱める変更もしていません。Build 番号は24、Version は1.0のまま
- 修正のあとの Mac での結果：**未報告**

Mac での確認結果：**未報告**。

## 実機確認手順（Build 24。わが家で家計簿を共有している2台で）

1. お金 → 上の予算のカード →「今月の予算を設定」→ 月の予算・カテゴリーの予算を入れて「保存」
2. 予算・使った金額・残り・使用割合・残りの日数・1日あたりの目安が出る
3. 「自分」「共有」「すべて」を切り替える → 「すべて」で2枚のカード（自分だけ・わが家で共有）が別々に出る
4. わが家の共有予算を設定 → パートナーの iPhone にも出る。パートナーが変えると自分にも出る
5. 自分だけの予算は、パートナーの iPhone に出ない
6. 前の月・次の月へ移る → その月の予算と実績。翌月は未設定のまま。「前月の予算をコピー」で欄に入る（保存を押すまで保存しない）
7. 予算を上回る支出を入れる → 「予算を○円上回っています」（強い赤・強い警告にならない）
8. カテゴリーの予算の合計が月の予算を超える → 保存できず、理由が出る。小数・マイナス・文字も理由が出る
9. 支出のカテゴリーを変える・支出を消す・自分だけ⇔共有を変える → カードの値が重ならずに変わる
10. 予算を解除する → 未設定に戻る（支出は消えない）
11. 今日の画面の MONEY が、お金の画面と同じ値。タップでお金の画面が開く
12. 金額の入力中に、背景のタップ・スクロール・「完了」でキーボードが閉じる。保存・キャンセルが1回のタップで動く
13. VoiceOver でカード・カテゴリー・月の切り替えが読み上げられる
14. 今までの機能：検索・購入履歴・参考価格（Build 23）・キーボードと数字の読み取り（Build 22）・商品明細（Build 21）・レシート・保証書・予定・ToDo・買い物・通知・招待・共有の同期

## 既知の制限

- 支出の月は、それぞれの iPhone の暦・タイムゾーンで決めます。パートナーと違うタイムゾーンにいると、月の境目の共有の支出が別の月に数えられることがあります
- 1日あたりの目安は、単純に「残り ÷ 残りの日数」です（曜日・固定費・予定は考えない。お金の助言ではない）
- 予算の変更の履歴・変えた人の表示・通知はありません
- 予算を保存できるのは 2000年〜2099年の月だけです
- 一人で使う設定では、わが家の共有予算のカードは出しません
- わが家の予算を同時に2人が変えると、あとから届いた方の内容になります（月ごとの文書1つを置き換えるため）
- 以前の「予算」の値（見本の値）は使わないので、見本のデータのままの iPhone でも、予算は未設定から始まります

## リスク

- **ルールの公開が必要**：公開する前は、わが家の共有予算を保存できません（自分だけの予算は使える）
- **画面の作り直し**：「お金」の画面の上部（今月の支出・予算・残り）を、予算のカードに置き換えました。カテゴリーの合計は、カテゴリーのチップの下からカードの中へ移りました
- **今日画面の値が変わる**：以前は見本の固定値でしたが、実際の支出になります（見本のデータのままの iPhone では値が変わって見えます）
- **Xcode・Emulator で未実行**：画面（SwiftUI）の組み立てと、ルールのテストは Mac で確かめる

## Mac での次の手順

1. `git fetch origin` → `git switch build24-monthly-budget-and-category-summary`
2. `cd firebase/functions` → `npm test`（単体・Rules・Functions・アカウント削除。予定は合計304件）
3. Xcode でテスト（予定は782件）→ Release ビルド
4. 結果を教えてください（この文書に記録します）。main への取り込み・Firestore のルールの公開・TestFlight は、そのあとの指示で行います
