# Build 19：レシートの店名候補を選ぶ・予定を登録した人の色で表示する

2026-11-04。ブランチ `build19-receipt-store-selection-and-calendar-colors`（`origin/main` の `18f736c` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `18f736c`（予定どおり。Build 18 の修正版） |
| ブランチ | `build19-receipt-store-selection-and-calendar-colors` を `origin/main` から作成 |
| commit していない変更・stash | なし（混ぜていない） |
| Build 18 の実機での結果 | `docs/BUILD_18_RECEIPT_TO_BUDGET.md` に、機能とは別の commit で記録（「レシート読み取りから家計簿への支出作成が動いた」。13項目それぞれ・枚数は未報告） |

**Build 16 は欠番** です（`docs/BUILD_17_EVENT_DESTINATION_SWITCH.md` に記録。そのまま残しています）。
**商品明細の読み取りは Build 20 の予定** で、今回は作っていません。

## 1. 何を作ったか

1. **レシートの店名候補**：読み取ったレシートの上の方から店名の候補を最大5件作り、確認画面（レシートから開いた「支出を追加」）で選べるようにした
2. **予定の色分け**：カレンダー・今日の予定を、最初に登録した人で色分けし、「自分／パートナー／共有」の文字も出すようにした

## 2. なぜ必要か

- レシートの上の方には、店名のほかに会社名・支店名・キャッチコピーなどが並ぶことがあり、最初の1行が正しい店名とは限りません。候補から選べれば、手で打ち直す手間が減ります
- わが家で予定を共有すると、誰が入れた予定か分からなくなります。色と文字で、自分の予定とパートナーの予定を見分けられるようにしました

## 3. 店名候補の抽出条件（`ReceiptFieldExtractor.storeNames`）

- レシートの上の方（最初の10行）から、**上から下の順** に最大 **5件**
- 日付・合計の見出し・金額（¥）・商品の明細（「大根 198」「牛乳 1,980円」「2点」「@100」「×2」）の行より下は探さない
- 同じ候補は1つだけ（前後の飾り文字を除いたあとで比べる）
- 前後の飾り文字（`*` `=` `-` `【】` `「」` など）、`店名：` `店舗名：` `店舗` を除く。40文字まで
- 候補にしない行：電話番号・FAX・郵便番号・住所（丁目・番地・数字の番地、都道府県＋市区町村）・登録番号・インボイス・レシート番号・レジ番号・伝票・取引番号・日付・時刻・URL・あいさつ（いらっしゃいませ・ありがとう・ご来店など）・領収書・合計・小計・税・商品・明細・点数・半角の数字ばかりの行
- 「八百屋」「三越」「八百八町そば」など、**漢数字を含む店名は除外しない**（数字ばかりの判定は半角の 0〜9 だけを数える。Build 18 の修正と同じ）
- **最初の候補** を、はじめのタイトルにする。候補が無ければ、これまでどおり「レシート」

### 確認画面

- レシートから開いた「支出を追加」にだけ「店名候補」を出す（ふつうの支出の追加・編集には出さない）
- 最大5件を縦に並べる。タップでタイトル欄へ入れる。今のタイトルと同じ候補にチェックマーク
- 長い候補は1行で省略して表示（VoiceOver は全文を読む）。1行の高さは 44pt 以上
- 「候補を選ぶか、上のタイトル欄に入力できます。」。タイトル欄はこれまでどおり手入力・修正できる
- 候補が0件なら候補の欄は出さない（タイトル「レシート」を手入力できる）
- 保存するのは、最後にタイトル欄に入っている1つだけ

## 4. 予定の色の意味

| 予定 | 色 | 文字（色だけに頼らない） |
| --- | --- | --- |
| 自分だけの予定・自分が登録した共有の予定 | ミント | 自分 |
| パートナーが登録した共有の予定 | 淡い桃色 | パートナー |
| 登録した人が分からない共有の予定（古いデータなど） | 中立的なグレー | 共有 |

- **最初に登録した人** で決める（Firestore の共有項目にもとからある `createdBy`）。あとから編集した人（`updatedBy`）では変えない
- 自分だけの予定を「わが家で共有」にしたとき：その操作をした本人（`createdBy` がその人）
- 共有の予定を「自分だけ」にしたとき：自分の色（端末の自分だけの予定）
- 色はライト・ダークのどちらでも見分けられる明るさにした（クリーム・ミント・淡い桃色の今のデザインに合わせた）
- 既存の共有マークはそのまま（カレンダーの予定の行にも出す）

### 表示する場所

- **カレンダーの予定の行**：左に登録した人の色の点、補足の行に「自分／パートナー／共有」の小さな印（VoiceOver は「自分が登録した予定」「パートナーが登録した予定」「共有の予定。登録した人は分かりません」）
- **日付のマスの下の点**：予定は登録した人の色（自分・パートナー・不明の順に1つずつ）。そのあとに予定以外の種類のカテゴリー色。同じ色は1日に1つ、最大3つ。選んだ日の見た目・文字・タップ範囲は変えていない
- **今日**：予定の行の補足の前に「自分／パートナー／共有」、点をその人の色に（レイアウトは変えていない）
- 「すべて／自分／共有」の絞り込みはこれまでどおり（点も絞り込みに従う）

## 5. 保存する情報・保存しない情報

| | 保存する | 保存しない |
| --- | --- | --- |
| 店名候補 | 最後にタイトル欄に入っている1つ（支出のタイトル） | 候補の一覧・読み取った全文・写真（確認画面を閉じたら手放す） |
| 予定の色 | なし（新しく保存するものは無い） | `createdBy` の UID・メールアドレス。「自分／パートナー／不明」は起動中だけ持つ（`life-store.json` に書かない） |

- 登録した人は、共有項目を受け取ったとき（`FirestoreSharedItemsBackend`）に、`createdBy` とサインインしている本人の UID を **比べるだけ** で「自分／パートナー／不明」にします。UID は画面・ログ・端末の保存・`LifeItem` に渡しません
- メールアドレスは色分けに使いません
- Firestore のデータの形・Rules・Functions・索引は変えていません。色分けのために通信や書き込みを増やしていません

## 6. 外部へ送る情報

**ありません。** 店名候補・読み取った全文・写真は外部へ送りません（外部の検索・AI・文字認識・Analytics・Crashlytics は使わない）。色分けのための新しいサーバーのデータも作りません。共有の支出・共有の予定で送る項目は、これまでと同じです。

## 7. 既存の機能への影響

| 機能 | 影響 |
| --- | --- |
| Build 18 のレシートの読み取り・家計簿への保存 | 店名の候補が増えただけ（はじめのタイトルは最初の候補で、今までと同じ決まり）。店名にしない行（番号・伝票・取引・合計・小計・税・商品・時刻）を少し増やした |
| 個人／共有の家計簿の同期 | 変更なし |
| Build 17 の予定の保存先の変更・予定の編集・削除 | 変更なし（色は保存先の変更のあとも正しく出る） |
| ToDo の日付指定・共有の ToDo・買い物・通知・招待・保証書の撮影と文字の読み取り・Firestore のキャッシュの修復 | 変更なし |
| 共有項目を受け取る処理 | 受け取った一覧に「登録した人」を付けた（同じ一覧なら描き直さない決まりはそのまま） |

## 8. 変更したファイル

アプリ：

- `LifeOS/Core/Utilities/ReceiptFieldExtractor.swift`：店名候補（最大5件・上から順・重複なし）、候補にしない行の追加
- `LifeOS/Features/Money/MoneyViewModel.swift`：下書きに一時的な店名候補、候補の選択
- `LifeOS/Features/Money/MoneyView.swift`：確認画面の「店名候補」
- `LifeOS/Core/Sharing/HouseholdItems.swift`：`ItemRegistrant`（自分／パートナー／不明）、`SharedItemSnapshot.registrant`
- `LifeOS/Core/Sharing/FirestoreSharedItemsBackend.swift`：受け取ったときに `createdBy` から登録した人を決める（UID は比べるだけ）
- `LifeOS/Core/Store/LifeStore.swift`：登録した人を起動中だけ持つ（`registrant(of:)`）
- `LifeOS/DesignSystem/Colors/LifeCategoryColors.swift`：ミント・淡い桃色・グレー（ライト・ダーク）
- `LifeOS/Features/Calendar/CalendarViewModel.swift`：日付の点（`dayMarkers(on:)`）、予定の登録した人
- `LifeOS/Features/Calendar/CalendarView.swift`：予定の行の点・「自分／パートナー／共有」・共有マーク、日付の点
- `LifeOS/Features/Today/TodayViewModel.swift`・`TodayView.swift`：予定に「自分／パートナー／共有」とその色
- `LifeOS.xcodeproj/project.pbxproj`：Build 18 → 19（4か所）

テスト・文書：

- 追加：`LifeOSTests/Build19ReceiptStoreSelectionAndCalendarColorsTests.swift`（30件）
- 更新：`LifeOSTests/SharedTodoShoppingTests.swift`（偽物のサーバーも、本物と同じ `ItemRegistrant.from` で登録した人を付ける・作成者を消す操作を足した。既存のテストは変えていない）
- 更新：`LifeOSTests/Build18ReceiptToBudgetTests.swift` の `testBuildNumberIs18`（「ちょうど 18」→「4か所がそろっていて 18 以上」。ちょうど 19 は Build 19 のテストで確かめる。Version・暗号化・Build 16 の欠番の記録の確認はそのまま）
- `docs/BUILD_19_RECEIPT_STORE_SELECTION_AND_CALENDAR_COLORS.md`（この文書）、`README.md`（リンク）、`docs/BUILD_18_RECEIPT_TO_BUDGET.md`（Build 18 の実機の結果。別の commit）

## 9. テスト

### 追加したテスト（Swift、30件）

| 必須の項目 | テスト |
| --- | --- |
| 1 上から順に複数の候補 | `testReturnsCandidatesTopToBottom` |
| 2 最大5件 | `testAtMostFiveCandidates` |
| 3 重複を除く | `testRemovesDuplicates` |
| 4 `店名：` などを除く | `testRemovesLabelsAndDecorations` |
| 5 電話・住所・番号・日時・URL・あいさつを除く | `testExcludesContactNumbersDatesUrlsAndGreetings` |
| 6 合計・商品明細を除く | `testExcludesTotalsAndItemDetails` |
| 7 漢数字の店名を残す | `testKeepsKanjiNumeralNames` |
| 8 最初の有効な候補がはじめのタイトル | `testFirstValidCandidateIsInitialTitle` |
| 9 候補なしなら「レシート」 | `testNoCandidateFallsBackToReceipt` |
| 10 候補の選択でタイトルが変わる | `testSelectingCandidateChangesTitle` |
| 11・12 手入力できる・保存は最後のタイトルだけ | `testManualTitleAndOnlyFinalTitleIsSaved` |
| 13 候補の一覧・全文を保存しない | `testCandidatesAndFullTextAreNotPersisted` |
| 14 外部と通信しない | `testNoNetworkAccess` |
| 15 キャンセルで支出を作らない | `testCancelCreatesNothing` |
| 16 二重に保存しない | `testDoubleSaveCreatesOne` |
| 確認画面（縦に5件・チェック・省略と VoiceOver・説明・0件なら出さない） | `testEditorShowsCandidatesAccessibly` |
| 17 自分だけの予定は自分の色 | `testPersonalEventIsMine` |
| 18・19 自分の共有の予定・パートナーの共有の予定 | `testSharedEventsByMeAndPartner` |
| 20・33 登録した人が不明ならグレー・古い予定でも落ちない | `testUnknownCreatorIsGray` |
| 21 パートナーが編集しても色は変わらない | `testPartnerEditDoesNotChangeRegistrant` |
| 22 個人→共有は操作した本人の色 | `testPersonalToSharedIsOperatorsColor` |
| 23 共有→個人は自分の色 | `testSharedToPersonalIsMine` |
| 24・25 同じ日に2色・同じ色は1つ | `testTwoColorsWithoutDuplicates` |
| 26 日付の点は最大3つ | `testAtMostThreeMarkers` |
| 27 絞り込みのあとも正しい | `testMarkersFollowScopeFilter` |
| 28・32 今日とカレンダーで同じ意味・文字でも出す | `testTodayAndCalendarMatchAndUseText` |
| 31 VoiceOver | `testVoiceOverLabels` |
| 29 UID・メールを出さない・保存しない・ログに出さない | `testNoUIDOrEmailShownSavedOrLogged` |
| 30 Firestore の項目が増えていない | `testFirestoreFieldsUnchanged` |
| Build 19・Build 16 の欠番 | `testBuildNumberIs19` |

ソースを確かめるテストは、コメントの行を除いてから調べます（コメントの単語だけで誤検出しないため）。

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 91 | 実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules Emulator | 93 | 実行できなかった（Emulator が無い） | **未実行**（Rules は変更なし） |
| Functions Emulator | 46 | 実行できなかった | **未実行**（Functions は変更なし） |
| アカウント削除 | 26 | 実行できなかった | **未実行** |
| サーバーの合計 | 256 | — | 単体の91件だけ実行 |
| Swift（Xcode） | **601**（571＋30） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |

## 10. Release ビルド

**未確認**（この作業環境には Xcode がありません）。Mac で確かめてください。

## 11. 2台の iPhone での確認（A・B。2台とも Build 19、わが家の設定で予定・家計簿をオン）

1. A：店名が何行かあるレシートを読み取る → 「店名候補」が複数出る
2. A：正しい店名の候補をタップ → タイトルが変わり、チェックが付く
3. A：選んだ店名をタイトル欄で手直しできる
4. A：店名の無い写真（読み取れない写真）でも、タイトル「レシート」を手入力できる
5. A：保存 → 家計簿には選んだ（直した）店名だけが残る
6. A：自分の予定（自分だけ・共有）がミントで「自分」
7. A：B が登録した共有の予定が淡い桃色で「パートナー」（B から見ると A の予定が桃色）
8. 同じ日に A と B の予定がある日に、ミントと桃色の2つの点
9. 色と文字（自分／パートナー／共有）の両方で登録した人が分かる。VoiceOver でも分かる
10. B が A の予定のタイトル・日時を変えても、A の予定の色は変わらない
11. 予定を自分だけ↔わが家で共有に切り替えたあとも、色と文字が正しい
12. アプリが重くならない
13. Build 18 のレシートの読み取り・保証書の撮影と文字の読み取りが壊れていない

## 12. Firebase の再公開

**不要です。** Firestore のデータの形・Rules・Functions・索引・Hosting は変えていません（`createdBy` はもとから保存されている項目です）。

## 13. 今回作らないもの

- 商品明細の読み取り（**Build 20 の予定**）
- 3人以上のわが家の色分け（今回は2人利用だけ）
- ToDo・買い物の色分け（予定だけ）

## 14. 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アプリ：TestFlight で Build 18 を配る。保存の形は変えていないので、そのまま読める
