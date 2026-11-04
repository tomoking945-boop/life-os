# Build 18：レシートを読み取って家計簿に入れる

2026-11-02。ブランチ `build18-receipt-to-budget`（`origin/main` の `b44fcbd` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `b44fcbd`（予定どおり。Build 17 を取り込んだもの） |
| ブランチ | `build18-receipt-to-budget` を `origin/main` から作成 |
| commit していない変更・stash | なし（混ぜていない） |

**Build 16 は欠番** です（Build 17 の文書 `docs/BUILD_17_EVENT_DESTINATION_SWITCH.md` に記録。そのまま残しています）。

## 1. 何を作ったか

お金の画面の「支出を追加」の下に **「レシートを読み取る」**（`doc.text.viewfinder`）を足しました。

1. 「レシートを読み取る」→「カメラで撮る」「写真から選ぶ」「キャンセル」
2. この iPhone の中で、Apple Vision（`VNRecognizeTextRequest`）でレシートの文字を読み取る
3. 読み取った文字から、**店名・合計金額・購入日・カテゴリー** の候補を作る
4. 候補を入れた「支出を追加」の画面（既存の画面）を開く。タイトル・金額・カテゴリー・日付・保存先を直せる
5. **「保存」を押したときだけ** 家計簿に入る（それまでは支出を作らない）

外部の AI・外部の文字認識サービスは使いません。レシートは1枚だけです。レシートの写真を残す機能は作っていません。

## 2. なぜ必要か

家計簿は、金額や日付を1件ずつ手で入れるのが手間で、続かない原因になります。レシートを撮るだけで候補が入れば入力が速くなります。一方で、読み間違えた金額が勝手に保存されると家計簿が信用できなくなるため、**必ず利用者が確認してから保存** し、合計が分からないときは **金額を空** にします。

## 3. 画面の流れ

```
お金 →「レシートを読み取る」
  ├ カメラで撮る（保証書と同じカメラ。案内は「レシート1枚を、合計と日付が入るように枠いっぱいに」）
  ├ 写真から選ぶ（1枚。写真全体へのアクセス許可は不要）
  └ キャンセル
→「このiPhoneの中でレシートを読み取っています…」（キャンセルできる。二重に始めない）
→「レシートから追加」（既存の支出の追加画面）
    タイトル（店名）・金額（合計）・カテゴリー・日付・保存先（初期値は必ず「自分だけ」）
    読み取れなかった項目の一言、「保存するまで家計簿には入りません。写真と読み取った文字は保存しません。」
→「保存」で1件だけ家計簿へ（合計・カテゴリーの合計・支出一覧にすぐ出る）／「キャンセル」で何も残らない
```

- 保証書のカメラの部品（`WarrantyCameraView`）に、撮影の案内を変えられる引数を足しました。保証書の画面は今までの案内・動きのままです
- 保証書の文字認識（`WarrantyTextRecognizer`）をそのまま使います。読み取りの「キャンセル」で、まだ始まっていない読み取りを始めないようにしました（保証書の動きは同じ）

## 4. 抽出ルール（`ReceiptFieldExtractor`。すべて端末内の計算）

### 合計金額

- 「総合計」「合計金額」「税込合計」「お買上金額」「お支払額」「お支払金額」「ご請求額」「請求額」「領収金額」「TOTAL AMOUNT」などの **強い見出し** を優先し、次に「合計」「お会計」「TOTAL」
- 見出しと同じ行の金額。無ければ、次の行が金額だけのときその金額（「合計」の下に「¥1,080」）
- 合計にしない行：小計・SUBTOTAL・消費税・内税・外税・税額・対象・TAX・お預り・お釣り・現金・CASH・CHANGE・値引・割引・クーポン・点数・個数・ポイント・電話・TEL・番号・会員・カード
- 金額として読まない数字：日付・時刻・電話番号・郵便番号・カード番号（伏せ字を含む）・登録番号（T＋13桁）・10桁以上の数字・「点」「個」「%」が続く数字
- 読める形：`1,234`・`1,234円`・`¥1,234`・`￥1,234`・全角の数字・円記号がバックスラッシュで読まれたもの・末尾の「-」（`¥1,080-`）
- 同じ強さの見出しで **違う金額が複数** あるときは決めない
- 合計を決められないときは **金額を空** にして確認画面を開き、理由を出す（いちばん大きな数字などで推測しない。推測した金額を保存しない）
- 金額は今までどおり 1〜999,999,999 円の整数だけ

### 購入日

- 上から最初の、存在する日付（`2026年11月2日`・`2026/11/02`・`2026-11-02`・`令和8年11月2日`・`R8.11.2`・全角）。有効期限などの行は見ない
- `2026/2/30`・`令和8年2月29日` のような存在しない日付は使わず、**別の日に直さない**
- 読み取れなければ今日を初期値にし、その一言を出す

### 店名

- 上の方（最初の8行、日付・合計・金額の行より上）から
- 店名にしない行：電話番号・FAX・住所（丁目・番地・数字の番地、都道府県＋市区町村）・登録番号・インボイス・あいさつ（いらっしゃいませ・ありがとう・ご来店など）・領収書・レシート・URL・レジ・担当・番号ばかりの行
- 決められなければ「レシート」（利用者が直せる）

### カテゴリー

- 確かな手掛かりが **1種類だけ** あるときだけ候補にする（2種類以上・無しなら「その他」）
- 外食：レストラン・食堂・居酒屋・カフェ・ラーメン・寿司・焼肉・定食・イートイン、よく知られた飲食チェーン
- 交通：乗車・運賃・乗車券・定期券・タクシー・ガソリン・給油・軽油・ハイオク・ENEOS・出光など
- 日用品：ドラッグ・薬局・ホームセンター・カインズ・コーナン・DCM・ダイソーなど
- 食費：スーパー・マーケット・生鮮・青果・精肉・鮮魚・イオン・西友・マルエツなど
- カテゴリーは確認画面で必ず変えられる

## 5. 保存する情報・保存しない情報

| | 保存する | 保存しない |
| --- | --- | --- |
| 自分だけで保存 | 支出（タイトル・金額・カテゴリー・日付）を、これまでどおり端末の `life-store.json` に | レシートの写真、読み取った全文、候補を作る途中の文字 |
| わが家で共有 | 既存の共有の支出の **9項目だけ**（schemaVersion・title・amount・category・date・createdBy・updatedBy・createdAt・updatedAt） | レシートの写真、読み取った全文（共有の支出にも足さない） |

- 写真のデータは、読み取りの処理の中だけで持ち、読み取りが終わった・キャンセルしたら手放します（カメラで撮った写真も、カメラの画面が閉じたら読み取りへ渡して手放す）
- 読み取った全文は、候補（4項目）を作ったら捨てます。確認画面の下書きにも全文は入りません
- ログ（店名・金額・読み取った全文・トークン・UID）は出しません

## 6. 外部へ送る情報

**ありません。** 写真も読み取った文字も、Firebase・外部の AI・外部の文字認識・Analytics・Crashlytics へ送りません。文字認識は Apple Vision の端末内の処理です。共有を選んで保存したときに送るのは、これまでの共有の支出と同じ9項目だけです。

## 7. 個人／共有の扱い

- 保存先の初期値は必ず「自分だけ」。読み取った内容から共有を選ぶことはありません
- 「わが家で共有」は、既存の家計簿の共有の条件（サインイン・わが家に参加・わが家の設定で家計簿がオン）を満たすときだけ選べます。満たさないときは選べず、理由を出します
- 保存したあとの支出の編集・削除・保存先の変更は、これまでの家計簿と同じです

## 8. 失敗したときの動き

| 状況 | 動き |
| --- | --- |
| カメラが無い・許可されていない | 保証書と同じく理由と「設定を開く」を出す。アプリは止まらない。「写真から選ぶ」も使える |
| 写真を読み込めない | 「写真を読み込めませんでした。手入力できます。」で追加画面を開く |
| 25MB を超える | 「25MBを超える写真は読み取れません。手入力できます。」 |
| HEIC・JPEG・PNG 以外 | 「読み取れるのは HEIC・JPEG・PNG の写真です。手入力できます。」 |
| 写真として読めない・文字が読めない | 「読み取れませんでした。手入力できます。」 |
| 合計が分からない | 金額を空にして理由を出す（金額を入れるまで保存できない） |
| 日付が読めない・存在しない日付 | 今日にして一言を出す |
| 店名が分からない | 「レシート」にして一言を出す |
| 読み取り中の「キャンセル」 | 何も保存しない。あとから結果が届いても捨てる |
| 「保存」を続けて押した | 1件だけ作る（同じ下書きの2回目は保存しない） |

## 9. 変更したファイル

アプリ：

- 追加：`LifeOS/Core/Utilities/ReceiptFieldExtractor.swift`（候補を作る。`ReceiptExtractionProposal`・`ReceiptAmountIssue`）
- 追加：`LifeOS/Core/Utilities/ReceiptTextRecognizer.swift`（読み取る前の確かめ・保証書と同じ文字認識を使う。`ReceiptImageError`・`ReceiptTextRecognizing`）
- `LifeOS/Core/Utilities/WarrantyTextRecognizer.swift`：取り消しを読み取りの処理へ伝える（保証書の動きは同じ）
- `LifeOS/Features/Documents/Warranty/WarrantyCameraView.swift`：撮影の案内を変えられるように（既定は今までの文言）
- `LifeOS/Features/Money/MoneyViewModel.swift`：読み取りの流れ、レシートからの下書き、同じ新しい支出の2回目の保存をしない
- `LifeOS/Features/Money/MoneyView.swift`：「レシートを読み取る」、撮る・選ぶ、読み取り中の表示とキャンセル、確認画面の一言
- `LifeOS.xcodeproj/project.pbxproj`：Build 17 → 18（4か所）

テスト・文書：

- 追加：`LifeOSTests/Build18ReceiptToBudgetTests.swift`（30件）
- 置き換え：`LifeOSTests/Build14SharedCalendarAndDeleteFixTests.swift` の `testNoReceiptToExpenseFeature` → `testReceiptToExpenseUsesOnlyOnDeviceRecognition`（下の10）
- 更新：`LifeOSTests/Build17EventDestinationSwitchTests.swift` の `testBuildNumberIs17InAllFourSettings`（下の10）
- `docs/BUILD_18_RECEIPT_TO_BUDGET.md`（この文書）、`README.md`（リンク）

Firestore のデータの形・Rules・Functions・索引・Hosting・招待・Firestore の端末のキャッシュの修復は変えていません。カメラの使用目的の説明（Info.plist）も変えていません。

## 10. テスト

### 追加したテスト（Swift、30件）

| 必須の項目 | テスト |
| --- | --- |
| 1 合計の見出しの近くの金額 | `testPicksAmountNearTotalLabel` |
| 2 小計より合計 | `testTotalWinsOverSubtotal` |
| 3 お預り・お釣り・消費税を合計にしない | `testDepositChangeAndTaxAreNotTotal` |
| 4 電話番号・郵便番号・カード番号を金額にしない | `testPhonePostalCardAndTimeAreNotAmounts` |
| 5 カンマ・円・￥・¥・全角 | `testReadsCommaYenSignsAndFullWidthDigits` |
| 6 TOTAL | `testReadsEnglishTotal` |
| 7 複数の合計の候補 | `testMultipleTotalCandidatesAreHandledSafely` |
| 8 判断できなければ空 | `testUnknownTotalLeavesAmountEmpty` |
| 9 西暦・和暦 | `testReadsWesternAndJapaneseDates` |
| 10 存在しない日付を使わない | `testNonexistentDateIsNotAdopted` |
| 11 店名の候補 | `testStoreNameCandidate` |
| 12 無ければ「レシート」 | `testFallbackTitleIsReceipt` |
| 13 カテゴリーの候補 | `testCategoryCandidates` |
| 14 判断できなければ「その他」 | `testUndeterminedCategoryIsOther` |
| 15 保存先は自分だけ | `testReceiptDraftDefaultsToPersonalAndDoesNotSaveUntilConfirmed` |
| 16 選んだときだけ共有 | `testSharesOnlyWhenUserChooses` |
| 17 キャンセルで保存しない | `testCancelDoesNotSave` |
| 18 保存で1件だけ | `testSaveCreatesExactlyOneExpense` |
| 19 二重タップでも1件 | `testDoubleTapDoesNotCreateTwo` |
| 20 失敗しても手入力できる | `testRecognitionFailureStillAllowsManualEntry` |
| 21 写真・全文を保存しない | `testImageAndFullTextAreNotPersisted` |
| 22 Firestore へ写真・全文を送らない | `testFirestoreReceivesNoImageOrFullText` |
| 23 ログに出さない | `testNoLoggingInReceiptFlow` |
| 24 保証書の読み取りは今までどおり | `testWarrantyRecognitionStillWorks` |
| 25 支出の編集・削除・保存先の変更 | `testExistingExpenseEditDeleteAndDestinationChangeStillWork` |
| 26 保存・キャンセルのあとメモリに持たない | `testImageAndResultsAreReleasedAfterSaveOrCancel` |
| 27 VoiceOver・44pt | `testAccessibilityAndTapTargets` |
| 28 カメラ拒否・カメラ無し・写真の読み込み失敗 | `testCameraDeniedMissingAndPhotoLoadFailureDoNotCrash` |
| 大きさ・形式の確かめ | `testValidatesSizeAndFormat` |
| Build 18・Build 16 の欠番の記録 | `testBuildNumberIs18` |

### 置き換えた・直した既存のテスト（削除・スキップしていない）

- Build 14 の `testNoReceiptToExpenseFeature` は「家計簿用のレシートの読み取りが無い」ことを確かめていました。Build 18 でレシートの読み取りを作ったため、**削除せず**、新しい仕様を確かめる `testReceiptToExpenseUsesOnlyOnDeviceRecognition` に置き換えました。確かめる内容：お金の画面は Vision を直接使わない／文字認識は保証書と同じ端末内の部品だけ（別の文字認識を作らない）／お金の画面・レシートの部品は Firebase・通信・ログを使わない
- Build 17 の `testBuildNumberIs17InAllFourSettings` は「ちょうど 17」を確かめていたため、「4か所がそろっていて 17 以上」に変えました（ちょうど 18 であることは Build 18 のテストで確かめます。Version・暗号化の設定の確認はそのまま）

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 91 | 実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules Emulator | 93 | 実行できなかった（Emulator が無い） | **未実行**（Rules は変更なし） |
| Functions Emulator | 46 | 実行できなかった | **未実行**（Functions は変更なし） |
| アカウント削除 | 26 | 実行できなかった | **未実行** |
| サーバーの合計 | 256 | — | 単体の91件だけ実行 |
| Swift（Xcode） | **570**（540＋30） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

### Mac での確認結果（2026-11-04、池上さんの報告。`0067b2d`）

| 確認 | 結果 |
| --- | --- |
| テスト | **確認できた**（池上さんの報告） |
| ターミナルのテスト・Xcode のテストの件数・失敗数・スキップ数 | 未報告 |
| Release ビルド | 未報告 |
| 実機（TestFlight）での確認（下の11の13項目） | 未報告 |

- 池上さんの指示で、この報告のあと main へ取り込んだ（fast-forward）
- Firebase への公開・TestFlight へのアップロード：していない

### Xcode で失敗した2件のテストの修正（2026-11-04、池上さんの報告。修正はこのブランチ）

池上さんの報告で、Build 18 の Xcode のテストが **2件失敗** しました（上の「テスト：確認できた」の記録のあと）。

| テスト | 原因 | 直し方 |
| --- | --- | --- |
| `Build14SharedCalendarAndDeleteFixTests.testReceiptToExpenseUsesOnlyOnDeviceRecognition` | `ReceiptTextRecognizer.swift` の説明のコメントに `VNRecognizeTextRequest` という型の名前が入っていて、テストが「レシート側が文字認識を別に作っている」と判断した（実装は正しく、`WarrantyTextRecognizer.recognizeLines` だけを使っている） | コメントを「端末内の Apple Vision で読み取る」に変えた。テストはそのまま（削除・スキップ・弱めていない）。実装も変えていない |
| `Build18ReceiptToBudgetTests.testStoreNameCandidate` | 「店名：まちの八百屋」が「レシート」になった。`ReceiptFieldExtractor.isStoreName` の「数字ばかりの行は店名にしない」の判定が `Character.isNumber` を使っていて、漢数字の「八」「百」も数字として数えた（6文字中2文字＝30%超で除外） | 数えるのを **半角の 0〜9 だけ** にした（全角の数字は normalize で半角になってから数える）。「八百屋」「三越」などの漢数字の店名を除外しない。電話番号・郵便番号・登録番号・レシート番号などの除外はそのまま |

追加したテスト（1件）：`Build18ReceiptToBudgetTests.testKanjiNumeralStoreNamesAndNumberLines`

- 「店名：まちの八百屋」→「まちの八百屋」
- 「三越 日本橋店」「八百八町そば」を店名として扱える
- 半角の数字ばかりの番号の行は、引き続き店名にしない
- 全角の電話番号も、半角にしてから店名から除く（「ＴＥＬ」付き・無しの両方）
- 郵便番号・登録番号・レシート番号の行も除く

変更したファイル：`LifeOS/Core/Utilities/ReceiptTextRecognizer.swift`（コメントだけ）、`LifeOS/Core/Utilities/ReceiptFieldExtractor.swift`（数字の数え方）、`LifeOSTests/Build18ReceiptToBudgetTests.swift`（1件追加）、この文書。Build 18・Version 1.0 のまま。Firebase・Rules・Functions・索引・Hosting は変更なし。

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 91 | 再実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules・Functions・アカウント削除 | 93・46・26 | 実行できなかった | **未実行**（変更なし） |
| Swift（Xcode） | **571**（570＋1） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

- 注意：Build 18 は、この2件の失敗が分かる前に main へ取り込み済み（`49c2b86`）。この修正は作業ブランチだけにあり、**main にはまだ入っていない**

## 11. Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 91・Rules 93・Functions 46・アカウント削除 26、合計 256）
2. Xcode で ⌘U（**570件の予定**・失敗0件）、Release ビルド
3. 実機（TestFlight）
   1. カメラでレシートを撮れる
   2. 写真から選べる
   3. 読み取り中の表示が出る（キャンセルできる）
   4. 店名・合計・日付・カテゴリーの候補が入る
   5. 内容を直せる
   6. 保存する前は家計簿に入っていない
   7. 自分だけで保存できる
   8. わが家で共有して、両方の iPhone に1件だけ出る
   9. キャンセルで何も残らない
   10. 読み取れない写真でも手入力できる
   11. 同じ操作で重複しない（保存を続けて押しても1件）
   12. アプリが重くならない
   13. 保証書の撮影と読み取りが壊れていない

## 12. 既存の機能へのリスクと対策

| リスク | 対策 |
| --- | --- |
| 保証書のカメラ・文字認識が変わる | 案内の文言は既定値で今までどおり。文字認識は取り消しを伝えるだけ（保証書のテストはそのまま） |
| 読み間違えた金額が保存される | 合計の見出しの近くだけを使い、決められなければ空。保存は利用者が「保存」を押したときだけ |
| 支出が2件できる | 読み取りは二重に始めない。同じ新しい支出の2回目の保存はしない |
| 写真・文字が残る・外へ出る | 写真・全文は保存・送信しない。読み取りの処理を終えたら手放す。共有の支出は9項目のまま |
| 重くなる | 文字認識は画面とは別の処理で動く（保証書と同じ）。読み取りは1枚だけ |
| Build 17 の予定の保存先の変更・共有の ToDo・買い物・予定・家計簿の同期・通知・招待・Firestore のキャッシュの修復 | 触っていない |

## 13. Firebase の再公開

**不要です。** Firestore のデータの形・Rules・Functions・索引・Hosting は変えていません。

## 14. 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アプリ：TestFlight で Build 17 を配る。保存済みの支出の形は変えていないので、Build 17 でもそのまま読める
