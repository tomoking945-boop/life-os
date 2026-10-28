# Build 10：使っているうちに重くなる不具合と、「今日」と「やること」の食い違いの修正

2026-10-28。ブランチ `fix-build9-performance-and-todo-consistency`（main の `ba6bd4c` から）。main にはまだ入れていません。
2026-10-29：Instruments の記録で見つかった「端末の文書の保存の嵐」（原因4）の修正を、同じブランチの `c93ee9f` のあとに追加しました。Build は 10 のままです（まだ TestFlight へ公開していないため）。
Firebase（Functions・Firestore のルール・索引・Hosting）への公開、TestFlight へのアップロード、Firebase Console・Apple Developer の変更はしていません。

## 起きていたこと（池上さんの報告）

- TestFlight 1.0（9）。オーナー・パートナーの2台とも、使っているうちに徐々に重くなり、ホーム画面に戻される
- 通常のクラッシュログ・くらしOSの Jetsam の記録は取れていない（添付の Jetsam の記録は、15:34 の YouTube・Safari のもの）
- 再起動すると、しばらく出なくなることがある
- 「今日の流れ」にある未完了の ToDo が、「やること」に無いことがある

## 調べたこと（コードを追った結果）

| 確かめたこと | 結果 |
| --- | --- |
| Firestore の見張り（snapshot listener）を作る場所 | `FirestoreSharedItemsBackend.listen` だけ。呼ぶのは `SharedItemsService.apply` だけ。`apply` を呼ぶのは `MainTabView.applyHousehold` だけ |
| 画面の表示・タブの切り替え・サインイン・わが家の読み直しのたびに増えるか | 増えない。`apply` は同じ groupID なら何もしない。見張りの解除の情報（`RepositoryObservation`）はサービスが1つだけ持ち、groupID が変わる・わが家が無くなるときに解除する |
| 見張りが Store やクロージャを強く持ち続けるか | 持たない（`[weak self]`。Store も弱い参照） |
| Timer・NotificationCenter・Combine | 使っていない。くり返しの Task は「今日」の1分ごとの時刻の更新だけ（画面が消えると止まる） |
| 受信 → Store → 再保存 → 受信 のくり返し | 無い。受け取った一覧で Firestore へ書き込むことは無い（テストで確認） |
| 同じ内容の一覧でも入れ替えて、全画面を描き直していないか | **描き直していた**（原因2） |
| 送信待ちの項目が一覧ごとに増えないか | 増えない（ID で1つにまとめている）。ただし並びが一覧ごとに変わり得た（原因2） |
| 失敗の退避で共有版と個人版が両方残らないか | 残らない（退避のときに共有の一覧と送信待ちから外す） |
| **通知の登録のくり返し** | **くり返していた**（原因1） |
| 通知の登録から共有の同期を始めていないか | 始めていない |

## 特定した原因

### 原因1（重くなる主な原因）：通知の登録が自分自身を呼び続けていた（Build 8 から）

- 場所：`LifeOS/Core/Notifications/SharedPushNotifications.swift`（`ba6bd4c` の `register()` と `apnsTokenDidArrive(_:)`）、`LifeOS/App/AppDelegate.swift`
- 流れ：
  1. `register()` は、呼ばれるたびに `permission.registerForRemoteNotifications()`（APNs への登録）を頼んでいた
  2. iOS は、頼まれるたびに `didRegisterForRemoteNotificationsWithDeviceToken` を呼ぶ → `apnsTokenDidArrive`
  3. `apnsTokenDidArrive` は「状態が登録済みでなければ」`register()` をもう一度始めていた
  4. `register()` は始めるたびに状態を「登録中」にし、Firestore への端末の文書の保存を待つ。保存を待っているあいだに 2 の返事が届くと、また 3 → 1 …
- その結果、「APNs への登録 → 返事 → 登録 → Firestore への保存 …」が止まらず、端末の文書への書き込み（Firestore の送信待ち）・通知用のトークンの取得・APNs の登録が、時間とともに積み重なった。保存に失敗したとき（状態が「失敗」）も同じようにくり返した
- 「共有の通知を受け取る」がオンの端末で起きる（2台とも通知を許可済み）。再起動すると一度リセットされる、という報告とも合う
- ログが取れていないため、実機での確認はまだ。Build 10 で、下の「負荷の確認」を行ってください

### 原因2：同じ内容の一覧でも、毎回画面を描き直していた

- 場所：`LifeOS/Core/Store/LifeStore.swift` の `applyHouseholdSnapshot`、`LifeOS/Core/Sharing/HouseholdItems.swift` の `SharedItemsService`
- Firestore の見張りは、送信待ち → 保存済み などの印の変化でも一覧を届ける（`includeMetadataChanges`）。そのたびに、内容が同じでも共有の一覧を入れ替え、状態（`status`）や種類も書き直していた
- 入れ替えるたびに、開いたことのある「今日・カレンダー・やること・買い物」がすべて描き直される。送信待ちの項目は辞書の順番で並べていたため、同じ内容でも並びが変わり得た
- 通知の設定の画面を開くたび、許可の状態も同じ値で書き直していた

### 原因3：「やること」の「今日」が、今日画面と違う決まり・違う日付で絞っていた

- 場所：`LifeOS/Features/Tasks/TasksViewModel.swift`
- 「やること」の基準の日付（`now`）は、画面を作ったときのまま変わらなかった。アプリは閉じずに裏で動き続けるので、日付が変わると「今日の流れ」（1分ごと・アプリに戻ったときに日付を更新）と「やること・今日」が別の日付になった（新しい日の ToDo は「今後」に入る）
- 「やること」には、今日より前に残っている未完了の ToDo を出す場所が無かった（今日画面の「昨日残ったもの」には出る）

### 原因4（2026-10-29 追加）：保存の返事を待つあいだに、同じ端末の文書の保存を次々に始めていた

- 実機で確かめたこと（池上さんの Instruments、Run 2・35.46秒）：
  - くらしOSの残っているメモリ（Persistent）約 803.88 MiB、止めるまで右肩上がり
  - `firebase::firestore::model::SetMutation::Rep` と `ServerTimestampTransform::Rep` が、どちらも **482,975件** 残っていた（`ResourcePath` は約313万件）
  - `FirestoreDeviceRegistry.save()` は、1回の保存で `setData` と `FieldValue.serverTimestamp()` を1回ずつ使う。2つの数が同じなので、通知の端末の文書の保存が大量に出されていた
- 場所：`LifeOS/Core/Notifications/SharedPushNotifications.swift`（`c93ee9f` の `tokenDidRefresh()` → `saveDevice()`）
- 流れ：
  1. `saveDevice()` は `await registry.save(...)` で Firestore の返事を待つ。待っているあいだは、ほかの処理（次のトークンの更新など）が入れる
  2. 最初の保存が終わるまでは「登録済み」（`hasRegistration`）も「保存した内容」（`lastSavedRecord`）もまだ空
  3. そのため、待っているあいだに届いた呼び出しは、同じトークンでもすべて「まだ保存していない」と判断し、新しい保存を始めていた。返事が遅いほど積み重なる
- `c93ee9f` の修正（原因1）は `register()` を同時に1つにしたが、`tokenDidRefresh()` からの保存は通らない道だったので残っていた。テストの偽物は保存がすぐ終わるため、この状態を作れていなかった

## 変更内容

### 端末の文書の保存（原因4。2026-10-29 追加）

保存の入口を1つ（`saveDevice()` → `performSaves()`）にし、**サーバーへ同時に出す端末の文書の保存は、いつも最大1件**にしました。トークンの更新・画面の表示・アプリに戻る・APNs の返事・項目名の設定が何回来ても同じです。

- 保存を始める前（`await` の前）に、「保存中」と保存する内容（`inFlightRecord`）・世代を記録する
- 保存中に同じ内容が来たら何もしない（何回来ても新しい保存を始めない）
- 保存中に違うトークン・設定が来たら、**最新の1件だけ**を保留する（`pendingRecord`。入れ物は1件だけで、配列に積まない。来るたびに上書き）
- 保存が終わったら、保留した最新の内容が、いま保存したものと違うときだけ、もう1回だけ保存する
- 保存済みと同じ内容なら書かない
- 失敗したら、保留も捨て、自動ではやり直さない。トークンの更新では、失敗した内容と同じものはやり直さない。次にアプリに戻ったとき・画面で操作したときに1回だけ試す（くり返しにならない）
- **世代番号**（`contextGeneration`）：通知のオフ・サインアウト・わが家からの退出・わが家の削除のたびに1つ進め、保留中の保存を捨てる。保存を始めたときと終わったときで世代が違えば、その結果は使わない（「登録済み」に戻さない・保存済みとして覚えない）
- 古い保存が後から成功で返ってきたときは、端末の文書を残さないよう、念のためもう一度消す。Firestore は同じ端末からの書き込みを出した順番どおりに反映するので、保存のあとに出した削除で、消えた状態になる（新しい世代の保存が頼まれていたときは消さず、その新しい内容を1回だけ保存する）
- サインアウトの準備（`prepareForSignOut`）では、最初にサインアウト扱いにする（削除を待つあいだにトークンの更新が来ても、新しい保存を始めない）
- 登録中の印（`isRegistrationInFlight`）も世代ごとにした。古い保存が返ってこないままサインインし直しても、新しい世代の登録を頼める（その保存は、古い保存が終わってから1件ずつ行う）
- 確認用の数（保存の回数・同時に動いている保存の数とその最大・保留の数〔0か1〕）を数だけで持つ。トークン・UID・ID の実際の値は持たない・ログに出さない
- 変えていないもの：端末の文書の形（`fcmToken`・`platform`・`notificationsEnabled`・`sharedUpdatesEnabled`・`showsPreview`・`updatedAt`）、保存先（`users/{uid}/devices/{端末のID}`）、Firestore のルール・Functions・Hosting

### 通知の登録（原因1）

- `register()` は同時に1つだけ（動いているあいだは2つ目を始めない）
- APNs への登録は、1回の起動で1回だけ頼む
- `apnsTokenDidArrive` は、トークンを Firebase Messaging へ渡すだけ。登録の続きは「APNs のトークン待ちで止まっていたとき」だけ1回行い、APNs への登録を頼み直さない
- 端末の文書は、内容（トークン・項目名の表示）が前回と同じなら書かない
- 保存に失敗しても自動でくり返さない（次にアプリに戻ったときに1回だけ試す）
- 登録済み・登録中なら、画面を開いても・アプリに戻っても登録し直さない
- 確認用の回数（APNs への登録・登録の開始・端末の保存）を数だけで持つ（トークン・UID は持たない。外へ送らない）

### 画面の描き直し（原因2）

- 共有の一覧は、受け取った内容が前と同じなら入れ替えない（`householdUpdateCount` で数える）。送信待ちは ID の順に並べ、並びを毎回同じにする
- `SharedItemsService` の状態・種類・参加中の印は、変わったときだけ書く
- 通知の許可の状態は、変わったときだけ書く

### 「今日」と「やること」（原因3）

- `LifeStore.taskItems(dueOn:scope:)` を追加。「やること・今日」はこれを使う。今日画面と同じ正本（`visibleItems`：端末の項目＋わが家の共有項目＋送信待ち。同じ ID は1回だけ）から絞る
- 「やること」「買い物」は、画面を開いたとき・アプリに戻ったときに日付を新しくする（同じ日なら書き込まない）

### 両画面の決まり

| 項目 | 今日（今日の流れ・昨日残ったもの） | やること |
| --- | --- | --- |
| 今日の未完了 ToDo | 出る | 「今日・未完了」に出る |
| 今日より前に残った未完了 ToDo | 「昨日残ったもの」に出る | 「今日・未完了」に出る |
| 今日の完了した ToDo | 出る（完了の表示） | 「今日・完了」に出る |
| 「あとで」で明日以降に回した ToDo | 出ない | 「今後」に出る |
| 「もうやらない」 | 出ない | 出ない |
| 削除した項目 | 出ない | 出ない |
| 習慣 | 習慣の欄 | 出ない |
| すべて／自分／共有 | 同じ切り替え（自分＝個人の項目、共有＝共有の印の項目） | 同じ |
| 共有の送信待ち | 出る（共有マーク） | 出る（共有マーク） |
| 共有に失敗して「自分だけ」に戻した項目 | 「自分」に出る | 「自分」に出る |

## データを失わない理由

- 端末の個人データ（`life-store.json`）の形・中身は変えていない。消す処理・まとめ直す処理も足していない
- 共有の一覧は、同じ内容のときに入れ替えないだけ（内容が変われば、これまでどおり入れ替える）
- 送信待ち・失敗の退避の決まりは Build 9 のまま（消さない・自分だけに残す・理由を出す・2つ作らない・あとで共有し直せる）
- 通知の登録は、書き込む回数を減らしただけ。端末の文書の形は同じ
- 端末の文書の保存を1件ずつにしても、最後に頼まれた内容（最新のトークン・設定）は必ず1回保存する（保留の1件で覚えておく）

## 既存の機能への影響

- 共有 ToDo・買い物の同期、通知の内容・宛先、ローカル通知、わが家の管理：動きは同じ
- 「やること・今日」に、今日より前に残っている未完了の項目も出るようになった（今日画面の「昨日残ったもの」と同じ項目）
- 通知の登録：失敗したとき、すぐにはやり直さず、次にアプリに戻ったときに1回だけ試す
- 端末の文書の保存：保存中に頼まれた新しい内容は、いまの保存が終わってから保存する（すぐには書かない。数秒遅れることがある）

## Firebase の再公開

**不要**。Firestore のルール・Functions・索引・Hosting・データの形は変えていません（ルールや Functions の問題は見つかっていません）。

## テスト

### 追加したテスト（`LifeOSTests/Build10StabilityTests.swift`。16件）

| # | 確かめること | テスト |
| --- | --- | --- |
| 1・14 | 同じ groupID で100回始めても見張りは1つ・見張りは長く生きるサービスだけが持つ | `testSameGroupStartsOneListener`・`testOnlyServiceOwnsListener` |
| 2 | groupID が変わったら古い見張りを外す | `testGroupChangeRemovesOldListener` |
| 3 | サインアウト・退出・削除で見張りが0 | `testLeavingStopsListener` |
| 4・5・6 | 同じ一覧1000回で、項目数・送信待ちが増えず、入れ替え・書き込みが起きない | `testRepeatedSnapshotsDoNotGrowOrRedraw`・`testReceivingNeverWritesBack` |
| 7 | 送信待ちは空・古い一覧で消えない | `testPendingSurvivesEmptyAndStaleSnapshots` |
| 8 | 成功したら送信待ちから1回だけ外れる | `testSuccessClearsPendingOnce` |
| 9 | 失敗したら同じ ID の個人の項目が1件だけ | `testFailureLeavesExactlyOnePersonalCopy` |
| 10 | 今日に出る未完了 ToDo は、やることの「今日」（すべて）にも出る | `testTodayOpenTodosAppearInTasks` |
| 11 | 個人は「自分」、共有は「共有」。両画面で同じ | `testScopesMatchBetweenScreens` |
| 12 | 完了・あとで・もうやらないの決まりが両画面で同じ | `testCompletionPostponeAndDropRules` |
| — | 日付が変わったら、やることの「今日」も変わる | `testTasksTodayFollowsDateChange` |
| 13 | 通知の設定を100回開いても、APNs への登録・端末の保存は1回。登録がくり返されない | `testRegistrationDoesNotLoopOrMultiply` |
| 13 | 保存に失敗しても自動でくり返さない | `testFailedSaveDoesNotRetryInLoop` |
| 13 | 通知の登録から共有の同期を始めない | `testPushDoesNotTouchSharedSync` |

テスト用の偽物（`FakeSharedItemsBackend`）に、見張りの開始・動いている数・解除の回数を、偽物（`FakePushPermission`・`FakePushTokens`・`FakeDeviceRegistry`）に、本物の iOS と同じ「APNs への登録を頼むとすぐに返事が届く」動き・保存の遅れを足しました。既存のテストは削除・スキップしていません。

### 追加したテスト（2026-10-29。`LifeOSTests/PushDeviceSaveCoordinationTests.swift`。14件）

保存を好きなところで止めておける偽物 `PausableDeviceRegistry` を作りました（`finishNext` を呼ぶまで保存が返ってこない。同時に動いている保存の数とその最大を数える。Firestore と同じく、保存のあとに出した削除が勝つ）。

| # | 確かめること | テスト |
| --- | --- | --- |
| 1 | 最初の保存を止めたまま、同じトークンで1000回届いても、始まる保存は1件 | `testSameTokenWhileSavingStartsOnlyOneSave` |
| 2 | トークンの更新・アプリに戻る・許可の読み直し・APNs・項目名の設定が500回入り混じっても、同時に動く保存は最大1件 | `testConcurrentSavesNeverExceedOne` |
| 3 | 保存中に違うトークンが1000回来ても、保存は最初と最後の2回だけ（2回目は最後のトークン） | `testManyDifferentTokensSaveFirstAndLastOnly` |
| 4 | 保存済みと同じ内容が1000回来ても、追加の保存は0回 | `testSavedRecordIsNotRewritten` |
| 5 | 保存中に通知をオフ：終わっても「登録済み」に戻らない・文書が残らない・世代が進む | `testTurningOffDuringSaveDoesNotRegister` |
| 5 | 保存中にわが家から退出（削除も同じ道）：結果を使わない・文書が残らない | `testLeavingHouseholdDuringSaveDiscardsIt` |
| 6 | 保存中にサインアウト：古い結果を使わない・文書が残らない・そのあと保存しない | `testSignOutDuringSaveIgnoresStaleResult` |
| 6 | サインアウトしてすぐサインインし直し：古い保存と同時に保存しない・古い結果で登録済みにしない・新しい登録を消さない | `testStaleSaveAfterSignInAgainKeepsNewRegistration` |
| 7 | 保存に失敗したあと、トークンの更新が大量に来ても自動でやり直さない。アプリに戻ったときに1回だけ | `testFailureDoesNotCauseRetryStorm` |
| 8 | APNs の返事とトークンの更新（1000回）が同時に来ても、保存は1件 | `testAPNsCallbackAndTokenRefreshTogetherSaveOnce` |
| 9 | 保存中に項目名の設定を切り替え・トークンの更新も来た：最後の設定を1回だけ追加で保存 | `testShowsTitleChangeDuringSaveSavesFinalSettingOnce` |
| 9 | 保存中に切り替えてすぐ元に戻した：追加の保存は0回 | `testShowsTitleToggledBackDuringSaveAddsNoSave` |
| 10 | 保留はいつも0か1件（1000回の途中でも） | `testPendingIsSingleSlot` |
| 10 | ソースでも、保留が1件の入れ物で配列に積んでいない・保存の入口が1か所 | `testSourceKeepsSingleSlotWithoutQueue` |

既存のテスト（`SharedPushNotificationTests.swift`・`Build10StabilityTests.swift` など）は変えていません（削除・スキップ・必ず成功する形にはしていません）。

### 結果

| テスト | 件数 | この作業環境 | 結果 |
| --- | --- | --- | --- |
| サーバーの単体テスト | 74 | 実行した（Node 22） | **74件成功・失敗0・スキップ0** |
| Rules Emulator | 70 | 実行できなかった（変更なし） | 未実行 |
| Functions Emulator | 43 | 実行できなかった（変更なし） | 未実行 |
| アカウント削除 | 20 | 実行できなかった（変更なし） | 未実行 |
| Swift（Xcode） | **415**（385＋16＋14） | 実行できなかった（Xcode が無い） | **未実行・未確認**（全 Swift ファイルの簡易の字句チェックだけ実行。問題なし） |
| Release ビルド | — | 実行できなかった | **未確認** |
| Instruments（Allocations・Leaks・Time Profiler） | — | 実行できなかった（Xcode が無い） | **未確認**（原因4の修正のあとの記録は、まだ無い） |

サーバーの単体テストは、2026-10-29（原因4の修正のあと）にも実行し、74件成功・失敗0・スキップ0でした。サーバー側（ルール・Functions）は変えていません。

## Mac での確認（池上さん）

1. `firebase/functions` で `npm test`（目安：単体 74・Rules 70・Functions 43・アカウント削除 20）
2. Xcode で ⌘U（**415件の予定**・失敗0件）、Release ビルド
3. 負荷の確認（Instruments。実機がおすすめ。共有の通知をオンにした状態で）
   1. Xcode のメニュー Product → Profile（⌘I）→「Allocations」を選ぶ
   2. 記録を始め、10分間、今日 → やること → 買い物 → プロフィール → わが家の設定 を行き来する。あいだに、2台の両方から共有の ToDo・買い物を追加・名前の変更をする
   3. グラフ（All Heap & Anonymous VM）が右肩上がりに増え続けないこと。操作をやめると平らになること
   4. 同じ手順を「Leaks」で行い、赤い印（リーク）が増え続けないこと
   5. 「Time Profiler」で、操作をやめたあと CPU の使用率が落ち着くこと（ずっと高いままにならない）
   6. 比べるため、Build 9 でも同じ手順を行うと、違いが分かりやすい（Build 9 は通知の登録がくり返されるため、通知をオンにした端末で増え方が大きいはず）
4. 端末の文書の保存の嵐が止まったかの確認（原因4。実機で、Allocations を15〜30秒）
   1. 実機をつなぎ、Xcode でこのブランチの Build 10 を選ぶ。「共有の通知を受け取る」をオンにしておく（前の記録と同じ条件）
   2. Product → Profile（⌘I）→「Allocations」を選び、記録を始める
   3. 15〜30秒、前の Run 2 と同じ操作をする（アプリを開く → 今日 → やること → プロフィール → わが家の設定 → 通知の設定を開く。いったんホーム画面へ戻ってまた開く）
   4. 記録を止め、下の検索欄（Filter）に次の名前を入れて、「Persistent」（残っている数）を見る
      - `SetMutation` … **数件〜数十件で止まる**こと（前は 482,975件）
      - `ServerTimestampTransform` … `SetMutation` と同じくらいの少ない数で止まること
      - `ResourcePath` … 前（約313万件）のように増え続けないこと
   5. グラフ（All Heap & Anonymous VM）が、操作をやめると平らになること。Persistent のメモリが 803 MiB のように右肩上がりにならないこと
   6. 記録のスクリーンショット（数のところだけ）を残してください。トークン・UID・メールアドレスが写る画面（通知の設定の詳しい情報など）は写さないでください

## 2台の iPhone での確認（A：オーナー、B：パートナー）

1. 2台とも Build 10 を入れ、「共有の通知を受け取る」をオンにしたまま、30分ほどふつうに使う（今日・やること・買い物・わが家の設定を行き来）→ 重くならない・ホーム画面に戻されない
2. A・B で共有の ToDo・買い物を追加・名前の変更 → 相手に出る・通知が届く（自分には届かない）
3. 今日の流れにある未完了の ToDo が、「やること」の「今日」（すべて）にも出る。昨日から残っている ToDo も「やること・今日」に出る
4. 「自分」「共有」に切り替えて、両画面で同じ項目が出る
5. 夜をまたいでアプリを開いたままにし、翌朝「やること・今日」が今日の日付の項目になっている
6. 機内モードで共有の ToDo を追加 → 消えない → 戻すと相手に出る（1件だけ）

## 問題があったときの戻し方

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- main に入れたあとで戻すときは、取り込みの commit を `git revert` する
- アプリ：TestFlight で前の Build を配る（ただし Build 8・9 は通知の登録がくり返されるため、戻すなら「共有の通知を受け取る」をオフにして使う）
- サーバーは変えていないので、戻す作業は無い

## Build

- Build 9 → **10**（アプリとテスト、Debug と Release の4か所）。Version 1.0、`ITSAppUsesNonExemptEncryption = NO`、Bundle Identifier、Associated Domains、Sign in with Apple、App Attest、Push Notifications は変更なし
