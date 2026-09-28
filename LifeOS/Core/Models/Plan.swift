import Foundation

/// 料金プラン（Mock。StoreKit には接続しない）
enum PlanType: String, CaseIterable, Identifiable, Hashable {
    case free
    case premium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        }
    }
}

/// Premium の支払い周期
enum PremiumBillingOption: String, CaseIterable, Identifiable, Hashable {
    case monthly
    case annual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: return "月額"
        case .annual: return "年額"
        }
    }

    /// 価格（円）
    var price: Int {
        switch self {
        case .monthly: return 480
        case .annual: return 5_280
        }
    }

    /// 補足表示
    var note: String? {
        switch self {
        case .monthly: return nil
        case .annual: return "年額なら1か月分お得"
        }
    }
}
