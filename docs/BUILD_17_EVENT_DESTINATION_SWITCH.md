# Build 17：予定の編集で保存先（自分だけ／わが家で共有）を変える

2026-11-02。ブランチ `build17-event-destination-switch`（`origin/main` の `df8a168` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| `git fetch origin` のあとの `origin/main` | `df8a168`（指定どおり） |
| ブランチ | `build17-event-destination-switch` を `origin/main` から作成 |
| 古い手元の main | 使っていない |
| `stash@{0}`（Xcode が作った署名・workspace の変更） | この作業環境には stash がありません（Mac の手元にあるもの）。触っていません（pop・drop もしていません） |

### Build 16 は欠番

同じ内容を、はじめはブランチ `build16-event-destination-switch`（`842fb4e`、Build 16）で作りました。池上さんの指示で **Build 17** として作り直し、Build 16 は欠番にしました。

- 中身は `842fb4e` と同じです。違うのは Build 番号（16 → 17）と、文書・テストの名前（Build 16 → Build 17）だけです
- `build16-event-destination-switch` は GitHub に残っています（使いません。main には入れていません）。ブランチを GitHub から消す操作は、この作業環境からはできないため、不要なら GitHub の画面から消してください

## 1. 何を作ったか

予定の「鉛筆 → 予定を編集」に、追加の画面と同じ **保存先**（自分だけ／わが家で共有）を出しました。

- 初期値は **今の保存先**：自分だけの予定は「自分だけ」、わが家で共有している予定は「わが家で共有」
  - 「共有しているか」は、Firestore から届いた共有の予定かどうかで決めます（以前の版の端末の中の「共有」の印では決めない）
- 保存先を変えない編集は、Build 15 と同じ動き（自分だけは端末だけ、共有は同じ文書を1回更新）
- 新規追加の画面の保存先（初期値は自分だけ）は変えていません
- 単なる表示の切り替えではなく、**データを失わず、相手の端末に重複を作らない** 順番で保存先を変えます。予定の UUID は変えません

## 2. 自分だけ → わが家で共有

選べるのは、次をすべて満たすときだけ（Build 14 の新規追加と同じ条件）。満たさないときは選べず、理由を日本語で出します。

- Appleでサインイン済み
- わが家へ参加済み
- わが家の設定で「予定」がオン

保存の順番（`LifeStore.saveEvent(_:destination:)` → `makeEventShared`）：

1. 編集後のタイトル・日付・終日／時刻を、端末の **同じ予定** へ保存する
2. **同じ UUID** で Firestore への作成を始める（新しい UUID は作らない）
3. Firestore で保存が確かめられるまで、端末の予定は消さない（オフラインでも消さない）
4. 確かめられたあとだけ、端末の予定を片付ける（以前からある「共有への変換」の仕組み）
5. 断られたときは、編集後の予定が「自分だけ」として **1件だけ** 残る
6. 画面の上に「共有できなかったため、自分だけに保存しました（理由）」を出す

途中で端末の予定と送信待ちの共有の予定が同じ UUID で両方あっても、画面・通知には1件だけです。

## 3. わが家で共有 → 自分だけ

保存するときに確認を出します。

| | 文言 |
| --- | --- |
| タイトル | 自分だけの予定に変更しますか？ |
| 本文 | 変更すると、この予定はパートナーのカレンダーから削除されます。 |
| 実行 | 自分だけに変更（赤） |
| キャンセル | キャンセル（何も変えない。編集画面はそのまま） |

保存の順番（`makeEventPersonal`）：

1. 編集後の予定を、**同じ UUID** で端末へ先に保存する
2. 端末への保存が **成功したことを確かめてから**、共有の予定を **1回だけ** 消す
   - 端末に保存できなかったときは、何も変えず（共有の予定も消さず）「この iPhone に保存できなかったため、共有のまま残しました。」を出す
3. 消せたら、自分の端末には自分だけの予定として1件だけ出る
4. パートナーの端末からは消える
5. 消せなかったとき（通信できない・権限がない）も、予定は失わない。理由を画面に出し、自分だけの予定として残す
6. 削除が確かめられるまで、同じ UUID の共有の予定が届いても **画面には出さず**、端末の自分だけの予定も **片付けない**（画面には1件だけ）
7. 再起動・オフラインでも失わない（下の4）

わが家の設定で「予定」がオフでも、既存の共有の予定を「自分だけ」へ戻すことはできます（Rules の削除は種類の設定を見ない。Build 14 から同じ）。

## 4. データを守るしくみ

- **変更の途中の印**：「自分だけ」へ変えている途中の予定の UUID を、端末の `life-store.json` に保存します（`personalConversionIDs`。UUID だけ。外へは送りません。以前の版の保存データには無い項目なので、無ければ空として読みます。以前の版のアプリは、この項目を読み飛ばします）
  - 印のある UUID の共有の予定は、画面に出さない・端末の予定を片付けない
  - 削除がサーバーで確かめられたら、印を消して保存し直す
- **再起動したとき**：前の起動で削除が確かめられなかった予定は、Firestore の一覧にまだあれば、その起動で **1回だけ** 消し直します（同じ起動の中ではくり返さない。通信や権限の問題があっても、送り続けるループにはならない）
- **端末への保存の確認**：`LocalStorage.save` が「保存できたか」を返すようにしました（これまでは返していなかった。ほかの呼び出し元の動きは同じ）
- **重複しない**：UUID は変えず、作成は同じ UUID の1回だけ。同じ UUID の2回目の作成は Rules が断ります（Build 14 から）
- **印が古くなったとき**：削除の結果だけが届かなかった（共有の予定はもう無い）ときは、もう一度「わが家で共有」にすると印を外して進めます。共有の予定がまだサーバーにあるときは、重ねて作らず「前に「自分だけ」へ変更した予定の片付けがまだ終わっていません。」を出します

## 5. 変えていないもの

- 予定の UUID・タイトル・日付・終日／時刻（編集した内容はそのまま運ぶ）
- ローカル通知：同じ識別子（`lifeos.event.<UUID>`）のまま、変更後の日時へ移る（自分だけ・共有のどちらでも1件）
- 共有のまま編集するときの作成者・作成日時（更新では送らない）
- Build 15 の ToDo の日付指定、予定の追加・共有・削除、ToDo・買い物・家計簿の共有、プッシュ通知
- Firestore に保存する項目（作成・更新・削除のどれも、今までと同じ項目だけ）
- Firestore Rules・Functions・索引・Hosting（変更なし。Firebase への公開は不要）
- 既存のデータの一括変換はしない（利用者が編集画面で選んだ1件だけ）
- アプリの軽さ：見張りは今までどおり最大1つ。同じ一覧が届いても入れ替えない（変えていない）

## 6. 変更したファイル

アプリ：

- `LifeOS/Core/Store/LifeStore.swift`：`saveEvent(_:destination:)`（保存先の変更）、変更の途中の印（保存・読み込み・画面に出さない・片付けない・再起動で1回だけ消し直す）、`save()` が成功を返す
- `LifeOS/Core/Sharing/HouseholdItems.swift`：`EventSaveOutcome`、`HouseholdItemSyncing` に `canDeleteHouseholdItems`・`deleteHouseholdItemForPersonalConversion`（`SharedItemsService` が実装。消せなかった理由の表示）
- `LifeOS/Core/Utilities/LocalStorage.swift`：`save` が成功を返す
- `LifeOS/Features/Calendar/CalendarViewModel.swift`：編集の保存先（初期値は今の保存先）、確認・キャンセル、変えられなかった理由
- `LifeOS/Features/Calendar/CalendarEventSheet.swift`：編集でも保存先を出す、説明の文
- `LifeOS/Features/Calendar/CalendarView.swift`：「自分だけの予定に変更しますか？」の確認、保存できなかった理由
- `LifeOS.xcodeproj/project.pbxproj`：Build 15 → 17（4か所。Build 16 は欠番）

テスト・文書：

- 追加：`LifeOSTests/Build17EventDestinationSwitchTests.swift`（17件）
- 更新：`LifeOSTests/Build15EventEditTests.swift`（2件。下の7）
- `docs/BUILD_17_EVENT_DESTINATION_SWITCH.md`（この文書）、`README.md`（リンク）

## 7. テスト

### 追加したテスト（Swift、17件）

| 必須の項目 | テスト |
| --- | --- |
| 編集画面に保存先が表示される | `testEditSheetShowsDestinationAndConfirmationTexts` |
| 今の保存先が初期選択される | `testCurrentDestinationIsInitiallySelected` |
| 保存先を変えない個人・共有の編集 | `testEditWithoutDestinationChangeWorksAsBefore` |
| 自分→共有は同じ UUID で作成1回／2台で相手へ出る | `testPersonalToSharedCreatesOnceWithSameUUIDAndAppearsOnPartner` |
| 共有の確認前に個人データを消さない／オフラインから復帰しても重複しない | `testPersonalDataStaysUntilServerConfirmsAndNoDuplicateAfterReconnect` |
| 共有失敗時に編集後の個人予定が1件残る | `testShareFailureKeepsOneEditedPersonalEvent` |
| 予定共有がオフなら自分→共有は不可 | `testPersonalToSharedIsBlockedWhenEventSharingIsOff` |
| 確認のキャンセルでは何も変わらない | `testCancelConfirmationChangesNothing` |
| 共有→自分は端末保存後に削除1回／個人化すると相手から消える／一時的に両方あっても表示は1件 | `testSharedToPersonalSavesOnDeviceFirstThenDeletesOnce` |
| 予定共有がオフでも共有→自分は可能 | `testSharedToPersonalWorksWhenEventSharingIsOff` |
| 共有→自分の削除失敗でも予定を失わない（再起動で1回だけ消し直す） | `testDeleteFailureKeepsEventAndRetriesOnceAfterRelaunch` |
| 端末に保存できなければ共有の予定を消さない | `testDeviceSaveFailureDoesNotDeleteSharedEvent` |
| オフラインから復帰しても重複しない（共有→自分） | `testOfflineSharedToPersonalDoesNotDuplicateAfterReconnect` |
| 古い印でもう一度共有できる・重ねて作らない | `testStaleMarkerDoesNotBlockSharingAgain` |
| 通知が変更後の日時へ移る | `testLocalReminderMovesToEditedTimeAcrossDestinationChanges` |
| Firestore の項目を増やさない | `testNoNewFirestoreFieldsOrWrites` |
| Build 17・Version 1.0・暗号化の設定 | `testBuildNumberIs17InAllFourSettings` |

### 直した Build 15 のテスト（弱めていない）

Build 15 では「編集では保存先を出さない」「Build は 15」が仕様だったため、Build 17 の仕様に合わせました。

- `testEditSheetUsesSameFieldsButDoesNotOfferDestinationChange`：「保存先は追加のときだけ」の確認を、「保存先を追加・編集の両方で出す」「初期値は今の保存先（共有なら household、自分だけなら personal）」の確認に置き換え（同じ入力部品の確認はそのまま）
- `testBuildNumberIs15InAllFourSettings`：4か所がそろっていて 15 以上であることを確かめる（ちょうど 17 であることは Build 17 のテストで確かめる）

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 91 | 実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules Emulator | 93 | 実行できなかった（Emulator が無い） | **未実行**（Rules は変更なし） |
| Functions Emulator | 46 | 実行できなかった | **未実行**（Functions は変更なし） |
| アカウント削除 | 26 | 実行できなかった | **未実行** |
| サーバーの合計 | 256 | — | 単体の91件だけ実行 |
| Swift（Xcode） | **540**（523＋17） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

## 8. Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 91・Rules 93・Functions 46・アカウント削除 26、合計 256）
2. Xcode で ⌘U（**540件の予定**・失敗0件）、Release ビルド
3. 2台の iPhone（A・B。2台とも Build 17、わが家の設定で「予定」をオン）
   1. A：自分だけの予定の鉛筆 → 保存先が「自分だけ」で始まる
   2. A：タイトルと時刻を変えて「わが家で共有」で保存 → B のカレンダー・今日に1件だけ出る。A にも1件だけ
   3. B：その予定の鉛筆 → 保存先が「わが家で共有」で始まる
   4. A：共有の予定を「自分だけ」にして保存 → 確認が出る →「キャンセル」で何も変わらない
   5. A：もう一度保存 →「自分だけに変更」→ A に自分だけの予定として1件、B から消える
   6. A：機内モードで 2・5 を行い、戻したあとも A・B に重複が無い
   7. A：アプリを終了して開き直しても、予定は1件のまま
   8. わが家の設定で「予定」をオフ → 自分だけの予定では「わが家で共有」が選べず理由が出る。共有の予定は「自分だけ」へ戻せる
   9. 時刻つきの予定の10分前の通知が、変更後の時刻で1件だけ届く
   10. 保存先を変えない編集・新規追加・削除・ToDo の日付指定が、これまでどおり

## 9. 公開

- Firebase（Rules・Functions）の公開は **不要**（どちらも変更なし）
- TestFlight へ Build 17 を上げる前に、上の8の確認をお願いします
- ここでは、どれも公開していません

## 10. 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- アプリ：TestFlight で Build 15 を配る。Build 15 は端末の `personalConversionIDs` を読み飛ばす。変更の途中で Build 15 に戻した場合は、同じ UUID の共有の予定が残っていれば、Build 15 の決まりで共有の予定の方が出ます（端末の予定はそのとき片付けられます）

## 11. 今回は作らないもの

- 「なんでも追加」から予定を共有すること（Build 14 から自分だけのまま）
- ToDo・買い物・家計簿の保存先の変更の画面の変更
- 予定のプッシュ通知
