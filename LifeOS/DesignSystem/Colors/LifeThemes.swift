import SwiftUI

/// LifeOS Themes（v2 仕様 20：Premium の機能）。
/// テーマとダークモード（2026-10-08）：Premium で選んだテーマを、アプリ全体の色（LifeColors）に反映する。
/// 色の値はテーマごとのライト・ダーク（`lightPalette`・`darkPalette`、LifePalette.swift）。
enum LifeTheme: String, CaseIterable, Identifiable, Hashable, Codable {
    case forest
    case hotel
    case sage
    case midnight
    case terracotta

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forest: return "Forest"
        case .hotel: return "Hotel"
        case .sage: return "Sage"
        case .midnight: return "Midnight"
        case .terracotta: return "Terracotta"
        }
    }

    var caption: String {
        switch self {
        case .forest: return "いつもの深い緑"
        case .hotel: return "エスプレッソと真鍮"
        case .sage: return "やわらかな草木"
        case .midnight: return "夜の静けさ"
        case .terracotta: return "あたたかな土"
        }
    }

    /// 背景（プレビュー用。ライト／ダークに合わせる）
    var background: Color { LifeThemeRuntime.color(of: self) { $0.background } }

    /// 主要色（ヒーロー・ボタン）
    var primary: Color { LifeThemeRuntime.color(of: self) { $0.primary } }

    /// アクセント
    var accent: Color { LifeThemeRuntime.color(of: self) { $0.accent } }

    /// 背景の上の文字
    var text: Color { LifeThemeRuntime.color(of: self) { $0.text } }
}
