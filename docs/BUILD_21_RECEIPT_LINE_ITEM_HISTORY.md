# Build 21：商品明細を支出と一緒に保存し、あとから見返す

2026-11-08。ブランチ `build21-receipt-line-item-history`（`origin/main` の `0ebbe66` から）。main にはまだ入れていません。
Firebase（Firestore のルール・索引・Functions・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `0ebbe66`（予定どおり。Build 20 と、その Mac での確認結果の記録） |
| ブランチ | `build21-receipt-line-item-history` を `origin/main` から作成 |
| commit していない変更・送っていない変更・stash | なし（上書きしていない） |
| Build 20 の実機での結果 | `docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md` に、機能とは別の commit（`d515e80`）で記録（スーパー・コンビニ・ドラッグストア・飲食店は成功、読み取りにくいレシートは未報告。枚数・14項目それぞれの結果は未報告） |

**Build 16 は欠番** です（`docs/BUILD_17_EVENT_DESTINATION_SWITCH.md`）。Build 17〜20 に続き、今回は Build 21 です。Version は 1.0、`ITSAppUsesNonExemptEncryption = NO` のままです。

## 何を作ったか

1. **商品明細の保存**：レシートから支出を保存するとき、確認画面に残っている（利用者が確かめた）商品明細も一緒に保存する。確認画面で消した明細は保存しない
2. **保存できない明細の案内**：商品名が空・80文字を超える・数量／単価／金額が正しくない・51件目以降の明細は保存せず、確認画面に「3行目：商品名が空のため保存されません…」のように理由を出す（支出そのものは保存できる）
3. **支出の詳細画面**：お金の画面で支出をタップすると開く。店名（タイトル）・合計金額・カテゴリー・日付・自分だけ／わが家で共有・商品明細・明細の合計・レシートの合計との一致／不一致／比較不能を出す。明細の無い支出は「商品明細はありません」
4. **明細の修正・削除**：詳細画面で、商品名・数量・単価・金額を1件ずつ直す・1件だけ消す。支出全体の削除とは分けた（支出の削除は「支出を編集」から）。保存できなければ元の内容のまま、理由を出す
5. **自分だけ／共有**：自分だけの支出の明細は端末の中だけ。わが家で共有の支出の明細は、わが家のメンバーだけが読み書きできる Firestore の場所へ
6. **保存先の変更**：自分だけ → 共有、共有 → 自分だけ のどちらでも、明細を失わず・重ならないように移す

検索・価格比較・在庫管理は作っていません。

## 保存する情報

明細1件に持つのは、次の6つだけです。

| 項目 | 内容 | 決まり |
| --- | --- | --- |
| 明細ID | UUID | 確認画面の明細のまま（移しても変えない） |
| 商品名 | 文字 | 1〜80文字（Unicode の文字単位）。タブ・改行などの制御文字は空白にして、前後の空白を除く |
| 数量 | 小数（任意） | 0 より大きく 10000 未満。小数3桁まで（下の「数量の保存の形と丸め方」） |
| 単価 | 整数（任意） | 0〜999,999,999 円 |
| 金額 | 整数 | 0〜999,999,999 円（0円の明細も保存できる） |
| 表示順 | 整数 | 0 から。保存するたびに並び順のとおりに振り直す |

1支出あたり **最大50件**。

### 数量の保存の形と丸め方

- 数量は **小数3桁まで** を扱う（量り売りの「1.5」「0.352」など）。それより細かい数は **四捨五入**（例：1.2345 → 1.235、0.0005 → 0.001）。四捨五入して 0 になる数・10000 以上は保存しない
- 端末のファイルでも Firestore でも、数量は **文字**（"2"・"1.5"）で保存する（小数の誤差を出さないため）。終わりの 0 は付けない（"1.50" は "1.5"）
- 全角の数字・「点」「個」を付けた入力（「２点」）も読む

## 保存しない情報

| 情報 | 端末 | Firestore | ログ |
| --- | --- | --- | --- |
| レシートの写真 | 保存しない | 送らない | 出さない |
| 読み取った全文 | 保存しない | 送らない | 出さない |
| 読み取りの途中の候補（店名・合計の候補） | 保存しない | 送らない | 出さない |
| Vision の認識の位置・信頼度 | 保存しない | 送らない | 出さない |
| 商品名・金額・UID | 明細として必要な分だけ保存 | 共有の明細として必要な分だけ（UID は書かない） | **出さない** |
| メールアドレス・通知トークン・端末の情報 | — | 送らない | 出さない |

外部の AI・外部の文字認識・Analytics・Crashlytics は足していません。文字の読み取りは今までどおり Apple Vision の端末の中の処理です。

## 個人と共有の保存先

| 支出 | 明細の保存先 | 読み書きできる人 |
| --- | --- | --- |
| 自分だけ | この iPhone の `life-store.json` の `expenseLineItems`（支出の ID ごと） | この iPhone だけ（Firestore へ送らない） |
| わが家で共有 | Firestore の `groups/{groupID}/expenseLineItems/{expenseID}`（支出1件に文書1つ。文書の ID は支出の UUID） | わが家のメンバーだけ |

共有の明細の文書は次の2項目だけです。

```
schemaVersion: 1
rows: [
  "E621E1F8-…\t牛乳\t\t\t198",          // 明細ID・商品名・数量・単価・金額をタブでつないだ1件
  "0F8FAD5B-…\tティッシュ\t2\t250\t500"
]
```

- 1件を「区切った文字」にしたのは、Security Rules が **50件それぞれの形を正規表現で確かめられる** ようにするため（ルールには繰り返しが無く、項目つきの1件を50件分確かめると、ルールの評価の上限を超えるおそれがある）。並び順が表示順
- 支出そのもの（`groups/{groupID}/expenses`）の9項目は変えていない（明細は別の場所）
- 共有の支出は端末に保存しない（今までどおり）。共有の明細も端末のファイルには保存しない（起動中だけ持ち、Firestore から読み直す）

## 既存データとの互換性

- Build 20 までの `life-store.json` には明細が無い → 読むと「明細なし」。支出そのものは変えない・消さない
- 明細の記録が壊れていても（形の違う値・知らない支出・読めない明細）、その記録だけを飛ばし、ほかのデータは今までどおり読む（ファイル全体を読めなくしない）
- 端末に無い支出の明細の記録は、次に保存するときに残さない
- Firestore の共有の支出（9項目）は変えていないので、Build 20 の iPhone でも共有の支出は今までどおり見える（明細は見えない）
- 既存の支出を自動で変更・削除することはしない

## 削除と移動の手順

| 操作 | 手順 | 失敗したとき |
| --- | --- | --- |
| 自分だけの支出を消す | 端末の支出と明細を、1回の保存で一緒に消す | — |
| 共有の支出を消す | **明細の文書を先に消し**、そのあと支出を消す（ルールが、明細が残っている支出の削除を断る） | 支出の削除が断られたら、消した明細を元に戻し、理由を出す |
| 共有で新しく作る | 支出を作ってから、明細の文書を置く（ルールは、支出がある明細だけを受け付ける） | 支出が断られたら、明細ごと「自分だけ」に保存。明細だけ断られたら、共有の支出を取り消して「自分だけ」に保存（明細を失わない） |
| 自分だけ → 共有 | 支出を作ってから明細を置く。**両方がサーバーで確かめられてから**、端末の支出と明細を片付ける（そのあいだも画面には1件・1組だけ） | 支出が断られたら自分だけのまま。明細だけ断られたら共有の支出を取り消し、自分だけのまま |
| 共有 → 自分だけ | **先に端末へ支出と明細を保存**してから、共有の明細・支出の順に消す（明細ID は変えない） | 支出の削除が断られたら、端末の写しを片付け、共有のまま残す（消えた明細は元に戻す） |
| 明細を直す・1件消す | 自分だけ：端末に保存。共有：明細の文書を置き換える（最後の1件を消したら文書を消す） | 自分だけ：端末に保存できなければ元のまま。共有：断られたら元の明細に戻し、理由を出す |
| わが家の削除・1人のわが家のアカウント削除 | Functions の `recursiveDelete` が、わが家の下（支出・明細を含む）を丸ごと消す（Functions のコードは変えていない） | — |
| パートナーの退出・アカウント削除 | わが家の共有の支出と明細は残る（今までの支出と同じ） | — |

## セキュリティルール（`firestore.rules`）

### `groups/{groupID}/expenseLineItems/{expenseID}`（新しく足した）

- 読む：わが家のメンバーだけ
- 作る・置き換える：わが家のメンバーだけ・文書の ID は UUID・**その支出がある**（同じ書き込みで作る場合も含む）・決まった2項目（`schemaVersion` は 1、`rows` はリスト）・`rows` は 1〜50件・**50件それぞれが正しい形**
  - 1件の形：明細ID（UUID）・商品名（制御文字を除く1〜80文字）・数量（空、または 0 より大きく 10000 未満・小数3桁まで）・単価（空、または 0〜999,999,999 の整数）・金額（0〜999,999,999 の整数）
- 消す：わが家のメンバーだけ
- サインインしていない人・メンバーでない人・退出した人・ほかのわが家の人は、読めず書けない。グループをまたいだ検索もできない

### `groups/{groupID}/expenses/{expenseID}`（削除の条件だけ変えた）

- 削除：メンバーで、かつ **その支出の明細の文書が残っていない**（`!existsAfter(…/expenseLineItems/{expenseID})`）ときだけ。明細だけが残らない
- 作成・更新の決まり（9項目）は変えていない

### 古いアプリ（Build 20）への影響

Build 20 の iPhone で、**明細のある共有の支出を消そうとすると、ルールが断ります**（明細だけが残らないため）。そのときは画面上いったん消えても、Firestore の結果が届くと元に戻ります。**わが家の2台とも Build 21 にしてから** 明細つきの共有の支出を使ってください。明細の無い共有の支出は、Build 20 でも今までどおり消せます。

## Firebase の公開が必要か

**必要です（Firestore Rules だけ）。** ただし、この作業では公開していません。

| 対象 | 公開 | 理由 |
| --- | --- | --- |
| Firestore Rules | **必要** | 共有の明細の場所（`expenseLineItems`）を足し、共有の支出の削除の条件を変えた |
| Functions | 不要 | コードを変えていない（テストだけ足した。わが家の削除・アカウント削除は今の `recursiveDelete` で明細も消える） |
| Firestore の索引（Indexes） | 不要 | 新しい索引は使わない（1つのコレクションを見張るだけ） |
| Hosting | 不要 | 変えていない |

## 公開順序

1. Mac でテスト（下の「テスト件数と結果」）をすべて通す
2. **Firestore Rules だけを公開**：`firebase deploy --only firestore:rules`（`firebase deploy` だけのコマンドは使わない）
3. Rules の公開が終わってから、TestFlight で Build 21 を配る（Rules より先にアプリを配ると、共有の明細の保存が断られ、「自分だけ」に保存される）
4. わが家の2台とも Build 21 にする（上の「古いアプリへの影響」）

※ 2・3 は池上さんの指示があるまで行いません。

## 元に戻す方法

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アプリ：TestFlight で Build 20 を配る。端末の `life-store.json` に足した `expenseLineItems` は、Build 20 では読まずに無視される（支出はそのまま読める。Build 20 で一度保存すると、明細の記録は消える）
- Rules：Build 20 のときの `firestore.rules`（`0ebbe66`）を `firebase deploy --only firestore:rules` で公開し直す。共有の明細の文書は残るが、アプリからは読めなくなる（わが家を削除すると消える）
- Functions・索引・Hosting は変えていないので、戻す作業は無い

## 既存機能への影響

| 機能 | 影響 |
| --- | --- |
| 保証書の撮影・文字の読み取り・画像の保存 | 変えていない |
| 予定・ToDo・買い物・通知 | 変えていない（通知の Function は共有 ToDo・買い物だけを見る。明細では通知しない） |
| Build 20 の読み取り（店名・合計の候補・商品明細の確認） | そのまま。確認画面の案内の文を「ここに残っている商品明細は、支出と一緒に保存されます…」に変え、保存されない明細の理由を足した |
| 支出の一覧 | タップすると、編集画面ではなく **詳細画面** が開く（編集は詳細の「支出を編集」から。長押しの「支出を削除」は今までどおり） |
| 家計簿の自分だけ／共有の同期 | 支出の9項目・同期の仕組みは変えていない。明細は別の見張り（1つだけ） |

### 既存のテストで変えたところ（仕様の変更に合わせて。削除・スキップはしていない）

| テスト | 変えたこと | 理由 |
| --- | --- | --- |
| Build 18 テスト21（`testImageAndFullTextAreNotPersisted`） | 端末のファイルの確認から「牛乳」「食パン」を外した | 確認した明細を保存する仕様になったため。全文（あいさつ・電話・登録番号・お預り）は今までどおり確かめる |
| Build 19 テスト13（`testCandidatesAndFullTextAreNotPersisted`） | 端末のファイルの確認から「大根」を外した | 同上。店名の候補は今までどおり確かめる |
| Build 20 テスト29（`testCandidatesAndLineItemsAreNotPersisted`） | 明細の名前と `lineItems` を保存しないものから外し、**直した明細が保存されること** を確かめるようにした。信頼度・位置の単語も確かめる | 同上 |
| Build 20 テスト41（`testVoiceOverAndTapTargets`） | 案内の文を新しい文に差し替えた | 案内の文を変えたため |
| Build 20 テスト42（`testBuildNumberIs20`） | 「4か所がそろっていて 20 以上」に | Build 21 にしたため（Build 15・17〜19 と同じ扱い） |
| `AppCheckTests`（Firestore を使ってよいファイル） | 新しい窓口 `FirestoreSharedExpenseLineItemsBackend.swift` を足し、その窓口の決まり（使うコレクション・書く2項目・一括書き込みなし・ログなし）を **新しく確かめる** | 共有の明細の窓口を足したため |
| `Build10StabilityTests`（見張りを持つファイル） | 見張りを持ってよいファイルに、新しい窓口を足した | 同上 |
| サーバー `sharedExpenses.test.js` | 支出の削除の決まりの確認を、新しい条件（明細が残っていない）に合わせた（より厳しく） | ルールを変えたため |

## 変更ファイル

**アプリ**

- `LifeOS/Core/Models/ExpenseLineItem.swift`（新規）：明細・上限・確かめ方・保存できない理由・端末のファイルの記録
- `LifeOS/Core/Sharing/SharedExpenseLineItems.swift`（新規）：共有の明細の形（rows）・窓口の決まり
- `LifeOS/Core/Sharing/FirestoreSharedExpenseLineItemsBackend.swift`（新規）：共有の明細を Firestore で読み書きする
- `LifeOS/Core/Sharing/SharedExpenses.swift`：明細の見張り・作成／削除の順番・失敗したときの戻し方
- `LifeOS/Core/Store/LifeStore.swift`：明細の保存・読み込み・移動・修正・削除
- `LifeOS/Core/Repositories/Repositories.swift`：明細の窓口を足した
- `LifeOS/Features/Money/ExpenseDetailView.swift`（新規）：支出の詳細画面
- `LifeOS/Features/Money/MoneyView.swift`：支出をタップすると詳細、確認画面の案内と保存されない明細の理由
- `LifeOS/Features/Money/MoneyViewModel.swift`：明細の保存・詳細画面・修正・削除
- `LifeOS.xcodeproj/project.pbxproj`：Build 番号 20 → 21（4か所）

**サーバー**

- `firestore.rules`：`expenseLineItems` を足した。共有の支出の削除の条件
- `firebase/functions/test/unit/expenseLineItems.test.js`（新規、12件）
- `firebase/functions/test/unit/sharedExpenses.test.js`：上の表
- `firebase/functions/test/emulator/rules.test.js`：Build 21 の7件を足した
- `firebase/functions/test/emulator/accountDeletion.test.js`：Build 21 の4件を足した
- `firebase/functions/test/emulator/functions.test.js`：Build 21 の1件を足した（明細では通知しない）

**テスト（Swift）**

- `LifeOSTests/Build21ReceiptLineItemHistoryTests.swift`（新規、25件）
- `LifeOSTests/AppCheckTests.swift`・`Build10StabilityTests.swift`・`Build18ReceiptToBudgetTests.swift`・`Build19ReceiptStoreSelectionAndCalendarColorsTests.swift`・`Build20ReceiptAccuracyAndLineItemPreviewTests.swift`：上の表

**文書**

- `docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md`（この文書）、`README.md`（リンク）
- `docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md`：Build 20 の実機での結果（別の commit `d515e80`）

## テスト件数と結果

### 件数（変更前 → 変更後）

| テスト | 変更前 | 変更後 |
| --- | --- | --- |
| サーバーの単体テスト | 91 | **103**（＋12） |
| Rules Emulator | 93 | **100**（＋7） |
| Functions Emulator | 46 | **47**（＋1） |
| アカウント削除 | 26 | **30**（＋4） |
| サーバーの合計 | 256 | **280** |
| Swift（Xcode） | 641（Build 20 時点の予定の数。Mac での実行件数は未報告） | **666**（＋25） |

### 指示のテスト1〜24 と、確かめている場所

| 指示 | Swift（`Build21ReceiptLineItemHistoryTests`） | サーバー |
| --- | --- | --- |
| 1 確認済み明細だけ保存 | `testConfirmedLineItemsAreSavedWithExpense` | — |
| 2 削除した候補は保存しない | `testRemovedCandidatesAreNotSaved` | — |
| 3 50件まで・51件目は拒否 | `testFiftyItemsAreSavedAndFiftyFirstIsRejected` | Rules「テスト3・12」、unit |
| 4 空の商品名を拒否 | `testEmptyAndTooLongNamesAreRejected` | Rules・unit |
| 5 長すぎる商品名を拒否 | `testEmptyAndTooLongNamesAreRejected` | Rules・unit |
| 6 不正な数量・単価・金額を拒否 | `testInvalidQuantityUnitPriceAndAmountAreRejected` | Rules・unit |
| 7 手入力は明細なしで保存 | `testManualExpenseSavesWithoutLineItems` | — |
| 8 古い支出を読み込める | `testOldDataAndBrokenRecordsStillLoad` | — |
| 9 個人明細を Firestore へ送らない | `testPersonalLineItemsAreNotSent` | — |
| 10 共有明細をメンバーだけが読める | `testSharedSaveSendsExpenseThenLineItems`・`testSharedPayloadMatchesServerGoldenRows` | Rules「テスト10」 |
| 11 非メンバー・未認証を拒否 | `testNonMemberCannotSendOrSeeSharedLineItems` | Rules「テスト11」 |
| 12 不要なフィールドを拒否 | `testSharedPayloadMatchesServerGoldenRows` | Rules「テスト3・12」、unit |
| 13 支出削除後に共有明細が残らない | `testDeletingSharedExpenseDeletesLineItemsFirst` | Rules「テスト13」 |
| 14 アカウント削除・わが家削除で明細も削除 | `testHouseholdRemovalClearsSharedLineItemsOnly` | アカウント削除「テスト14」2件 |
| 15 自分だけ→共有で重複しない | `testPersonalToSharedMovesLineItemsWithoutDuplicates` | Rules「テスト15・16・17」 |
| 16 共有→自分だけで失わない | `testSharedToPersonalKeepsLineItems` | Rules「テスト15・16・17」 |
| 17 同じ保存の繰り返しで重複しない | `testRepeatedSaveDoesNotDuplicate` | Rules「テスト15・16・17」 |
| 18 編集失敗時に元の明細を失わない | `testPersonalEditFailureKeepsOriginal`・`testSharedEditFailureRestoresOriginal` | — |
| 19 明細合計の一致・不一致・比較不能 | `testComparisonOfSavedLineItems`・`testDetailScreenFlow` | — |
| 20 写真・全文・候補・信頼度を保存しない | `testImageFullTextCandidatesAndConfidenceAreNotSaved` | unit（項目の名前） |
| 21 商品名・金額・UID をログに出さない | `testNoLoggingAccessibilityAndTapTargets` | — |
| 22 保証書OCR | `testWarrantyOCRStillWorks` | — |
| 23 Build 番号4か所が21 | `testBuildNumberIs21` | — |
| 24 Version・暗号化の設定 | `testBuildNumberIs21` | — |

アプリとサーバーで同じ見本の行（`E621E1F8-…\t牛乳\t\t\t198` など4件）を確かめ、両方の形がずれないようにしています。ソースを確かめるテストは、コメントの行を除いてから調べます。

### 結果（この作業環境）

| テスト | 結果 |
| --- | --- |
| サーバーの単体テスト | **103件成功・失敗0・スキップ0** |
| ルールの1件の正規表現 | Go の正規表現（Firestore のルールと同じ RE2 の書き方）で、正しい行が通り、正しくない行が通らないことを確かめた（別の確認。テストの件数には入れていない） |
| Rules Emulator・Functions Emulator・アカウント削除 | **未実行**（この作業環境では Firestore Emulator を取得できない） |
| Swift（Xcode） | **未実行**（この作業環境に Xcode が無い）。全 Swift ファイルの簡易の字句チェック（かっこ・文字列・コメントの対応）だけ実行：問題なし |

Mac での確認結果：未報告。

## Release ビルド

この作業環境では未確認（Xcode が無い）。Mac での結果：未報告。

## 実機確認手順（Build 21。わが家で家計簿を共有している2台で）

1. **Firestore Rules を公開してから**（上の「公開順序」）、2台とも Build 21 を入れる
2. レシートを読み取る → 確認画面の「商品明細（確認用）」を開く → 1件を消し、1件の名前を直す → 「保存」
3. お金の画面でその支出をタップ → 詳細画面に、消した明細が無く、直した名前で出る。明細の合計と「一致／不一致」が出る
4. 詳細画面で明細を1件タップ → 金額を直して「保存」→ 合計と比較の表示が変わる。商品名を空にして「保存」→ 理由が出て、元のまま
5. 明細のごみ箱で1件消す → 支出は残る
6. 手入力で支出を足す → 詳細に「商品明細はありません」。Build 20 までに作った支出も同じ
7. 「わが家で共有」でレシートの支出を保存 → もう1台で、同じ支出の詳細に同じ明細が出る。もう1台で明細を直す → 1台目にも反映
8. 自分だけの支出（明細あり）を「支出を編集」で共有に変える → 明細がそのまま、2件にならない。共有から自分だけに戻す → 明細がそのまま
9. 共有の支出（明細あり）を削除 → 両方の iPhone から消える
10. アプリを終了して開き直す → 自分だけの支出の明細が残っている
11. 機内モードで明細を直す → 機内モードを切ると反映される（共有）
12. 保証書の撮影・読み取りが今までどおり
13. VoiceOver で、明細が「商品名・数量・単価・金額」の順に読まれる。ごみ箱・明細の行が押しやすい

結果：未報告（推測しない）。

## リスク

- **ルールの評価の上限**：1件ずつの確認を50件分並べた。式の数は上限（1回の書き込みで1000）より十分少ない見込みだが、50件ちょうどの書き込みは Rules Emulator のテスト（「テスト10」「テスト3・12」）で必ず確かめる
- **Build 20 の iPhone**：明細のある共有の支出を消せない（上の「古いアプリへの影響」）。2台とも Build 21 にしてから使う
- **書き込みの順番**：支出と明細は別々の書き込み（Firestore の送信の列に頼んだ順に並ぶ）。明細だけが断られたときは共有の支出を取り消すが、その取り消しも断られた場合は、共有の支出が明細なしで残り、端末の「自分だけ」の支出も残る（画面には1件）。まれな組み合わせのため、理由を画面に出す
- **同時の編集**：2人が同じ支出の明細を同時に直すと、あとから届いた方の内容になる（文書1つを置き換えるため）

## Mac での次の手順

1. `git fetch origin` → `git switch build21-receipt-line-item-history`
2. `cd firebase/functions` → `npm test`（単体・Rules・Functions・アカウント削除。予定は合計280件）
3. Xcode でテスト（予定は666件）→ Release ビルド
4. 結果を教えてください（この文書に記録します）。Rules の公開・TestFlight・main への取り込みは、そのあとの指示で行います
