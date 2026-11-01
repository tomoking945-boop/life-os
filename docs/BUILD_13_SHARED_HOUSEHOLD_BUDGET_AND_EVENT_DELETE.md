# Build 13：家計簿の支出を「自分だけ／わが家で共有」から選ぶ・カレンダーの予定を削除する

2026-11-01。ブランチ `build13-shared-household-budget-and-event-delete`（main の `9f4bb6d` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| ブランチ | `build13-shared-household-budget-and-event-delete` |
| HEAD | `9f4bb6d`（最新の main と同じ） |
| commit していない変更 | なし |
| GitHub の同じ名前のブランチ | `9f4bb6d`（一致） |
| リポジトリの中の指示（`AGENTS.md`・`CLAUDE.md`） | ありません |

## 1. 仕様

### 家計簿の支出

- お金の画面に「＋ 支出を追加」。タイトル・金額・カテゴリー・日付・保存先（自分だけ／わが家で共有）を入れる
- 支出を押すと編集（同じ項目と保存先・削除）。削除は「この支出を削除しますか？」で確かめてから
- 「すべて／自分／共有」の切り替え（家族・パートナーの使い方のとき。一人のときは出さず「すべて」）
- 今月の合計・カテゴリーごとの合計は、表示している範囲だけで数える（すべて＝自分＋共有、自分＝自分だけ、共有＝共有だけ）。同じ支出は1回だけ
- 月の予算は、これまでどおり端末の中の設定（Firestore へは送らない）。「残り」＝予算−表示している範囲の今月の合計
- 新しい支出の保存先の初期値は、必ず「自分だけ」。入力の内容・AI・自動の分類から共有を選ばない
- 「わが家で共有」を選べないときは、理由を日本語で出す

| 状態 | 出す理由 |
| --- | --- |
| 一人で使う設定 | 一人で使う設定のため、自分だけに保存します。 |
| Firebase に接続していない | 共有の準備ができていないため、自分だけに保存します。 |
| サインインしていない | Appleでサインインして、わが家に参加すると共有できます。 |
| わが家に参加していない | わが家に参加すると共有できます。 |
| わが家の設定で「家計簿」がオフ | わが家の設定で「家計簿」がオフのため、共有できません。 |

- なんでも追加で支出と判断されたときも、初期値は「自分だけ」。なんでも追加の「保存先」で利用者が「わが家で共有」を選び、家計簿を共有できるときだけ共有する（一人の使い方では選んでいても共有しない）

### わが家の設定

- 「家計簿」をオン・オフできる（`SharedSpaceKind.money` を同期できる種類にした。サーバーの `SYNC_SUPPORTED_KINDS` も `['todo', 'shopping', 'money']`）
- はじめに選んでおく種類は、これまでどおり ToDo・買い物だけ（家計簿は利用者がオンにしたときだけ）
- オフにしても、すでにある共有の支出は消さない。オフのあいだは新しく共有できない（理由を出す）が、すでにある共有の支出の変更・削除はできる
- 予定・家事・保証書・リスト・メモは、これまでどおり「今後対応」（保存されていても消さない）

### 保存先の変更（編集画面）

データを失わない手順で、保存したあとの保存先の変更も入れた。

- **自分だけ → 共有**：Firestore へ作成し、保存が確かめられてから端末の支出を消す。失敗したら端末の支出はそのまま（自分だけ）で、理由を出す。結果が届くまでのあいだ、同じ ID の支出は「自分だけ」の方だけを出す（二重に数えない）
- **共有 → 自分だけ**：先に端末へ「自分だけ」の支出として保存してから、Firestore の共有の支出を消す。消すのに失敗したら、端末の写しを片付けて共有のまま残し、「自分だけに変更できませんでした（理由）。共有のまま残しています。」と出す（データを失わない・2件にしない）
- 文書の ID は支出の UUID のまま（自分だけ・共有のあいだで ID を変えない）

## 2. 個人／共有の保存先

| 支出 | 保存先 | 端末の `life-store.json` |
| --- | --- | --- |
| 自分だけ | 端末の中だけ（`LifeStore.expenses`） | 保存する（これまでどおり） |
| わが家で共有 | Firestore の `groups/{groupID}/expenses/{expenseID}`（`expenseID` は支出の UUID） | **保存しない**（起動中だけ `LifeStore.householdExpenses` に持ち、Firestore から読み直す） |

- `Expense` に `ownership`（自分だけ／共有）を足した。古い保存データ（この項目が無い）は、読むときに「自分だけ」になる。保存ファイルに残っている支出は、読み込むときにすべて「自分だけ」として扱う
- 足した項目は省略できるので、Build 12 のアプリでも新しい保存ファイルを読める（知らない項目は無視される）
- 既存の支出を一括で Firestore へ送る仕組みは無い。共有の支出を個人の支出として二重に保存しない
- 共有 ToDo・買い物（`items`）とは別のコレクション・別の形（`SharedExpensePayload`・`SharedExpensesBackend`・`FirestoreSharedExpensesBackend`・`SharedExpensesService`）。ToDo・買い物の形は変えていない

## 3. Firestore へ送る情報・送らない情報

**送る（共有を選んだ支出だけ）**：`schemaVersion`（1）・`title`（1〜200文字）・`amount`（1〜999,999,999 の整数）・`category`（`food`・`dailyGoods`・`diningOut`・`transport`・`subscription`・`other`）・`date`（Timestamp）・`createdBy`・`updatedBy`（操作した本人の UID。Firebase の窓口が入れる。画面・ログには出さない）・`createdAt`・`updatedAt`（サーバーの時刻）

**送らない**：月の予算・レシートの画像・メモ・メールアドレス・端末の情報・自分だけの支出・保証書・予定・そのほかの生活データ。UID・トークン・金額・支出名はログに出さない

## 4. 共有に失敗したとき

- 支出は消さない。「自分だけ」の支出として端末に残す（同じ ID で1件だけ。同じ失敗が2回届いても2件にしない）
- 画面の上に「共有できなかったため、自分だけに保存しました（理由）。」を出す。理由は 権限がありません／サインインの確認ができません／通信できません／原因が分かりません（Firestore のエラー番号 7・16・14 と 4・そのほか）
- エラーの中身・トークン・UID は画面・ログに出さない
- 共有の支出の変更・削除が断られたときは「共有の支出の変更（削除）を保存できませんでした（理由）。」を出す

## 5. オフラインのとき

- Firestore が端末にためて、つながったら送る（標準の設定のまま）
- 共有で作った支出は、結果が届くまで画面に出し続ける（空の一覧・古い一覧が届いても消さない）
- つながったあとで断られたら、上の「共有に失敗したとき」と同じ（自分だけに残す）
- 自分だけの支出は、オフラインでもこれまでどおり端末に保存する

## 6. 見張り（Build 8〜11 のくり返しを起こさないため）

- 見張りは同じわが家につき最大1つ。同じ開始の要求を何度受けても増えない（`listenStartCount`・`activeListenerCount` で確かめる）
- わが家が変わると古い見張りを外す。サインアウト・退出・わが家の削除で外す（0になる）
- 同じ一覧を何度受け取っても、入れ替えない（印の変化だけでは描き直さない）。受け取った一覧で書き込まない
- 端末の中の Firestore の片付け（Build 10・11）が終わるまで待つ（`FirestoreAccessGate`）。片付けの処理・完了の印は変えていない
- 共有の支出の通知は作らない（Functions の通知は `items` だけ。金額・支出名を通知に出さない。ToDo・買い物の通知の宛先・文面は変えていない）

## 7. 予定の削除

- カレンダーで選んだ日の予定の行を左へスワイプすると、赤い「削除」が出る（`LifeSwipeDeleteRow`）
- 押すと「この予定を削除しますか？」。ボタンは「予定を削除」（赤・破壊的な操作）と「キャンセル」
- VoiceOver の操作（カスタムアクション）「予定を削除」でも、同じ確認が出る
- 消すのは選んだ予定1件だけ（`LifeStore.deleteEvent`・`LifeItemRepository.deleteEvent`）。予定でない項目（ToDo・買い物・家事など）・わが家の共有項目は消さない
- キャンセルなら何も変えない
- 消したら保存する（アプリを開き直しても戻らない）。カレンダーと今日からすぐ消える
- 通知は、`items` が変わると `MainTabView` が予約し直す（`LifeNotificationService.resync`）ので、その予定の「まもなく予定」の通知は取り消される
- 予定の編集・予定の共有は Build 13 では足していない

## 8. セキュリティルール（`firestore.rules`）

`groups/{groupID}/expenses/{expenseID}` を追加した。

| 操作 | 条件 |
| --- | --- |
| 読み取り | サインインしているわが家のメンバーだけ |
| 作成 | メンバー・わが家の `sharedKinds` に `money` がある・文書の ID が UUID・決まった項目だけ（9つすべて、ほかは不可）・`schemaVersion` 1・タイトル 1〜200文字・金額 1〜999,999,999 の整数・決まったカテゴリー・日付は Timestamp・`createdBy`／`updatedBy` は本人・`createdAt`／`updatedAt` はサーバーの時刻 |
| 更新 | メンバー（家計簿がオフでもできる）・同じ項目の決まり・`updatedBy` は本人・`updatedAt` はサーバーの時刻・`createdBy`・`createdAt`・`schemaVersion` は変えられない |
| 削除 | メンバー（家計簿がオフでもできる） |
| メンバーでない人・サインインしていない人 | すべて拒否 |

- レシート・メモ・予算・メール・端末・持ち主の印などの項目は置けない。支出の下にさらに置くこともできない
- 共有 ToDo・買い物（`items`）・招待・端末の登録・わが家・メンバーの権限は変えていない（緩めていない）
- 新しい複合インデックスは不要（わが家の `expenses` を丸ごと見張るだけ。並べ替え・絞り込みの問い合わせはしない）。`firestore.indexes.json` は変えていない

## 9. アカウント・わが家の削除（監査）

| 確認 | 結果 |
| --- | --- |
| わが家の削除（`deleteHousehold`） | `recursiveDelete(groups/{groupID})` で、`expenses` も含めて消える（テストを追加） |
| パートナーの退出（`leaveHousehold`） | メンバー文書と memberships だけを消す。共有の支出はオーナー側に残る（テストを追加） |
| パートナーのアカウント削除 | 本人のメンバー文書・利用者の情報を消す。共有の支出はわが家に残る（テストを追加） |
| オーナーのアカウント削除（パートナーがいる） | パートナーが引き継ぎ、共有の支出は残る（テストを追加） |
| 1人のわが家のオーナーのアカウント削除 | わが家を丸ごと消すので、共有の支出も残らない（テストを追加） |
| 個人の支出 | アプリが送らないので、サーバーにも、ほかの人の下にも無い（テストで、利用者の下や一番上に `expenses` ができないことを確かめる） |
| 孤立した情報 | 削除の処理は変えていない（わが家の下は丸ごと消える。退出では共有の支出だけが残る） |

Functions の削除の処理は変更不要だった（`expenses` はわが家のサブコレクションなので、既存の丸ごと削除の対象）。

## 10. 公開の順番

1. **Functions**（`firebase deploy --only functions`）：`SYNC_SUPPORTED_KINDS` に `money` を足したので、アプリから家計簿をオンにできるようになる。家計簿の共有の Function は新しく作っていない（通知の Function も変えていない）
2. **Firestore Rules**（`firebase deploy --only firestore:rules`）：`expenses` の決まりを足した。ルールが無いと共有の支出は作れない（アプリは自分だけに残す）
3. **Build 13 を TestFlight へ**

- 索引・Hosting の公開は不要
- 注意：Functions を公開したあと、Build 12 以前のアプリで共有する種類を切り替えると、そのアプリは家計簿を知らないため、家計簿がオフになる（共有の支出は消えない。Build 13 でオンに戻せる）。2台とも Build 13 にしてから家計簿をオンにしてください
- ここではどれも公開していない

## 11. 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- Functions：前の版（`SYNC_SUPPORTED_KINDS` が ToDo・買い物だけ）を公開し直す。保存されている `money` は「今後対応」として残る（消さない）
- Rules：前の版を公開し直すと、`expenses` は読み書きできなくなる（データは残る。アプリは見張りが断られ、共有の支出の表示を消す。自分だけの支出はそのまま）
- アプリ：TestFlight で Build 12 を配る。Build 12 は `expenses` を読まない。端末の保存ファイルの支出は、Build 12 でもそのまま読める

## 12. 2台の iPhone での確認（A：オーナー、B：パートナー。2台とも Build 13、わが家の設定で「家計簿」をオン）

1. A が自分だけの支出を作る → B に出ない
2. B が自分だけの支出を作る → A に出ない
3. A が共有の支出を作る → 2台に出る
4. B が共有の支出を作る → 2台に出る
5. A・B がそれぞれ、相手が作った共有の支出を編集 → 相手に反映
6. A・B がそれぞれ、共有の支出を削除（確認のあと）→ 相手からも消える
7. 「すべて／自分／共有」を切り替え、一覧が正しい
8. 今月の合計・カテゴリーの合計が、範囲ごとに正しい（同じ支出を二重に数えない）
9. 機内モードで共有の支出を作る → 消えない → 戻すと相手に出る（1件だけ）
10. わが家の設定で「家計簿」をオフ → 新しい支出で「わが家で共有」を選べない（理由が出る）
11. オフのまま、すでにある共有の支出を修正・削除できる
12. 共有の支出では、金額・タイトルの通知が届かない
13. カレンダーで予定を左へスワイプ →「削除」→ キャンセル（何も変わらない）→ もう一度 →「予定を削除」
14. 削除した予定が、カレンダーと今日から消える
15. アプリを終了して開き直しても、削除した予定が戻らない（時刻つきの予定なら、通知も届かない）
16. 30分ほど使ってもアプリが重くならない
17. 共有 ToDo・買い物の追加・名前の変更と、その通知が、Build 12 と同じように動く

## 13. まだ作っていない範囲

- 共有の支出の通知（作らない決まり）
- レシートの画像・メモの共有、月の予算の共有
- 予定の編集・予定の共有、保証書の共有
- 今日画面の「MONEY」の数字は、これまでどおり端末の月のまとめ（`budget.spent`）のまま。お金の画面の合計とは別（範囲ごとの合計はお金の画面だけ）

## 14. 変更したファイル

| ファイル | 内容 |
| --- | --- |
| `LifeOS/Core/Models/Expense.swift` | `ownership`（古いデータは自分だけ） |
| `LifeOS/Core/Sharing/SharedExpenses.swift`（新規） | 送る形・窓口・理由・`SharedExpensesService` |
| `LifeOS/Core/Sharing/FirestoreSharedExpensesBackend.swift`（新規） | Firestore の `expenses` の読み書き |
| `LifeOS/Core/Store/LifeStore.swift` | 共有の支出（保存しない）・保存先の変更・予定の削除 |
| `LifeOS/Core/Repositories/Repositories.swift` | 支出・予定の削除の窓口 |
| `LifeOS/Core/Sharing/HouseholdModels.swift` | 家計簿を同期できる種類に |
| `LifeOS/Features/Money/MoneyView.swift`・`MoneyViewModel.swift` | 追加・編集・削除・範囲・合計 |
| `LifeOS/Features/Calendar/CalendarView.swift`・`CalendarViewModel.swift` | 予定の削除（確認・VoiceOver） |
| `LifeOS/DesignSystem/Components/LifeSwipeDeleteRow.swift`（新規） | 左へスワイプで「削除」 |
| `LifeOS/Features/QuickAdd/QuickAddViewModel.swift` | なんでも追加の支出の保存先 |
| `LifeOS/Features/Profile/HouseholdSettingsView.swift`・`HouseholdSection.swift`・`LifeOS/Features/Sharing/SharedItemComponents.swift` | 説明の文言 |
| `LifeOS/App/MainTabView.swift` | 共有の支出の見張り・お知らせ |
| `firestore.rules` | `expenses` の決まり |
| `firebase/functions/src/household.js` | `SYNC_SUPPORTED_KINDS` に `money` |
| `LifeOS.xcodeproj/project.pbxproj` | Build 13 |
| テスト | 下の表 |

## 15. テスト

### 追加したテスト

| 場所 | 件数 | 内容 |
| --- | --- | --- |
| `LifeOSTests/Build13SharedBudgetAndEventDeleteTests.swift` | 28 | 古い支出は自分だけ・初期値は自分だけ・個人の支出は Firestore を呼ばない・選んだときだけ送る・決まった項目だけ（レシート・メモなし）・`life-store.json` に共有の支出を書かない・同じ一覧100回・見張りは最大1つ・サインアウト／退出／削除で0・失敗で自分だけに1件・オフライン・範囲の内容・範囲ごとの月とカテゴリーの合計・編集と削除の保存先・家計簿オフ・理由・保存先の変更（両方向・成功と失敗）・編集画面・削除の確認・なんでも追加は自分だけ／予定の削除の確認とキャンセル・選んだ予定だけ・開き直しても戻らない・今日とカレンダー・通知が残らない・ToDo や買い物を消さない・VoiceOver の操作 |
| `firebase/functions/test/unit/sharedExpenses.test.js` | 5 | 家計簿を同期できる・将来用の種類を残す・通知の Function は `items` だけ・わが家の削除で丸ごと消える・退出などで支出に触れない・ルールの形 |
| `firebase/functions/test/unit/household.test.js` | ＋1 | 家計簿のオン・オフ（既存の2件は家計簿が同期できる種類になったことに合わせて期待値を直した） |
| `firebase/functions/test/emulator/rules.test.js` | ＋11 | 作成・読取・更新・削除（双方向）・未認証／非メンバー・退出後・家計簿オフ・金額・カテゴリー／タイトル／日付・UID／時刻・作成の情報の改ざん・余分な項目・文書の ID・ToDo／買い物の権限 |
| `firebase/functions/test/emulator/functions.test.js` | ＋2 | 家計簿のオン・オフと支出を消さない・支出では通知しない（ToDo の通知の宛先と文面は同じ） |
| `firebase/functions/test/emulator/accountDeletion.test.js` | ＋6 | 退出・アカウント削除で支出が残る・わが家の削除で消える・個人の支出の場所ができない・家計簿オフで消えない |

### 直した既存のテスト（弱めていない）

家計簿が「今後対応」から「同期できる種類」に変わったため、次のテストの期待値を新しい仕様に合わせた。「今後対応の種類は残す」ことの確かめは、見本を予定・保証書・リストに変えて同じ強さで残した。

- `HouseholdManagementTests`：`testSyncSupportedKinds`・`testKindsAfterSettingKeepComingSoon`・`testSetSyncKindsKeepsComingSoon`
- `household.test.js`：同期できる種類・切り替え・送れない値
- `functions.test.js`：「今後対応の種類は消さない」（見本を保証書に）
- `AppCheckTests.testAppSourceDoesNotUseFirestore`：Firestore を使ってよいファイルに `FirestoreSharedExpensesBackend.swift` を足し、そのファイルには「`groups`・`expenses` だけ・UUID の文書 ID・一括／グループまたぎ／ログなし・4つの操作が片付けを待つ」の確かめを足した
- `Build10StabilityTests.testOnlyServiceOwnsListener`：見張りを持ってよいのに `FirestoreSharedExpensesBackend.swift`・`SharedExpenses.swift` を足し、共有の支出の同期を始めるのは `MainTabView` だけであることを足した

テストの削除・スキップ・必ず成功する形への変更はしていない。

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | **80**（74＋6） | 実行した（Node 22） | **80件成功・失敗0・スキップ0** |
| Rules Emulator | 81（70＋11） | 実行できなかった（Firebase の Emulator・npm の取得ができない） | **未実行** |
| Functions Emulator | 45（43＋2） | 実行できなかった | **未実行** |
| アカウント削除 | 26（20＋6） | 実行できなかった | **未実行** |
| Swift（Xcode） | **469**（441＋28） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

## Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 80・Rules 81・Functions 45・アカウント削除 26）
2. Xcode で ⌘U（**469件の予定**・失敗0件）、Release ビルド
3. 上の「2台の iPhone での確認」

## Build

- **13**（アプリとテスト、Debug と Release の4か所）。Version 1.0、`ITSAppUsesNonExemptEncryption = NO`、Bundle Identifier、Associated Domains、Sign in with Apple、App Attest、Push Notifications、アプリアイコンは変更なし
