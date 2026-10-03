import Foundation

/// 買い物のカテゴリー（v2 仕様 11）
enum ShoppingCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case food
    case chilled
    case dailyGoods
    case drinks
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: return "食品"
        case .chilled: return "冷蔵"
        case .dailyGoods: return "日用品"
        case .drinks: return "飲料"
        case .other: return "その他"
        }
    }
}

/// よく買うもの（共有スターター・買い物の再購入候補で使う）
struct FrequentPurchase: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var categories: [ShoppingCategory]
    /// 前回買った日（「前回購入から◯日」の表示用。Mock）
    var lastPurchasedAt: Date?

    init(id: UUID = UUID(), title: String, categories: [ShoppingCategory], lastPurchasedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.categories = categories
        self.lastPurchasedAt = lastPurchasedAt
    }

    /// 「食品 / 冷蔵」
    var categoryText: String {
        categories.map(\.label).joined(separator: " / ")
    }
}
