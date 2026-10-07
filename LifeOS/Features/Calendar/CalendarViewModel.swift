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

    // MARK: - パートナーと共有（v2 1タップ家族招待）

    /// 招待シートで見せる項目（パートナー未参加のとき）
    var invitingItem: LifeItem?

    /// 家族・パートナーモードの自分の項目だけ共有ボタンを出す
    func canShare(_ item: LifeItem) -> Bool {
        appState.usageStyle == .shared && item.ownership == .personal
    }

    /// 参加済みならすぐ共有、未参加なら招待を出す
    func shareTapped(_ item: LifeItem) {
        if appState.partnerJoined {
            store.share(item.id)
        } else {
            invitingItem = item
        }
    }

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }
}
