import SwiftUI

/// カテゴリー色（v2 Editorial Living）。
/// 既存のブランド色（Warm Ivory / Deep Forest / Brass）と調和する低彩度の色。原色は使わない。
/// 文字色には使わず、ドット・細い線・淡い背景にだけ使う（文字は LifeColors.text でコントラストを保つ）。
enum LifeCategoryColors {
    /// 予定：Mist Blue
    static let mistBlue = Color(hex: 0x8A9DAD)
    /// 買い物：Sage
    static let sage = Color(hex: 0x8FA38A)
    /// 家事：Terracotta
    static let terracotta = Color(hex: 0xB97E66)
    /// お金：Warm Gold
    static let warmGold = Color(hex: 0xBF9D62)
    /// 習慣：Lavender Gray
    static let lavenderGray = Color(hex: 0x9C97AC)
    /// ToDo：Deep Forest を少し明るくした色
    static let forestGray = Color(hex: 0x6F857C)

    /// 淡い背景にするときの透過度
    static let subtleOpacity: Double = 0.14
}

extension LifeItemKind {
    /// 種類ごとのカテゴリー色
    var tint: Color {
        switch self {
        case .event: return LifeCategoryColors.mistBlue
        case .shopping: return LifeCategoryColors.sage
        case .chore: return LifeCategoryColors.terracotta
        case .payment: return LifeCategoryColors.warmGold
        case .habit: return LifeCategoryColors.lavenderGray
        case .todo: return LifeCategoryColors.forestGray
        }
    }

    /// 種類ごとの淡い背景色
    var subtleTint: Color { tint.opacity(LifeCategoryColors.subtleOpacity) }
}
