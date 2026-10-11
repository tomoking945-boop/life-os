# パートナー共有・通知 実装仕様（正本）

2026-10-11 に受け取った仕様書をそのまま保存しています。実装の進み具合と解釈は [PARTNER_NOTIFICATIONS_REPORT.md](PARTNER_NOTIFICATIONS_REPORT.md)、設定の手順は [FIREBASE_SETUP.md](FIREBASE_SETUP.md)。

---


更新日：2026-10-11

## 1. 目的

共有の予定・ToDo・買い物・家事が追加または変更されたとき、同じ生活グループの相手の端末へ安全に反映し、必要な更新だけをPush通知する。

個人項目は端末外へ送らず、通知対象にも絶対に含めない。AIはこの機能では使用しない。

## 2. 現在の状態

- 予定10分前と当日20時の未完了タスク通知は、端末内通知として実装済み。
- `Ownership.shared`、共有画面、招待画面、参加済み状態はMock。
- 保存先は端末内JSONで、別のiPhoneとは同期されない。
- 「共有の更新」スイッチは、誤認防止のため現在は無効。

## 3. 採用構成

- 認証：Sign in with Apple + Firebase Authentication
- 共有データ：Cloud Firestore
- 通知：Firebase Cloud Messaging経由のAPNs
- 通知送信：Cloud Functions for Firebase
- 招待：期限つき・一度だけ使える招待トークン + Universal Links
- 写真や添付：この段階では同期しない。必要になった段階でFirebase Storageを別途検討する。

アプリから相手の端末へ直接通知を送らない。共有データの書き込みをサーバーで検証したあと、Cloud Functionが相手だけへ通知する。

## 4. データ設計

```text
users/{uid}
  displayName
  createdAt
  updatedAt

users/{uid}/devices/{tokenHash}
  fcmToken
  platform
  notificationsEnabled
  sharedUpdatesEnabled
  updatedAt

groups/{groupID}
  name
  createdBy
  createdAt
  updatedAt

groups/{groupID}/members/{uid}
  role: owner | member
  joinedAt
  displayName

groups/{groupID}/items/{itemID}
  title
  kind
  date
  hasTime
  assigneeUID: string | null
  isCompleted
  deferredTo
  droppedAt
  createdBy
  updatedBy
  createdAt
  updatedAt

invites/{tokenHash}
  groupID
  createdBy
  expiresAt
  usedAt: timestamp | null
  usedBy: string | null
```

招待の生トークンはFirestoreに保存せず、ハッシュだけを保存する。期限は24時間。使用済みトークンは再利用できない。

## 5. プライバシーと権限

- `Ownership.personal` の項目はFirestoreへ送らない。
- ユーザーは自分が所属するグループだけ読める。
- 項目の作成・更新は、対象グループのメンバーだけ許可する。
- メンバー追加は有効な招待トークンを検証するCallable Functionだけが行う。
- 通知は操作した本人には送らない。
- 端末トークンは本人だけが登録・削除できる。
- アプリ削除やログアウト後に古いトークンが無効なら、送信結果を受けてサーバーから削除する。
- ロック画面の初期文言は「共有情報が更新されました」。設定で内容表示を許可した場合だけ項目名を表示する。

## 6. 通知ルール

| 操作 | 相手への通知 | 文言例 |
|---|---:|---|
| 共有の予定を追加 | する | 共有予定が追加されました |
| 共有予定の日時を変更 | する | 共有予定が変更されました |
| 共有ToDo・家事・買い物を追加 | する | 共有のやることが追加されました |
| 完了状態だけを変更 | 初期値はしない | アプリ内同期のみ |
| 個人項目を追加・変更 | 絶対にしない | 対象外 |
| 同じユーザーの別端末で操作 | しない | 対象外 |

短時間に複数回更新された場合は、同じグループ・同じ項目を30秒以内でまとめる。通知をタップすると該当項目を開く。

## 7. iPhone側の変更

1. Firebase SDKをSwift Package Managerで追加する。
2. Sign in with Appleを追加し、Firebase Authへ接続する。
3. `RemoteLifeItemRepository` を作り、共有項目だけFirestoreで監視する。
4. 既存の端末内Repositoryと組み合わせる `HybridLifeItemRepository` を作る。
5. APNs登録、FCMトークン更新、ログアウト時の削除を実装する。
6. 通知タップから `groupID` と `itemID` を読み、該当画面へ移動する。
7. 本物のメンバー参加が確認できた場合だけ「共有の更新」スイッチを有効にする。
8. Mockの `partnerJoined` は本番コードから削除し、メンバー監視結果に置き換える。

## 8. サーバー側の変更

1. `createInvite`：所属確認後、期限つき招待トークンを発行する。
2. `acceptInvite`：トークンをトランザクションで一度だけ消費し、メンバーを追加する。
3. `onSharedItemWritten`：追加・重要変更を検出し、操作本人を除くメンバーへ通知する。
4. 無効なFCMトークンを送信結果から削除する。
5. Firestore Security RulesとRulesテストを作る。

## 9. 既存データの移行

- 初回ログイン時に、端末内の `ownership == .shared` の項目だけを一覧でプレビューする。
- ユーザーが「共有を開始」を承認した後だけアップロードする。
- 個人項目は端末内のままにする。
- `itemID` は既存UUIDを維持し、二重登録を防ぐ。
- 移行完了フラグを端末とユーザー情報に保存し、再実行しても重複しないようにする。

## 10. 変更禁止範囲

- 現在の5タブ構成と「すべて／自分／共有」の意味を変えない。
- 個人データをFirestoreへ移行しない。
- 端末内の予定・タスク通知を壊さない。
- Firebase設定ファイル、APNs秘密鍵、サービスアカウント鍵をリポジトリへコミットしない。
- AI連携、課金、広告、レシートOCRは同時に実装しない。

## 11. テスト方法

- Unit：個人項目はアップロード対象外、通知判定、本人除外、設定OFF、同一項目の集約。
- Rules Emulator：非メンバーの読み書きを拒否、メンバーの共有項目だけ許可、権限昇格を拒否。
- Functions Emulator：招待の期限・一度きり利用、通知対象端末の選別、無効トークン削除。
- 実機2台：招待、参加、双方向同期、追加・変更通知、タップ遷移、ログアウト後の停止。
- 回帰：既存の全Unit Test、端末内通知、個人項目、オフライン起動。

## 12. 完了条件

- 2つのApple Account、2台のiPhoneで同じ生活グループへ参加できる。
- 共有予定の追加が相手端末へ同期され、通知設定ONならPush通知が1回届く。
- 個人項目は相手端末・Firestore・Push通知のどこにも出ない。
- 通知OFF、ログアウト、グループ退出後には届かない。
- オフラインで追加した共有項目が復帰後に同期される。
- Security Rulesと既存テストがすべて成功する。

## 13. 実装開始に必要なもの

- Apple Developer Programの登録完了
- Firebaseプロジェクト
- iOSアプリ登録済みの `GoogleService-Info.plist`（リポジトリには含めない）
- APNs認証キーをFirebase Consoleへ登録
- 実機2台と、テスト用の別Apple Account

外部設定が無い状態でもアプリは起動でき、現在の端末内機能をそのまま使用できること。
