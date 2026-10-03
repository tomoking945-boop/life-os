import SwiftUI

/// LifeOS Themes（v2 仕様 20：Premium の将来機能。今回はプレビュー表示のみで、アプリには適用しない）
/// TODO: Premium 接続時に、選んだテーマをアプリ全体（LifeColors）へ適用できる仕組みにする。
enum LifeTheme: String, CaseIterable, Identifiable, Hashable {
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

    /// 背景
    var background: Color {
        switch self {
        case .forest: return LifeColors.background
        case .hotel: return Color(hex: 0xF4F1EC)
        case .sage: return Color(hex: 0xF2F4EF)
        case .midnight: return Color(hex: 0x1F2428)
        case .terracotta: return Color(hex: 0xF7F1EB)
        }
    }

    /// 主要色（ヒーロー・ボタン）
    var primary: Color {
        switch self {
        case .forest: return LifeColors.primary
        case .hotel: return Color(hex: 0x3A3230)
        case .sage: return Color(hex: 0x5E7259)
        case .midnight: return Color(hex: 0x34404A)
        case .terracotta: return Color(hex: 0x8A4F3C)
        }
    }

    /// アクセント
    var accent: Color {
        switch self {
        case .forest: return LifeColors.accent
        case .hotel: return Color(hex: 0xB39169)
        case .sage: return Color(hex: 0xA39A74)
        case .midnight: return Color(hex: 0xB59B6E)
        case .terracotta: return Color(hex: 0xC49A6C)
        }
    }

    /// 背景の上の文字
    var text: Color {
        switch self {
        case .midnight: return Color(hex: 0xECE6DA)
        default: return LifeColors.text
        }
    }
}
