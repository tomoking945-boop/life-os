import Foundation
import Observation

/// カレンダーから追加する予定の下書き（Build 12。docs/BUILD_12_CALENDAR_EVENT_AND_ICON.md）。
/// 保存すると、これまでと同じ `LifeItem(kind: .event)` の「自分」の予定になる（予定の共有はまだしない）
struct NewEventDraft: Equatable {
    /// 時刻を指定するときの初期の時刻
    static let defaultHour = 10

    var title = ""
    /// 日付（選んだ日が初期値）
    var date: Date
    var isAllDay = true
    /// 時刻（時と分だけを使う）
    var time: Date

    init(day: Date) {
        let start = LifeCalendar.startOfDay(day)
        date = start
        time = LifeCalendar.date(on: start, hour: Self.defaultHour, minute: 0)
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 保存できるか（タイトルが空なら保存しない）
    var canSave: Bool { !trimmedTitle.isEmpty }

    /// 保存する予定（保存できないときは nil）
    func makeItem() -> LifeItem? {
        guard canSave else { return nil }
        let day = LifeCalendar.startOfDay(date)
        return LifeItem(
            title: trimmedTitle,
            kind: .event,
            ownership: .personal,
            date: isAllDay ? day : ClockTime(date: time).date(on: day),
            hasTime: !isAllDay,
            assignee: .me
        )
    }
}

/// 月表示の1マス（前月分の空白は date が nil）
struct CalendarDayCell: Identifiable, Hashable {
    let id: Int
    let date: Date?
}

@Observable
final class CalendarViewModel {
    private let store: LifeStore
    private let appState: AppState
    private let calendar = LifeCalendar.calendar
    let today: Date

    var displayedMonth: Date
    var selectedDate: Date
    /// 選んだ日から予定を追加するシートの下書き（開いていなければ nil。Build 12）
    var eventDraft: NewEventDraft?

    init(store: LifeStore, appState: AppState, now: Date = LifeCalendar.now) {
        self.store = store
        self.appState = appState
        self.today = LifeCalendar.startOfDay(now)
        self.displayedMonth = LifeCalendar.startOfMonth(now)
        self.selectedDate = LifeCalendar.startOfDay(now)
    }

    // MARK: - フィルター

    var scope: ScopeFilter {
        get { appState.scope }
        set { appState.scope = newValue }
    }

    /// 一人モードでは「すべて / 自分 / 共有」を出さない
    var showsScopeFilter: Bool { appState.usageStyle.showsScopeFilter }

    // MARK: - 月表示

    var monthTitle: String { LifeFormatters.month(displayedMonth) }

    /// 曜日の見出し（日 月 火 …）
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var dayCells: [CalendarDayCell] {
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        let blanks = (0..<leadingBlanks).map { CalendarDayCell(id: -($0 + 1), date: nil) }
        let days = (0..<dayCount).map { offset in
            CalendarDayCell(
                id: offset + 1,
                date: calendar.date(byAdding: .day, value: offset, to: displayedMonth)
            )
        }
        return blanks + days
    }

    func dayNumber(of date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    func isToday(_ date: Date) -> Bool {
        LifeCalendar.isSameDay(date, today)
    }

    func isSelected(_ date: Date) -> Bool {
        LifeCalendar.isSameDay(date, selectedDate)
    }

    func itemCount(on date: Date) -> Int {
        store.items(on: date, scope: appState.effectiveScope).count
    }

    /// その日の項目の種類（カテゴリー色の点に使う。多い順ではなく種類の並び順で最大3つ）
    /// Calm Future 第4段階：これまでの1色の点を、低彩度のカテゴリー色の点にした。
    func markerKinds(on date: Date) -> [LifeItemKind] {
        let kinds = Set(store.items(on: date, scope: appState.effectiveScope).map(\.kind))
        return Array(LifeItemKind.allCases.filter { kinds.contains($0) }.prefix(Self.maxMarkerCount))
    }

    /// 1日に出す点の数の上限
    static let maxMarkerCount = 3

    /// 選んだ日の大きな見出し（例：10月7日（水））
    var selectedDateHeadline: String { LifeFormatters.headerDate(selectedDate) }

    /// 選んだ日の小さな見出し（今日なら TODAY）
    var selectedDateEyebrow: String { isToday(selectedDate) ? "TODAY" : "SELECTED DAY" }

    func select(_ date: Date) {
        selectedDate = LifeCalendar.startOfDay(date)
    }

    func showPreviousMonth() {
        moveMonth(by: -1)
    }

    func showNextMonth() {
        moveMonth(by: 1)
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = month
    }

    func accessibilityLabel(for date: Date) -> String {
        let count = itemCount(on: date)
        var parts = [LifeFormatters.spokenDate(date)]
        if isToday(date) { parts.append("今日") }
        parts.append(count > 0 ? "\(count)件" : "予定なし")
        return parts.joined(separator: "、")
    }

    // MARK: - 選択日の項目

    var selectedDateTitle: String { LifeFormatters.shortDate(selectedDate) }

    var selectedItems: [LifeItem] {
        store.items(on: selectedDate, scope: appState.effectiveScope)
    }

    func timeText(for item: LifeItem) -> String? {
        item.showsTime ? LifeFormatters.time(item.displayDate) : nil
    }

    func detailText(for item: LifeItem) -> String {
        var parts = [item.kind.label, item.ownership.label]
        if let assignee = item.assignee {
            parts.append("担当：\(appState.profile.displayName(for: assignee))")
        }
        return parts.joined(separator: "・")
    }

    // MARK: - 選んだ日から予定を追加（Build 12）

    /// 「予定を追加」：選んだ日を初期値にしてシートを開く
    func startAddingEvent() {
        eventDraft = NewEventDraft(day: selectedDate)
    }

    func cancelAddingEvent() {
        eventDraft = nil
    }

    /// 予定を保存する（自分だけ）。保存した日を選び、その月を表示して、一覧にすぐ出す。
    /// タイトルが空なら保存しない
    /// - Returns: 保存したら true
    @discardableResult
    func saveEvent(_ draft: NewEventDraft) -> Bool {
        guard let item = draft.makeItem() else { return false }
        store.add([item])
        select(item.date)
        displayedMonth = LifeCalendar.startOfMonth(item.date)
        // 「共有」だけを表示していると自分の予定が見えないため、「すべて」に戻す
        if !appState.effectiveScope.includes(.personal) {
            scope = .all
        }
        eventDraft = nil
        return true
    }

    // 予定の「パートナーと共有」ボタン（端末の中で印を付けるだけの Mock）は 2026-10-28 になくした。
    // 予定の共有は今後対応（いま2台で同期できるのは ToDo・買い物だけ。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }

    /// わが家で共有している項目か（共有マーク。2026-10-28）
    func isShared(_ item: LifeItem) -> Bool {
        store.isHouseholdItem(item.id)
    }
}
