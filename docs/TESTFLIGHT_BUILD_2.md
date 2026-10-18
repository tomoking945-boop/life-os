# TestFlight ビルド2：実際の現在時刻

作業用ブランチ：`fix-real-current-time`（commit `8a2abca`、池上さんのパッチ `fix-real-current-time.patch` をそのまま適用）

## 変更したこと

- `LifeCalendar.now` を、見本用の「今日の 9:10」固定から、端末の実際の現在時刻（`Date()`）に変更
- 今日画面は、表示したとき・アプリに戻ったとき・1分ごとに現在時刻を更新（`TodayViewModel.refreshNow`）
- テストでは、これまでどおり固定の時刻を渡せる
- Version 1.0 のまま、Build を 1 → 2（アプリ・テスト、Debug／Release）
- テスト2件を追加（`CurrentTimeTests`）

Bundle Identifier・表示名「くらしOS」・暗号化の申告・通知・保証書管理は変更なし。

## 確認結果（2026-10-18 池上さんの Mac）

- Release ビルド：成功
- テスト：223件、失敗0件（実機専用のファイル保護テストはスキップの想定）
- 同日 main に取り込み

## 残っていること

- `AppState.swift` の `ambientPreview` の説明に「Mock の現在時刻は 9:10 固定」という古い文が残っている（動作には関係なし）
- Archive と App Store Connect へのアップロードは未実施
