# Repository 設計（Firestore 移行の準備）

v2 仕様 22 に対応する設計メモです。コードは `LifeOS/Core/Repositories/Repositories.swift`。

## 目的

いまは `LifeStore`（端末内の JSON 保存）を ViewModel が直接使っています。
Firestore に移すとき、画面側のコードをなるべく変えずに保存先だけを差し替えられるよう、
「データの出し入れの窓口（Repository）」を用意し、ViewModel はその窓口を通して読み書きするようにします。

## 窓口（Protocol）

| Repository | 担当 | 主なメソッド |
| --- | --- | --- |
| `LifeItemRepository` | 予定・ToDo・家事・買い物・支払予定・習慣 | `items(on:scope:)`、`leftovers(before:scope:)`、`add`、`toggleCompletion`、`reschedule`、`drop`、`share` |
| `ExpenseRepository` | 支出・今月の予算 | `expenses`、`budget`、`add` |
| `ListRepository` | リスト | `lists`、`list(id:)`、`addList`、`addItem`、`removeItems` |
| `InboxRepository` | おまかせInbox | `inbox`、`addToInbox`、`removeFromInbox`、`postponeInbox` |

今は `LifeStore` がこの4つすべてに適合しています（`extension LifeStore: LifeItemRepository {}` など）。
今後、暮らしメモリー・家事オートパイロット・よく買うもの も同じ形で窓口を足します。

## 段階的な移行

| 段階 | 内容 | 状況 |
| --- | --- | --- |
| 1 | Protocol を定義し、`LifeStore` を適合させる | 済（第6回） |
| 2 | お金（`MoneyViewModel`）・リスト（`ListsViewModel`）を Protocol 経由に切り替え | 済（第6回） |
| 3 | 今日・カレンダー・やること・Inbox・買い物の ViewModel を切り替え | 未 |
| 4 | 暮らしメモリー・家事・よく買うもの の Protocol を追加 | 未 |
| 5 | `FirestoreLifeItemRepository` などを作り、アプリ起動時に差し替え | 未（Firebase 接続時） |

ViewModel の `init(store:)` の引数ラベルは変えていないため、画面側の呼び出しはそのままです。

## Firebase 導入前に決める・直すこと

1. **非同期と失敗**：いまの窓口はすべて同期・失敗なし。Firestore では保存の失敗・オフライン・競合が起きるため、
   書き込みを `async throws` にするか、楽観的に画面を更新して失敗時に戻すかを決める。
2. **リアルタイム更新**：共有メンバーの変更を受け取るため、スナップショットの監視（Listener）から
   `@Observable` の配列を更新する形にする。
3. **共有の単位**：いまは `Ownership`（自分 / 共有）だけ。Firestore では「生活グループ（わが家）」の ID と、
   作成者・担当者のユーザー ID を各データに持たせる必要がある（`Assignee` の me / partner / either をユーザー ID に置き換える）。
4. **ID と日時**：`UUID` は文字列 ID に、`Date` はタイムゾーンを含めて保存する。「今日」の判定は端末のタイムゾーンで行う。
5. **Mock の現在時刻**：`LifeCalendar.now` は 9:10 固定。本番前に `Date()` に戻す（挨拶の時間帯切り替えも合わせて）。
6. **開発用設定**：Free/Premium・利用スタイル・パートナー参加済み・データ初期化は、本番では隠す（DEBUG のみ）。
7. **保存データの移行**：端末内 JSON に入っている既存データを Firestore へ一度だけ移す処理が必要か決める。
8. **セキュリティルール**：グループのメンバーだけが読み書きできるルールを最初に用意する。
