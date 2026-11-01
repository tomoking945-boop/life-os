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
    /// 自分だけ（端末の中の life-store.json）か、わが家で共有（Firestore の groups/{groupID}/expenses）か（Build 13）。
    /// 端末に保存するのは「自分だけ」の支出だけ。以前の保存データには無いため、読むときに無ければ「自分だけ」
    var ownership: Ownership

    // 2026-10-01：支出は「自分 / 共有」で分けないと決めていた。
    // 2026-11-01（Build 13）：利用者が「わが家で共有」を選んだ支出だけを共有する（初期値は必ず「自分だけ」）

    init(id: UUID = UUID(), title: String, amount: Int, category: ExpenseCategory, date: Date, ownership: Ownership = .personal) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.ownership = ownership
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, category, date, ownership
    }

    /// 以前の保存データ（ownership が無い）も読める。無ければ「自分だけ」
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Int.self, forKey: .amount)
        category = try container.decode(ExpenseCategory.self, forKey: .category)
        date = try container.decode(Date.self, forKey: .date)
        ownership = try container.decodeIfPresent(Ownership.self, forKey: .ownership) ?? .personal
    }

    var isShared: Bool { ownership == .shared }
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
