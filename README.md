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

## UIプロトタイプの動かし方

Xcode 16 以降で `LifeOS.xcodeproj` を開き、iPhone Simulator（iOS 17 以降）を選んで実行してください。
外部サービスには接続していません。データは端末内にだけ保存します。

- はじめて起動したとき（保存データが無いとき）は「はじめての設定」が出ます。見本（Mock）データは入らず、空のデータから始まります。
- 以前から使っている端末（保存データがある）では、はじめての設定は出ず、保存データをそのまま読み込みます。
- SwiftUI のプレビューと、開発用設定の「データを初期化」では、これまでどおり Mock データを使います。
- はじめての設定をもう一度見るには、プロフィール → 開発用設定 →「はじめての設定を再表示」（データは消えません）。
