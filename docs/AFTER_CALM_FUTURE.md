# Calm Future のあと：計画と報告

Calm Future（[CALM_FUTURE_SPEC.md](CALM_FUTURE_SPEC.md)）の4段階は 2026-10-07 にすべて完了・確認済み。
そのあと、報告書の提案から池上さんが次の2つを選んだ（2026-10-07）。どちらも仕様に影響するため、内容は提案どおりに限り、細かい解釈は [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) に記録する。

1. **入力をもっと賢く**：時刻の読み取り（「10:30 歯医者」を時刻つきの予定に）、帰宅時・夜・余力があれば・今週中を自分で選ぶ、Inbox の修正内容の保存
2. **テーマとダークモード**：選んだ Premium テーマをアプリ全体の色に反映、夜の色をもとにしたダークモード

1 → 2 の順に、それぞれ Mac でビルド・Simulator 確認をしてから次へ進む。外部サービスには接続しない。

## 1. 入力をもっと賢く（2026-10-07）

### 変更したファイル

新規
- Core/Models：`ClockTime.swift`（時刻だけを持つ型）
- Core/Utilities：`TimeReader.swift`（時刻の読み取り）
- LifeOSTests：`SmartInputTests.swift`（17件）

変更
- Core：`InboxItem.swift`（`InboxItem.edit`、`InboxSuggestion` に時刻・いつごろを選んだか・保存できる形）、`InboxClassifier.swift`（時刻を先に読む）、`LifeStore.swift`（修正内容の保存）
- Features：QuickAdd（`QuickAddViewModel`・`QuickAddConfirmView`）、Inbox（`InboxViewModel`・`TidyUpViewModel`・`TidyUpView` の修正画面）
- docs：`IMPLEMENTATION_NOTES.md`、本書

### 見た目・動きの変化

- なんでも追加に「10:30 歯医者」と入れると、LifeOSの理解が「予定・今日 10:30」になり、提案どおり追加で今日画面の 10:30 に並ぶ。
- 「詳しく整える」の各項目の下に「いつごろ：決めない ▾」。押すと 帰宅時・夜・余力があれば・今週中 を選べる。
- Inbox の「修正」に「時刻を決める」と「いつごろ」。修正した内容は、Inbox を閉じても・アプリを終了しても残る。

### 維持した既存機能

これまでの読み取り（土曜・明日・買い物・品名だけの入力・支出・共有）、提案どおり追加・そのまま預ける・詳しく整える・種類を決めて追加、Inbox のこのまま追加・修正・後で・削除・元に戻す、まとめて整理、一人モード、保存データ。

### 未実装・将来対応

- 「来週の火曜」「10/15」のような日付の読み取り（今は 今日・明日・土曜・日曜・週末）
- 「夕方」「朝」などの言葉からの柔らかい時間の読み取り
- 予定の終わりの時刻・移動時間

### ビルド結果

この環境には Xcode が無いため、コードの読み合わせでビルドエラーが無いことを確認済み。2026-10-08 に Mac の Xcode でビルド成功・テスト120件成功・Simulator 確認済み。

### Simulator で確認すべき操作

1. なんでも追加に「10:30 歯医者」→ 理解「予定」「今日 10:30」→ 提案どおり追加 → 今日画面の 10:30
2. 「19時に美容院」「明日10時半 会議」「3時 銀行」（→ 15:00）、「1時間 ジョギング」（時刻にしない）
3. 「母へ電話」→ 詳しく整える → いつごろ：夜 → 追加 → 今日画面の EVENING 夜
4. 種類を決めて追加の「予定」で「19時 美容院」→ 19:00 の予定
5. Inbox のメモ → 修正 → 時刻を決める・いつごろ → 決定 →「修正済み」→ Inbox を閉じて開き直しても残る
6. アプリを終了して開き直しても、修正済みが残る

## 2. テーマとダークモード（2026-10-08）

### 変更したファイル

新規
- DesignSystem/Colors：`LifePalette.swift`（テーマごとのライト・ダークの基本色、`LifeThemeRuntime`、`LifeAppearanceMode`）
- LifeOSTests：`ThemeTests.swift`（8件）

変更
- DesignSystem/Colors：`LifeColors.swift`（各色をテーマとライト／ダークに合わせて決まる色に）、`LifeThemes.swift`（プレビューの色を基本色から）、`LifeAmbientColors.swift`（説明のみ）
- App：`LifeOSApp.swift`（`LifeThemedRoot`：テーマとライト／ダークの反映）、`AppState.swift`（ライト／ダーク・選んだテーマの保存）、`LifeAppearance.swift`（タブバー・ナビゲーションバーの色）
- Features：Profile の `DisplaySettingsView`（ライト／ダークの選択・カラーテーマ）、Premium（`PremiumView`・`PremiumViewModel`：テーマを使う）
- docs：`IMPLEMENTATION_NOTES.md`、本書

### 見た目・動きの変化

- 表示設定で「端末に合わせる／ライト／ダーク」を選べる。ダークは深い森のような暗い背景で、文字は明るいアイボリー。
- Premium のとき、Premium 画面でテーマを選んで［◯◯ を使う］を押すと、アプリ全体がそのテーマの色になる。
- Free のときはテーマはプレビューだけで、アプリは Forest のまま。

### 維持した既存機能

すべての画面の表示と操作、Forest のライトの色（これまでと同じ）、時間帯の背景、すりガラス、カテゴリー色、Free／Premium（広告の有無）、Dynamic Type・VoiceOver・視差効果を減らす・透明度を下げる、保存データ。

### 未実装・将来対応

- テーマを変えたときに、開いている画面を戻さずに色だけ変えること
- 時間帯でテーマやライト／ダークを自動で変えること（例：夜だけダーク）
- カテゴリー色のダーク向けの調整（今はライトと同じ低彩度の色）

### ビルド結果

この環境には Xcode が無いため、コードの読み合わせでビルドエラーが無いことを確認済み。2026-10-08 に Mac の Xcode でビルド成功・テスト128件成功・Simulator 確認済み。選んだ2つ（入力をもっと賢く・テーマとダークモード）はどちらも完了。

### Simulator で確認すべき操作

1. プロフィール → 表示設定 →「ダーク」：全画面が暗い色に。今日・カレンダー・やること・リスト・お金・なんでも追加・Inbox・Premium を見て、文字が読めること
2. 「ライト」に戻す：これまでと同じ色
3. 「端末に合わせる」：Simulator の Features → Toggle Appearance（⇧⌘A）でライト／ダークが切り替わること
4. Free のまま Premium 画面：テーマのプレビューを押しても、アプリの色は変わらない（説明文に Free の案内）
5. 開発用設定で Premium にする → Premium 画面で「Hotel」→［Hotel を使う］→ 今日画面に戻り、全体がエスプレッソと真鍮の色に
6. ほかのテーマ（Sage・Midnight・Terracotta）もライトとダークで確認
7. 開発用設定で Free に戻す → Forest に戻る。Premium に戻す → 選んだテーマに戻る
8. アプリを終了して開き直しても、ライト／ダークとテーマが残っていること
9. 設定アプリ → アクセシビリティ → 透明度を下げる：タブバーが不透明になり、色はテーマに合うこと

## 3. 習慣を自分で追加・編集（2026-10-08）

2つが完了したあと、次の希望は特に無しだったため、残っていた提案（習慣を自分で追加・編集／おまかせで整える／日付の読み取り／はじめての設定画面）から、見本の習慣しか使えない状態を解消する「習慣を自分で追加・編集」を先に進めた。残りは確認のあと1つずつ。

### 変更したファイル

新規
- Features/Habits：`HabitsView.swift`（一覧・追加・編集の画面）、`HabitsViewModel.swift`
- LifeOSTests：`HabitEditingTests.swift`（10件）

変更
- Core：`LifeStore.swift`（習慣の追加・編集・外す・元に戻す、種類「習慣」の項目を習慣に登録）
- Features：Today（`TodayView`：習慣の「追加・編集」への入口）
- LifeOSTests：`CalmFutureStage3Tests.swift`（以前の保存データの例を、登録されない形で作るよう調整）
- docs：`IMPLEMENTATION_NOTES.md`、本書

### ビルド結果

この環境には Xcode が無いため、コードの読み合わせでビルドエラーが無いことを確認済み。2026-10-09 までに Mac の Xcode でビルド成功・テスト138件成功・Simulator 確認でエラーなし（池上さんの確認）。

### Simulator で確認すべき操作

1. 今日画面の「習慣」→ 右の「追加・編集」→ 習慣の画面
2. 「散歩」と入れて「軽い習慣にする」をオン → ＋ → 一覧に追加され、上に「元に戻す」付きの一言
3. 今日画面に戻ると「散歩」が出ている。余力「少ない」でも出る（軽い習慣）
4. 習慣の画面で「ストレッチ」の「編集」→ くり返し「曜日を選ぶ」→ 月・水・金 → 決定。今日がその曜日でなければ、今日画面から消え、習慣の画面に「今日はお休みの日です」
5. 「編集」→「この習慣を外す」→「元に戻す」で、点（記録）ごと戻る
6. Inbox のメモ →「修正」→ 種類「習慣」→ このまま追加 → 今日画面の習慣に出る
7. アプリを終了して開き直しても、追加・編集した習慣が残っていること

## 4. はじめての設定（2026-10-09）

仕様：[ONBOARDING_SPEC.md](ONBOARDING_SPEC.md)。新しく使い始める人が、見本データではなく自分の生活から始められるようにする。

### 変更したファイル

新規
- Core/Models：`OnboardingProgress.swift`（途中経過・最初の習慣の候補）
- Features/Onboarding：`OnboardingView.swift`、`OnboardingViewModel.swift`
- LifeOSTests：`OnboardingTests.swift`（18件）
- docs：`ONBOARDING_SPEC.md`（受け取った指示をそのまま保存）

変更
- App：`LifeOSApp.swift`（AppState を先に読み、空のデータか保存データかを決める。最上位で はじめての設定／MainTabView を切り替え）、`AppState.swift`（完了状態・途中経過・反映・再表示）
- Core：`LifeStore.swift`（`persistent(startEmptyIfNoSavedData:)`・`empty()`）、`LocalStorage.swift`（テスト用の保存先・ファイルがあるか）
- DesignSystem：`LifeScreen.swift`（細い線の一覧は空なら何も出さない）
- Features：Profile の `DeveloperSettingsView`（はじめての設定を再表示）、Lists の `ListsView`・LifeMemory の `LifeMemoryView`（空のときの案内）
- `README.md`、`docs/IMPLEMENTATION_NOTES.md`、本書

### 初回起動の判定と、以前から使っている人の移行

- 設定もデータも保存が無い → 新しく使い始める人：はじめての設定を出し、空のデータから始める
- 設定の保存に完了状態が無い（以前のバージョン）→ 完了済みとして扱い、はじめての設定は出さない。データはそのまま
- 完了したら完了状態を保存し、途中経過を消す

### ビルド結果

この環境には Xcode が無いため、こちらではビルドとテストを実行していない（コードの読み合わせのみ）。
2026-10-09、池上さんから Mac での確認について「確認完了」の報告を受けた（⌘B・⌘U の対象は合計156件＝これまでの138件＋18件）。

### Simulator 確認

2026-10-09、池上さんから「確認完了」の報告を受けた（確認する操作は仕様の「Simulator確認」と同じ）。個々の項目ごとの結果は受け取っていない。
新しく使い始める人の確認は、Simulator のアプリを長押しして削除してから実行する。

### 今回実装していないもの

仕様の「変更禁止範囲」のもの（Firebase・同期・AI・StoreKit など）、すべてのデータを消す操作、予算を設定する画面（新しい人の予算は 0 円のまま）。
