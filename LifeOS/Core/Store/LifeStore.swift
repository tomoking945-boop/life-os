import Foundation
import Observation

/// アプリ内データの置き場。
/// アプリ本体では `LifeStore.persistent()` を使い、変更のたびに端末内へ保存する。
/// プレビューなどで `LifeStore()` を使った場合は保存しない（Mock のまま）。
/// TODO: Firebase 等へ接続する際は、ここを Repository プロトコル経由の読み書きに置き換える（v2 第6回で設計）。
@Observable
final class LifeStore {
    var items: [LifeItem]
    var expenses: [Expense]
    var budget: MonthlyBudget
    var lists: [LifeList]
    /// おまかせInbox（未整理の生活メモ）
    var inbox: [InboxItem]
    /// 暮らしメモリー
    var memories: [LifeMemory]
    /// 家事オートパイロットの候補
    var choreTemplates: [ChoreTemplate]
    /// 家事オートパイロットの今日の状態
    var autopilot: AutopilotDay?
    /// よく買うもの
    var frequentPurchases: [FrequentPurchase]

    /// true のとき、変更のたびに端末内へ保存する
    @ObservationIgnored private var persists = false

    /// 端末内に保存する形
    /// v2 で追加した項目は、以前の保存データには無いため Optional（無ければ Mock の例で始める）
    private struct Snapshot: Codable {
        var items: [LifeItem]
        var expenses: [Expense]
        var budget: MonthlyBudget
        var lists: [LifeList]
        var inbox: [InboxItem]?
        var memories: [LifeMemory]?
        var choreTemplates: [ChoreTemplate]?
        var autopilot: AutopilotDay?
        var frequentPurchases: [FrequentPurchase]?
    }

    private static let fileName = "life-store.json"

    init(
        items: [LifeItem] = MockData.items(),
        expenses: [Expense] = MockData.expenses(),
        budget: MonthlyBudget = MockData.budget(),
        lists: [LifeList] = MockData.lists,
        inbox: [InboxItem] = MockData.inbox(),
        memories: [LifeMemory] = MockData.memories(),
        choreTemplates: [ChoreTemplate] = MockData.choreTemplates,
        autopilot: AutopilotDay? = nil,
        frequentPurchases: [FrequentPurchase] = MockData.frequentPurchases()
    ) {
        self.items = items
        self.expenses = expenses
        self.budget = budget
        self.lists = lists
        self.inbox = inbox
        self.memories = memories
        self.choreTemplates = choreTemplates
        self.autopilot = autopilot
        self.frequentPurchases = frequentPurchases
    }

    /// 端末内に保存されたデータを読み込む。初回（保存がない）ときは Mock データで始めて保存する。
    static func persistent() -> LifeStore {
        let store: LifeStore
        if let snapshot = LocalStorage.load(Snapshot.self, from: fileName) {
            store = LifeStore(
                items: snapshot.items,
                expenses: snapshot.expenses,
                budget: snapshot.budget,
                lists: snapshot.lists,
                inbox: snapshot.inbox ?? MockData.inbox(),
                memories: snapshot.memories ?? MockData.memories(),
                choreTemplates: snapshot.choreTemplates ?? MockData.choreTemplates,
                autopilot: snapshot.autopilot,
                frequentPurchases: snapshot.frequentPurchases ?? MockData.frequentPurchases()
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
            Snapshot(
                items: items,
                expenses: expenses,
                budget: budget,
                lists: lists,
                inbox: inbox,
                memories: memories,
                choreTemplates: choreTemplates,
                autopilot: autopilot,
                frequentPurchases: frequentPurchases
            ),
            to: Self.fileName
        )
    }

    /// 開発用：保存したデータを捨てて、今日の日付の Mock データに戻す
    func resetToMock() {
        items = MockData.items()
        expenses = MockData.expenses()
        budget = MockData.budget()
        lists = MockData.lists
        inbox = MockData.inbox()
        memories = MockData.memories()
        choreTemplates = MockData.choreTemplates
        autopilot = nil
        frequentPurchases = MockData.frequentPurchases()
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

    /// 指定日に表示する項目（フィルター適用・時刻のあるものを先に、その後にタスク）
    /// 「あとで」「未完了救済」で回した項目は、回した先の日に表示する（元の日付は変えない）。
    /// 「もうやらない」にした項目は出さない。
    func items(on day: Date, scope: ScopeFilter) -> [LifeItem] {
        items
            .filter { !$0.isDropped && LifeCalendar.isSameDay($0.displayDate, day) && scope.includes($0.ownership) }
            .sorted { lhs, rhs in
                if lhs.showsTime != rhs.showsTime { return lhs.showsTime }
                return lhs.displayDate < rhs.displayDate
            }
    }

    /// 未完了救済：指定日より前に残っている未完了のタスク（習慣は除く）
    func leftovers(before day: Date, scope: ScopeFilter) -> [LifeItem] {
        let start = LifeCalendar.startOfDay(day)
        return items
            .filter { item in
                item.isTask && !item.isHabit && !item.isCompleted && !item.isDropped
                    && item.displayDate < start && scope.includes(item.ownership)
            }
            .sorted { $0.displayDate < $1.displayDate }
    }

    /// あとで・未完了救済：表示先の日時を変える（元の日付 `date` は変えない）
    func reschedule(_ id: LifeItem.ID, to date: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].deferredTo = date
        save()
    }

    /// もうやらない：削除せず、一覧に出さないだけにする
    func drop(_ id: LifeItem.ID, at date: Date = LifeCalendar.now) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].droppedAt = date
        save()
    }

    /// パートナーと共有：自分の項目を共有にする（担当は「どちらでも」）
    func share(_ id: LifeItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].ownership = .shared
        items[index].assignee = .either
        save()
    }

    // MARK: - 買い物

    /// 買い物を追加する（ワンタップ追加・献立から作成）。同じ品名の未完了の買い物があれば追加しない。
    /// - Returns: 実際に追加した件数
    @discardableResult
    func addShopping(_ names: [String], ownership: Ownership, now: Date = LifeCalendar.now) -> Int {
        let today = LifeCalendar.startOfDay(now)
        let open = Set(items
            .filter { $0.kind == .shopping && !$0.isCompleted && !$0.isDropped }
            .map { ShoppingCategorizer.itemName(from: $0.title) })
        let newItems = names
            .filter { !open.contains($0) }
            .map { name in
                LifeItem(
                    title: "\(name)を買う",
                    kind: .shopping,
                    ownership: ownership,
                    date: today,
                    assignee: ownership == .shared ? .either : .me
                )
            }
        guard !newItems.isEmpty else { return 0 }
        items.append(contentsOf: newItems)
        save()
        return newItems.count
    }

    /// 買えたとき：よく買うものの「前回購入」を今日にする
    func markPurchased(_ title: String, now: Date = LifeCalendar.now) {
        let name = ShoppingCategorizer.itemName(from: title)
        guard let index = frequentPurchases.firstIndex(where: { $0.title == name }) else { return }
        frequentPurchases[index].lastPurchasedAt = now
        save()
    }

    // MARK: - 共有スターター

    /// 二人の生活OSを30秒で作る：選んだものだけ反映する（どれも省略できる）
    func applySharedStarter(trashWeekdays: [Int], frequentTitles: [String], commonEvent: (title: String, date: Date)?) {
        if !trashWeekdays.isEmpty {
            if let index = memories.firstIndex(where: { $0.title == "ゴミ" }) {
                memories[index].rule = .weekdays(trashWeekdays.sorted())
            } else {
                memories.append(LifeMemory(title: "ゴミ", rule: .weekdays(trashWeekdays.sorted()), action: .notifyOnly))
            }
        }
        for title in frequentTitles where !frequentPurchases.contains(where: { $0.title == title }) {
            frequentPurchases.append(FrequentPurchase(title: title, categories: ShoppingCategorizer.categories(for: title)))
        }
        if let commonEvent {
            items.append(LifeItem(
                title: commonEvent.title,
                kind: .event,
                ownership: .shared,
                date: LifeCalendar.startOfDay(commonEvent.date),
                assignee: .either
            ))
        }
        save()
    }

    // MARK: - おまかせInbox

    /// 分類せずに「とりあえず保存」する
    func addToInbox(_ text: String, now: Date = LifeCalendar.now) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inbox.append(InboxItem(text: trimmed, createdAt: now))
        save()
    }

    func removeFromInbox(_ ids: Set<InboxItem.ID>) {
        inbox.removeAll { ids.contains($0.id) }
        save()
    }

    /// 「後で」：指定日時まで、おまかせ整理に出さない（Inbox には残る）
    func postponeInbox(_ ids: Set<InboxItem.ID>, until date: Date) {
        for index in inbox.indices where ids.contains(inbox[index].id) {
            inbox[index].postponedUntil = date
        }
        save()
    }

    // MARK: - 暮らしメモリー

    /// 指定日時まで今日画面に出さない
    func hideMemory(_ id: LifeMemory.ID, until date: Date) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].hiddenUntil = date
        save()
    }

    /// 「前回から」の起点を変える（今回はスキップ：周期をここから数え直す）
    func restartMemoryCycle(_ id: LifeMemory.ID, from date: Date) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        if case let .sinceLast(_, dueAfterDays) = memories[index].rule {
            memories[index].rule = .sinceLast(lastDate: date, dueAfterDays: dueAfterDays)
        }
        save()
    }

    // MARK: - 家事オートパイロット

    /// 今日の状態（日付が変わっていたら新しい日として扱う）
    func autopilotDay(for now: Date) -> AutopilotDay {
        let today = LifeCalendar.startOfDay(now)
        if let current = autopilot, LifeCalendar.isSameDay(current.day, today) {
            return current
        }
        return AutopilotDay(day: today, energy: nil, doneChoreIDs: [])
    }

    func setEnergy(_ energy: EnergyLevel, now: Date) {
        var day = autopilotDay(for: now)
        day.energy = energy
        autopilot = day
        save()
    }

    func toggleChore(_ choreID: ChoreTemplate.ID, now: Date) {
        var day = autopilotDay(for: now)
        if day.doneChoreIDs.contains(choreID) {
            day.doneChoreIDs.removeAll { $0 == choreID }
        } else {
            day.doneChoreIDs.append(choreID)
        }
        autopilot = day
        save()
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
