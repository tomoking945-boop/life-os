import Foundation
import Observation

@Observable
final class MoneyViewModel {
    /// v2 第6回：LifeStore ではなく Repository の窓口を通して読む（将来 Firestore に差し替えやすくするため）
    private let repository: any ExpenseRepository

    /// nil のときは「すべて」
    var selectedCategory: ExpenseCategory?

    init(store repository: any ExpenseRepository) {
        self.repository = repository
    }

    // MARK: - 今月のまとめ

    var spent: Int { repository.budget.spent }
    var budget: Int { repository.budget.budget }
    var remaining: Int { repository.budget.remaining }
    var usageRatio: Double { repository.budget.usageRatio }

    var usagePercentText: String {
        "\(Int((usageRatio * 100).rounded()))%"
    }

    // MARK: - 支出一覧

    let categories = ExpenseCategory.allCases

    /// TODO: カテゴリー別の集計金額は仕様未定のため表示していない（一覧の絞り込みのみ）。
    var expenses: [Expense] {
        repository.expenses
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
