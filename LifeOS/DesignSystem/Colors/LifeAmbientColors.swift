import SwiftUI

/// 時間帯の空気感の色（Calm Future）。
/// 背景にごく弱く重ねるだけ。文字の色には使わない（可読性を最優先）。
///
/// - 朝：Warm Ivory ＋ 弱い Brass
/// - 昼：Ivory ＋ Mist Blue
/// - 夕方：Ivory ＋ Terracotta
/// - 夜：Deep Forest ＋ Midnight
///
/// 新しい解釈：ライトでは夜も背景は Ivory のまま（ダークモードでは、テーマのダークの背景の上に同じ色をごく弱く重ねる）。
/// Deep Forest と Midnight を上部にごく弱く重ねて「夜の気配」だけを出す（文字は濃い色のまま読める）。
enum LifeAmbientColors {
    static let warmIvory = LifeColors.background
    static let brass = LifeColors.accent
    static let mistBlue = LifeCategoryColors.mistBlue
    static let terracotta = LifeCategoryColors.terracotta
    static let deepForest = LifeColors.primary
    /// #2A3442 夜の青み（Midnight）
    static let midnight = Color(hex: 0x2A3442)

    /// 上から重ねる色の強さ（ごく弱く）
    static let washOpacity: Double = 0.10
    /// 夜は色が濃いので、さらに弱くする
    static let nightWashOpacity: Double = 0.07
    /// 右上の弱い光の強さ
    static let glowOpacity: Double = 0.10
}

extension LifeTimeOfDay {
    /// 上から重ねる色
    var ambientWash: Color {
        switch self {
        case .morning: return LifeAmbientColors.brass
        case .day: return LifeAmbientColors.mistBlue
        case .evening: return LifeAmbientColors.terracotta
        case .night: return LifeAmbientColors.deepForest
        }
    }

    /// 右上の弱い光の色
    var ambientGlow: Color {
        switch self {
        case .morning: return LifeAmbientColors.brass
        case .day: return LifeAmbientColors.mistBlue
        case .evening: return LifeAmbientColors.brass
        case .night: return LifeAmbientColors.midnight
        }
    }

    var ambientWashOpacity: Double {
        self == .night ? LifeAmbientColors.nightWashOpacity : LifeAmbientColors.washOpacity
    }
}
