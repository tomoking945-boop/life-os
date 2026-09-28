# UIプロトタイプ 実装メモ

`docs/LIFE_OS_UI_PROTOTYPE_IMPLEMENTATION.md` を正として実装した内容と、仕様が未確定のため判断を保留した点をまとめています。
コード中の `TODO:` コメントと対応しています。

## 動かし方

1. Xcode 16 以降で `LifeOS.xcodeproj` を開く
2. スキーム `LifeOS`、実行先に任意の iPhone Simulator（iOS 17 以降）を選ぶ
3. ⌘R で実行

- 外部サービス（Firebase / OpenAI API / StoreKit / AdMob など）には一切接続していません。
- データはすべて `LifeOS/Mock/MockData/MockData.swift` のメモリ上 Mock です。アプリを再起動すると初期状態に戻ります。
- Bundle Identifier は仮の `com.example.LifeOS` です（実機で動かす場合は変更が必要）。

## 構成

```text
LifeOS
├─ App            … 起動・タブ・画面共通の状態（AppState）
├─ Core
│  ├─ Models      … LifeItem / Expense / LifeList / Plan / UserProfile
│  ├─ Extensions  … Color+Hex
│  ├─ Utilities   … LifeCalendar（暦・Mockの現在時刻）/ LifeFormatters
│  └─ Store       … LifeStore（Mockデータの読み書き。将来ここを外部接続に置き換える）
├─ DesignSystem
│  ├─ Colors / Typography / Spacing / Radius / Shadow
│  └─ Components  … LifeCard / LifeButton / LifeSectionTitle / LifeAvatar /
│                   LifeSegmentControl / LifeTaskRow / LifeMoneyRow / LifeEmptyState / LifeChip
├─ Features       … Today / Calendar / Tasks / Lists / Money / QuickAdd / Profile / Premium（各 View + ViewModel）
└─ Mock/MockData  … MockData
```

`Core/Store` と `LifeChip` は仕様の構成図にはありませんが、Mockデータの置き場所と、チップ型ボタンの共通部品として追加しました。

## 仕様内の矛盾・未確定事項（実装は止めずに TODO として保留）

| 箇所 | 内容 | 現状の扱い |
| --- | --- | --- |
| 今日 | レイアウト例の TODAY に「ゴミ出し」があるが、Mockデータ一覧にない | **決定（9/28）**：自分の家事として追加 |
| 今日 | Mockデータの「筋トレ」がレイアウト例の TODAY にない | Mockデータ一覧を優先し表示 |
| 今日 | レイアウト例では共有の「牛乳を買う」が TODAY に入っている | TODAY＝妻担当以外のタスク、SHARED＝妻担当のタスク、として再現 |
| 今日 | NEXT 以外の予定（外食 20:00）の表示場所 | **決定（9/28）**：NEXT カードの下に「このあと」として時刻とタイトルを表示 |
| 今日 | 「あと1時間20分」を再現するための現在時刻 | **決定（9/28）**：プロトタイプでは「今日の 9:10」固定を継続（`LifeCalendar.now`）。本実装時に実時刻へ |
| 今日 | 「Good morning.」の時間帯による切り替え | 固定表示 |
| 今日 | 広告カードの表示位置 | 画面の最後（MONEY の下）。Premium では条件ごと外れ、余白も残らない |
| 共通 | Mock項目の種類（予定/ToDo/家事/買い物/支払予定）と担当者 | タイトルから最低限判断（電気代＝支払予定、クリーニング受取＝家事、外食＝担当未設定 など） |
| 共通 | 今日とカレンダーの「すべて/自分/共有」を共有するか | 共有（片方で切り替えるともう片方も変わる） |
| やること | 「すべて/自分/共有」フィルターを適用するか | **決定（9/28）**：付けない（全件表示・担当者表示で区別） |
| お金 | 支出の自分/共有区分、フィルター適用 | 未適用 |
| お金 | 今月合計 ¥82,450 は支出一覧（2件）の合計と一致しない | 仕様の固定値を表示 |
| お金 | スーパーのカテゴリー、Netflix の日付 | 食費／3日前 |
| お金 | カテゴリー別の集計金額 | 表示せず、一覧の絞り込みのみ |
| リスト | 各リストの中身、項目の追加・編集 | 空のリストとして表示のみ |
| なんでも追加 | 「すぐ追加」ボタンの動作 | 選択状態の切り替えのみ |
| なんでも追加 | 入力欄が空でも「整理する」を押せるか | 常に押せる |
| なんでも追加 | 追加した項目の自分/共有区分 | 「自分」として追加 |
| プロフィール | アカウント／生活グループ／通知／表示設定の中身 | 「準備中」の仮画面 |
| プロフィール | 写真を再起動後も保持するか | 保持しない（メモリのみ） |
| Premium | 初期選択の支払い周期 | 年額 |
| 全体 | ダークモード配色 | ライトモード固定 |
| カレンダー | 週の始まり | 日曜始まり |

## 今回やっていないこと（仕様どおり）

Firebase / Apple Sign In / OpenAI API / StoreKit / AdMob / Push通知 / WidgetKit / レシートOCR / Apple Calendar同期 / 位置情報 / 家計分担ロジック / PDFアップロード / 音声入力 / カメラ撮影 / カレンダー週表示
