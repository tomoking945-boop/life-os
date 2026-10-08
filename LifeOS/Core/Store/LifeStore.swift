import Foundation
import Observation

/// アプリ内データの置き場。
/// アプリ本体では `LifeStore.persistent()` を使い、変更のたびに端末内へ保存する。
/// プレビューなどで `LifeStore()` を使った場合は保存しない（Mock のまま）。
/// Repository の窓口（Core/Repositories）にすべて適合している。Firebase 接続時は Firestore 版の Repository に差し替える。
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
    /// 習慣（毎日くり返す。Calm Future 第3段階）
    var habits: [Habit]
    /// LifeOSからの提案に答えた記録（Calm Future 第3段階）
    var suggestionDecisions: [SuggestionDecision]

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
        // Calm Future 第3段階で追加
        var habits: [Habit]?
        var suggestionDecisions: [SuggestionDecision]?
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
        frequentPurchases: [FrequentPurchase] = MockData.frequentPurchases(),
        habits: [Habit] = MockData.habits(),
        suggestionDecisions: [SuggestionDecision] = []
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
        self.habits = habits
        self.suggestionDecisions = suggestionDecisions
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
                frequentPurchases: snapshot.frequentPurchases ?? MockData.frequentPurchases(),
                habits: snapshot.habits ?? migratedHabits(from: snapshot.items),
                suggestionDecisions: snapshot.suggestionDecisions ?? []
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
                frequentPurchases: frequentPurchases,
                habits: habits,
                suggestionDecisions: suggestionDecisions
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
        habits = MockData.habits()
        suggestionDecisions = []
        save()
    }

    /// 第3段階より前の保存データ：日付つきの習慣の項目（水を飲む など）から、毎日くり返す習慣を作る。
    /// もとの項目は消さない（カレンダーのその日には今までどおり出る）。今日画面では同じ名前の習慣として表示する。
    /// 習慣の項目が無ければ Mock の習慣で始める。
    static func migratedHabits(from items: [LifeItem]) -> [Habit] {
        let habitItems = items.filter { $0.isHabit && !$0.isDropped }
        guard !habitItems.isEmpty else { return MockData.habits() }
        var titles: [String] = []
        for item in habitItems where !titles.contains(item.title) {
            titles.append(item.title)
        }
        return titles.map { title in
            let sameTitle = habitItems.filter { $0.title == title }
            let startedAt = sameTitle.map(\.displayDate).min() ?? LifeCalendar.now
            let doneDays = sameTitle.filter(\.isCompleted).map { LifeCalendar.startOfDay($0.displayDate) }
            return Habit(
                title: title,
                isLight: MockData.lightHabitTitles.contains(title),
                startedAt: startedAt,
                doneDays: Array(Set(doneDays))
            )
        }
    }

    // MARK: - 項目

    func toggleCompletion(of id: LifeItem.ID) {
        toggleCompletion(of: id, at: LifeCalendar.now)
    }

    /// 完了を切り替える。暮らしメモリーから追加した項目なら、完了で「前回」の記録を残し、取り消しで記録を消す。
    func toggleCompletion(of id: LifeItem.ID, at now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()
        let item = items[index]
        if let memoryID = item.memoryID, let memoryIndex = memories.firstIndex(where: { $0.id == memoryID }) {
            var history = memories[memoryIndex].history ?? []
            history.removeAll { $0.itemID == item.id }
            if item.isCompleted {
                // 新しい解釈：この端末で完了した人を「対応した人」とする。パートナー担当の項目はパートナー。
                // TODO: 共有の同期をつないだら、実際に完了したメンバーを記録する。
                history.append(MemoryRecord(date: now, by: item.assignee == .partner ? .partner : .me, itemID: item.id))
            }
            memories[memoryIndex].history = history
        }
        save()
    }

    func add(_ newItems: [LifeItem]) {
        items.append(contentsOf: newItems)
        registerHabits(from: newItems)
        save()
    }

    /// 習慣の追加・編集（2026-10-08）：種類「習慣」で追加した項目（Inbox の修正・詳しく整える など）は、
    /// 毎日くり返す習慣としても登録する。習慣の id は項目と同じにして、「元に戻す」で項目と一緒に消せるようにする。
    /// 同じ名前の習慣がすでにあれば登録しない。
    private func registerHabits(from newItems: [LifeItem]) {
        for item in newItems where item.isHabit && !habits.contains(where: { $0.title == item.title }) {
            habits.append(Habit(id: item.id, title: item.title, startedAt: item.date))
        }
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

    // MARK: - 元に戻す（Calm Future）

    /// 「元に戻す」：あとで・救済・もうやらない・共有 の前の状態に戻す。
    /// 戻すのは表示先・もうやらない・持ち主・担当だけ。その間に変えた完了チェックやタイトルは残す。
    func restore(_ snapshot: LifeItem) {
        guard let index = items.firstIndex(where: { $0.id == snapshot.id }) else { return }
        items[index].deferredTo = snapshot.deferredTo
        items[index].droppedAt = snapshot.droppedAt
        items[index].ownership = snapshot.ownership
        items[index].assignee = snapshot.assignee
        save()
    }

    /// 「元に戻す」：直前に追加した項目を取り除く
    func removeItems(withIDs ids: Set<LifeItem.ID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        // 項目と一緒に登録した習慣も取り除く（id が同じ）
        habits.removeAll { ids.contains($0.id) }
        save()
    }

    /// 「元に戻す」：暮らしメモリーを前の状態（周期・表示しない期間）に戻す
    func restoreMemory(_ snapshot: LifeMemory) {
        guard let index = memories.firstIndex(where: { $0.id == snapshot.id }) else { return }
        memories[index] = snapshot
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

    /// 「修正」した理解を保存する（nil で修正前に戻す）。「入力をもっと賢く」2026-10-07
    func saveInboxEdit(_ id: InboxItem.ID, suggestion: InboxSuggestion?) {
        guard let index = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[index].edit = suggestion
        save()
    }

    /// 「元に戻す」：Inbox のメモを前の状態に戻す（消したものは戻し、変えたものは元の内容にする）
    func restoreInbox(_ snapshots: [InboxItem]) {
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots {
            if let index = inbox.firstIndex(where: { $0.id == snapshot.id }) {
                inbox[index] = snapshot
            } else {
                inbox.append(snapshot)
            }
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

    /// 暮らしメモリーの提案に答えた記録を残す（買い物に追加＝採用、今回はスキップ＝スキップ）
    func recordMemoryDecision(_ id: LifeMemory.ID, choice: SuggestionChoice, at date: Date) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        var decisions = memories[index].decisions ?? []
        decisions.append(MemoryDecision(decidedAt: date, choice: choice))
        memories[index].decisions = decisions
        save()
    }

    // MARK: - 習慣（Calm Future 第3段階）

    /// その日に出す習慣（始めた日以降で、くり返しのルール上ある日）
    func habits(on day: Date) -> [Habit] {
        habits.filter { $0.isActive(on: day) }
    }

    /// 習慣を追加する（名前が空、または同じ名前の習慣があれば追加しない）
    /// - Returns: 追加した習慣
    @discardableResult
    func addHabit(title: String, isLight: Bool, repeatRule: HabitRepeat, startedAt: Date) -> Habit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !habits.contains(where: { $0.title == trimmed }) else { return nil }
        let habit = Habit(title: trimmed, repeatRule: repeatRule, isLight: isLight, startedAt: startedAt)
        habits.append(habit)
        save()
        return habit
    }

    /// 習慣の名前・軽い習慣か・くり返しを変える（できた日の記録はそのまま）。名前が空なら名前は変えない
    func updateHabit(_ id: Habit.ID, title: String, isLight: Bool, repeatRule: HabitRepeat) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { habits[index].title = trimmed }
        habits[index].isLight = isLight
        habits[index].repeatRule = repeatRule
        save()
    }

    /// 習慣を削除する。「元に戻す」のため、消した習慣と位置を返す
    @discardableResult
    func removeHabit(_ id: Habit.ID) -> (habit: Habit, index: Int)? {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return nil }
        let habit = habits.remove(at: index)
        save()
        return (habit, index)
    }

    /// 「元に戻す」：消した習慣を同じ位置に戻す（できた日の記録も戻る）
    func restoreHabit(_ habit: Habit, at index: Int) {
        guard !habits.contains(where: { $0.id == habit.id }) else { return }
        habits.insert(habit, at: min(max(index, 0), habits.count))
        save()
    }

    /// その日にできたかを切り替える
    func toggleHabit(_ id: Habit.ID, on day: Date) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        let start = LifeCalendar.startOfDay(day)
        if habits[index].isDone(on: start) {
            habits[index].doneDays.removeAll { LifeCalendar.isSameDay($0, start) }
        } else {
            habits[index].doneDays.append(start)
        }
        save()
    }

    // MARK: - LifeOSからの提案（Calm Future 第3段階）

    func recordSuggestion(_ decision: SuggestionDecision) {
        suggestionDecisions.append(decision)
        save()
    }

    /// 「元に戻す」：答えた記録を消す（同じ日にまた提案が出る）
    func removeSuggestionDecision(_ id: SuggestionDecision.ID) {
        suggestionDecisions.removeAll { $0.id == id }
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
