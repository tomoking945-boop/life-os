import Foundation
import Observation

@Observable
final class TodayViewModel {
    private let store: LifeStore
    private let appState: AppState
    let now: Date

    init(store: LifeStore, appState: AppState, now: Date = LifeCalendar.now) {
        self.store = store
        self.appState = appState
        self.now = now
    }

    // MARK: - ヘッダー

    var dateTitle: String { LifeFormatters.headerDate(now) }
    var spokenDateTitle: String { LifeFormatters.spokenDate(now) }

    /// TODO: 時間帯による挨拶の切り替えは仕様未定。現状はレイアウト例どおり固定。
    let greeting = "Good morning."
    let subtitle = "今日の暮らしを、シンプルに。"

    // MARK: - フィルター

    var scope: ScopeFilter {
        get { appState.scope }
        set { appState.scope = newValue }
    }

    private var todaysItems: [LifeItem] {
        store.items(on: now, scope: appState.scope)
    }

    // MARK: - NEXT

    /// 現在時刻より後の今日の予定（時刻順）
    private var upcomingEvents: [LifeItem] {
        todaysItems
            .filter { $0.kind == .event && $0.hasTime && $0.date > now }
            .sorted { $0.date < $1.date }
    }

    /// 現在時刻より後で最も近い予定
    var nextEvent: LifeItem? { upcomingEvents.first }

    /// NEXT の後に続く今日の予定（「このあと」として NEXT カードの下に小さく表示）
    /// 決定済み：NEXT 以外の今日の予定は NEXT カードの下に並べる（2026-09-28）。
    var laterEvents: [LifeItem] { Array(upcomingEvents.dropFirst()) }

    func timeText(for item: LifeItem) -> String {
        LifeFormatters.time(item.date)
    }

    func remainingText(for item: LifeItem) -> String {
        LifeFormatters.remaining(from: now, to: item.date)
    }

    // MARK: - TODAY / SHARED

    /// TODAY：パートナー担当以外のタスク（レイアウト例に合わせ、共有の「牛乳を買う（どちらでも）」もここに入る）
    var todayTasks: [LifeItem] {
        todaysItems.filter { $0.isTask && $0.assignee != .partner }
    }

    /// SHARED：パートナー担当のタスク
    var partnerTasks: [LifeItem] {
        todaysItems.filter { $0.isTask && $0.assignee == .partner }
    }

    var partnerName: String { appState.profile.partnerName }

    var hasNoSchedule: Bool {
        nextEvent == nil && todayTasks.isEmpty && partnerTasks.isEmpty
    }

    func detailText(for item: LifeItem) -> String? {
        guard let assignee = item.assignee, assignee != .me else { return nil }
        return "担当：\(appState.profile.displayName(for: assignee))"
    }

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }

    // MARK: - MONEY

    /// TODO: お金は「自分 / 共有」の区分が未定のため、フィルターを適用していない。
    var todaySpending: Int {
        store.expenses
            .filter { LifeCalendar.isSameDay($0.date, now) }
            .reduce(0) { $0 + $1.amount }
    }

    var monthSpending: Int { store.budget.spent }

    // MARK: - 広告

    var showsAd: Bool { !appState.isPremium }
}
