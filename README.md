# life-os
生活OSアプリ開発プロジェクト

## ドキュメント

- [生活OS UIプロトタイプ実装指示](docs/LIFE_OS_UI_PROTOTYPE_IMPLEMENTATION.md)
- [Claude Code送信用メッセージ](docs/CLAUDE_CODE_MESSAGE.md)
- [生活OS v2 仕様（Editorial Living・ズボラ継続機能）](docs/LIFE_OS_V2_SPEC.md)
- [UIプロトタイプ 実装メモ（動かし方・TODO）](docs/IMPLEMENTATION_NOTES.md)
- [Repository 設計（Firestore 移行の準備）](docs/REPOSITORY_DESIGN.md)
- [v2 改修の報告](docs/V2_REPORT.md)
- [Calm Future Living OS デザイン改修 仕様](docs/CALM_FUTURE_SPEC.md)
- [Calm Future 改修の報告](docs/CALM_FUTURE_REPORT.md)
- [Calm Future のあと：計画と報告](docs/AFTER_CALM_FUTURE.md)
- [はじめての設定 仕様](docs/ONBOARDING_SPEC.md)
- [パートナー共有・通知 実装仕様（正本）](docs/PARTNER_NOTIFICATIONS_IMPLEMENTATION.md)
- [パートナー共有・通知 実装の報告](docs/PARTNER_NOTIFICATIONS_REPORT.md)
- [Apple / Firebase の設定手順](docs/FIREBASE_SETUP.md)
- [保証書管理 MVP 仕様（正本）](docs/WARRANTY_MANAGEMENT_MVP_SPEC.md)
- [保証書管理 実装の報告](docs/WARRANTY_MANAGEMENT_REPORT.md)
- [保証書管理 確認の手順](docs/WARRANTY_MANUAL_CHECK.md)

## UIプロトタイプの動かし方

Xcode 16 以降で `LifeOS.xcodeproj` を開き、iPhone Simulator（iOS 17 以降）を選んで実行してください。
外部サービスには接続していません。データは端末内にだけ保存します。
パートナー共有・通知のサーバー側（`firestore.rules`・`firebase/functions`）は準備中で、iPhone アプリはまだ Firebase につながっていません（[設定手順](docs/FIREBASE_SETUP.md)）。

- はじめて起動したとき（保存データが無いとき）は「はじめての設定」が出ます。見本（Mock）データは入らず、空のデータから始まります。
- 以前から使っている端末（保存データがある）では、はじめての設定は出ず、保存データをそのまま読み込みます。
- SwiftUI のプレビューと、開発用設定の「データを初期化」では、これまでどおり Mock データを使います。
- Premium の「大切な書類」（保証書）：リストタブの一番上から。写真と読み取った文字は端末内だけで扱い、外部へは送りません。保証終了前の通知は、この iPhone の中のローカル通知です。
- はじめての設定をもう一度見るには、プロフィール → 開発用設定 →「はじめての設定を再表示」（データは消えません）。
