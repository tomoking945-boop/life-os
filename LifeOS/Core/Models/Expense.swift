import Foundation

/// 支出カテゴリー
enum ExpenseCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case food
    case dailyGoods
    case diningOut
    case transport
    case subscription
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: return "食費"
        case .dailyGoods: return "日用品"
        case .diningOut: return "外食"
        case .transport: return "交通"
        case .subscription: return "サブスク"
        case .other: return "その他"
        }
    }
}

/// 支出1件
struct Expense: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var amount: Int
    var category: ExpenseCategory
    var date: Date

    // TODO: 支出の「自分 / 共有」区分は仕様未定のため未実装（お金は現状フィルター対象外）。
    // TODO: 家計分担ロジックは今回やらない。

    init(id: UUID = UUID(), title: String, amount: Int, category: ExpenseCategory, date: Date) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
    }
}

/// 月の予算と支出
struct MonthlyBudget: Hashable, Codable {
    var month: Date
    /// 今月の支出合計（Mock では仕様どおり固定値 ¥82,450）
    var spent: Int
    var budget: Int

    var remaining: Int { budget - spent }

    /// 予算に対する使用率（0〜1）
    var usageRatio: Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(spent) / Double(budget), 0), 1)
    }
}
