# Calm Future 改修の報告

仕様：[CALM_FUTURE_SPEC.md](CALM_FUTURE_SPEC.md)／詳しい解釈：[IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) の「Calm Future Living OS」

## 第1段階：DesignSystem と今日画面（2026-10-05）

### 1. 変更したファイル

新規
- Core/Models：`LifeTimeOfDay.swift`（時間帯）、`SoftTime.swift`（帰宅時・夜・余力があれば・今週中）
- Core/Utilities：`LivingTimelineBuilder.swift`（今日これだけ・NEXT・このあと → ひとつのタイムライン）
- DesignSystem/Colors：`LifeAmbientColors.swift`
- DesignSystem/Surface：`LifeSurface.swift`（面の段階 sunken / normal / floating / selected / suggestion、`LifeGlassSurface`）
- DesignSystem/Motion：`LifeMotion.swift`（Duration・Easing・`withLifeAnimation`）
- DesignSystem/Components：`LifeAmbientBackground`、`LifeTimeline`（`LifeTimelineSection`）、`LifeInsightCard`（＋`LifeSuggestionCard`・`LifeCapsuleButton`）、`LifeUndoBanner`
- LifeOSTests：`CalmFutureTests.swift`（14件）
- docs：`CALM_FUTURE_SPEC.md`、`CALM_FUTURE_REPORT.md`

変更
- `LifeItem.swift`（`softTime` を Optional で追加）、`LifeStore.swift`（元に戻す用の3メソッド）、`LifeFormatters.swift`（`duration`）
- DesignSystem：`LifeSpacing`・`LifeTypography`・`LifeRadius`・`LifeShadow` にトークン追加
- `AppState.swift`（開発用の `ambientPreview`、保存しない）、`DeveloperSettingsView.swift`（時間帯の切り替え）
- `TodayView.swift`・`TodayViewModel.swift`
- `README.md`、`docs/IMPLEMENTATION_NOTES.md`

### 2. 見た目の変化

- 背景が時間帯でごく弱く変わる（朝：Brass／昼：Mist Blue／夕方：Terracotta／夜：Deep Forest＋Midnight）。上部だけに薄く重ね、中ほどから下は従来の Ivory。
- 濃い緑のヒーローカードをやめ、背景の上に直接 Ambient Header（Good morning.／10:30の歯医者まで1時間20分／今日は3つだけで十分です）。
- 「今日これだけ」「NEXT」「このあと」を Living Timeline に統合。左に細い線とカテゴリー色の点、見出しは NOW／10:30／ON THE WAY HOME 帰宅時／20:00／IF YOU HAVE TIME 余力があれば。
- セクションごとに見せ方を変えた：昨日残ったもの・Inbox＝細い線／招待＝静かな提案の面／暮らしメモリー＝小さな横スクロール／今日の余力＝紙色の面／習慣＝余白だけ／お金＝大きな数字と予算の細い線。
- 操作のあとの一言は、上部に浮かぶすりガラスの面に「元に戻す」と一緒に出る。

### 3. 維持した既存機能

5タブ、すべて/自分/共有（共有モードのみ）、一人モード、パートナー招待（未参加時）と共有、今日これだけ（最大3件・番号・あと◯件）、完了チェック、あとで（今夜・明日・週末・来週）、昨日残ったもの（今日に表示・今週に回す・あとで・もうやらない）、暮らしメモリー（買い物に追加・土曜日に追加・今回はスキップ・すべて見る）、今日の余力と家事、習慣、Inbox、お金、Free の広告カード、プロフィール導線、なんでも追加、保存データ（以前のデータもそのまま読める）。

### 4. 新しく追加した解釈

- 時間帯の区切り（朝 5〜10時台／昼 11〜15時台／夕方 16〜18時台／夜 19〜4時台）。
- 夜もライトモードのまま、色をごく弱く重ねるだけにした。
- タイムラインの置き場所のルール：時刻あり→その時刻、今日これだけ の買い物→帰宅時、それ以外→いま、残り→余力があれば。
- 挨拶を時間帯で切り替え（9:10 では従来どおり Good morning.）。
- 「元に戻す」を今日画面の操作（あとで・救済・共有・暮らしメモリー）に付けた。完了チェックは戻さない。
- 「残りは明日に整えておきます」は、実際に自動で移していないため今は使わない。

### 5. 未実装・将来対応

- 「移動を考えると9:55に出れば大丈夫」（移動時間の情報が必要。下の提案1）
- `softTime` を自分で選ぶ画面（第2段階の QuickAdd・Inbox で検討）
- `LifeSuggestionCard` を使った「LifeOSからの提案」本体（第3段階）。今は招待カードの見た目にだけ使用
- 習慣のリズム表示（7日の点）・毎日のくり返し（第3段階）
- 他の画面への展開（第4段階）、ダークモード

### 6. ビルド結果

この環境には Xcode が無いため、コードの読み合わせ（別の確認役によるレビューを含む）でビルドエラーが無いことを確認済み。2026-10-06 に Mac の Xcode でビルド成功・テスト52件成功・Simulator 確認済み。
確認後の調整（今日の余力のタイル化・残ったものを3件まで表示・見出しの切り替え）とテスト2件を追加（合計54件）。

### 7. Simulator で確認すべき操作

1. 今日画面：Good morning.／10:30の歯医者まで1時間20分／今日は3つだけで十分です
2. タイムライン：NOW ゴミ出し → 10:30 歯医者（パートナーと共有）→ 帰宅時 牛乳を買う → 20:00 外食 → 余力があれば「あと3件」
3. 時計ボタン →「明日」→ 上に「元に戻す」付きの一言 →「元に戻す」で戻る
4. 昨日残ったもの：行を押す →「もうやらない」→「元に戻す」
5. 暮らしメモリーを横にスクロール →「買い物に追加」→「元に戻す」
6. 今日の余力「少ない」→ 二つ目の一言が「今日は軽めで大丈夫です」
7. プロフィール → 開発用設定 →「時間帯の背景」で 昼・夕方・夜 → 今日画面の背景と挨拶
8. 開発用設定：ひとり（切り替えが消える）／パートナー未参加（提案の面の招待カード）／Premium（広告が消える）
9. 設定アプリ → アクセシビリティ：文字を大きく（メモリーが縦並び）、視差効果を減らす、透明度を下げる

### 8. 追加で提案したい改善案

1. **移動時間の目安（仕様に影響）**：予定に「移動時間（分）」を任意で持たせ、「9:55に出れば大丈夫」を出す。位置情報は使わず、手入力または予定の種類ごとの目安。
2. **柔らかい時間の選択（仕様に影響）**：QuickAdd の確認画面で「帰宅時／夜／余力があれば／今週中」を選べるようにする（第2段階で一緒に）。
3. **タブバー・なんでも追加の統一（小さな視覚改善）**：第4段階を待たず、タブバー背景を Ivory のすりガラス寄りにしておくと、今日画面との差が小さくなる。

## 第2段階：なんでも追加（生活コンソール）と Inbox（2026-10-06）

### 1. 変更したファイル

新規
- Core/Models：`LifeFeedback.swift`（一言と「元に戻す」。今日画面から移して共通化）
- Core/Utilities：`LifeInterpreter.swift`（なんでも追加の「LifeOSの理解」）
- LifeOSTests：`CalmFutureStage2Tests.swift`（21件）

変更
- Core：`InboxItem.swift`（土曜・日曜、理解の表示、理由）、`InboxClassifier.swift`（曜日・品名だけの入力・帰宅時・手がかり）、`ShoppingCategorizer.swift`（品名の判定）、`LifeStore.swift`（Inbox を元に戻す）
- DesignSystem：`LifeUndoBanner.swift`（`lifeFeedbackBanner`）、`LifeSpacing`・`LifeSurface`（Orb のトークン）
- Features：QuickAdd（`QuickAddButton`・`QuickAddSheet`・`QuickAddViewModel`・`QuickAddConfirmView`）、Inbox（`InboxView`・`InboxViewModel`・`TidyUpView`・`TidyUpViewModel`）、Today（共通の一言表示に置き換え）
- docs：`IMPLEMENTATION_NOTES.md`、本報告

### 2. 見た目の変化

- なんでも追加ボタンの左に小さな Orb。
- なんでも追加は「生活コンソール」に：時間帯の背景、すりガラスの入力欄（マイクは入力欄の中）、入力例、入力するとその場で出る「LifeOSの理解」（提案の面）、3つの操作。種類を決めて追加は下に小さく。
- Inbox はリストをやめ、背景の上に細い線で区切ったメモ。原文はセリフ体、その下にカテゴリー色の細い線と「LifeOSの理解」、カプセル型の3つの操作。
- まとめて整理は、最初に「4件を整理しました」と行き先ごとの件数（大きめの数字）。

### 3. 維持した既存機能

とりあえず保存（そのまま預ける）、すぐ追加の4種類（種類を決めて追加）、整理する（詳しく整える。空なら従来の例）、確認画面の自分/共有と選択、音声入力のお知らせ、支出の金額チェック、Inbox の追加・削除・後で、まとめて整理の 修正・スキップ・後で・全部OK（すべて反映）、一人モード、5タブ、保存データ（以前のデータもそのまま読める）。

### 4. 新しく追加した解釈

- 今日の買い物は「帰宅時に表示」。
- 支出とみなす条件（100円以上・時刻や単位が付いていない）。
- 品名だけの入力は1品ずつに分けて追加。
- 行き先の言い方（家族と共有へ／買い物へ／明日へ・土曜へ／支払いへ／家事へ／予定へ／やることへ）。
- 一人モードでは共有と読み取っても「自分」として追加。
- まとめて整理の最初の画面ではまだ何も変えず、反映後に「元に戻す」。
- Inbox の削除はスワイプから長押しメニューへ。

### 5. 未実装・将来対応

- 時刻の読み取り（「10:30 歯医者」を予定にする）
- 「帰宅時／夜／余力があれば／今週中」を自分で選ぶ（今は理解として表示するだけ）
- Inbox で修正した内容の保存
- 音声入力
- 本物の AI 分類

### 6. ビルド結果

この環境には Xcode が無いため、コードの読み合わせ（別の確認役によるレビュー）でビルドエラーが無いことを確認済み。Mac での ⌘B・⌘U（合計75件）は確認待ち。

### 7. Simulator で確認すべき操作

1. なんでも追加：ボタンの Orb → 入力例「牛乳とティッシュ」→ 理解「買い物・食品／冷蔵」「帰宅時に表示」→「提案どおり追加（2件）」→ 今日画面の「帰宅時」
2. 「土曜に母へ電話」→ 10/◯（土）、「ランチ 1200」→ 支出・外食 → お金タブ
3. 「そのまま預ける」→ Inbox に入る／空のまま「詳しく整える」→ 従来の整理の例
4. 今日画面 → Inbox：メモの原文と理解、「このまま追加」→ 上の「元に戻す」、「後で」、長押しで削除
5. Inbox の「修正」で種類やいつを変える → 「修正済み」の表示
6. まとめて整理 → 「4件を整理しました」→「内容を確認」で1件ずつ →「すべて反映」→「元に戻す」
7. 開発用設定で「ひとり」にして、自分/共有の表示が消えること

### 8. 追加で提案したい改善案

1. **時刻の読み取り（仕様に影響）**：「10:30 歯医者」「19時 美容院」を時刻つきの予定として理解する。
2. **柔らかい時間の選択（仕様に影響）**：「詳しく整える」と Inbox の「修正」で、帰宅時／夜／余力があれば／今週中を選べるようにする。
3. **Inbox の修正内容の保存（仕様に影響）**：`InboxItem` に Optional で修正内容を持たせ、アプリを閉じても残す。
