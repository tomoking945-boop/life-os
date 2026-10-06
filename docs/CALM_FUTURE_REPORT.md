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

この環境には Xcode が無いため、コードの読み合わせ（別の確認役によるレビューを含む）でビルドエラーが無いことを確認済み。Mac の Xcode でのビルド（⌘B）とテスト（⌘U、38＋14件）は確認待ち。

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
