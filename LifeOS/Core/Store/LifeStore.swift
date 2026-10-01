import Foundation
import Observation

/// アプリ内データの置き場。
/// アプリ本体では `LifeStore.persistent()` を使い、変更のたびに端末内へ保存する。
/// プレビューなどで `LifeStore()` を使った場合は保存しない（Mock のまま）。
/// TODO: Firebase 等へ接続する際は、ここを Repository プロトコル経由の読み書きに置き換える。
@Observable
final class LifeStore {
    var items: [LifeItem]
    var expenses: [Expense]
    var budget: MonthlyBudget
    var lists: [LifeList]

    /// true のとき、変更のたびに端末内へ保存する
    @ObservationIgnored private var persists = false

    /// 端末内に保存する形
    private struct Snapshot: Codable {
        var items: [LifeItem]
        var expenses: [Expense]
        var budget: MonthlyBudget
        var lists: [LifeList]
    }

    private static let fileName = "life-store.json"

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

    /// 端末内に保存されたデータを読み込む。初回（保存がない）ときは Mock データで始めて保存する。
    static func persistent() -> LifeStore {
        let store: LifeStore
        if let snapshot = LocalStorage.load(Snapshot.self, from: fileName) {
            store = LifeStore(
                items: snapshot.items,
                expenses: snapshot.expenses,
                budget: snapshot.budget,
                lists: snapshot.lists
            )
        } else {
            store = LifeStore()
        }
        store.persists = true
        store.save()
        return store
    }

    private func save() {
        guard persists else { return }
        LocalStorage.save(
            Snapshot(items: items, expenses: expenses, budget: budget, lists: lists),
            to: Self.fileName
        )
    }

    /// 開発用：保存したデータを捨てて、今日の日付の Mock データに戻す
    func resetToMock() {
        items = MockData.items()
        expenses = MockData.expenses()
        budget = MockData.budget()
        lists = MockData.lists
        save()
    }

    // MARK: - 項目

    func toggleCompletion(of id: LifeItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()
        save()
    }

    func add(_ newItems: [LifeItem]) {
        items.append(contentsOf: newItems)
        save()
    }

    /// 指定日の項目（フィルター適用・予定は時刻順、その後にタスク）
    /// TODO: 前日以前の未完了タスクを今日に繰り越すかは仕様未定。現状は日付どおりに表示する。
    func items(on day: Date, scope: ScopeFilter) -> [LifeItem] {
        items
            .filter { LifeCalendar.isSameDay($0.date, day) && scope.includes($0.ownership) }
            .sorted { lhs, rhs in
                if lhs.hasTime != rhs.hasTime { return lhs.hasTime }
                return lhs.date < rhs.date
            }
    }

    // MARK: - お金

    func add(_ expense: Expense) {
        expenses.append(expense)
        save()
    }

    // MARK: - リスト

    func list(id: LifeList.ID) -> LifeList? {
        lists.first(where: { $0.id == id })
    }

    func addList(title: String) {
        lists.append(LifeList(title: title))
        save()
    }

    func addItem(_ title: String, toList id: LifeList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].items.append(LifeListItem(title: title))
        save()
    }

    func removeItems(at offsets: IndexSet, fromList id: LifeList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        for offset in offsets.sorted(by: >) where lists[index].items.indices.contains(offset) {
            lists[index].items.remove(at: offset)
        }
        save()
    }
}
