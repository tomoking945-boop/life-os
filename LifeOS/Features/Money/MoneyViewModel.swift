import Foundation
import Observation

@Observable
final class MoneyViewModel {
    private let store: LifeStore

    /// nil のときは「すべて」
    var selectedCategory: ExpenseCategory?

    init(store: LifeStore) {
        self.store = store
    }

    // MARK: - 今月のまとめ

    var spent: Int { store.budget.spent }
    var budget: Int { store.budget.budget }
    var remaining: Int { store.budget.remaining }
    var usageRatio: Double { store.budget.usageRatio }

    var usagePercentText: String {
        "\(Int((usageRatio * 100).rounded()))%"
    }

    // MARK: - 支出一覧

    let categories = ExpenseCategory.allCases

    /// TODO: カテゴリー別の集計金額は仕様未定のため表示していない（一覧の絞り込みのみ）。
    var expenses: [Expense] {
        store.expenses
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { $0.date > $1.date }
    }

    func detailText(for expense: Expense) -> String {
        "\(expense.category.label)・\(LifeFormatters.shortDate(expense.date))"
    }

    func select(_ category: ExpenseCategory?) {
        selectedCategory = category
    }
}
