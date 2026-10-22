# Firestore 共有ルールの監査（2026-10-20）

作業用ブランチ：`audit-firestore-sharing-rules`（main `4cec290` から作成。**main にはまだ入れていない**）

## 概要

- 監査した日：2026-10-20
- 基準の commit：`4cec290`（main）
- 対象：`firestore.rules`、`firestore.indexes.json`、`firebase.json`、`firebase/functions/`（テストを含む）、アプリの Firebase の起動の設定
- 結論：**`firestore.rules` 本体に問題は見つからなかったので変えていない**。足りなかったテストを足し、招待の Functions に App Check を必須にし、招待リンクの設定ファイルの Team ID を書き換えた
- 本番の Firebase（Firestore のルール・Functions・Hosting・Console の設定）には何も送っていない・変えていない

## 今の本番の状態（2026-10-20 時点、池上さんの確認）

| 項目 | 状態 |
| --- | --- |
| Authentication の App Check 強制適用 | **有効** |
| Firestore の App Check 強制適用 | **まだ無効** |
| Firebase Console の Firestore のルール | **すべて拒否**（このリポジトリの `firestore.rules` はまだ送っていない） |
| Cloud Functions | **未 deploy** |
| Hosting（招待リンクのドメイン） | **未 deploy** |
| Firestore の生活データ | **無し**（アプリは Firestore に何も書かない。テストで確認） |

## 監査項目と結果

### Firestore のルール

| 項目 | 結果 | ルールでの根拠 | テスト |
| --- | --- | --- | --- |
| サインインしていない人を拒否 | ✅ | すべての許可が `signedIn()`（`request.auth != null`）を含む | 読み取り（既存）・書き込み・グループ作成（今回追加） |
| メンバーでない人は、グループ・メンバー・共有項目を読めない | ✅ | `isMember(groupID)` = 自分の UID の `members` が在るときだけ | 既存 |
| 個人項目の保存場所が無い | ✅ | 書かれている場所は `users/{uid}`・`users/{uid}/devices`・`groups/{g}`・`members`・`items`・`invites`（拒否）だけ。それ以外は自動的にすべて拒否 | 今回追加（ルールに無い場所・個人データらしい場所） |
| 予定・ToDo・家事・買い物以外を拒否 | ✅ | `kind in ['event', 'todo', 'chore', 'shopping']` | 既存（支払予定・習慣） |
| owner への昇格ができない | ✅ | `members` の更新は `false`。自分で owner を作れるのは「まだ無いグループを、同じ書き込みで作るとき」だけ（2026-10-22 から、アプリからは作れない。作成は createHousehold だけ → [わが家の作成・招待・参加](FIREBASE_INVITE_JOIN_MEMBERSHIP.md)） | 既存（役割の変更）・今回追加（退出して owner で戻る） |
| 招待をアプリから作れない・使えない | ✅ | `invites` は読み書きとも `false`。メンバーの追加も `false`（acceptInvite だけが管理者として追加） | 既存 |
| 他人の端末トークンを読めない・書けない | ✅ | `devices` は `isSelf(uid)` だけ | 既存 |
| `createdBy`・`createdAt` を変えられない | ✅ | 作成時は本人の UID・サーバーの時刻。更新時は元の値と同じでなければ拒否 | `createdBy`（既存）・`createdAt`（今回追加） |
| `updatedBy` を他人の UID にできない | ✅ | `validItem` の `data.updatedBy == request.auth.uid`（作成・更新とも） | 更新（既存）・作成（今回追加） |
| 担当者の UID はメンバーか null | ✅ | `assigneeUID == null` か、その UID の `members` が在る | 作成（既存）・更新・退出した人（今回追加） |

すべて **Firebase Authentication の UID（`request.auth.uid`）** で判断している。アプリが送る名前や端末の情報は判断に使わない。

### Firebase の設定との整合性

| 項目 | 結果 | 確認した場所 |
| --- | --- | --- |
| Bundle Identifier がすべて `com.tomoking945boop.lifeos` | ✅（アプリの Debug・Release とも。テストは `com.tomoking945boop.lifeos.tests`） | `LifeOS.xcodeproj/project.pbxproj` |
| `GoogleService-Info.plist` の Bundle ID が一致 | ✅ `com.tomoking945boop.lifeos`。起動時にも一致を確かめ、違えば Firebase を設定しない | `LifeOS/GoogleService-Info.plist`・`FirebaseBootstrap.swift` の `loadValidOptions` |
| App Check を Firebase の設定より先に設定する | ✅ `installAppCheckProviderFactory` → `configure` の順 | `FirebaseBootstrap.run`・`AppCheckTests`（順番のテスト） |
| Debug は Debug Provider、Release は App Attest | ✅ | `AppCheckProviderPolicy`・`KurashiAppCheckProviderFactory`・`AppCheckTests` |
| App Attest の環境 | ✅ `production` | `LifeOS.entitlements` |
| Authentication の App Check 強制適用は有効 | ✅（Console。池上さんの確認） | — |
| Firestore の App Check 強制適用はまだ無効 | ✅（Console。池上さんの確認） | — |
| Firestore のルールは Authentication の UID を使う | ✅ | `firestore.rules` |
| アプリは Firestore を使っていない | ✅ | `NoFirestoreWritesTests`（ソースに `import FirebaseFirestore` や書き込みが無い） |

## App Check と Security Rules の役割（両方必要）

| | App Check | Security Rules（＋Authentication） |
| --- | --- | --- |
| 確かめること | 通信が **本物のくらしOSアプリ・本物の端末** から来たか | **誰が**（どの UID が）**何を**読み書きしてよいか |
| 防ぐもの | アプリを使わない機械的な呼び出し、偽のアプリ、スクリプトからの大量アクセス | 他人のグループの読み取り、権限の昇格、決まっていないデータの保存 |
| 防げないもの | 本物のアプリを使う、サインインした人のやりすぎ（他人のデータを見ようとするなど） | 本物のアプリ以外からでも、サインインさえしていれば、ルールの範囲で読み書きできる |

App Check は「どのアプリか」、Security Rules は「どの人か・何をしてよいか」を確かめる。**App Check だけでは誰のデータかを判断できず、ルールだけでは偽のアプリからの呼び出しを止められない**。だから両方を使う。招待の Functions も同じで、App Check（`enforceAppCheck: true`）とサインインの確認（`requireUID`）の両方を行う。

## 今回の変更

### 追加した Rules Emulator のテスト（`firebase/functions/test/emulator/rules.test.js`、19件 → 33件）

「監査（2026-10-20）」の describe にまとめた14件：

1. サインインしていない人：グループ・メンバー・利用者情報・端末も読めない
2. サインインしていない人：共有項目・メンバー・グループ・利用者情報・端末・招待に書き込めない（作成・更新・削除）
3. サインインしていない人：生活グループを作れない（自分を owner にする同じ書き込みでも）
4. ルールに無い場所（`personalItems`、`users/{uid}/items`、`groups/{g}/personal`、共有項目の下）は本人・メンバーでも読み書きできない
5. グループをまたいだ一括検索（collection group：`items`・`members`・`devices`）はできない
6. 支払・習慣・保証書・お金・メモ・写真の場所は、いちばん上・本人の下・グループの下のどこにも作れない
7. 共有項目に、決まっていない項目（金額・場所・写真・メモ・個人の印・非公開の印）を、作成でも更新でも足せない
8. 利用者情報・グループ・メンバー・端末にも、決まっていない項目を足せない
9. 退出した人は、owner としても member としても戻れない（グループを作り直すふりも拒否）
10. owner も一度退出すると戻れない
11. 更新で `createdAt` を変えられない（サーバーの時刻でも、端末の時刻でも）
12. 作成のとき `updatedBy` を他人の UID にできない（本人なら作れることも確認）
13. 更新で担当者をメンバーでない人・存在しない人・文字でない値に変えられない（メンバー・null には変えられる）
14. 退出した人は担当者に設定できない

### 招待の Functions の App Check（`firebase/functions/index.js`）

- `createInvite`・`acceptInvite` を `onCall({ enforceAppCheck: true }, …)` に変更（Firebase Functions v2 の正式な設定）
- App Check の情報が無い・正しくない呼び出しは、関数の中に入る前に `unauthenticated` で断られる
- サインインの確認（`requireUID`）はこれまでどおり。App Check があってもサインインしていなければ断る
- `onSharedItemWritten` は Firestore のトリガー（アプリから直接呼ばれない）なので対象外
- 使い捨てのトークン（`consumeAppCheckToken`。同じトークンの使い回しを防ぐ）は、アプリ側で limited-use トークンを取る必要があるため、今回は使わない（次段階）

追加したテスト：

- Functions Emulator（`test/emulator/functions.test.js`、9件 → 13件）
  - App Check の情報が無いと、サインインしていても招待を発行できない（招待は作られない）
  - App Check の情報が無いと、サインインしていても招待を使えない（メンバーに追加されず、招待は未使用のまま。App Check を付ければ同じ招待が使える）
  - App Check の情報だけでは、サインインしたことにならない
  - App Check もサインインも無い呼び出しは断られる
  - 既存の招待のテストは、正規のアプリと同じく App Check の情報を付けて呼ぶように変更
- 単体（`test/unit/appCheck.test.js`、新規3件。20件 → 23件）
  - 2つの招待の Callable が `enforceAppCheck: true` で作られている。App Check を必須にしない Callable が増えていない
  - サインインの確認を省いていない
  - `onSharedItemWritten` は Firestore のトリガー

Emulator での App Check について：Functions Emulator は App Check の **署名を確かめない**（Firebase の公式の動き。`firebase-functions` が Emulator のときだけ署名の確認を省く）。そのため Emulator のテストで確かめられるのは「App Check の情報が無い呼び出しを断る」ことまで。偽の情報を本番が断ることは、本番の Firebase が確かめる。テストで使う値は、テストの中で作った署名なしの偽物で、本物のアプリ ID や Debug Token とは関係ない。

### 招待リンク（Universal Links）の Team ID

`firebase/hosting/.well-known/apple-app-site-association`：

- 変更前：`TEAMID.com.tomoking945boop.lifeos`
- 変更後：`A8D9YY866R.com.tomoking945boop.lifeos`

Team ID と Bundle ID は公開してよい識別情報。Hosting へはまだ送っていない。アプリで招待リンクを開くには、このほかにアプリ側の Associated Domains（`applinks:` の設定）が必要で、それは招待画面を作るときに追加する。

### そのほか

- `docs/FIREBASE_SETUP.md`：B-10 の Team ID の TODO を「書き換え済み」に、A-4 のテストの説明に今回の内容を追加
- `README.md`：本書へのリンク
- 変えていないもの：`firestore.rules`、`firestore.indexes.json`、`firebase.json`、アプリのコード・設定、Version 1.0／Build 4、Firebase Console の設定

## 本番に deploy したあとに許可される操作

（`firestore.rules`・Functions を送ったあと。いまは Console のルールが全拒否なので、どれもできない）

- サインインした本人：自分の `users/{uid}`（表示名など決まった4項目）と、自分の端末（`devices`）の読み書き
- サインインした人：新しい生活グループを、自分を owner にする同じ書き込みで作る（→ 2026-10-22 から、アプリからは作れない。Cloud Function の createHousehold だけが作る。[わが家の作成・招待・参加](FIREBASE_INVITE_JOIN_MEMBERSHIP.md)）
- メンバー：自分のグループ・メンバー一覧・共有項目を読む
- メンバー：決まった形の共有項目（予定・ToDo・家事・買い物）を作る・更新する・削除する
- メンバー：グループの名前を変える、自分が退出する
- 招待（Functions 経由、正規のアプリ＋サインイン）：メンバーが招待を発行し、招待された人が一度だけ使って member として参加する
- 共有項目が変わったら、操作した本人以外のメンバーの、通知を許可した端末に通知が届く（Functions）

## 引き続き拒否される操作

- サインインしていない人のすべての読み書き
- メンバーでない人の、グループ・メンバー・共有項目の読み書き
- 役割（owner／member）の変更、自分や他人をメンバーに追加すること（招待の Function を除く）、退出したあと戻ること
- ほかのメンバーを外すこと（自分の退出だけ）
- グループの削除、作成者・作成日時の変更
- 共有できない種類（支払予定・習慣など）、決まっていない項目、ルールに無い場所への保存
- 他人の UID を作成者・更新者にすること、メンバーでない人を担当者にすること
- 招待（`invites`）・通知の記録（`notificationLog`）の、アプリからの読み書き
- 他人の利用者情報・端末トークンの読み書き
- グループをまたいだ一括検索
- App Check の情報が無い、招待の Functions の呼び出し

## 個人項目が保存されない根拠

1. **ルールに置き場所が無い**：Firestore のルールは、書かれていない場所をすべて拒否する。書かれているのは利用者情報・端末・生活グループ・メンバー・共有項目・招待（拒否）だけ
2. **共有項目は決まった項目だけ**：`hasOnly` で12の項目以外を拒否し、種類も予定・ToDo・家事・買い物の4つだけ。金額・メモ・写真・場所・個人の印は入らない
3. **利用者情報・端末も決まった項目だけ**：利用者情報は表示名など4項目、端末は通知の設定とトークンだけ
4. **アプリが送らない**：iPhone アプリには Firestore に書き込む処理が無い（`NoFirestoreWritesTests` で確認）。保証書・お金・習慣・個人の予定などは端末の中だけ
5. **テストで確認**：上の1〜3を Rules Emulator のテストで確かめる（今回の追加分を含む）

## アカウント削除のあとの整理（未実装）

アプリの「アカウントを削除」は Firebase Authentication の利用者を消すが、**Firestore の `groups/{g}/members/{uid}`・`users/{uid}`・`users/{uid}/devices` は残る**。いまは Firestore に何も保存していないので影響はないが、共有を始める前に、Authentication の利用者の削除をきっかけに整理する Function か、削除の前の整理を用意する（下の「次段階で決めること」）。

## 次段階で決めること（今回は実装しない）

| 項目 | 今回実装しない理由 |
| --- | --- |
| アカウント削除時の Firestore の整理 | 共有グループを使い始めるまでは残るデータが無い。owner が消えるときの扱い（下の所有権の移行）と一緒に決める必要がある（→ 2026-10-20 にブランチ `firebase-account-deletion-cleanup` で実装：[FIREBASE_ACCOUNT_DELETION_CLEANUP.md](FIREBASE_ACCOUNT_DELETION_CLEANUP.md)） |
| owner が削除・退出するときの所有権の移行 | 誰に移すか（自動・選ぶ）、メンバーがいなくなったグループをどうするかを決めてから作る |
| グループの人数の上限 | 家族・パートナーで何人まで使うかの仕様がまだ決まっていない |
| owner がメンバーを外す機能 | 外された人のデータや通知の扱いを含め、画面と一緒に決める |
| 誰が招待を作れるか（いまはメンバー全員） | owner だけにするかは、家族での使い方を決めてから |
| App Check の使い捨てトークン（`consumeAppCheckToken`） | アプリ側で limited-use トークンを取る処理が必要。招待画面を作るときに合わせる |
| アプリの Associated Domains（招待リンクを開く設定） | 招待画面が無いいまは開く先が無い |
| iPhone アプリからの Firestore の読み書き | 生活データを送り始めるのは、上の仕様と、Firestore の App Check 強制適用の判断が済んでから |
| 招待画面・同期画面 | 上の仕様が決まってから |
| Firestore・Functions・Hosting への deploy | ルールとテストの確認（Mac での Emulator テスト）が済み、池上さんが判断してから。deploy してもアプリが Firestore を使わないので生活データは増えない |
| Firestore の App Check 強制適用 | アプリが Firestore を使い始め、App Check の指標で「確認済み」がほぼすべてになってから |

**現在 Firestore に生活データは無いため、どれを後に回しても、いまの利用者への影響はない。**

## テストの結果

### Mac での確認結果（2026-10-20 池上さん・commit `be42adf`・`npm test`）

| テスト | 件数 | 失敗 | スキップ | 結果 |
| --- | --- | --- | --- | --- |
| サーバー単体テスト（`test:unit`） | 23 | 0 | 0 | 成功 |
| Rules Emulator（`test:rules`） | 33 | 0 | 0 | 成功 |
| Functions Emulator（`test:functions`） | 13 | 0 | 0 | 成功 |
| **合計** | **69** | **0** | **0** | **すべて成功** |

テストの途中に出る `PERMISSION_DENIED` の表示は、「拒否されること」を確かめるテストで出る想定どおりの出力（失敗ではない）。

この結果を記録したあとの変更は本書だけで、アプリ・`firestore.rules`・Functions・テストの中身は `be42adf` から変えていない。Firebase（Firestore のルール・Functions・Hosting）へはまだ deploy していない。

### 作業環境での実行（参考）

| テスト | この環境で | 結果 |
| --- | --- | --- |
| サーバー単体テスト（`npm run test:unit`） | 実行した | 23件すべて成功（`# pass 23`・`# fail 0`） |
| Rules Emulator・Functions Emulator | 実行できなかった | 上の Mac の結果で確認 |

この作業環境では、Firebase のテストの道具（`firebase-tools`・`@firebase/rules-unit-testing`）を取りに行く npm の配布元につながらない（通信が許可されていない）ため、Emulator を動かせなかった。そのため Emulator のテストは Mac で実行した。

### Mac で実行する手順

（もう一度確かめるときの手順）

1. GitHub でブランチ `audit-firestore-sharing-rules` を選び、ZIP でダウンロードして展開する（または、いつもの life-os のフォルダをこのブランチの中身にする）
2. ターミナルで、展開したフォルダの `firebase/functions` に移動する（例：`cd ~/Downloads/life-os-audit-firestore-sharing-rules/firebase/functions`）
3. `npm install`（初回やダウンロードし直したとき。最後に `added … packages`）
4. `npm test`
5. 3種類（単体 → Rules → Functions）が順に動く。それぞれの最後に `# fail 0` が出れば成功。件数の目安：単体 `# tests 23`、Rules `# tests 33`、Functions `# tests 13`
6. 失敗が出たら、出てきた文をそのまま送ってください

（Java と Node.js は、2026-10-11 のテストで使ったものがそのまま使える。Firebase へのログインや deploy は不要で、テストは手元の Emulator だけで動き、本番の Firebase には触れない）

## 元に戻す方法

- このブランチは main に入れていない。やめる場合はブランチを使わなければよい
- main に入れたあとで戻すときは、取り込みの commit を `git revert` する。または：
  - `firebase/functions/index.js` の `onCall({ enforceAppCheck: true }, …)` を `onCall(…)` に戻す（`test/unit/appCheck.test.js` も消す）
  - `apple-app-site-association` の Team ID を戻す
  - 追加したテストは消しても本番の動きには関係しない
- deploy したあとで招待の Functions の App Check を外す必要が出たら、上の変更を戻して Functions を送り直す
- `firestore.rules` は今回変えていないので、戻すものは無い
