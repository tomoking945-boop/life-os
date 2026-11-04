import SwiftUI
import UIKit

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

    // MARK: 予定を登録した人（Build 19）。ライト・ダークのどちらでも見分けられる明るさにする

    /// 自分：ミント
    static let registrantMint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x86D1B8) : UIColor(hex: 0x4FAE8F)
    })
    /// パートナー：淡い桃色
    static let registrantPink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0xF0B3C2) : UIColor(hex: 0xDE8FA4)
    })
    /// 登録した人が分からない：中立的なグレー
    static let registrantGray = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0xA7A39D) : UIColor(hex: 0x8E8A84)
    })
}

extension ItemRegistrant {
    /// 登録した人の色（点・印に使う。文字の色には使わない。色だけに頼らず label も出す）
    var tint: Color {
        switch self {
        case .me: return LifeCategoryColors.registrantMint
        case .partner: return LifeCategoryColors.registrantPink
        case .unknown: return LifeCategoryColors.registrantGray
        }
    }
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
