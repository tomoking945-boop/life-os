import Foundation
import Observation

/// 操作のあとに短く出す一言と「元に戻す」（Calm Future）
struct TodayFeedback: Equatable {
    let id = UUID()
    let message: String
    /// nil なら「元に戻す」を出さない
    let undo: (() -> Void)?

    static func == (lhs: TodayFeedback, rhs: TodayFeedback) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
final class TodayViewModel {
    private let store: LifeStore
    private let appState: AppState
    let now: Date

    /// 「あとで」シートの対象
    var postponingItem: LifeItem?
    /// 家族招待シートを出しているか
    var isShowingInvite = false
    /// 家族招待シートで見せる項目（項目から招待したとき）
    var invitingItem: LifeItem?
    /// 「今日これだけ」の残りを開いているか
    var isShowingRest = false
    /// 操作のあとに短く出す一言（例：明日に回しました）と「元に戻す」
    var feedback: TodayFeedback?

    init(store: LifeStore, appState: AppState, now: Date = LifeCalendar.now) {
        self.store = store
        self.appState = appState
        self.now = now
    }

    // MARK: - ヘッダー

    /// Editorial Living：英語の日付をセリフ体で（例：Saturday, October 3）
    var dateTitle: String { LifeFormatters.editorialDate(now) }
    /// 日本語の日付（小さく添える）
    var japaneseDateTitle: String { LifeFormatters.headerDate(now) }
    var spokenDateTitle: String { LifeFormatters.spokenDate(now) }

    /// 時間帯（背景の空気感と挨拶）。開発用設定で切り替えたときはそちらを使う。
    var timeOfDay: LifeTimeOfDay {
        appState.ambientPreview ?? LifeTimeOfDay(date: now)
    }

    /// 挨拶（時間帯で変わる。Mock の現在時刻 9:10 では従来どおり Good morning.）
    var greeting: String { timeOfDay.greeting }
    /// v2 の目標イメージに合わせたキャッチコピー（Ambient Header に一言が無いときに使う）
    let subtitle = "今日も、無理なく。"

    // MARK: - Ambient Header（Calm Future）

    /// いちばん上に出す一言。
    /// 次の予定があれば「10:30の歯医者まで1時間20分」、無ければ余白を伝える。
    var ambientMessage: String {
        if isFocusCompleted {
            return focusCompletedMessage
        }
        if let next = nextEvent, let duration = LifeFormatters.duration(from: now, to: next.displayDate) {
            return "\(timeText(for: next))の\(next.title)まで\(duration)"
        }
        if timelineSections.isEmpty {
            return "今日は少し余白があります"
        }
        return subtitle
    }

    /// 二つ目の一言（今日これだけ の件数・余力）。責めない言い方だけを使う。
    var ambientSubMessage: String {
        if energy == .low {
            return "今日は軽めで大丈夫です"
        }
        let open = focusItems.filter { !$0.isCompleted }.count
        if open > 0 {
            return "今日は\(open)つだけで十分です"
        }
        if !extraItems.isEmpty {
            return "ほかは、余力があればで大丈夫です"
        }
        return subtitle
    }

    var ambientSpokenText: String {
        "\(greeting)。\(ambientMessage)。\(ambientSubMessage)"
    }

    // MARK: - フィルター

    var scope: ScopeFilter {
        get { appState.scope }
        set { appState.scope = newValue }
    }

    /// 一人モードでは「すべて / 自分 / 共有」を出さない
    var showsScopeFilter: Bool { appState.usageStyle.showsScopeFilter }

    private var todaysItems: [LifeItem] {
        store.items(on: now, scope: appState.effectiveScope)
    }

    // MARK: - 一人 / 家族・パートナー

    var usageCopy: String { appState.usageStyle.copy }

    /// 家族・パートナーモードで、パートナーがまだ参加していないとき招待を出す
    var showsInviteCard: Bool {
        appState.usageStyle == .shared && !appState.partnerJoined
    }

    /// 「パートナーと共有」ボタンを出すか（家族・パートナーモードの自分の項目だけ）
    func canShare(_ item: LifeItem) -> Bool {
        appState.usageStyle == .shared && item.ownership == .personal
    }

    /// パートナーと共有：参加済みならすぐ共有、未参加なら招待を出す
    func shareTapped(_ item: LifeItem) {
        if appState.partnerJoined {
            let before = snapshot(of: item)
            store.share(item.id)
            notify("「\(item.title)」をパートナーと共有しました", undo: undoRestoring(before))
        } else {
            invitingItem = item
            isShowingInvite = true
        }
    }

    func startInvite() {
        invitingItem = nil
        isShowingInvite = true
    }

    // MARK: - 今日これだけ

    private var focusSplit: (focus: [LifeItem], rest: [LifeItem]) {
        TodayFocusSelector.split(todaysItems)
    }

    /// 目立つ位置に出す最大3件。完了したものは下へ移動する（入れ替えはしない）。
    var focusItems: [LifeItem] {
        let focus = focusSplit.focus
        return focus.filter { !$0.isCompleted } + focus.filter(\.isCompleted)
    }

    /// 01 / 02 / 03（今日これだけの番号）
    func focusNumber(_ index: Int) -> String {
        String(format: "%02d", index + 1)
    }

    /// タイムライン上の番号（今日これだけ の項目だけ。完了しても番号は変えない）
    func focusNumber(for item: LifeItem) -> String? {
        guard let index = focusSplit.focus.firstIndex(where: { $0.id == item.id }) else { return nil }
        return focusNumber(index)
    }

    /// 折りたたむ残り
    var restItems: [LifeItem] { focusSplit.rest }

    // MARK: - Living Timeline（Calm Future）

    /// 今日これだけ・NEXT・このあと をひとつにしたタイムライン
    private var timeline: LivingTimelineBuilder.Timeline {
        let split = focusSplit
        return LivingTimelineBuilder.build(focus: split.focus, rest: split.rest, now: now)
    }

    var timelineSections: [TimelineSection] { timeline.sections }

    /// 「余力があれば」に折りたたむ項目
    var extraItems: [LifeItem] { timeline.extra }

    var restToggleTitle: String {
        isShowingRest ? "閉じる" : "あと\(extraItems.count)件"
    }

    /// 区間の点の色に使う種類（最初の項目の種類）
    func markerKind(for section: TimelineSection) -> LifeItemKind {
        section.items.first?.kind ?? .todo
    }

    /// 「いま」の区間か
    func isCurrent(_ section: TimelineSection) -> Bool {
        section.slot == .now
    }

    func isTime(_ section: TimelineSection) -> Bool {
        if case .time(_) = section.slot { return true }
        return false
    }

    /// タイムラインの行の補足（予定は残り時間、それ以外は従来の補足）
    func timelineDetail(for item: LifeItem) -> String? {
        if item.kind == .event && item.showsTime && item.displayDate > now {
            var parts = [remainingText(for: item)]
            if let assignee = item.assignee, assignee != .me {
                parts.append("担当：\(appState.profile.displayName(for: assignee))")
            }
            return parts.joined(separator: "・")
        }
        if item.showsTime {
            // 時刻はタイムラインの見出しに出ているので、補足には種類と担当だけ
            var parts: [String] = []
            if item.kind != .todo && item.kind != .event { parts.append(item.kind.label) }
            if let assignee = item.assignee, assignee != .me {
                parts.append("担当：\(appState.profile.displayName(for: assignee))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "・")
        }
        return detailText(for: item)
    }

    /// 次の予定（タイムラインで「パートナーと共有」を出す項目）か
    func isNextEvent(_ item: LifeItem) -> Bool {
        nextEvent?.id == item.id
    }

    /// 3つとも終わったか
    var isFocusCompleted: Bool {
        !focusItems.isEmpty && focusItems.allSatisfy(\.isCompleted)
    }

    let focusCompletedMessage = "今日の大事なこと、完了。"

    /// 行の補足（時刻・種類・担当）
    func detailText(for item: LifeItem) -> String? {
        var parts: [String] = []
        if item.showsTime {
            let hour = LifeCalendar.calendar.component(.hour, from: item.displayDate)
            parts.append(item.deferredTo != nil && hour >= 18 ? "今夜" : LifeFormatters.time(item.displayDate))
        } else if item.kind != .todo {
            parts.append(item.kind.label)
        }
        if let assignee = item.assignee, assignee != .me {
            parts.append("担当：\(appState.profile.displayName(for: assignee))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }

    // MARK: - あとで

    func startPostponing(_ item: LifeItem) {
        postponingItem = item
    }

    func postpone(_ item: LifeItem, to option: PostponeOption) {
        let before = snapshot(of: item)
        expandedLeftoverID = nil
        store.reschedule(item.id, to: option.date(from: now))
        notify("「\(item.title)」を\(option.doneMessage)", undo: undoRestoring(before))
    }

    // MARK: - 元に戻す（Calm Future）

    private func notify(_ message: String, undo: (() -> Void)?) {
        feedback = TodayFeedback(message: message, undo: undo)
    }

    /// 「元に戻す」を押したとき
    func performUndo() {
        guard let undo = feedback?.undo else { return }
        undo()
        notify("元に戻しました", undo: nil)
    }

    /// 変更前の状態（保存されている最新のもの）
    private func snapshot(of item: LifeItem) -> LifeItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }

    private func undoRestoring(_ before: LifeItem) -> () -> Void {
        let store = self.store
        return { store.restore(before) }
    }

    // MARK: - 未完了救済（昨日残ったもの）

    /// 責めないための見出し（赤字・警告は使わない）
    /// 昨日の分だけなら「昨日残ったもの」、2日以上前の分もあれば「残っているもの」
    var leftoverTitle: String {
        let yesterday = LifeCalendar.calendar.date(byAdding: .day, value: -1, to: LifeCalendar.startOfDay(now)) ?? now
        let onlyYesterday = leftovers.allSatisfy { LifeCalendar.isSameDay($0.displayDate, yesterday) }
        return onlyYesterday ? "昨日残ったもの" : "残っているもの"
    }

    /// 最初に見せる件数（多い日も詰め込みすぎない）
    let leftoverPreviewLimit = 3

    /// 残りをすべて開いているか
    var isShowingAllLeftovers = false

    /// 画面に出す分（ふだんは3件まで）
    var visibleLeftovers: [LifeItem] {
        isShowingAllLeftovers ? leftovers : Array(leftovers.prefix(leftoverPreviewLimit))
    }

    /// 「あと◯件」を出すか
    var hasHiddenLeftovers: Bool { leftovers.count > leftoverPreviewLimit }

    var leftoverToggleTitle: String {
        isShowingAllLeftovers ? "閉じる" : "あと\(leftovers.count - leftoverPreviewLimit)件"
    }

    /// 選択肢を開いている行（ふだんは1行だけ表示して、押したときだけ選択肢を出す）
    var expandedLeftoverID: LifeItem.ID?

    func toggleLeftoverExpansion(_ item: LifeItem) {
        expandedLeftoverID = expandedLeftoverID == item.id ? nil : item.id
    }

    var leftovers: [LifeItem] {
        store.leftovers(before: now, scope: appState.effectiveScope)
    }

    func leftoverDetail(for item: LifeItem) -> String {
        "\(LifeFormatters.shortDate(item.displayDate))の分"
    }

    func showToday(_ item: LifeItem) {
        let before = snapshot(of: item)
        expandedLeftoverID = nil
        store.reschedule(item.id, to: LifeCalendar.startOfDay(now))
        notify("「\(item.title)」を今日に表示します", undo: undoRestoring(before))
    }

    func moveToThisWeek(_ item: LifeItem) {
        postpone(item, to: .thisWeek)
    }

    func dropLeftover(_ item: LifeItem) {
        let before = snapshot(of: item)
        expandedLeftoverID = nil
        store.drop(item.id, at: now)
        notify("「\(item.title)」はもうやらないことにしました", undo: undoRestoring(before))
    }

    // MARK: - NEXT

    /// 現在時刻より後の今日の予定（時刻順）
    private var upcomingEvents: [LifeItem] {
        todaysItems
            .filter { $0.kind == .event && $0.showsTime && $0.displayDate > now }
            .sorted { $0.displayDate < $1.displayDate }
    }

    /// 現在時刻より後で最も近い予定
    var nextEvent: LifeItem? { upcomingEvents.first }

    /// NEXT の後に続く今日の予定（「このあと」として NEXT カードの下に小さく表示）
    /// 決定済み：NEXT 以外の今日の予定は NEXT カードの下に並べる（2026-09-28）。
    var laterEvents: [LifeItem] { Array(upcomingEvents.dropFirst()) }

    func timeText(for item: LifeItem) -> String {
        LifeFormatters.time(item.displayDate)
    }

    func remainingText(for item: LifeItem) -> String {
        LifeFormatters.remaining(from: now, to: item.displayDate)
    }

    // MARK: - 暮らしメモリー

    /// 今日画面に出す件数の上限（情報を詰め込みすぎない）
    private let memoryLimit = 2

    private var dueMemories: [LifeMemory] {
        store.memories.filter { LifeMemoryEvaluator.isDue($0, now: now) }
    }

    var visibleMemories: [LifeMemory] { Array(dueMemories.prefix(memoryLimit)) }

    var hasMoreMemories: Bool { dueMemories.count > memoryLimit }

    func memoryMessage(_ memory: LifeMemory) -> String {
        LifeMemoryEvaluator.message(memory, now: now)
    }

    func memoryCycle(_ memory: LifeMemory) -> String {
        LifeMemoryEvaluator.cycleText(memory, now: now)
    }

    /// ボタンの文言（なければボタンを出さない）
    func memoryActionTitle(_ memory: LifeMemory) -> String? {
        switch memory.action {
        case .addToShopping(_): return "買い物に追加"
        case .addOnSaturday(_): return "土曜日に追加"
        case .addToTodo(_): return "やることに追加"
        case .notifyOnly: return nil
        }
    }

    /// カードの細い光の色に使う種類（買い物・家事・やること）
    func memoryKind(_ memory: LifeMemory) -> LifeItemKind {
        switch memory.action {
        case .addToShopping(_): return .shopping
        case .addOnSaturday(_): return .chore
        case .addToTodo(_): return .todo
        case .notifyOnly: return .event
        }
    }

    /// 「今回はスキップ」を出すか（前回からの周期のものだけ）
    func canSkipMemory(_ memory: LifeMemory) -> Bool {
        if case .sinceLast(_, _) = memory.rule { return true }
        return false
    }

    func performMemoryAction(_ memory: LifeMemory) {
        let today = LifeCalendar.startOfDay(now)
        let tomorrow = PostponeOption.tomorrow.date(from: now)
        let memoryBefore = memory
        let store = self.store

        /// 追加した項目を取り除き、メモリーを前の状態に戻す
        func undo(removing item: LifeItem?) -> () -> Void {
            let ids: Set<LifeItem.ID> = item.map { Set([$0.id]) } ?? Set<LifeItem.ID>()
            return {
                store.removeItems(withIDs: ids)
                store.restoreMemory(memoryBefore)
            }
        }

        switch memory.action {
        case let .addToShopping(title):
            let item = LifeItem(title: title, kind: .shopping, ownership: .personal, date: today, assignee: .me)
            store.add([item])
            store.hideMemory(memory.id, until: tomorrow)
            notify("「\(title)」を買い物に追加しました", undo: undo(removing: item))
        case let .addOnSaturday(title):
            let saturday = PostponeOption.weekend.date(from: now)
            let item = LifeItem(title: title, kind: .chore, ownership: .personal, date: saturday, assignee: .me)
            store.add([item])
            store.hideMemory(memory.id, until: tomorrow)
            notify("「\(title)」を\(LifeFormatters.shortDate(saturday))に追加しました", undo: undo(removing: item))
        case let .addToTodo(title):
            let item = LifeItem(title: title, kind: .todo, ownership: .personal, date: today, assignee: .me)
            store.add([item])
            store.hideMemory(memory.id, until: tomorrow)
            notify("「\(title)」をやることに追加しました", undo: undo(removing: item))
        case .notifyOnly:
            store.hideMemory(memory.id, until: tomorrow)
        }
    }

    /// 今回はスキップ：周期を今日から数え直す
    /// TODO: 「今回はスキップ」で周期を数え直すか、一定期間だけ隠すかは仕様に明記がない。現状は数え直す。
    func skipMemory(_ memory: LifeMemory) {
        let memoryBefore = memory
        let store = self.store
        store.restartMemoryCycle(memory.id, from: now)
        notify("「\(memory.title)」は今回スキップしました", undo: { store.restoreMemory(memoryBefore) })
    }

    // MARK: - 家事オートパイロット

    private var autopilotDay: AutopilotDay { store.autopilotDay(for: now) }

    var energy: EnergyLevel? { autopilotDay.energy }

    func selectEnergy(_ energy: EnergyLevel) {
        store.setEnergy(energy, now: now)
    }

    var autopilotChores: [ChoreTemplate] {
        guard let energy else { return [] }
        return ChoreTemplate.chores(for: energy, from: store.choreTemplates)
    }

    func isChoreDone(_ chore: ChoreTemplate) -> Bool {
        autopilotDay.doneChoreIDs.contains(chore.id)
    }

    func toggleChore(_ chore: ChoreTemplate) {
        store.toggleChore(chore.id, now: now)
    }

    var autopilotSummary: String {
        let total = autopilotChores.reduce(0) { $0 + $1.minutes }
        return "\(autopilotChores.count)つ・合計\(total)分"
    }

    // MARK: - 習慣

    /// 今日の習慣（できていなくても警告などは出さない）
    var habits: [LifeItem] {
        todaysItems.filter(\.isHabit)
    }

    // MARK: - Inbox

    var inboxCount: Int { store.inbox.count }

    var inboxSummary: String { "未整理 \(inboxCount)件・今日の整理は30秒" }

    var hasNoSchedule: Bool {
        timelineSections.isEmpty && extraItems.isEmpty
    }

    // MARK: - MONEY

    /// 決定済み：お金は「自分 / 共有」で分けない（2026-10-01）。フィルターは適用しない。
    var todaySpending: Int {
        store.expenses
            .filter { LifeCalendar.isSameDay($0.date, now) }
            .reduce(0) { $0 + $1.amount }
    }

    var monthSpending: Int { store.budget.spent }

    var monthlyBudget: Int { store.budget.budget }

    /// 今月の予算に対する割合（0〜1。細い線の長さに使う）
    var budgetRatio: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(max(Double(monthSpending) / Double(monthlyBudget), 0), 1)
    }

    var budgetText: String {
        "予算 \(LifeFormatters.yen(monthlyBudget))"
    }

    // MARK: - 広告

    var showsAd: Bool { !appState.isPremium }
}
