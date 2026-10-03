import Foundation
import Observation

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
    /// 操作のあとに短く出す一言（例：明日に回しました）
    var feedbackMessage: String?

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

    /// 決定済み：プロトタイプでは現在時刻を 9:10 に固定するため、挨拶も固定（2026-09-28）。
    /// TODO: 実時刻にする段階で、時間帯による挨拶の切り替えを決める。
    let greeting = "Good morning."
    /// v2 の目標イメージに合わせたキャッチコピー
    let subtitle = "今日も、無理なく。"

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
            store.share(item.id)
            feedbackMessage = "「\(item.title)」をパートナーと共有しました"
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

    /// 折りたたむ残り
    var restItems: [LifeItem] { focusSplit.rest }

    var restToggleTitle: String {
        isShowingRest ? "閉じる" : "あと\(restItems.count)件"
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
        store.reschedule(item.id, to: option.date(from: now))
        feedbackMessage = "「\(item.title)」を\(option.doneMessage)"
    }

    // MARK: - 未完了救済（昨日残ったもの）

    /// 責めないための見出し（赤字・警告は使わない）
    let leftoverTitle = "昨日残ったもの"

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
        store.reschedule(item.id, to: LifeCalendar.startOfDay(now))
        feedbackMessage = "「\(item.title)」を今日に表示します"
    }

    func moveToThisWeek(_ item: LifeItem) {
        postpone(item, to: .thisWeek)
    }

    func dropLeftover(_ item: LifeItem) {
        store.drop(item.id, at: now)
        feedbackMessage = "「\(item.title)」はもうやらないことにしました"
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

    /// 「今回はスキップ」を出すか（前回からの周期のものだけ）
    func canSkipMemory(_ memory: LifeMemory) -> Bool {
        if case .sinceLast(_, _) = memory.rule { return true }
        return false
    }

    func performMemoryAction(_ memory: LifeMemory) {
        let today = LifeCalendar.startOfDay(now)
        let tomorrow = PostponeOption.tomorrow.date(from: now)
        switch memory.action {
        case let .addToShopping(title):
            store.add([LifeItem(title: title, kind: .shopping, ownership: .personal, date: today, assignee: .me)])
            store.hideMemory(memory.id, until: tomorrow)
            feedbackMessage = "「\(title)」を買い物に追加しました"
        case let .addOnSaturday(title):
            let saturday = PostponeOption.weekend.date(from: now)
            store.add([LifeItem(title: title, kind: .chore, ownership: .personal, date: saturday, assignee: .me)])
            store.hideMemory(memory.id, until: tomorrow)
            feedbackMessage = "「\(title)」を\(LifeFormatters.shortDate(saturday))に追加しました"
        case let .addToTodo(title):
            store.add([LifeItem(title: title, kind: .todo, ownership: .personal, date: today, assignee: .me)])
            store.hideMemory(memory.id, until: tomorrow)
            feedbackMessage = "「\(title)」をやることに追加しました"
        case .notifyOnly:
            store.hideMemory(memory.id, until: tomorrow)
        }
    }

    /// 今回はスキップ：周期を今日から数え直す
    /// TODO: 「今回はスキップ」で周期を数え直すか、一定期間だけ隠すかは仕様に明記がない。現状は数え直す。
    func skipMemory(_ memory: LifeMemory) {
        store.restartMemoryCycle(memory.id, from: now)
        feedbackMessage = "「\(memory.title)」は今回スキップしました"
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
        nextEvent == nil && focusItems.isEmpty
    }

    // MARK: - MONEY

    /// 決定済み：お金は「自分 / 共有」で分けない（2026-10-01）。フィルターは適用しない。
    var todaySpending: Int {
        store.expenses
            .filter { LifeCalendar.isSameDay($0.date, now) }
            .reduce(0) { $0 + $1.amount }
    }

    var monthSpending: Int { store.budget.spent }

    // MARK: - 広告

    var showsAd: Bool { !appState.isPremium }
}
