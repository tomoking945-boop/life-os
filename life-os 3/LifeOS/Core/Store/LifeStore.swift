import Foundation
import Observation

/// アプリ内データの置き場（今回はメモリ上のMockのみ）。
/// TODO: Firebase 等へ接続する際は、ここを Repository プロトコル経由の読み書きに置き換える。
@Observable
final class LifeStore {
    var items: [LifeItem]
    var expenses: [Expense]
    var budget: MonthlyBudget
    var lists: [LifeList]

    init(
        items: [LifeItem] = MockData.items(),
        expenses: [Expense] = MockData.expenses(),
        budget: MonthlyBudget = MockData.budget(),
        lists: [LifeList] = MockData.lists
    ) {
        self.items = items
        self.expenses = expenses
        self.budget = budget
        self.lists = lists
    }

    // MARK: - 項目

    func toggleCompletion(of id: LifeItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()
    }

    func add(_ newItems: [LifeItem]) {
        items.append(contentsOf: newItems)
    }

    /// 指定日の項目（フィルター適用・予定は時刻順、その後にタスク）
    func items(on day: Date, scope: ScopeFilter) -> [LifeItem] {
        items
            .filter { LifeCalendar.isSameDay($0.date, day) && scope.includes($0.ownership) }
            .sorted { lhs, rhs in
                if lhs.hasTime != rhs.hasTime { return lhs.hasTime }
                return lhs.date < rhs.date
            }
    }

    // MARK: - リスト

    func list(id: LifeList.ID) -> LifeList? {
        lists.first(where: { $0.id == id })
    }

    func addList(title: String) {
        lists.append(LifeList(title: title))
    }
}
