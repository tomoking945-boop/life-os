import Foundation
import Observation

/// カレンダーから追加する予定の下書き（Build 12。docs/BUILD_12_CALENDAR_EVENT_AND_ICON.md）。
/// 保存すると、これまでと同じ `LifeItem(kind: .event)` の「自分」の予定になる。
/// Build 14：保存先で「わが家で共有」を選んだときだけ、わが家の共有の予定にする（初期値は自分だけ）
struct NewEventDraft: Equatable {
    /// 時刻を指定するときの初期の時刻
    static let defaultHour = 10

    var title = ""
    /// 日付（選んだ日が初期値）
    var date: Date
    var isAllDay = true
    /// 時刻（時と分だけを使う）
    var time: Date
    /// 保存先（Build 14）。初期値は必ず「自分だけ」。利用者が選んだときだけ「わが家で共有」
    var destination: SaveDestination = .initial

    init(day: Date) {
        let start = LifeCalendar.startOfDay(day)
        date = start
        time = LifeCalendar.date(on: start, hour: Self.defaultHour, minute: 0)
    }

    /// 既存の予定を編集するときの初期値（Build 15）。保存先の初期値は元の持ち主（Build 17 から編集画面に表示する）。
    init(item: LifeItem) {
        title = item.title
        date = LifeCalendar.startOfDay(item.date)
        isAllDay = !item.hasTime
        time = item.hasTime ? item.date : LifeCalendar.date(on: item.date, hour: Self.defaultHour, minute: 0)
        destination = item.ownership == .shared ? .household : .personal
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

    /// 元の予定の ID・持ち主などを保ったまま、編集できる3項目だけを反映する。
    func applying(to item: LifeItem) -> LifeItem? {
        guard canSave, item.kind == .event else { return nil }
        let day = LifeCalendar.startOfDay(date)
        var updated = item
        updated.title = trimmedTitle
        updated.date = isAllDay ? day : ClockTime(date: time).date(on: day)
        updated.hasTime = !isAllDay
        // 「あとで」で表示日が変わっていた場合も、利用者が選んだ新しい日を表示する。
        updated.deferredTo = nil
        return updated
    }
}

/// 編集中の予定と下書き。元の予定を識別するため ID を保つ。
/// Build 17：開いたときの保存先（`originalDestination`）を持ち、下書きの保存先の初期値にする
struct EventEditSession: Equatable {
    let original: LifeItem
    /// 開いたときの保存先（いま「わが家で共有」している予定なら household）
    let originalDestination: SaveDestination
    var draft: NewEventDraft

    /// - Parameter isShared: わが家で共有している予定か（nil なら予定の持ち主から決める）
    init(item: LifeItem, isShared: Bool? = nil) {
        original = item
        originalDestination = (isShared ?? (item.ownership == .shared)) ? .household : .personal
        draft = NewEventDraft(item: item)
        draft.destination = originalDestination
    }
}

/// 日付のマスの下の小さな点（Build 19）。予定は登録した人の色、ほかはカテゴリー色
enum CalendarDayMarker: Hashable {
    case registrant(ItemRegistrant)
    case kind(LifeItemKind)
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
    /// 編集中の既存予定（Build 15）。追加とは別に持つ。Build 17 から保存先も変えられる
    var eventEditSession: EventEditSession?
    /// 「自分だけの予定に変更しますか？」の確認を出している下書き（Build 17。確認するまで何も変えない）
    var pendingPersonalConversionDraft: NewEventDraft?
    /// 予定の編集で、保存先を変えられなかった理由（Build 17。編集画面に出す）
    var eventEditError: String?
    /// 削除の確認を出している予定（Build 13）
    var eventPendingDeletion: LifeItem?

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

    /// 日付のマスの下の点（Build 19）。予定は登録した人の色（自分・パートナー・不明の順に1つずつ）、
    /// そのあとに予定以外の種類のカテゴリー色。同じ色は1日に1つ、最大3つ。「すべて／自分／共有」の絞り込みに従う
    func dayMarkers(on date: Date) -> [CalendarDayMarker] {
        let items = store.items(on: date, scope: appState.effectiveScope)
        let registrants = Set(items.filter { $0.kind == .event }.map { store.registrant(of: $0) })
        let eventMarkers = ItemRegistrant.allCases.filter { registrants.contains($0) }.map(CalendarDayMarker.registrant)
        let kinds = Set(items.map(\.kind))
        let kindMarkers = LifeItemKind.allCases.filter { $0 != .event && kinds.contains($0) }.map(CalendarDayMarker.kind)
        return Array((eventMarkers + kindMarkers).prefix(Self.maxMarkerCount))
    }

    /// 予定を最初に登録した人（Build 19。予定でなければ nil）。自分だけの予定は「自分」
    func registrant(for item: LifeItem) -> ItemRegistrant? {
        item.kind == .event ? store.registrant(of: item) : nil
    }

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

    /// 予定を「わが家で共有」にできない理由（できるなら nil。Build 14）
    var eventSharingBlock: EventSharingBlock? {
        showsScopeFilter ? store.eventSharingBlock : .soloMode
    }

    /// 予定を保存する。保存した日を選び、その月を表示して、一覧にすぐ出す。タイトルが空なら保存しない。
    /// 保存先は、利用者が「わが家で共有」を選び、共有できるときだけ共有（Build 14）。それ以外は自分だけ。
    /// 共有の保存に失敗したときは、自分だけの予定として1件だけ端末に残る（LifeStore・SharedItemsService）
    /// - Returns: 保存したら true
    @discardableResult
    func saveEvent(_ draft: NewEventDraft) -> Bool {
        guard let item = draft.makeItem() else { return false }
        let ownership: Ownership
        if draft.destination == .household, eventSharingBlock == nil {
            ownership = store.add([item], destination: .household) == 1 ? .shared : .personal
        } else {
            store.add([item])
            ownership = .personal
        }
        select(item.date)
        displayedMonth = LifeCalendar.startOfMonth(item.date)
        // 表示している範囲で見えないときは「すべて」に戻す（自分の予定を「共有」だけで、共有の予定を「自分」だけで見ていたとき）
        if !appState.effectiveScope.includes(ownership) {
            scope = .all
        }
        eventDraft = nil
        return true
    }

    // MARK: - 予定の編集（Build 15）

    /// 編集できるのは予定だけ。個人・共有のどちらも同じ画面を使う。
    func canEditEvent(_ item: LifeItem) -> Bool {
        item.kind == .event
    }

    /// 編集画面を開く。タイトル・日付・終日／時刻・保存先を元の値で始める。
    /// 保存先は、わが家で共有している予定（Firestore から届いたもの）かどうかで決める（Build 17）
    func startEditingEvent(_ item: LifeItem) {
        guard canEditEvent(item) else { return }
        eventEditSession = EventEditSession(item: item, isShared: store.isHouseholdItem(item.id))
        pendingPersonalConversionDraft = nil
        eventEditError = nil
    }

    func cancelEditingEvent() {
        eventEditSession = nil
        pendingPersonalConversionDraft = nil
        eventEditError = nil
    }

    /// 編集画面で「わが家で共有」を選べない理由（Build 17）。
    /// - 自分だけの予定：新しく共有するときと同じ条件（サインイン・参加・設定で予定がオン）
    /// - 共有している予定：nil（「自分だけ」へ戻すのは、予定がオフでもできる。共有のままにもできる）
    var editSharingBlock: EventSharingBlock? {
        guard let session = eventEditSession, session.originalDestination == .personal else { return nil }
        return eventSharingBlock
    }

    /// 編集を保存する。共有の予定なら相手の端末にも反映される。
    /// Build 17：保存先も変えられる。「わが家で共有」→「自分だけ」は、確認を出してから（ここでは何も変えずに false）
    /// - Returns: 保存してシートを閉じたら true
    @discardableResult
    func saveEditedEvent(_ draft: NewEventDraft) -> Bool {
        guard let session = eventEditSession else { return false }
        if session.originalDestination == .household, draft.destination == .personal {
            pendingPersonalConversionDraft = draft
            return false
        }
        return commitEditedEvent(draft)
    }

    /// 確認の「自分だけに変更」
    @discardableResult
    func confirmPersonalConversion() -> Bool {
        guard let draft = pendingPersonalConversionDraft else { return false }
        pendingPersonalConversionDraft = nil
        return commitEditedEvent(draft)
    }

    /// 確認の「キャンセル」：何も変えない（編集画面はそのまま）
    func cancelPersonalConversion() {
        pendingPersonalConversionDraft = nil
    }

    func dismissEventEditError() {
        eventEditError = nil
    }

    private func commitEditedEvent(_ draft: NewEventDraft) -> Bool {
        guard let session = eventEditSession,
              let updated = draft.applying(to: session.original) else { return false }
        // 共有できないのに「わが家で共有」になっていたら、何も変えずに理由を出す（画面では選べない）
        if session.originalDestination == .personal, draft.destination == .household, let block = editSharingBlock {
            eventEditError = block.message
            return false
        }
        let outcome = store.saveEvent(updated, destination: draft.destination)
        let ownership: Ownership
        switch outcome {
        case .failed(let reason):
            eventEditError = reason
            return false
        case .saved:
            ownership = session.originalDestination == .household ? .shared : .personal
        case .sharingStarted:
            ownership = .shared
        case .madePersonal:
            ownership = .personal
        }
        select(updated.date)
        displayedMonth = LifeCalendar.startOfMonth(updated.date)
        if !appState.effectiveScope.includes(ownership) {
            scope = .all
        }
        eventEditError = nil
        eventEditSession = nil
        return true
    }

    // MARK: - 予定の削除（Build 13）

    /// 消せる予定か（予定だけ。自分だけの予定も、わが家で共有している予定も。ToDo・買い物・家事は、ここからは消さない）
    func canDeleteEvent(_ item: LifeItem) -> Bool {
        item.kind == .event
    }

    /// 「削除」を押した：確認を出す（まだ消さない）
    func requestDeleteEvent(_ item: LifeItem) {
        guard canDeleteEvent(item) else { return }
        eventPendingDeletion = item
    }

    /// 「キャンセル」：何も変えない
    func cancelDeleteEvent() {
        eventPendingDeletion = nil
    }

    /// 「予定を削除」：選んだ予定1件だけを消す（保存する。通知は MainTabView が予約し直す）
    @discardableResult
    func confirmDeleteEvent() -> Bool {
        guard let item = eventPendingDeletion else { return false }
        eventPendingDeletion = nil
        return store.deleteEvent(item.id)
    }

    // 予定の「パートナーと共有」ボタン（端末の中で印を付けるだけの Mock）は 2026-10-28 になくした。
    // Build 14 から、カレンダーの「予定を追加」で保存先「わが家で共有」を選ぶと、ToDo・買い物と同じ
    // groups/{groupID}/items/{予定のUUID} に保存する（docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md）

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }

    /// わが家で共有している項目か（共有マーク。2026-10-28）
    func isShared(_ item: LifeItem) -> Bool {
        store.isHouseholdItem(item.id)
    }
}
