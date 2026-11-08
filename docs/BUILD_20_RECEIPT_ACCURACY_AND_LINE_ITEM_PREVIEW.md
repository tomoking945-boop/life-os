# Build 20：レシートの店名・合計金額の読み取り精度の改善と、商品明細（確認用）

2026-11-05。ブランチ `build20-receipt-accuracy-and-line-item-preview`（`origin/main` の `883f0d8` から）。作ったときは main に入れず、Mac での確認（2026-11-06）のあと、池上さんの指示で main へ fast-forward で取り込みました（下の11「Mac での確認結果」）。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `883f0d8`（予定どおり。Build 19 と、その Mac での確認結果の記録） |
| ブランチ | `build20-receipt-accuracy-and-line-item-preview` を `origin/main` から作成 |
| commit していない変更・stash | なし（混ぜていない） |
| Build 19 の実機での結果 | `docs/BUILD_19_RECEIPT_STORE_SELECTION_AND_CALENDAR_COLORS.md` に、機能とは別の commit（`421a37f`）で記録 |

**Build 16 は欠番** です（`docs/BUILD_17_EVENT_DESTINATION_SWITCH.md` に記録。そのまま残しています）。

## 1. 何を作ったか

1. **撮影の品質**：「カメラで撮る」は、使える iPhone では iOS の **書類スキャン**（VisionKit）を使い、レシートの輪郭を見つけて傾きを直し、切り抜く。使えないとき・失敗したときは、今までのカメラ（保証書と同じ部品）で撮る。「写真から選ぶ」でも、できればこの iPhone の中でレシートの範囲を見つけて直す
2. **写真の整え方**：写真の向き（EXIF）を直し、大きすぎる写真は文字が読める大きさ（長い辺 3000 ピクセル）まで縮小してから読む
3. **位置つきの読み取り結果**：文字・信頼度・レシートの中の位置（左上が原点、0〜1）を、読み取りのあいだだけ扱う。同じ高さの文字を1行にまとめる
4. **店名候補の順位付け**：位置（上の方）・文字の大きさ・信頼度・「店名：」の近さ・店名らしい言葉で順位を付ける（最大5件）
5. **合計金額の候補**：店名と同じように、合計金額も候補（最大5件）から選べる。例：`¥3,520（合計）`・`¥3,520（お支払額）`・`¥3,200（小計・選択非推奨）`
6. **商品明細（確認用）**：商品名・数量・単価・金額の候補を、確認画面の「商品明細（確認用）」に出す。直す・消すことができる。**保存・共有はしない**
7. **明細の合計との比較**：明細の金額の合計と、金額欄の合計を比べて「一致」「不一致」「比較不能」を出す（不一致でも保存できる）
8. **精度が低いときの案内**：読み取れた文字が少ない・信頼度が低いときは「読み取り精度が低い可能性があります。撮り直すか、内容を確認してください」と出す

## 2. なぜ精度改善が必要だったか

Build 19 の実機での確認で、「レシートの読み取り・店名候補の選択・予定の色分け・カメラでの撮影は動く。ただし、**店名と合計金額の読み取りの精度が低い**」と分かりました（池上さんの報告。試した枚数・正解率は未報告）。また「商品ごとの内容も確認したい」という要望がありました。

今までは、読み取った文字を「上から下の文字の行」としてだけ扱っていました。レシートでは、左の「合計」と右の「¥3,520」が離れていて別の行として読まれたり、傾いた写真で行の順番が崩れたりします。今回は、**写真をまっすぐにしてから読み、文字の位置で行をまとめる** ことで、見出しと金額・商品名と金額を正しく組み合わせやすくしました。それでも決められないときは、推測せずに候補から選んでもらいます。

## 3. 撮影・補正の仕組み

| 場面 | すること | 部品 |
| --- | --- | --- |
| カメラで撮る（書類スキャンを使える） | iOS の書類スキャンで撮る。輪郭の検出・傾きの補正・切り抜きは iOS がこの iPhone の中で行う。何枚撮っても **1枚目だけ** 使う | `ReceiptDocumentScannerView`（VisionKit） |
| カメラで撮る（書類スキャンを使えない） | 今までのカメラ（保証書と同じ部品・案内の文言だけレシート用） | `WarrantyCameraView` |
| 書類スキャンが失敗した | 閉じたあと、今までのカメラを開く。キャンセルのときは何もしない | `ReceiptScanOutcome.fallsBackToCamera` |
| 写真から選ぶ | 写真の中のレシートの範囲（四隅）を見つけ、見つかれば傾きを直して切り抜く。見つからない・小さすぎるときはそのまま | `ReceiptImagePreparer`（Vision の書類の範囲の検出・Core Image） |
| すべて | 向き（EXIF）を直す。長い辺が 3000 ピクセルを超えるときは縮小しながら読み込む（元の大きさで展開しないので、メモリを使い続けない） | `ReceiptImagePreparer` |

- 文字の読み取りは、今までどおり保証書と同じ端末内の部品（`WarrantyTextRecognizer`）
- 写真は **メモリの中だけ**。保存しない・送らない。書類スキャンで撮った写真も、画面が閉じたら読み取りへ渡してすぐに手放す
- 読み取りを二重に始めない（読み取り中・確認画面を開いている間は始めない）。キャンセルしたら、写真を整える段階・文字の読み取りの段階のどちらでも先へ進まない。あとから結果が届いても捨てる
- 精度が低いかもしれないとき：読み取れた文字が **15文字未満**、または **信頼度の平均が 0.5 未満** のとき、確認画面の「レシートから」に案内を出す

## 4. 店名候補の順位付け（`ReceiptFieldExtractor.storeNames`）

- 探す範囲：レシートの上の方（最初の10行）。日付・合計の見出し・金額・商品の明細の行から下は探さない（Build 19 と同じ）
- 候補にしないもの（Build 19 から）：電話番号・郵便番号・住所・登録番号・インボイス番号・レシート番号・レジ番号・担当・時刻・URL・あいさつ・合計・小計・税・商品の明細
- **Build 20 で足したもの**：お預り・お釣り・カード・会員・支払・現金の行も候補にしない
- 漢数字（八百屋・三越・一休堂など）は数字として数えない（Build 18 と同じ）
- 位置が分かるとき（実際の読み取り）は、次の点数の高い順（同じ点数なら上から）

| 手掛かり | 点数 |
| --- | --- |
| 上の方にあるほど高い | （1 − 行の中心の高さ）× 3 |
| 周りより文字が大きいほど高い | （文字の高さ ÷ 全体の文字の高さの中央値、最大2）× 2 |
| 信頼度 | 0〜1 |
| 「店名：」「店舗名：」の行、またはその見出しだけの行の次の行 | ＋2 |
| 店名らしい言葉（店・屋・堂・館・商店・薬局・スーパー・マート・ストア・ドラッグ・STORE・SHOP・MART・MARKET） | ＋1 |

- 位置が分からないとき（文字だけの読み取り結果）は、Build 19 と同じく上から下の順
- 最大 **5件**・同じ候補は1つだけ。いちばん上の候補をタイトルの初期値にする。候補が無ければ「レシート」
- 候補を選ぶ・タイトル欄に手入力する、は Build 19 と同じ。候補の一覧は保存・送信しない

## 5. 合計候補の順位付け（`ReceiptFieldExtractor.amountCandidates`）

**見出しの強さ**

| 強さ | 見出し | 扱い |
| --- | --- | --- |
| 強い | 総合計・合計金額・税込合計・お買上金額・お支払額・ご請求額・請求額・領収金額・TOTAL AMOUNT・GRAND TOTAL・AMOUNT DUE など | 自動で入れてよい |
| ふつう | 合計・お会計・TOTAL | 自動で入れてよい（強い見出しがあればそちらを優先） |
| 参考 | 小計・SUBTOTAL | **自動では入れない**。`¥3,200（小計・選択非推奨）` として、利用者が選べるだけ |

**候補にしない行**：お預り・お釣り・現金・消費税（内税・外税・税額・税率・対象・TAX）・値引き・割引・クーポン・点数・個数・ポイント・電話・番号・会員・カードの行。電話番号・郵便番号・カード番号・日付・時刻・登録番号は、金額として読まない。

**金額の見つけ方**：見出しと **同じ行の右側** の金額を優先。無ければ **直下の「金額だけの行」**。位置が分かるときは、左の「合計」と右に離れた「¥3,520」も同じ行にまとめて読む。

**順位**：見出しの強さ（強い100・ふつう50・小計0）＋ レシートの下の方ほど高い（位置×10）＋ 信頼度×3 ＋ 同じ行2／直下1。同じ「金額と見出し」は1つだけ。最大 **5件**。

**自動で金額欄に入れる決まり（Build 18 と同じ）**：いちばん強い見出しの候補が **1つの金額にそろうときだけ**。違う金額の強い候補が複数あるとき（例：総合計 ¥3,520 と お支払額 ¥3,600）は空欄にして、候補から選んでもらう。どれも安全でなければ空欄。

**確認画面**：「合計金額の候補」に最大5件。タップで金額欄へ入り、チェックが付く。金額欄はいつでも手入力でき、手で変えるとチェックは外れる。候補が無くても手入力できる。**保存するのは最後の金額欄の1つだけ**（候補の一覧は保存しない）。

## 6. 商品明細の抽出条件（`ReceiptFieldExtractor.lineItems`）

- 範囲：お店の情報・日時の行（いちばん下の日付・時刻の行）より下、小計・合計・支払い（お預り・お釣り・現金・クレジット・電子マネーなど）の行より上
- 1行の中で、左の商品名と右端の金額を組み合わせる（位置が分かるときは、左の商品名と右の金額を同じ行にまとめる）
- 数量・単価は、次の形のときだけ読む。読めなければ空（**推測で作らない**）

| 書き方 | 読み方 |
| --- | --- |
| `2点`・`2個`・`2コ` | 数量 2（`6枚切`・`3個入` は商品名の一部として扱う） |
| `2 x 198`・`2×198` | 数量 2・単価 198 |
| `198円×2`・`¥198×2` | 単価 198・数量 2 |
| `@198`・`単198`・`単価198` | 単価 198 |
| `2点 × ¥250` | 数量 2・単価 250 |

- 商品名の無い行（例：`2コ × 単198`）は、**直前の商品の空いている項目だけ** に入れる（読めた項目を上書きしない）
- 先頭の商品コード（4桁以上の数字）、末尾の税の印（※・*・軽など）は除く
- 商品にしない行：小計・合計・消費税・値引き・クーポン・お預り・お釣り・支払方法・ポイント・カード・会員・電話・住所・日付・時刻・レジ・担当・番号・あいさつ・空の行・記号だけの行
- 金額も単価も無い行は商品にしない。最大50件

**確認画面「商品明細（確認用）」**

- はじめは折りたたみ。開くと、商品名と金額。数量・単価は読めたときだけ（例：`牛乳　¥198`・`ティッシュ　2点 × ¥250　¥500`）
- 行をタップすると、商品名・数量・単価・金額を直せる。ごみ箱で一覧から外せる（どちらも保存しない）
- 「この商品明細は確認用で、今回は保存・共有されません」と出す。0件なら「商品明細を読み取れませんでした」
- VoiceOver：「商品名 ティッシュ、数量 2、単価 250円、金額 500円」のように読む。ボタン・入力欄は 44pt 以上

**明細の合計との比較**

| 結果 | 表示 |
| --- | --- |
| 一致 | 商品明細の合計と一致しています |
| 不一致 | 値引き・税・読み取り違いなどにより、商品明細の合計とレシート合計が一致しません |
| 金額の無い明細がある・合計金額が空 | 比較不能：金額が分からない明細があるか、合計金額が空のため、比べられません |
| 明細が0件 | 商品明細を読み取れませんでした |

不一致でも保存できます（外税・値引き・軽減税率などで、明細の合計とレシートの合計は一致しないことがあるため）。

## 7. 保存する情報／保存しない情報

| 情報 | 端末（`life-store.json`） | Firestore | UserDefaults・ほかのファイル | ログ・Analytics |
| --- | --- | --- | --- | --- |
| 支出（タイトル・金額・カテゴリー・日付・保存先） | 保存する（今までどおり） | 共有のときだけ、今までの **9項目** | なし | なし |
| 写真（撮った・選んだ・書類スキャン・整えたもの） | 保存しない | 送らない | 保存しない | 出さない |
| 読み取った全文・位置・信頼度 | 保存しない | 送らない | 保存しない | 出さない |
| 店名の候補・合計金額の候補 | 保存しない | 送らない | 保存しない | 出さない |
| 商品明細（直したものも） | 保存しない | 送らない | 保存しない | 出さない |

商品明細と候補は、確認画面の下書きの中だけにあり、**保存・キャンセル・画面を閉じる** のどれでも、下書きごとメモリから手放します。

## 8. 外部送信がないこと

- 写真・全文・候補・商品明細を、Firebase・外部の AI・外部の文字認識へ送りません。書類スキャン（VisionKit）・範囲の検出（Vision）・補正（Core Image）・文字認識はすべて端末の中の処理です
- 共有の支出として送るのは、今までの9項目（`schemaVersion`・`title`・`amount`・`category`・`date`・`createdBy`・`updatedBy`・`createdAt`・`updatedAt`）だけ
- UID・店名・金額・商品名・全文をログに出しません。Analytics・Crashlytics は足していません（Firebase の部品は Core・Auth・Firestore・AppCheck・Functions・Messaging のまま）

## 9. 既存機能への影響

| 機能 | 影響 |
| --- | --- |
| 保証書の撮影・文字の読み取り・画像の保存 | 変えていない。文字の読み取りの結果に「位置」を省略できる項目として足しただけ（保証書の候補づくりは使わない） |
| Build 19 の店名候補の選択 | そのまま。文字だけの行では、今までどおり上から下の順 |
| Build 19 の予定の色分け | 変えていない |
| Build 18 の支出の作成・二重保存の防止 | 変えていない |
| 家計簿の自分だけ／共有の同期・予定・ToDo の日付・通知・招待・Firestore のキャッシュ修復 | 変えていない |
| Firestore Rules・Functions・索引・Hosting | 変えていない |

Build 18 のテスト1件（21「写真・読み取った全文を保存しない」）は、下書きの中に「食パン」が無いことも確かめていました。Build 20 では確認用の商品明細を下書きの中に（確認画面のあいだだけ）持つ仕様になったため、**下書きの確認から「食パン」だけを外しました**（端末のファイルに書かないことの確認は、そのまま残しています）。理由はテストのコメントにも書きました。Build 19 の Build 番号のテストは、ほかの Build と同じく「4か所がそろっていて 19 以上」にしました。

## 10. 変更ファイル

**アプリ**

- `LifeOS/Core/Utilities/ReceiptFieldExtractor.swift`：位置つきの行からの抽出、店名の順位付け、合計金額の候補（小計は参考）、商品明細
- `LifeOS/Core/Utilities/ReceiptLayout.swift`（新規）：行のまとめ方、`ReceiptAmountCandidate`、`ReceiptLineItem`、`ReceiptLineItemComparison`
- `LifeOS/Core/Utilities/ReceiptImagePreparer.swift`（新規）：向きの補正・縮小・範囲の検出と補正
- `LifeOS/Core/Utilities/ReceiptTextRecognizer.swift`：位置・信頼度つきの読み取り（`ReceiptRecognizedLine`）、キャンセル、`ReceiptReadQuality`
- `LifeOS/Core/Utilities/WarrantyFieldExtractor.swift`：`RecognizedTextBox`（位置）、`WarrantyRecognizedLine.box`（省略できる）
- `LifeOS/Core/Utilities/WarrantyTextRecognizer.swift`：位置も返す
- `LifeOS/Features/Money/ReceiptDocumentScannerView.swift`（新規）：書類スキャン、今までのカメラへの切り替え
- `LifeOS/Features/Money/MoneyViewModel.swift`：合計金額の候補・商品明細（確認用）・比較、範囲を直すかを読み取りへ渡す
- `LifeOS/Features/Money/MoneyView.swift`：書類スキャン、「合計金額の候補」「商品明細（確認用）」
- `LifeOS.xcodeproj/project.pbxproj`：Build 番号 19 → 20（4か所）

**テスト**

- `LifeOSTests/Build20ReceiptAccuracyAndLineItemPreviewTests.swift`（新規、40件）
- `LifeOSTests/Build18ReceiptToBudgetTests.swift`：上の9の理由で、下書きの確認から「食パン」を外した
- `LifeOSTests/Build19ReceiptStoreSelectionAndCalendarColorsTests.swift`：Build 番号の確認を「19 以上」に

**文書**

- `docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md`（この文書）、`README.md`（リンク）
- `docs/BUILD_19_RECEIPT_STORE_SELECTION_AND_CALENDAR_COLORS.md`：Build 19 の実機での結果（別の commit `421a37f`）

## 11. テスト件数と結果

### 追加したテスト（Swift、40件。指示の1〜42をすべて含む）

| 指示の番号 | テスト |
| --- | --- |
| 1 上部の店名を優先 | `testTopAndLargeStoreNameIsPreferred` |
| 2 商品名を店名にしない | `testItemNamesAreNotStoreNames` |
| 3 住所・電話・番号を除外 | `testExcludesAddressPhoneNumbersAndPaymentWords` |
| 4 漢数字の店名を残す | `testKeepsKanjiNumeralStoreNames` |
| 5 複数候補の順位 | `testRankingOfMultipleCandidates` |
| 6 同じ候補を重ねない | `testNoDuplicateCandidates` |
| 7 候補の選択と手入力 | `testStoreCandidateSelectionAndManualEntry` |
| 8・18・29 候補・明細を保存しない | `testCandidatesAndLineItemsAreNotPersisted` |
| 9 同じ行の合計 | `testReadsTotalOnSameRow` |
| 10 右に離れた合計 | `testReadsTotalFarToTheRight` |
| 11 直下の合計 | `testReadsTotalDirectlyBelow` |
| 12 下部の合計を優先 | `testBottomTotalIsRankedFirst` |
| 13 お預り・お釣り・税を除外 | `testDepositChangeAndTaxAreExcluded` |
| 14 小計を自動確定しない | `testSubtotalIsNeverAutoSelected` |
| 15 異なる強い候補なら空欄 | `testDifferentStrongCandidatesLeaveAmountEmpty` |
| 16 候補選択で金額へ反映 | `testSelectingAmountCandidateFillsAmount` |
| 17 手入力 | `testAmountCanBeEnteredManually` |
| 19 商品名と右の金額 | `testCombinesNameAndRightAmount` |
| 20 複数の商品を行ごとに | `testSplitsMultipleItemsByRow` |
| 21 数量 | `testReadsQuantity` |
| 22 単価 | `testReadsUnitPrice` |
| 23 小計・合計・税・支払いを除外 | `testExcludesTotalsTaxPaymentAndInfoRows` |
| 24 明細の修正 | `testEditingLineItem` |
| 25 明細の削除 | `testDeletingLineItem` |
| 26 明細の合計の一致 | `testMatchingTotals` |
| 27 不一致の警告 | `testMismatchWarningAndInsufficientData` |
| 28 不一致でも保存できる | `testCanSaveEvenWhenTotalsMismatch` |
| 30 Firestore へ送らない | `testFirestoreReceivesOnlyNineFields` |
| 31 キャンセル・保存のあとに手放す | `testCandidatesAreReleasedAfterCancelOrSave` |
| 32 二重の読み取り・二重の保存なし | `testNoDoubleReadingOrDoubleSave` |
| 33 向きの違う写真 | `testOrientationIsCorrected` |
| 34 大きな写真の縮小 | `testLargeImageIsDownscaledSafely` |
| 35 読み取りのキャンセル | `testCancellationStopsReading` |
| 36 信頼度が低いときの案内 | `testLowQualityGuidance` |
| 37 VisionKit を使えないときの切り替え | `testDocumentScannerFallback` |
| 38 保証書の文字の読み取り | `testWarrantyOCRStillWorks` |
| 39 Build 19 の店名候補と色分け | `testBuild19StoreCandidatesAndColorsStillWork` |
| 40 外部通信・ログ・Firebase の追加なし | `testNoNetworkLoggingOrFirebaseAdditions` |
| 41 VoiceOver と 44pt | `testVoiceOverAndTapTargets` |
| 42 Build 番号4か所が20・Build 16 の欠番 | `testBuildNumberIs20` |

ソースを確かめるテストは、コメントの行を除いてから調べます（コメントの単語だけで誤検出しないため）。既存のテストは削除・スキップしていません。

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 91 | 実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules Emulator | 93 | 実行できなかった（Emulator が無い） | **未実行**（Rules は変更なし） |
| Functions Emulator | 46 | 実行できなかった | **未実行**（Functions は変更なし） |
| アカウント削除 | 26 | 実行できなかった | **未実行** |
| サーバーの合計 | 256 | — | 単体の91件だけ実行 |
| Swift（Xcode） | **641**（601＋40） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし。店名・合計・明細の抽出の決まりは、別に書いた確認用の写しで、テストの入力と期待値を突き合わせた） |

Mac での確認結果：下の「Mac での確認結果（2026-11-06）」。

### Xcode のテストのコンパイルエラーの修正（2026-11-05、池上さんの報告。`73ec0e7`）

Mac で Xcode のテストを始めたところ、テストのファイル（`LifeOSTests/Build20ReceiptAccuracyAndLineItemPreviewTests.swift`）でコンパイルエラー1件と警告1件が出ました。アプリ本体・レシートの抽出の処理は変えず、テストの書き方だけを直しました。確かめる内容は弱めていません（削除・スキップもしていません）。

| 場所 | 出たもの | 原因 | 直し方 |
| --- | --- | --- | --- |
| `testCandidatesAreReleasedAfterCancelOrSave` | エラー：`'async' call in an autoclosure that does not support concurrency` | `XCTAssertTrue(saved.viewModel.save(try await readDraft(saved)))` のように、`XCTAssertTrue` の中（autoclosure）で `await` を使っていた。autoclosure の中では `await` を使えない | 先に `let savedDraft = try await readDraft(saved)`・`let didSave = saved.viewModel.save(savedDraft)` を行い、そのあと `XCTAssertTrue(didSave)` で確かめる |
| `testWarrantyOCRStillWorks` | 警告：`Main actor-isolated static property 'warrantyGuide' can not be referenced from a nonisolated autoclosure` | `WarrantyCameraView.warrantyGuide` は SwiftUI の View の値なので MainActor 扱い。MainActor ではないテストの `XCTAssertEqual` の中から直接読んでいた | テストを `@MainActor` にし、値を `let warrantyGuide = WarrantyCameraView.warrantyGuide` でローカル変数に取り出してから `XCTAssertEqual` で比べる。ほかの確認はすべて残す |

変えていないもの：アプリ本体の仕様、レシートの抽出の処理、Firebase Messaging の既存の deprecated の警告、Xcode の Recommended Settings、Signing Team、Firebase（Rules・Functions・索引・Hosting）、Build 番号 20、Version 1.0。

修正後の結果（この作業環境）：

| テスト | 結果 |
| --- | --- |
| サーバーの単体テスト | **91件成功・失敗0・スキップ0**（再実行） |
| 全 Swift ファイルの簡易の字句チェック | 問題なし |
| Xcode のテスト・Release ビルド | **未実行**（この作業環境に Xcode が無い。Mac での再確認が必要） |

### Mac での確認結果（2026-11-06、池上さんの報告。`6ca8ad8`）

**最初の Xcode の実行（`73ec0e7`）**

- 新しいテストのファイルで **コンパイルエラー1件**（`testCandidatesAreReleasedAfterCancelOrSave`：autoclosure の中の `await`）と **MainActor の警告1件**（`testWarrantyOCRStillWorks`：`WarrantyCameraView.warrantyGuide`）が出て、テストを始められなかった
- `6ca8ad8` で **テストの書き方だけ** を直した（上の表。アプリ本体・抽出の処理・確かめる内容は変えていない）

**修正後（`6ca8ad8`）**

| 確認 | 結果 |
| --- | --- |
| ターミナルの全テスト（単体91・Rules 93・Functions 46・アカウント削除26） | **256件成功・失敗0・スキップ0** |
| Xcode のテスト | **Test Succeeded・失敗0**（実行件数・スキップ数：未報告。予定は641件） |
| Release ビルド | **成功** |
| 実機でのレシートの確認（下の13の14項目） | **未実施**（2026-11-06 時点。2026-11-08 の結果は下の13の「実機での確認結果」） |

- この確認のあと、池上さんの指示で main へ取り込んだ（fast-forward。rebase・force push はしていない）
- Firebase へのデプロイ・TestFlight へのアップロード・Console の変更：していない
- Xcode で手動で設定した Signing Team などは commit に含めていない

## 12. Release ビルド

この作業環境では未確認（Xcode が無い）。**Mac で成功**（2026-11-06、池上さんの報告。`6ca8ad8`。上の11「Mac での確認結果」）。

## 13. 実機での確認手順（Build 20。家計簿をわが家で共有している iPhone で）

5種類のレシートで、それぞれ次の14項目を確かめます。

| レシート | 見どころ |
| --- | --- |
| A：スーパー | 商品が多い・外税／内税・「小計」「合計」「お預り」「お釣り」がそろう |
| B：コンビニ | 縦に細長い・「合計」と金額が左右に離れている・電子マネーやバーコード決済 |
| C：ドラッグストア | ポイント・会員番号・クーポンや値引きの行が多い |
| D：飲食店 | 「お会計」「ご請求額」・人数や席番号・品名が短い |
| E：形式の異なるレシート（手書きの領収書・海外の英語のレシート・感熱紙が薄いものなど） | 「TOTAL」「AMOUNT DUE」・読み取り精度が低いときの案内 |

1. **自動切り抜き・傾き補正**：「カメラで撮る」で書類スキャンが開き、レシートの輪郭が自動で囲まれ、まっすぐな形で取り込まれる（斜めに置いても）。「写真から選ぶ」でも読み取れる
2. **店名候補**：いちばん上の候補が正しい店名か。住所・電話・レジ番号・担当が候補に入らない
3. **合計金額候補**：`¥3,520（合計）` のような候補が出る。お預り・お釣り・税・ポイントが入らない。小計は「小計・選択非推奨」
4. **正しい候補の選択**：候補をタップで金額欄が変わり、チェックが付く。金額欄を手で直せる
5. **商品明細の表示**：「商品明細（確認用）」を開くと、商品名と金額が並ぶ
6. **数量・単価**：「2点」「×」「@」のあるレシートで、数量・単価が出る（読めないものは出ない）
7. **誤った明細の修正・削除**：行をタップして直せる。ごみ箱で消せる
8. **明細合計との比較**：一致・不一致・比較不能の表示が出る。不一致でも保存できる
9. **支出保存**：保存すると家計簿に1件だけ入る（タイトル・金額・カテゴリー・日付）
10. **商品明細が保存されない**：保存した支出を開いても、商品明細は出てこない。アプリを終了して開き直しても残っていない
11. **共有支出に商品明細が送られない**：わが家で共有して保存 → もう1台の iPhone では、支出（タイトル・金額など）だけが見え、商品明細は見えない
12. **キャンセルで何も残らない**：読み取り中のキャンセル・確認画面のキャンセルのどちらでも、支出が増えない
13. **アプリが重くならない**：大きな写真・続けて何枚か読み取っても、固まらない・落ちない
14. **保証書OCRが壊れていない**：書類の画面の保証書で、撮影・文字の読み取り・写真の保存が今までどおり

結果：**未実施**（2026-11-06 時点、池上さんの報告）。14項目それぞれの結果・試したレシートの枚数は未報告（推測しない）。

### 実機での確認結果（2026-11-08、池上さんの報告）

| レシート | 結果 |
| --- | --- |
| A：スーパー | **成功** |
| B：コンビニ | **成功** |
| C：ドラッグストア | **成功** |
| D：飲食店 | **成功** |
| E：形式の異なるレシート（読み取りにくいレシート） | **未報告** |

- 試したレシートの枚数・14項目それぞれの結果・正解率は **未報告**（推測で補わない）
- この結果を受けて、Build 21 で「確認した商品明細を支出と一緒に保存し、あとから見返す」機能を作る（`docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md`）

## 14. Firebase の再公開

**不要です。** Firestore のデータの形・Rules・Functions・索引・Hosting は変えていません。共有の支出は今までの9項目のままです。

## 15. 商品明細の永続保存は Build 21 以降

今回の商品明細は **確認用** で、保存・共有はしません。商品明細を家計簿に保存する・共有するのは **Build 21 以降** に、保存の形・Firestore のルール・プライバシーをあらためて決めてから作ります。

## 16. Build 16 は欠番

Build 16 は欠番です（`docs/BUILD_17_EVENT_DESTINATION_SWITCH.md`）。Build 17・18・19 に続き、今回は Build 20 です。Version は 1.0、`ITSAppUsesNonExemptEncryption = NO` のままです。

## 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アプリ：TestFlight で Build 19 を配る。保存の形は変えていないので、そのまま読める
