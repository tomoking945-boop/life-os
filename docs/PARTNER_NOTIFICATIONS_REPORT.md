# パートナー共有・通知：実装の報告

正本の仕様：[PARTNER_NOTIFICATIONS_IMPLEMENTATION.md](PARTNER_NOTIFICATIONS_IMPLEMENTATION.md)
設定の手順：[FIREBASE_SETUP.md](FIREBASE_SETUP.md)

## 進め方（2段階）

本物の Firebase・Apple の設定（プロジェクト、`GoogleService-Info.plist`、APNs の鍵、実機2台）がまだ無いため、2段階に分けています。

| 段階 | 内容 | 状態 |
| --- | --- | --- |
| 第1段階（2026-10-11） | サーバー側（Security Rules・Cloud Functions・Emulator テスト）と、iPhone 側の Firebase を使わない部分、設定手順書 | 実装済み。Mac でのビルド・テストは未確認 |
| 第2段階 | Firebase SDK の追加、Sign in with Apple、Firestore との同期、FCM トークン、通知タップ、移行の画面、Mock の参加済みの置き換え | 池上さんの Firebase 設定が済んでから |

**2026-10-13 時点：一時停止中。** 第1段階は完了（Mac で Emulator テスト48件すべて成功）。次は [FIREBASE_SETUP.md](FIREBASE_SETUP.md) の B-1（Bundle Identifier を決める）から。Apple Developer Program の登録と Firebase の Blaze プランが必要なため、池上さんの準備ができてから再開する。

外部設定が無い状態でもアプリは起動し、これまでどおり端末内だけで動きます（第1段階では iPhone アプリはネットワークに一切つながりません）。

## 仕様の実装順と対応

| 手順 | 内容 | 第1段階 | 残り（第2段階） |
| --- | --- | --- | --- |
| 1 | Repository の非同期・監視 API（後方互換） | `observeItems`・`addAsync` などを追加。既存の窓口は変えていない | Remote / Hybrid の実装 |
| 2 | Firebase Auth + Sign in with Apple | — | すべて（設定ファイルが無いときは端末内のみで動く作り） |
| 3 | 個人は端末・共有は Firestore | 送ってよい項目の選別（`SharedSyncPolicy`）と、送る形（`SharedItemRecord`） | `RemoteLifeItemRepository`・`HybridLifeItemRepository` |
| 4 | Security Rules と Rules テスト | `firestore.rules`・`rules.test.js` | Mac で Emulator テストを実行 |
| 5 | 招待の Function + Universal Link | `createInvite`・`acceptInvite`、リンクの読み取り（`InviteLink`）、AASA の雛形 | アプリで招待を作る・受ける画面、Team ID の書き換え |
| 6 | APNs/FCM トークン登録 + 通知 Function | `onSharedItemWritten`、端末トークンの保存場所とルール | アプリでのトークン登録・ログアウト時の削除 |
| 7 | 通知タップ・通知設定・内容表示 | 通知の data の読み取り（`SharedItemRoute`）、「共有の更新」を本物の参加まで無効 | タップで項目を開く、内容表示の設定の画面 |
| 8 | Mock の参加済み・ダミー招待を置き換え | `verifiedSharedMemberCount` を用意 | メンバー監視の結果で置き換え |
| 9 | 承認つきの一度きりの移行 | 移行の対象選び（`SharedMigrationPlan`） | プレビューと「共有を開始」の画面、アップロード |

## 変更したファイル

新規
- `firestore.rules`、`firestore.indexes.json`、`firebase.json`、`.firebaserc.example`、`.gitignore`
- `firebase/functions/`：`index.js`、`package.json`、`.env.demo-lifeos`（Emulator 用。秘密の情報は無し）、`src/`（`notificationPolicy.js`・`throttle.js`・`invites.js`・`recipients.js`・`timestamps.js`）、`test/unit/`（4ファイル・20件）、`test/emulator/`（`rules.test.js`・`functions.test.js`）
- `firebase/hosting/`：`.well-known/apple-app-site-association`（Team ID は TODO）、`invite/index.html`（アプリが無いときの案内）
- `LifeOS/Core/Sharing/`：`SharedSyncPolicy.swift`、`SharedItemRecord.swift`、`SharedLinks.swift`、`SharedMigrationPlan.swift`
- `LifeOSTests/PartnerSharingTests.swift`（13件）
- docs：`PARTNER_NOTIFICATIONS_IMPLEMENTATION.md`（受け取った仕様書をそのまま）、`FIREBASE_SETUP.md`、本書

変更
- `LifeOS/Core/Repositories/Repositories.swift`：非同期の窓口（既定の実装つき）、`RepositoryObservation`、`RepositoryError`
- `LifeOS/Core/Store/LifeStore.swift`：`observeItems`（保存のたびに知らせる）
- `LifeOS/App/AppState.swift`：`verifiedSharedMemberCount`・`canUseSharedUpdates`（保存しない）
- `LifeOS/Features/Profile/NotificationSettingsView.swift`：「共有の更新」を本物の参加まで無効にし、理由を表示
- `README.md`、`docs/IMPLEMENTATION_NOTES.md`、`docs/AFTER_CALM_FUTURE.md`

## データの流れ（第2段階まで完成したとき）

1. Aさんが共有の予定を追加 → 端末内に保存（これまでどおり）
2. 共有できる項目（共有・予定/ToDo/家事/買い物）だけを `SharedItemRecord` にして `groups/{groupID}/items/{itemID}` へ書く（ID は元の UUID）
3. Security Rules が「メンバーか・決まった項目だけか・種類は正しいか・作成者を偽っていないか」を確認
4. `onSharedItemWritten` が「通知するか」を判定（追加・予定の日時変更だけ。完了だけの変更は送らない）→ 30秒以内の同じ項目はまとめる → 操作した本人の全端末と通知 OFF の端末を除く → FCM（APNs）で送信 → 使えなくなったトークンの端末を削除
5. Bさんの端末は Firestore の変更を受け取り、端末内に反映。通知には `groupID`・`itemID`・`type` だけが入り、タップで項目を開く

招待：メンバーが `createInvite` → 24時間有効・一度だけのトークン（Firestore にはハッシュだけ）→ リンクを相手に送る → 相手のアプリが `acceptInvite` → トランザクションで使用済みにしてメンバー追加。

## Security Rules の要点

- 読めるのは、自分が所属する生活グループだけ（`members/{自分の uid}` があるか）
- 共有項目の作成・更新はメンバーだけ。項目名（キー）は決まったものだけ、種類は event/todo/chore/shopping だけ、`updatedBy` は自分、時刻はサーバーの時刻、作成者・作成日時は後から変えられない、担当はメンバーの uid か null
- メンバーの追加は Function（`acceptInvite`）だけ。アプリからできるのは「自分で新しく作るグループの owner になる」ことだけ
- 役割の変更（権限の昇格）は誰にもできない。退出は自分のメンバー情報を消すことでできる
- グループの削除は不可、変えられるのは名前だけ
- 端末トークンは本人だけが登録・削除できる（決まった項目だけ）
- 招待（`invites`）と通知の記録（`notificationLog`）は、アプリから読み書きできない

## 個人情報が外部へ出ない根拠

- 第1段階の iPhone アプリは、Firebase のライブラリを入れておらず、ネットワークにつながらない
- 第2段階でも、Firestore へ送る形 `SharedItemRecord` は、個人項目からは作れない（`init` が nil）。テストで全種類の個人項目を確認
- 送る形に、柔らかい時間・暮らしメモリーとのつながり・持ち主の区別は入らない（テストで確認）
- 支払予定・習慣は共有でも送らない（下の「解釈」）
- サーバーのルールも、共有の4種類・決まった項目しか受け付けない
- 通知の本文は、初期値では「共有情報が更新されました」だけ（項目名は内容表示を許可した端末だけ）。通知の data に項目名は入れない
- 秘密の鍵・設定ファイルは `.gitignore` で除外。リポジトリには入っていない

## 新しい解釈・TODO

- 新しい解釈：共有するのは予定・ToDo・家事・買い物だけ（仕様の目的の4つ）。支払予定・習慣は共有でも端末内のまま（TODO：共有するかは今後決める）
- 新しい解釈：内容表示の許可は端末ごと（`users/{uid}/devices` に `showsPreview` を追加。初期値は表示しない）
- 新しい解釈：移行完了フラグをユーザー情報に保存するため `users/{uid}` に `sharedMigrationCompletedAt` を追加
- 新しい解釈：「もうやらない」にした項目は移行しない
- 新しい解釈：招待に `createdAt` も保存（いつ作られたか分かるように）
- 新しい解釈：完了だけの変更は通知しない（仕様の初期値どおり。通知する設定は作っていない）
- TODO：生活グループの人数の上限（いまは制限なし）
- TODO：Bundle Identifier が `com.example.LifeOS` のまま。本物の ID が決まったら、プロジェクトと AASA を書き換える
- 仕様との違い：仕様「2. 現在の状態」の「予定10分前と当日20時の端末内通知」と「共有の更新が無効」は、GitHub の main にはありませんでした。端末内通知は今回作っていません（仕様の範囲外のため）。「共有の更新」スイッチは今回、本物の参加まで無効にしました

## テスト

| テスト | 件数 | 結果 |
| --- | --- | --- |
| サーバーの単体テスト（`npm run test:unit`） | 20件 | この環境で実行：すべて成功。2026-10-11 池上さんの Mac でも20件すべて成功 |
| Rules Emulator（`npm run test:rules`） | 19件 | 2026-10-11 池上さんの Mac で実行：すべて成功（fail 0） |
| Functions Emulator（`npm run test:functions`） | 9件 | 2026-10-11 池上さんの Mac で実行：すべて成功（fail 0） |
| XCTest（既存156件＋新規13件） | 169件 | この環境では未実行（Xcode が無いため）。2026-10-11 池上さんから「テスト完了」の報告あり（件数・成功数の記録は未確認） |
| 実機2台（招待・参加・双方向同期・通知・タップ・ログアウト後の停止） | — | 第2段階のあと |

`package-lock.json` はこの環境で作れなかったため入っていません（Mac で `npm install` すると作られます。コミットしてかまいません）。

### Mac での実行環境（2026-10-11）

Node.js v24.21.0、Java（Temurin）25.0.4.1。`npm test` の途中に出る赤い `PERMISSION_DENIED` は、テストがわざと禁止された書き込みを試して、ルールが拒否したことの記録（想定どおり）。

出た警告と扱い：
- `package.json` の Node 指定（20）と Mac の Node（24）が違う → テストは Node 24 で成功。TODO（第2段階）：本番で使う Node のバージョン（22 など）を決めて合わせる（→ 2026-10-20 に Node 22 に決定・変更。[FIREBASE_ACCOUNT_DELETION_CLEANUP.md](FIREBASE_ACCOUNT_DELETION_CLEANUP.md)）
- `firebase-functions` が古い → TODO（第2段階）：更新を検討（大きな変更があるため、テストし直してから）
- `npm audit` の脆弱性の表示 → テスト用の道具（firebase-tools など）の中の部品。アプリには入らない。第2段階で依存を更新するときに見直す
