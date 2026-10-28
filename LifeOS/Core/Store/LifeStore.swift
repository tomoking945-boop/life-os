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
    /// 保証書（Premium「大切な書類」2026-10-13）。端末内にだけ保存する
    var warranties: [WarrantyDocument]
    /// 保証書の写真の情報（写真そのものは WarrantyAttachmentStorage が別のファイルに保存する）
    var warrantyAttachments: [WarrantyAttachment]

    /// 保証書の写真の保存先（テストでは一時フォルダに差し替える）
    @ObservationIgnored var warrantyStorage = WarrantyAttachmentStorage()

    /// true のとき、変更のたびに端末内へ保存する
    @ObservationIgnored private var persists = false

    /// パートナー共有（2026-10-11）：項目の変更を知らせる先（observeItems で登録）
    @ObservationIgnored private var itemObservers: [UUID: ([LifeItem]) -> Void] = [:]

    /// わが家で共有している ToDo・買い物（2026-10-28 Build 7）。Firestore から受け取る。
    /// 端末の life-store.json には保存しない（items とは別。個人データの保存の形は変えない）
    private(set) var householdItems: [LifeItem] = []
    /// 共有項目の保存を頼む先（SharedItemsService）。無ければ「わが家で共有」は選べない
    @ObservationIgnored weak var householdSync: HouseholdItemSyncing?
    /// 共有の保存の結果がまだ届いていない作成（2026-10-28 Build 9）。
    /// Firestore から空・古い一覧が届いても、結果が届くまでは画面から消さない
    @ObservationIgnored private var pendingHouseholdCreates: [LifeItem.ID: LifeItem] = [:]

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
        // 保証書管理（2026-10-13）で追加。以前の保存データには無いため Optional（無ければ空）
        var warranties: [WarrantyDocument]?
        var warrantyAttachments: [WarrantyAttachment]?
    }

    /// 保存ファイルの名前（AppState が既存の利用者かどうかを調べるときにも使う）
    static let fileName = "life-store.json"

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
        suggestionDecisions: [SuggestionDecision] = [],
        warranties: [WarrantyDocument] = [],
        warrantyAttachments: [WarrantyAttachment] = []
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
        self.warranties = warranties
        self.warrantyAttachments = warrantyAttachments
    }

    /// 端末内に保存されたデータを読み込む。初回（保存がない）ときは Mock データで始めて保存する。
    static func persistent() -> LifeStore {
        persistent(startEmptyIfNoSavedData: false)
    }

    /// はじめての設定（2026-10-09）：端末内に保存されたデータを読み込む。
    /// 保存が無いとき、`startEmptyIfNoSavedData` が true なら空のデータ（`LifeStore.empty()`）で始める。
    /// 新しく使い始める人には見本（Mock）データを入れず、はじめての設定で本人のデータを作る。
    /// 保存済みのデータはこれまでどおりそのまま読み込む（以前の保存データに無い項目だけ、これまでどおり補う）。
    static func persistent(startEmptyIfNoSavedData: Bool) -> LifeStore {
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
                suggestionDecisions: snapshot.suggestionDecisions ?? [],
                warranties: snapshot.warranties ?? [],
                warrantyAttachments: snapshot.warrantyAttachments ?? []
            )
        } else if startEmptyIfNoSavedData {
            store = LifeStore.empty()
        } else {
            store = LifeStore()
        }
        store.persists = true
        store.save()
        // 保証書：前回の途中で残った一時ファイルと、どの保証書からも参照されていない写真を消す
        store.cleanUpWarrantyFiles()
        return store
    }

    private func save() {
        notifyItemObservers()
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
                suggestionDecisions: suggestionDecisions,
                warranties: warranties,
                warrantyAttachments: warrantyAttachments
            ),
            to: Self.fileName
        )
    }

    // MARK: - 監視（パートナー共有 2026-10-11）

    /// 項目の変更を監視する（LifeItemRepository）。変更を保存するたびに、今の一覧で呼ぶ
    func observeItems(_ onChange: @escaping ([LifeItem]) -> Void) -> RepositoryObservation {
        let id = UUID()
        itemObservers[id] = onChange
        onChange(items)
        return RepositoryObservation { [weak self] in
            self?.itemObservers[id] = nil
        }
    }

    private func notifyItemObservers() {
        guard !itemObservers.isEmpty else { return }
        let current = items
        for observer in itemObservers.values {
            observer(current)
        }
    }

    /// 新しく使い始める人の空のデータ（保存しない。保存は persistent から）。
    /// 予定・支出・リスト・Inbox・暮らしメモリー・よく買うもの・習慣は空。予算は 0 円。
    /// 新しい解釈：家事オートパイロットの候補（ゴミをまとめる 等）は本人の記録ではなく「今日の余力」の選択肢なので残す。
    static func empty(now: Date = LifeCalendar.now) -> LifeStore {
        LifeStore(
            items: [],
            expenses: [],
            budget: MonthlyBudget(month: LifeCalendar.startOfMonth(now), spent: 0, budget: 0),
            lists: [],
            inbox: [],
            memories: [],
            choreTemplates: MockData.choreTemplates,
            autopilot: nil,
            frequentPurchases: [],
            habits: [],
            suggestionDecisions: []
        )
    }

    /// 開発用：保存したデータを捨てて、今日の日付の Mock データに戻す
    /// 保証書（2026-10-13）は利用者の書類のため、ここでは消さない（Mock の保証書は無い）
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
    /// わが家の共有項目なら、共有の保存先へ送る（2026-10-28）
    func toggleCompletion(of id: LifeItem.ID, at now: Date) {
        if updateHouseholdItem(id, { $0.isCompleted.toggle() }) { return }
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
        visibleItems
            .filter { !$0.isDropped && LifeCalendar.isSameDay($0.displayDate, day) && scope.includes($0.ownership) }
            .sorted { lhs, rhs in
                if lhs.showsTime != rhs.showsTime { return lhs.showsTime }
                return lhs.displayDate < rhs.displayDate
            }
    }

    /// 未完了救済：指定日より前に残っている未完了のタスク（習慣は除く）
    func leftovers(before day: Date, scope: ScopeFilter) -> [LifeItem] {
        let start = LifeCalendar.startOfDay(day)
        return visibleItems
            .filter { item in
                item.isTask && !item.isHabit && !item.isCompleted && !item.isDropped
                    && item.displayDate < start && scope.includes(item.ownership)
            }
            .sorted { $0.displayDate < $1.displayDate }
    }

    /// あとで・未完了救済：表示先の日時を変える（元の日付 `date` は変えない）
    func reschedule(_ id: LifeItem.ID, to date: Date) {
        if updateHouseholdItem(id, { $0.deferredTo = date }) { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].deferredTo = date
        save()
    }

    /// もうやらない：削除せず、一覧に出さないだけにする
    func drop(_ id: LifeItem.ID, at date: Date = LifeCalendar.now) {
        if updateHouseholdItem(id, { $0.droppedAt = date }) { return }
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

    // MARK: - 編集・削除（2026-10-28）

    /// 名前を変える（端末の項目も、わが家の共有項目も）。空白だけの名前は受け付けない
    func rename(_ id: LifeItem.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if updateHouseholdItem(id, { $0.title = trimmed }) { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
        save()
    }

    /// 削除する（利用者が編集画面で「削除」を選んだときだけ）。わが家の共有項目なら、相手の画面からも消える
    func deleteItem(_ id: LifeItem.ID) {
        if isHouseholdItem(id) {
            deleteHouseholdItem(id)
            return
        }
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
    }

    // MARK: - わが家で共有（2026-10-28 Build 7。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）

    /// 画面に出す項目：端末の項目＋わが家の共有項目。
    /// 同じ ID（共有へ変換中）なら共有の方だけを出す（二重に出さない）
    var visibleItems: [LifeItem] {
        guard !householdItems.isEmpty else { return items }
        let sharedIDs = Set(householdItems.map(\.id))
        return items.filter { !sharedIDs.contains($0.id) } + householdItems
    }

    /// わが家の共有項目か（共有マークを出す）
    func isHouseholdItem(_ id: LifeItem.ID) -> Bool {
        householdItems.contains { $0.id == id }
    }

    /// その種類で「わが家で共有」を選べるか（ToDo・買い物で、わが家の設定でオン）
    func canShareInHousehold(_ kind: LifeItemKind) -> Bool {
        HouseholdItemPolicy.kinds.contains(kind) && (householdSync?.allowsSharing(kind) ?? false)
    }

    /// 新しい項目を、選んだ保存先へ追加する。
    /// 「わが家で共有」は、共有できる種類（ToDo・買い物）で、わが家の設定でオンのときだけ。それ以外は「自分だけ」として端末に保存する。
    /// - Returns: わが家で共有した件数
    @discardableResult
    func add(_ newItems: [LifeItem], destination: SaveDestination) -> Int {
        guard destination == .household else {
            add(newItems.map(Self.personalCopy))
            return 0
        }
        var local: [LifeItem] = []
        var sharedCount = 0
        for item in newItems {
            if let sync = householdSync, canShareInHousehold(item.kind), HouseholdItemPolicy.canShare(item) {
                let shared = Self.householdCopy(of: item)
                householdItems.append(shared)
                pendingHouseholdCreates[shared.id] = shared
                sync.createHouseholdItem(shared, convertingLocal: false)
                sharedCount += 1
            } else {
                local.append(Self.personalCopy(item))
            }
        }
        if !local.isEmpty { add(local) }
        return sharedCount
    }

    /// 端末の項目を「わが家で共有」にする（利用者が編集画面で選んだときだけ）。
    /// 端末の項目は、サーバーで保存が確かめられるまで消さない（通信できない・断られたときも残る）。
    /// - Returns: 共有の保存を始めたら true
    @discardableResult
    func convertToHousehold(_ id: LifeItem.ID) -> Bool {
        guard !isHouseholdItem(id),
              let item = items.first(where: { $0.id == id }),
              !item.isDropped,
              canShareInHousehold(item.kind),
              HouseholdItemPolicy.canShare(item),
              let sync = householdSync else { return false }
        let shared = Self.householdCopy(of: item)
        householdItems.append(shared)
        pendingHouseholdCreates[shared.id] = shared
        sync.createHouseholdItem(shared, convertingLocal: true)
        return true
    }

    /// Firestore から届いた一覧で、共有項目を入れ替える（自分の変更も相手の変更も、ここに1件ずつだけ）。
    /// サーバーで保存が確かめられた項目と同じ ID の端末の ToDo・買い物（共有へ変換したもの）は、ここで片付ける
    func applyHouseholdSnapshot(_ snapshots: [SharedItemSnapshot]) {
        var received = snapshots.map(\.item)
        // 保存の結果がまだ届いていない自分の作成は、一覧に無くても残す（最初の・一時的な空の一覧で消さない。2026-10-28 Build 9）
        let receivedIDs = Set(received.map(\.id))
        for (id, item) in pendingHouseholdCreates where !receivedIDs.contains(id) {
            received.append(item)
        }
        householdItems = received
        let confirmed = Set(snapshots.filter(\.isConfirmed).map(\.item.id))
        removeConvertedLocalItems(confirmed)
    }

    /// 共有への変換がサーバーで保存されたとき（SharedItemsService から）
    func finishHouseholdConversion(_ id: LifeItem.ID) {
        removeConvertedLocalItems([id])
    }

    /// 共有の保存が断られたとき（SharedItemsService から）。
    /// 新しく作った項目は「自分だけ」として端末に残す（消さない）。変換なら端末の項目がそのまま残っている
    func householdCreateFailed(_ item: LifeItem, convertingLocal: Bool) {
        pendingHouseholdCreates[item.id] = nil
        householdItems.removeAll { $0.id == item.id }
        guard !convertingLocal, !items.contains(where: { $0.id == item.id }) else { return }
        items.append(Self.personalCopy(item))
        save()
    }

    /// 共有項目の表示を消す（退出・わが家の削除・サインアウトのとき）。端末の個人データは消さない
    func clearHouseholdItems() {
        // 送信待ちの作成の印も外す（結果が届けば、断られたものは householdCreateFailed で自分だけに残る）
        pendingHouseholdCreates = [:]
        guard !householdItems.isEmpty else { return }
        householdItems = []
    }

    /// 共有の作成がサーバーで受け付けられたとき（SharedItemsService から）：送信待ちの印を外す
    func finishHouseholdCreate(_ id: LifeItem.ID) {
        pendingHouseholdCreates[id] = nil
    }

    private func removeConvertedLocalItems(_ ids: Set<LifeItem.ID>) {
        guard !ids.isEmpty else { return }
        let before = items.count
        items.removeAll { ids.contains($0.id) && HouseholdItemPolicy.kinds.contains($0.kind) }
        if items.count != before { save() }
    }

    /// わが家の共有項目を変えて、共有の保存先へ送る。共有項目でなければ false（端末の項目として扱う）
    private func updateHouseholdItem(_ id: LifeItem.ID, _ change: (inout LifeItem) -> Void) -> Bool {
        guard let index = householdItems.firstIndex(where: { $0.id == id }) else { return false }
        var item = householdItems[index]
        change(&item)
        householdItems[index] = item
        householdSync?.updateHouseholdItem(item)
        return true
    }

    private func deleteHouseholdItem(_ id: LifeItem.ID) {
        pendingHouseholdCreates[id] = nil
        householdItems.removeAll { $0.id == id }
        householdSync?.deleteHouseholdItem(id)
    }

    /// 共有へ送る形（持ち主は共有・担当なし・柔らかい時間と暮らしメモリーのつながりは送らない）
    private static func householdCopy(of item: LifeItem) -> LifeItem {
        var copy = item
        copy.ownership = .shared
        copy.assignee = nil
        copy.softTime = nil
        copy.memoryID = nil
        copy.title = SharedItemPayload.title(item.title)
        return copy
    }

    /// 端末に保存する形（自分だけ）
    private static func personalCopy(_ item: LifeItem) -> LifeItem {
        var copy = item
        copy.ownership = .personal
        if copy.assignee == nil || copy.assignee == .either { copy.assignee = .me }
        return copy
    }

    // MARK: - 元に戻す（Calm Future）

    /// 「元に戻す」：あとで・救済・もうやらない・共有 の前の状態に戻す。
    /// 戻すのは表示先・もうやらない・持ち主・担当だけ。その間に変えた完了チェックやタイトルは残す。
    func restore(_ snapshot: LifeItem) {
        // わが家の共有項目：表示先・もうやらないだけを戻す（持ち主・担当は共有のまま）
        if updateHouseholdItem(snapshot.id, { item in
            item.deferredTo = snapshot.deferredTo
            item.droppedAt = snapshot.droppedAt
        }) { return }
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
        // わが家の共有項目は、共有の保存先から消す（2026-10-28）
        for id in ids where isHouseholdItem(id) {
            deleteHouseholdItem(id)
        }
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

    /// 買い物を、選んだ保存先へ追加する（2026-10-28）。同じ品名の未完了の買い物（共有の買い物も含む）があれば追加しない。
    /// 「わが家で共有」は、わが家の設定で買い物がオンのときだけ。それ以外は自分だけ
    /// - Returns: 実際に追加した件数
    @discardableResult
    func addShopping(_ names: [String], destination: SaveDestination, now: Date = LifeCalendar.now) -> Int {
        let today = LifeCalendar.startOfDay(now)
        let open = Set(visibleItems
            .filter { $0.kind == .shopping && !$0.isCompleted && !$0.isDropped }
            .map { ShoppingCategorizer.itemName(from: $0.title) })
        var seen = Set<String>()
        let newItems = names
            .filter { !open.contains($0) && seen.insert($0).inserted }
            .map { name in
                LifeItem(title: "\(name)を買う", kind: .shopping, ownership: .personal, date: today, assignee: .me)
            }
        guard !newItems.isEmpty else { return 0 }
        add(newItems, destination: destination)
        return newItems.count
    }

    /// 買えたとき：よく買うものの「前回購入」を今日にする
    func markPurchased(_ title: String, now: Date = LifeCalendar.now) {
        let name = ShoppingCategorizer.itemName(from: title)
        guard let index = frequentPurchases.firstIndex(where: { $0.title == name }) else { return }
        frequentPurchases[index].lastPurchasedAt = now
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

    // MARK: - 保証書（Premium「大切な書類」2026-10-13）

    func warranty(id: WarrantyDocument.ID) -> WarrantyDocument? {
        warranties.first { $0.id == id }
    }

    /// 保証書の写真（保証書の並び順どおり）
    func attachments(for documentID: WarrantyDocument.ID) -> [WarrantyAttachment] {
        guard let document = warranty(id: documentID) else {
            return warrantyAttachments.filter { $0.documentID == documentID }
        }
        return document.attachmentIDs.compactMap { id in
            warrantyAttachments.first { $0.id == id && $0.documentID == documentID }
        }
    }

    /// 同じ画像（SHA-256 が同じ）がすでに登録されている保証書
    func warrantyContainingImage(sha256: String) -> WarrantyDocument? {
        guard let attachment = warrantyAttachments.first(where: { $0.sha256 == sha256 }) else { return nil }
        return warranty(id: attachment.documentID)
    }

    /// 保証書を追加・更新する。新しい写真は原本のまま保存先へ移し、取り除いた写真は消す。
    /// 写真の保存に失敗したら、データは何も変えずに throw する（移した写真は一時フォルダへ戻っている）。
    @discardableResult
    func saveWarranty(
        _ document: WarrantyDocument,
        adding newFiles: [WarrantyStagedFile] = [],
        removing removedAttachmentIDs: Set<WarrantyAttachment.ID> = [],
        now: Date = Date()
    ) throws -> WarrantyDocument {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw WarrantySaveError.missingTitle }

        let keptIDs = document.attachmentIDs.filter { id in
            !removedAttachmentIDs.contains(id)
                && warrantyAttachments.contains { $0.id == id && $0.documentID == document.id }
        }
        guard keptIDs.count + newFiles.count <= WarrantyDocument.maxAttachments else {
            throw WarrantyAttachmentError.tooManyAttachments
        }

        let committed = try warrantyStorage.commit(newFiles, documentID: document.id, now: now)

        var saved = document
        saved.title = title
        saved.attachmentIDs = keptIDs + committed.map(\.id)
        saved.updatedAt = now
        let removed = warrantyAttachments.filter { $0.documentID == document.id && !saved.attachmentIDs.contains($0.id) }
        warrantyAttachments.removeAll { $0.documentID == document.id && !saved.attachmentIDs.contains($0.id) }
        warrantyAttachments.append(contentsOf: committed)
        if let index = warranties.firstIndex(where: { $0.id == document.id }) {
            saved.createdAt = warranties[index].createdAt
            warranties[index] = saved
        } else {
            warranties.append(saved)
        }
        save()
        removed.forEach(warrantyStorage.delete)
        return saved
    }

    /// 保証書を削除する：データとすべての写真を消す（通知は、保証書の一覧が変わったときに予約し直して消える）
    func deleteWarranty(id: WarrantyDocument.ID) {
        warranties.removeAll { $0.id == id }
        warrantyAttachments.removeAll { $0.documentID == id }
        save()
        warrantyStorage.deleteFiles(for: id)
    }

    /// 写真を1枚消す（Premium 終了後も、容量を空けるために使える）
    func deleteWarrantyAttachment(id: WarrantyAttachment.ID) {
        guard let attachment = warrantyAttachments.first(where: { $0.id == id }) else { return }
        warrantyAttachments.removeAll { $0.id == id }
        if let index = warranties.firstIndex(where: { $0.id == attachment.documentID }) {
            warranties[index].attachmentIDs.removeAll { $0 == id }
        }
        save()
        warrantyStorage.delete(attachment)
    }

    /// 写真の合計の大きさ（この iPhone の中で使っている容量）
    var warrantyAttachmentByteCount: Int64 {
        warrantyAttachments.reduce(0) { $0 + $1.byteCount }
    }

    /// 起動時：一時ファイルと、どの保証書からも参照されていない写真を消す
    func cleanUpWarrantyFiles() {
        warrantyStorage.clearStaging()
        warrantyStorage.removeOrphans(keeping: warrantyAttachments)
    }
}

/// 保証書を保存できなかった理由
enum WarrantySaveError: Error, Equatable {
    /// 製品名が空
    case missingTitle
}
