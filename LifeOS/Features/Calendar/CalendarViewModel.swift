import Foundation
import Observation

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
        store.items(on: date, scope: appState.scope).count
    }

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
        store.items(on: selectedDate, scope: appState.scope)
    }

    func timeText(for item: LifeItem) -> String? {
        item.hasTime ? LifeFormatters.time(item.date) : nil
    }

    func detailText(for item: LifeItem) -> String {
        var parts = [item.kind.label, item.ownership.label]
        if let assignee = item.assignee {
            parts.append("担当：\(appState.profile.displayName(for: assignee))")
        }
        return parts.joined(separator: "・")
    }

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }
}
