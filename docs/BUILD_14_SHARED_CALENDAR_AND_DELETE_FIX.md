# Build 14：予定の削除の不具合を直す・カレンダーから予定を「わが家で共有」にする

2026-11-01。ブランチ `build14-shared-calendar-and-delete-fix`（main の `57c5323` から）。main にはまだ入れていません。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer・App Store Connect の変更はしていません。

## 始める前に確かめたこと

| 確認 | 結果 |
| --- | --- |
| ブランチ | `build14-shared-calendar-and-delete-fix`（新しく作成） |
| HEAD | `57c5323`（最新の main と同じ） |
| GitHub の main | `57c5323`（一致） |
| commit していない変更 | なし |

## 1. 予定を削除できなかった原因（Build 13）

Build 13 では、予定の行を左へスワイプすると赤い「削除」が出ましたが、実機で押しても予定は消えませんでした。原因は、行の部品 `LifeSwipeDeleteRow` の**タップの受け手の重なり**です。

- 部品は `ZStack` で、下に赤い「削除」ボタン、上に予定の行（中身）を重ねていました
- スワイプすると、中身を `.offset(x:)` で左へずらして、下の「削除」ボタンを見せていました
- ところが中身には、`.offset(x:)` の**あと**に `.contentShape(Rectangle())`・`.simultaneousGesture(DragGesture)`・`.onTapGesture { 開いていたら閉じる }` を付けていました
- SwiftUI では、`.offset` は「描く位置」だけをずらし、そのあとに付けたタップの範囲は**ずらす前の元の場所（行の全体）**のままになります
- そのため、見た目では「削除」ボタンが見えている場所にも、透明な中身のタップの範囲がかぶっていました。押すと中身の `onTapGesture` が先に受け取り、**行を閉じるだけ**で、`onDelete`（確認を出す処理）は一度も呼ばれていませんでした
- さらに、赤いボタンは VoiceOver から隠していて（`.accessibilityHidden(true)`）、ScrollView の中の独自のドラッグはスクロールと取り合うため、スワイプ自体も安定しませんでした

データを消す `LifeStore.deleteEvent` には問題がありませんでした（Build 13 のテストのとおり、呼ばれれば正しく1件だけ消えます）。壊れていたのは**画面のタップの経路**だけです。

## 2. 直し方

- 独自のスワイプ（`LifeSwipeDeleteRow`）を予定の画面から外し、使わなくなったので部品のファイルも消しました（操作を二重にしないため）
- 各予定の行の**右側に、ふつうの `Button` のごみ箱ボタン**（`CalendarEventDeleteButton`）を置きました
  - `trash` のアイコン、44×44 ポイント以上（`LifeSpacing.minTapTarget`）
  - アクセシビリティのラベル「予定を削除」、UI テスト用の識別子 `calendar.deleteEvent`
  - 行の上に重なる透明なタップの受け手は置いていません（原因の形を作らない）
- 押しただけでは消さず、これまでの確認を出します
  - 「この予定を削除しますか？」
  - 「予定を削除」（赤・破壊的な操作）／「キャンセル」（何も変えない）
- 「予定を削除」で、選んだ1件だけを `LifeStore.deleteEvent` で消します
  - 自分だけの予定：端末から消して保存（開き直しても戻らない）
  - わが家で共有している予定：Firestore の `groups/{groupID}/items/{予定のUUID}` を**1回だけ**削除（相手の iPhone からも消える。端末の保存ファイルには、もともと書いていない）
  - ToDo・買い物・家事・共有の ToDo は、ここからは消しません
- カレンダーと今日は同じ正本（`visibleItems`）を見ているので、両方からすぐ消えます
- ローカル通知は、予定の変化で予約し直し、消した予定の通知を取り消します（共有の予定も含む。下の5）

## 3. カレンダーから予定を共有する

カレンダーで日付を選び、「予定を追加」を押した画面に**保存先**を足しました。

| 保存先 | 内容 |
| --- | --- |
| 自分だけ（**初期値**） | これまでどおり、この iPhone だけに保存 |
| わが家で共有 | わが家のメンバーのカレンダー・今日にも出る |

- 初期値は必ず「自分だけ」。自動で共有を選ぶことはありません
- 「わが家で共有」を選べるのは、次をすべて満たすときだけ。満たさないときは選べず、理由を日本語で出します

| 状態 | 出す理由 |
| --- | --- |
| Appleでサインインしていない | Appleでサインインして、わが家に参加すると共有できます。 |
| わが家に参加していない | わが家に参加すると共有できます。 |
| わが家の設定で「予定」がオフ | わが家の設定で「予定」がオフのため、共有できません。 |
| 共有の準備ができていない（Firebase に接続していない） | 共有の準備ができていないため、自分だけに保存します。 |
| 一人で使う設定 | 一人で使う設定のため、自分だけに保存します。 |

- 「なんでも追加」から作る予定は、Build 14 でも**自分だけ**です（予定の共有はカレンダーの「予定を追加」からだけ）。ToDo・買い物は、これまでどおり選んだ保存先へ
- ToDo・買い物の編集画面から予定を共有へ変える入口も作っていません

## 4. 共有の予定の保存（既存の仕組みを広げただけ）

新しいサービスは作らず、共有の ToDo・買い物と**同じ場所・同じ形**を使います。

- 保存先：`groups/{groupID}/items/{予定のUUID}`（`kind: "event"`）
- 広げたところ：`HouseholdItemPolicy.kinds`（予定・ToDo・買い物）、`SharedSpaceKind.syncSupported`（予定・ToDo・買い物・家計簿）、Functions の `SYNC_SUPPORTED_KINDS`、Firestore Rules の作成の条件、わが家の設定画面
- 文書の ID は予定の UUID。再送やスナップショットの更新で予定が重なりません（同じ UUID の2回目の作成は Rules が断り、端末でも1件だけ出します）

### 送る情報

| 項目 | 内容 |
| --- | --- |
| `title` | タイトル（前後の空白を除き、200文字まで） |
| `date` | 日付（時刻を指定したときは、その日時） |
| `hasTime` | 終日か（`false`）、時刻を指定したか（`true`） |
| `createdBy`・`updatedBy` | 作成者・更新者（サインインしている本人。Rules が本人かを確かめる） |
| `createdAt`・`updatedAt` | サーバーの時刻 |
| `schemaVersion`（1）・`kind`（`event`）・`isCompleted`（`false`）・`assigneeUID`（`null`） | 既存の形に必要な決まった項目 |

### 送らない情報

自分だけの予定・メールアドレス・端末の情報・通知のトークン・メモ・位置情報・外部のカレンダーの情報・柔らかい時間・暮らしメモリーとのつながり・担当（自分／パートナー）・端末の中の持ち主の区別。
（アプリの予定には、もともとメモ・場所・外部のカレンダーの項目がありません。Rules でも、決まった項目以外は書けません。）

### 共有に失敗したとき

- 予定は消さず、「自分だけ」の予定として**1件だけ**端末に残します（同じ UUID）
- 画面の上に「共有できなかったため、自分だけに保存しました」の理由を出します（ToDo・買い物と同じお知らせ）
- オフラインのときは、送信待ちとして1件だけ表示し、つながったら1回だけ送ります

## 5. 表示と通知

- 共有の予定は、両方の iPhone の**カレンダー・今日・「すべて」・「共有」**に出ます（「自分」には出ません）。相手が追加・削除した予定も、見張り（最大1つ）でリアルタイムに反映
- 共有の予定は端末の保存ファイル（`life-store.json`）に**書きません**。起動のたびに Firestore から読み直します
- **プッシュ通知は足していません**。予定の追加・変更・削除では通知しません（Functions の `NOTIFY_KINDS` は ToDo・買い物のまま。ToDo・買い物の通知は変えていません）
- **ローカル通知**：共有の予定も、自分の予定と同じく「時刻のある予定の10分前」を、**それぞれの iPhone の通知設定**（今日の予定のお知らせ）に従って予約します。共有の予定が消えると、次の予約し直しで取り消します
  - 予約し直しのきっかけ（`MainTabView` の `NotificationSyncKey`）に、共有の予定を足しました。中身が同じなら値も同じなので、予約し直しのくり返し（ループ）は起きません
  - `LifeStore.notificationItems`：端末の項目＋共有の予定（同じ ID は1つだけ）。共有の ToDo・買い物はこれまでどおり入れません

## 6. わが家の設定

- 「予定」を「今後対応」から、切り替えられる種類へ移しました：**予定・ToDo・買い物・家計簿**
- 「今後対応」は 家事・保証書・リスト・メモ
- わが家を作るときの初期値は、これまでどおり **ToDo・買い物だけ**（予定を自動でオンにしない）
- 予定をオフにしても、すでにある共有の予定は消しません。削除はできます
- 注意：以前の版でわが家を作るときに「予定（今後対応）」を選んでいたわが家では、Build 14 では予定がオンとして表示されます。予定ごとに「わが家で共有」を選ばない限り、予定は共有されません

## 7. Firestore Rules（`firestore.rules`）

`groups/{groupID}/items/{itemID}` の作成の条件だけを変えました。

- 作成できる種類：`['todo', 'shopping']` → **`['event', 'todo', 'shopping']`**（家事は今までどおり作れない）
- `sharedKinds` にその種類があるときだけ作成（予定は `event` があるときだけ）
- 予定を作るときは、さらに `validNewEvent`：完了なし（`isCompleted == false`）・担当なし・あとで／もうやらないの印なし
- 形の確かめ（`validItem`）は今までどおり：決まった項目だけ、タイトル 1〜200 文字、日付は Timestamp、`hasTime`・`isCompleted` は bool、schemaVersion 1、更新者は本人・更新日時はサーバーの時刻
- 作成者は本人、作成日時はサーバーの時刻
- 読む・更新・削除はメンバーだけ。削除は種類の設定を見ないので、予定をオフにしたあとも消せる
- 未認証の人・メンバーでない人・退出した人は、読めず、作れず、消せない
- ToDo・買い物・家計簿（`expenses`）の権限は変えていません（緩めていない）
- 新しい索引は不要（一覧は今までどおり `items` をそのまま見張るだけ）

## 8. Functions の変更

- `src/household.js`：`SYNC_SUPPORTED_KINDS` を `['event', 'todo', 'shopping', 'money']` に（わが家の設定で予定をオン・オフできるように）。初期値 `DEFAULT_SHARED_SPACE_KINDS` は `['todo', 'shopping']` のまま
- `src/notificationPolicy.js`：説明の文だけ（予定は通知しない。`NOTIFY_KINDS` は変えていない）
- 新しい Function はありません

## 9. レシート（家計簿）について

- Build 14 では、家計簿用のレシートの読み取りは**足していません**
- **家計簿へ支出を自動で作る機能は未実装**です
- 保証書の画面の、Apple Vision による端末の中の文字の読み取り・保証書／レシート／製品ラベルの写真の保存・購入店や購入日の候補・確認したあとだけ反映・外へ画像や文字を送らない、はそのままです（触っていません）

## 10. 公開の順番

1. **Functions**（`firebase deploy --only functions`）：`SYNC_SUPPORTED_KINDS` に `event` を足したので、アプリから予定をオンにできるようになる
2. **Firestore Rules**（`firebase deploy --only firestore:rules`）：予定の作成を許す。ルールが無いと共有の予定は作れない（アプリは自分だけに1件残す）
3. **Build 14 を TestFlight へ**

- 索引・Hosting の公開は不要
- 注意：Functions を公開したあと、Build 13 以前のアプリで共有する種類を切り替えると、そのアプリは予定を「今後対応」として扱うため、保存されている `event` は残ります（消えません）。2台とも Build 14 にしてから予定をオンにしてください
- ここではどれも公開していない

## 11. 戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- Functions：前の版（`SYNC_SUPPORTED_KINDS` が ToDo・買い物・家計簿）を公開し直す。保存されている `event` は「今後対応」として残る
- Rules：前の版を公開し直すと、予定は新しく作れなくなる（すでにある共有の予定は残り、読む・消すはできる）
- アプリ：TestFlight で Build 13 を配る。Build 13 は共有の予定を読まない（表示されないだけで消えない）

## 12. 2台の iPhone での確認（A：オーナー、B：パートナー。2台とも Build 14）

1. A・B：カレンダーで予定を追加 →「保存先」の初期値が「自分だけ」
2. 予定がオフのとき：「わが家で共有」が選べず、「わが家の設定で「予定」がオフのため、共有できません。」が出る
3. A：わが家の設定で「予定」をオン
4. A：「わが家で共有」で 10:00 の予定を追加 → B のカレンダー・今日・「すべて」・「共有」に出る（「自分」には出ない）
5. B：終日の共有の予定を追加 → A に出る
6. A：予定の右のごみ箱を押す →「この予定を削除しますか？」→「キャンセル」で何も変わらない
7. A：もう一度押して「予定を削除」→ A・B の両方のカレンダー・今日から消える
8. A：自分だけの予定を削除 → 消える。アプリを終了して開き直しても戻らない
9. 共有の予定を削除してから開き直しても戻らない
10. ToDo・買い物・家事が、予定の削除で消えていない
11. 時刻つきの共有の予定：10分前のローカル通知が、通知設定がオンの iPhone だけに届く。削除したあとは届かない
12. 予定の追加・削除で、プッシュ通知が届かない。ToDo・買い物の追加ではこれまでどおり届く
13. A：わが家の設定で「予定」をオフ → 既存の共有の予定は残り、ごみ箱で消せる。新しくは「わが家で共有」を選べない
14. 機内モードで共有の予定を追加 → 1件だけ出て、つながると B に1件だけ出る
15. VoiceOver：ごみ箱が「予定を削除」と読まれ、ダブルタップで確認が出る
16. 保証書の画面の写真の文字の読み取りが、これまでどおり使える

## 13. まだ作っていない範囲

- 予定の編集（タイトル・日時の変更）
- 「なんでも追加」から予定を共有すること（Build 14 では自分だけ）
- 自分だけの予定を、あとから共有へ変えること・共有の予定を自分だけに戻すこと
- 予定のプッシュ通知
- 家計簿へ支出を自動で作る機能（レシートの読み取り）

## 14. 変更したファイル

アプリ：

- `LifeOS/Features/Calendar/CalendarView.swift`：スワイプを外し、ごみ箱ボタン（`CalendarEventDeleteButton`）を追加。シートへ共有できない理由を渡す
- `LifeOS/Features/Calendar/CalendarEventSheet.swift`：保存先（自分だけ／わが家で共有）と理由
- `LifeOS/Features/Calendar/CalendarViewModel.swift`：下書きの保存先、共有の保存、共有の予定も削除できる
- `LifeOS/DesignSystem/Components/LifeSwipeDeleteRow.swift`：削除（使わなくなった）
- `LifeOS/Core/Store/LifeStore.swift`：`deleteEvent` が共有の予定も消す、`eventSharingBlock`・`householdEvents`・`notificationItems`
- `LifeOS/Core/Sharing/HouseholdItems.swift`：`HouseholdItemPolicy.kinds` に予定、`EventSharingBlock`、`SharedItemsService.updateSignIn`・`eventSharingBlock`
- `LifeOS/Core/Sharing/HouseholdModels.swift`：`syncSupported` に予定
- `LifeOS/Core/Notifications/LifeNotificationService.swift`：予約し直しに共有の予定を含める
- `LifeOS/App/MainTabView.swift`：通知のきっかけに共有の予定、サインインの状態を伝える
- `LifeOS/Features/QuickAdd/QuickAddViewModel.swift`：なんでも追加の予定は自分だけ
- `LifeOS/Features/Sharing/SharedItemComponents.swift`：説明の文、編集画面から予定を共有へ変えない
- `LifeOS/Features/Profile/HouseholdSettingsView.swift`・`HouseholdSection.swift`：説明の文
- `LifeOS.xcodeproj/project.pbxproj`：Build 13 → 14（4か所）

サーバー：

- `firestore.rules`、`firebase/functions/src/household.js`、`firebase/functions/src/notificationPolicy.js`（説明の文だけ）

テスト・文書：

- 追加：`LifeOSTests/Build14SharedCalendarAndDeleteFixTests.swift`、`firebase/functions/test/unit/sharedCalendar.test.js`
- 更新：`LifeOSTests/Build13SharedBudgetAndEventDeleteTests.swift`・`HouseholdManagementTests.swift`・`SharedTodoShoppingTests.swift`、`firebase/functions/test/unit/household.test.js`・`sharedExpenses.test.js`、`firebase/functions/test/emulator/rules.test.js`・`functions.test.js`
- `docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md`（この文書）、`README.md`（リンク）

## 15. テスト

### 追加したテスト

Swift（`Build14SharedCalendarAndDeleteFixTests.swift`、30件）：

- 削除ボタン：ふつうの Button・trash・44pt 以上・ラベル・識別子・重なるタップの受け手なし／押すと確認の状態／キャンセルで残る
- 自分だけの予定の削除（Firestore を呼ばない）／共有の予定の削除で Firestore の削除を1回だけ（相手からも消える）
- 削除した1件以外（ToDo・買い物・家事・共有の ToDo・ほかの予定）は残る
- 今日とカレンダーの両方から消える（自分・相手の端末）
- 開き直しても戻らない（自分だけ・共有）／共有の予定を `life-store.json` に書かない
- 削除した予定のローカル通知が残らない（自分・相手）／共有の予定の通知は各 iPhone の設定に従う／通知の予約し直しに共有の予定を含める
- 保存先の初期値は自分だけ／自分だけの予定は Firestore を呼ばない／明示して共有を選んだときだけ決まった項目を送る
- なんでも追加の予定は自分だけ
- 予定がオフなら新しく共有できない／選べない理由（未サインイン・未参加・未接続・一人モード）／オフのあとも既存の共有の予定を消せる
- 相手のカレンダー・今日・「すべて」・「共有」に出る（「自分」には出ない）
- 同じ一覧を100回受けても重ならない（描き直し・通知のきっかけも変わらない）／同じ UUID の再送でも1件
- 見張りは最大1つ／共有の失敗で自分だけに1件だけ（メンバーでない・断られたときも）／オフラインでも1件
- わが家の設定（予定は切り替えられる・初期値に入らない）・説明の文／ToDo・買い物の通知の決まりは変えない／家計簿にレシートの読み取りを足していない

サーバー：

- 単体（`sharedCalendar.test.js`、11件）：予定はオン・オフできる・初期値に入らない／予定はプッシュ通知しない・ToDo・買い物の通知は変わらない／Rules のソースの決まり
- Rules Emulator（12件）：オフなら作れない／オンなら作れる（終日も）／相手が見えて消せる／オフのあとも消せる／作成者・日時／形／完了・担当・印つきは不可／メモ・場所・メール・端末・トークン・外部カレンダーは書けない／同じ UUID は1件／メンバーでない・未認証は不可／退出後は不可／種類を変えられない・家事と支出は items に作れない・ToDo の決まりは変わらない
- Functions Emulator（1件）：予定のオン・オフ、オフにしても共有の予定は消さない

### 直した既存のテスト（弱めていない）

予定が「今後対応」から「同期できる種類」へ移ったため、期待する値を新しい仕様に合わせ、「今後対応」の見本は家事・保証書に置き換えました。確かめる内容は減らしていません（予定のオン・オフの確認を足しています）。

- `HouseholdManagementTests`：`syncSupported`・`comingSoon`・種類の切り替え・`allowsSharing`
- `SharedTodoShoppingTests`：送れる種類（予定を足し、家事・支払・習慣は送らない）・受け取る種類（予定は読む、家事は読まない）・偽物のサーバーを新しい Rules と同じ決まりに
- `Build13SharedBudgetAndEventDeleteTests.testCalendarSourceHasSwipeConfirmationAndVoiceOverAction`：スワイプの代わりにごみ箱ボタンを確かめる（確認の文言・赤の操作・VoiceOver は今までどおり確かめる）
- サーバー：`household.test.js`・`sharedExpenses.test.js`・`rules.test.js`（「新しく作れるのは」）・`functions.test.js`（送れない種類の見本を `event` から `chore` に）

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | **91**（80＋11） | 実行した（Node） | **91件成功・失敗0・スキップ0** |
| Rules Emulator | 93（81＋12） | 実行できなかった（Firebase の Emulator・npm の取得ができない） | **未実行** |
| Functions Emulator | 46（45＋1） | 実行できなかった | **未実行** |
| アカウント削除 | 26 | 実行できなかった | **未実行** |
| Swift（Xcode） | **499**（469＋30） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |

保証書の Vision の読み取りのテスト（`WarrantyTests` など）は変更していません。Xcode での実行で成功を確かめてください。

### Xcode で失敗した3件のテストの修正（`39ff3ab`。テストだけ。アプリのコードは変更なし）

`a4f26dc` を Mac の Xcode で確かめたとき、テストが3件失敗しました（池上さんの報告）。

| テスト | 原因 | 直し方 |
| --- | --- | --- |
| `Build13SharedBudgetAndEventDeleteTests.testCalendarSourceHasSwipeConfirmationAndVoiceOverAction` | `CalendarView.swift` の説明のコメントに `LifeSwipeDeleteRow` の名前が残っていて、単語の有無の確認が誤って失敗した | 実際の呼び出し `LifeSwipeDeleteRow(` が無いことを確かめる。部品のファイルが無いことの確認は残した |
| `Build14SharedCalendarAndDeleteFixTests.testDeleteButtonSourceIsReliableButton` | 上と同じ | 上と同じ。`.onTapGesture` の確認は `CalendarEventDeleteButton` の範囲だけにし、独自のジェスチャーが無いことの確認を足した |
| `Build14SharedCalendarAndDeleteFixTests.testOnlyExplicitHouseholdChoiceSendsFixedFields` | 決まった項目の `assigneeUID` を、禁止語 `uid` の部分一致で拒否していて矛盾していた | 部分一致の一覧から `uid` だけを外し、実際の UID（`alice`）が値として送られていないことを別に確かめる。決まった項目の完全一致・`assigneeUID == .null`・`createdBy`／`updatedBy == .currentUser` の確認はそのまま |

### Mac での確認結果（2026-11-01、池上さんの報告。3件の修正 `39ff3ab` のあと）

| テスト | 件数 | 結果 |
| --- | --- | --- |
| サーバーの単体テスト | 91 | **成功** |
| Rules Emulator | 93 | **成功** |
| Functions Emulator | 46 | **成功** |
| アカウント削除 | 26 | **成功** |
| サーバーのテストの合計 | **256** | **256件成功・失敗0・スキップ0** |
| Xcode のテスト | 実行件数：未報告（予定は499件） | **Test Succeeded・失敗0**（スキップ数：未報告） |
| Release ビルド | — | **成功** |

- 2台の iPhone での確認（上の12の16項目）：**未実施**
- Firebase への公開（Functions・Rules）・TestFlight へのアップロード：していない
- main への取り込み：していない

### 本番・実機での最終結果（2026-11-01、池上さんの報告）

- Functions：本番へ公開成功（11個すべて成功）
- Firestore Rules：本番へ公開成功（コンパイル・公開とも成功）
- TestFlight：Build 14 をアップロード
- 実機確認：**今回の内容は成功**。予定の追加・共有・削除を確認できた
- 個別16項目の結果と2台それぞれの端末名は未報告のため、推測していない
- 次の改善として「予定の変更（タイトル・日付・終日／時刻）」を Build 15 で行う

## Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 91・Rules 93・Functions 46・アカウント削除 26）
2. Xcode で ⌘U（**499件の予定**・失敗0件）、Release ビルド
3. 上の「2台の iPhone での確認」

## Build

- **14**（アプリとテスト、Debug と Release の4か所）。Version 1.0、`ITSAppUsesNonExemptEncryption = NO`、Bundle Identifier、Associated Domains、Sign in with Apple、App Attest、Push Notifications、アプリアイコンは変更なし
