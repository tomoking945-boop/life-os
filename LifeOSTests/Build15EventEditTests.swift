import XCTest
@testable import LifeOS

// Build 15：既存の予定のタイトル・日付・終日／時刻を編集する。
// 保存先と UUID は変えず、個人の予定は端末だけ、共有の予定は同じ Firestore 文書を更新する。

private let build15Now = TestDates.make(2026, 11, 1, 9, 0)
private let build15OriginalDay = TestDates.make(2026, 11, 8)
private let build15MovedDay = TestDates.make(2027, 2, 14)

private func build15Store(items: [LifeItem] = []) -> LifeStore {
    LifeStore(items: items, expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func build15Event(
    _ title: String = "歯医者",
    ownership: Ownership = .personal,
    day: Date = build15OriginalDay,
    hour: Int? = 10
) -> LifeItem {
    if let hour {
        return LifeItem(
            title: title,
            kind: .event,
            ownership: ownership,
            date: LifeCalendar.date(on: day, hour: hour, minute: 30),
            hasTime: true,
            assignee: ownership == .personal ? .me : nil
        )
    }
    return LifeItem(
        title: title,
        kind: .event,
        ownership: ownership,
        date: LifeCalendar.startOfDay(day),
        assignee: ownership == .personal ? .me : nil
    )
}

private func build15Household() -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家",
        sharedKinds: [.event, .todo, .shopping],
        isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build15"
    )
}

private struct Build15Device {
    let store: LifeStore
    let backend: FakeSharedItemsBackend
    let service: SharedItemsService
    let appState: AppState

    init(server: FakeSharedServer, uid: String, items: [LifeItem] = []) {
        store = build15Store(items: items)
        backend = FakeSharedItemsBackend(server: server, uid: uid)
        service = SharedItemsService(backend: backend)
        service.attach(store)
        service.apply(household: build15Household())
        appState = AppState()
        appState.usageStyle = .shared
    }

    func calendar() -> CalendarViewModel {
        CalendarViewModel(store: store, appState: appState, now: build15Now)
    }
}

private func build15Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

final class Build15EventDraftTests: XCTestCase {
    func testTimedEventStartsWithExistingValues() {
        let item = build15Event("歯医者", ownership: .shared, hour: 10)
        let draft = NewEventDraft(item: item)

        XCTAssertEqual(draft.title, "歯医者")
        XCTAssertEqual(draft.date, LifeCalendar.startOfDay(build15OriginalDay))
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(ClockTime(date: draft.time).hour, 10)
        XCTAssertEqual(ClockTime(date: draft.time).minute, 30)
        XCTAssertEqual(draft.destination, .household)
    }

    func testAllDayEventStartsAsAllDay() {
        let item = build15Event(hour: nil)
        let draft = NewEventDraft(item: item)
        XCTAssertTrue(draft.isAllDay)
        XCTAssertEqual(draft.time, LifeCalendar.date(on: build15OriginalDay, hour: NewEventDraft.defaultHour, minute: 0))
        XCTAssertEqual(draft.destination, .personal)
    }

    func testApplyingEditKeepsIdentityAndOwnership() throws {
        var original = build15Event(ownership: .shared)
        original.isCompleted = true
        original.droppedAt = nil
        original.memoryID = UUID()
        var draft = NewEventDraft(item: original)
        draft.title = "  定期健診  "
        draft.date = build15MovedDay
        draft.isAllDay = false
        draft.time = TestDates.make(2027, 2, 14, 16, 45)

        let updated = try XCTUnwrap(draft.applying(to: original))
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.kind, .event)
        XCTAssertEqual(updated.ownership, .shared)
        XCTAssertEqual(updated.title, "定期健診")
        XCTAssertEqual(updated.date, TestDates.make(2027, 2, 14, 16, 45))
        XCTAssertTrue(updated.hasTime)
        XCTAssertEqual(updated.isCompleted, original.isCompleted)
        XCTAssertEqual(updated.memoryID, original.memoryID)
    }

    func testApplyingAllDayUsesStartOfSelectedDayAndClearsDeferral() throws {
        var original = build15Event()
        original.deferredTo = TestDates.make(2026, 11, 9, 20, 0)
        var draft = NewEventDraft(item: original)
        draft.date = build15MovedDay
        draft.isAllDay = true

        let updated = try XCTUnwrap(draft.applying(to: original))
        XCTAssertEqual(updated.date, LifeCalendar.startOfDay(build15MovedDay))
        XCTAssertFalse(updated.hasTime)
        XCTAssertNil(updated.deferredTo, "選び直した日を表示する")
    }

    func testEmptyTitleAndNonEventCannotBeApplied() {
        let original = build15Event()
        var empty = NewEventDraft(item: original)
        empty.title = "   "
        XCTAssertNil(empty.applying(to: original))

        let todo = LifeItem(title: "書類", kind: .todo, ownership: .personal, date: build15OriginalDay)
        XCTAssertNil(NewEventDraft(item: todo).applying(to: todo))
    }
}

final class Build15PersonalEventEditTests: XCTestCase {
    func testPersonalEditSavesOnlyOnDevice() throws {
        let original = build15Event()
        let server = FakeSharedServer()
        server.enabledKinds.insert("event")
        let device = Build15Device(server: server, uid: "alice", items: [original])
        let calendar = device.calendar()

        calendar.startEditingEvent(original)
        var draft = try XCTUnwrap(calendar.eventEditSession?.draft)
        draft.title = "健康診断"
        draft.date = build15MovedDay
        draft.isAllDay = false
        draft.time = TestDates.make(2027, 2, 14, 15, 15)
        XCTAssertTrue(calendar.saveEditedEvent(draft))

        let saved = try XCTUnwrap(device.store.items.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.title, "健康診断")
        XCTAssertEqual(saved.date, TestDates.make(2027, 2, 14, 15, 15))
        XCTAssertEqual(saved.ownership, .personal)
        XCTAssertEqual(device.backend.totalCalls, 0, "個人の予定は Firestore に送らない")
        XCTAssertNil(calendar.eventEditSession)
        XCTAssertEqual(calendar.selectedDate, LifeCalendar.startOfDay(build15MovedDay))
        XCTAssertEqual(calendar.displayedMonth, LifeCalendar.startOfMonth(build15MovedDay))
    }

    func testCancelKeepsOriginalEvent() {
        let original = build15Event()
        let store = build15Store(items: [original])
        let calendar = CalendarViewModel(store: store, appState: AppState(), now: build15Now)

        calendar.startEditingEvent(original)
        calendar.cancelEditingEvent()

        XCTAssertNil(calendar.eventEditSession)
        XCTAssertEqual(store.items, [original])
    }

    func testTodoCannotOpenEventEditorOrBeUpdated() {
        let todo = LifeItem(title: "書類", kind: .todo, ownership: .personal, date: build15OriginalDay)
        let store = build15Store(items: [todo])
        let calendar = CalendarViewModel(store: store, appState: AppState(), now: build15Now)

        calendar.startEditingEvent(todo)
        XCTAssertNil(calendar.eventEditSession)
        XCTAssertFalse(store.updateEvent(todo))
        XCTAssertEqual(store.items, [todo])
    }

    func testMissingEventIsNotRecreated() {
        let original = build15Event()
        let store = build15Store()
        var changed = original
        changed.title = "戻してはいけない予定"
        XCTAssertFalse(store.updateEvent(changed))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testEditingDateMovesLocalReminderWithoutChangingIdentifier() throws {
        let original = build15Event(day: build15OriginalDay, hour: 10)
        let store = build15Store(items: [original])
        let before = try XCTUnwrap(LifeNotificationPlanner.eventRequests(items: store.notificationItems, now: build15Now).first)

        var changed = original
        changed.title = "健康診断"
        changed.date = TestDates.make(2027, 2, 14, 16, 0)
        XCTAssertTrue(store.updateEvent(changed))
        let after = try XCTUnwrap(LifeNotificationPlanner.eventRequests(items: store.notificationItems, now: build15Now).first)

        XCTAssertEqual(after.identifier, before.identifier)
        XCTAssertNotEqual(after.fireDate, before.fireDate)
        XCTAssertEqual(after.fireDate, TestDates.make(2027, 2, 14, 15, 50))
        XCTAssertTrue(after.body.contains("健康診断"))
    }
}

final class Build15SharedEventEditTests: XCTestCase {
    func testPartnerEditUpdatesSameSharedEventOnBothDevices() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        server.memberUIDs = ["alice", "bob"]
        let alice = Build15Device(server: server, uid: "alice")
        let bob = Build15Device(server: server, uid: "bob")
        let original = build15Event()
        XCTAssertEqual(alice.store.add([original], destination: .household), 1)
        let shared = try XCTUnwrap(bob.store.householdItems.first)

        let calendar = bob.calendar()
        calendar.startEditingEvent(shared)
        var draft = try XCTUnwrap(calendar.eventEditSession?.draft)
        draft.title = "家族の予定"
        draft.date = build15MovedDay
        draft.isAllDay = false
        draft.time = TestDates.make(2027, 2, 14, 18, 20)
        XCTAssertTrue(calendar.saveEditedEvent(draft))

        for store in [alice.store, bob.store] {
            let item = try XCTUnwrap(store.householdItems.first)
            XCTAssertEqual(item.id, shared.id)
            XCTAssertEqual(item.title, "家族の予定")
            XCTAssertEqual(item.date, TestDates.make(2027, 2, 14, 18, 20))
            XCTAssertEqual(item.ownership, .shared)
            XCTAssertTrue(store.items.isEmpty, "共有の予定を端末の個人データに複製しない")
        }
        XCTAssertEqual(bob.backend.sentUpdates.count, 1)
        XCTAssertTrue(bob.backend.sentCreates.isEmpty)
        XCTAssertTrue(bob.backend.sentDeletes.isEmpty)
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(server.createdBy(of: shared.id), "alice", "作成者は変えない")
        XCTAssertEqual(server.updatedBy(of: shared.id), "bob")
    }

    func testSharedEditSendsOnlyMutableFixedFields() throws {
        let server = FakeSharedServer()
        server.enabledKinds.insert("event")
        let device = Build15Device(server: server, uid: "alice")
        device.store.add([build15Event()], destination: .household)
        let item = try XCTUnwrap(device.store.householdItems.first)
        var draft = NewEventDraft(item: item)
        draft.title = "変更後"
        draft.date = build15MovedDay
        draft.isAllDay = true

        let calendar = device.calendar()
        calendar.startEditingEvent(item)
        XCTAssertTrue(calendar.saveEditedEvent(draft))
        let fields = try XCTUnwrap(device.backend.sentUpdates.last?.fields)
        XCTAssertEqual(Set(fields.keys), ["title", "date", "hasTime", "isCompleted", "deferredTo", "droppedAt", "updatedBy", "updatedAt"])
        XCTAssertEqual(fields["title"], .string("変更後"))
        XCTAssertEqual(fields["date"], .date(LifeCalendar.startOfDay(build15MovedDay)))
        XCTAssertEqual(fields["hasTime"], .bool(false))
        XCTAssertNil(fields["kind"])
        XCTAssertNil(fields["createdBy"])
        XCTAssertNil(fields["createdAt"])
    }

    func testExistingSharedEventCanStillBeEditedWhenNewSharingIsOff() throws {
        let server = FakeSharedServer()
        server.enabledKinds.insert("event")
        let device = Build15Device(server: server, uid: "alice")
        device.store.add([build15Event()], destination: .household)
        let item = try XCTUnwrap(device.store.householdItems.first)

        server.enabledKinds.remove("event")
        device.service.apply(household: HouseholdSummary(
            name: "わが家", sharedKinds: [.todo, .shopping], isOwner: true,
            members: [HouseholdMember(role: .owner, isSelf: true)], groupID: "group-build15"
        ))
        var changed = item
        changed.title = "オフのあとも変更"
        XCTAssertTrue(device.store.updateEvent(changed))
        XCTAssertEqual(server.title(of: item.id), "オフのあとも変更")
        XCTAssertEqual(device.backend.sentUpdates.count, 1)
    }

    func testDeniedSharedEditShowsNoticeAndDoesNotCreatePersonalDuplicate() throws {
        let server = FakeSharedServer()
        server.enabledKinds.insert("event")
        let device = Build15Device(server: server, uid: "alice")
        device.store.add([build15Event()], destination: .household)
        let item = try XCTUnwrap(device.store.householdItems.first)
        let originalTitle = server.title(of: item.id)

        server.deniesEverything = true
        var changed = item
        changed.title = "保存できない変更"
        XCTAssertTrue(device.store.updateEvent(changed), "端末では編集操作を受け付ける")
        XCTAssertNotNil(device.service.notice)
        XCTAssertEqual(server.title(of: item.id), originalTitle, "サーバーの内容は変えない")
        XCTAssertTrue(device.store.items.isEmpty, "個人の複製を勝手に作らない")
        XCTAssertEqual(server.count, 1)
    }
}

final class Build15EventEditUITests: XCTestCase {
    func testEditButtonIsDiscoverableAndAccessible() throws {
        let source = try build15Source("LifeOS/Features/Calendar/CalendarView.swift")
        XCTAssertTrue(source.contains("struct CalendarEventEditButton: View"))
        XCTAssertTrue(source.contains("Image(systemName: \"pencil\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"予定を編集\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(Self.accessibilityIdentifier)"))
        XCTAssertEqual(CalendarEventEditButton.accessibilityIdentifier, "calendar.editEvent")
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        XCTAssertTrue(source.contains("viewModel.startEditingEvent(item)"))
    }

    /// Build 17（2026-11-02）：編集でも保存先を出すようになった（Build 15 では追加のときだけだった）。
    /// 同じ入力部品を使うこと・保存先の初期値が今の保存先であることを確かめる（docs/BUILD_17_EVENT_DESTINATION_SWITCH.md）
    func testEditSheetUsesSameFieldsButDoesNotOfferDestinationChange() throws {
        let source = try build15Source("LifeOS/Features/Calendar/CalendarEventSheet.swift")
        XCTAssertEqual(CalendarEventSheetPurpose.edit.title, "予定を編集")
        XCTAssertEqual(CalendarEventSheetPurpose.add.title, "予定を追加")
        XCTAssertFalse(source.contains("if purpose == .add {\n"), "Build 17：保存先は追加・編集の両方で出す")
        XCTAssertTrue(source.contains("Picker(\"保存先\", selection: $draft.destination)"))
        let shared = LifeItem(title: "共有", kind: .event, ownership: .shared, date: build15OriginalDay)
        XCTAssertEqual(EventEditSession(item: shared, isShared: true).draft.destination, .household, "初期値は今の保存先")
        XCTAssertEqual(EventEditSession(item: build15Event(), isShared: false).draft.destination, .personal)
        XCTAssertTrue(source.contains("DatePicker(\"日付\""))
        XCTAssertTrue(source.contains("Toggle(\"終日\""))
        XCTAssertTrue(source.contains("DatePicker(\"時刻\""))
        XCTAssertTrue(source.contains("calendar.saveEvent"))
    }

    /// Build 17（2026-11-02）：Build 番号は 17 になった（Build 16 は欠番）。4か所がそろっていて、Build 15 より前に戻っていないことを確かめる
    /// （ちょうど 17 であることは Build17EventDestinationSwitchTests で確かめる）
    func testBuildNumberIs15InAllFourSettings() throws {
        let project = try build15Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).filter { $0.contains("CURRENT_PROJECT_VERSION =") }
        XCTAssertEqual(lines.count, 4)
        let numbers = lines.compactMap { line -> Int? in
            guard let value = line.split(separator: "=").last else { return nil }
            return Int(value.trimmingCharacters(in: CharacterSet(charactersIn: " ;\t")))
        }
        XCTAssertEqual(numbers.count, 4)
        XCTAssertEqual(Set(numbers).count, 1, "4か所の Build 番号がそろっている")
        XCTAssertTrue(numbers.allSatisfy { $0 >= 15 })
    }
}

final class Build15TodoDueDateTests: XCTestCase {
    private func todo(_ title: String = "書類を出す", ownership: Ownership = .personal, day: Date = build15OriginalDay) -> LifeItem {
        LifeItem(
            title: title,
            kind: .todo,
            ownership: ownership,
            date: LifeCalendar.startOfDay(day),
            assignee: ownership == .personal ? .me : nil
        )
    }

    func testPersonalTodoDateCanMoveToAnyFutureDayWithoutFirestore() throws {
        let original = todo()
        let server = FakeSharedServer()
        let device = Build15Device(server: server, uid: "alice", items: [original])
        var changed = original
        changed.title = "確定申告を出す"
        changed.date = TestDates.make(2030, 12, 25, 18, 30)

        XCTAssertTrue(device.store.updateTodo(changed))
        let saved = try XCTUnwrap(device.store.items.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.title, "確定申告を出す")
        XCTAssertEqual(saved.date, TestDates.make(2030, 12, 25))
        XCTAssertFalse(saved.hasTime)
        XCTAssertEqual(device.backend.totalCalls, 0)
    }

    func testExplicitTodoDateClearsLaterDestination() throws {
        var original = todo()
        original.deferredTo = TestDates.make(2026, 11, 9, 20, 0)
        let store = build15Store(items: [original])
        var changed = original
        changed.date = build15MovedDay

        XCTAssertTrue(store.updateTodo(changed))
        let saved = try XCTUnwrap(store.items.first)
        XCTAssertEqual(saved.date, LifeCalendar.startOfDay(build15MovedDay))
        XCTAssertNil(saved.deferredTo)
    }

    func testPartnerTodoDateEditUpdatesSameItemOnBothDevicesOnce() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        server.memberUIDs = ["alice", "bob"]
        let alice = Build15Device(server: server, uid: "alice")
        let bob = Build15Device(server: server, uid: "bob")
        alice.store.add([todo()], destination: .household)
        let shared = try XCTUnwrap(bob.store.householdItems.first)
        var changed = shared
        changed.date = build15MovedDay

        XCTAssertTrue(bob.store.updateTodo(changed))
        for store in [alice.store, bob.store] {
            let saved = try XCTUnwrap(store.householdItems.first)
            XCTAssertEqual(saved.id, shared.id)
            XCTAssertEqual(saved.date, LifeCalendar.startOfDay(build15MovedDay))
        }
        XCTAssertEqual(bob.backend.sentUpdates.count, 1)
        XCTAssertTrue(bob.backend.sentCreates.isEmpty)
        XCTAssertTrue(bob.backend.sentDeletes.isEmpty)
        XCTAssertEqual(server.count, 1)
    }

    func testTodoDateMovesBetweenTodayAndUpcoming() {
        let original = todo(day: build15Now)
        let store = build15Store(items: [original])
        let state = AppState()
        let tasks = TasksViewModel(store: store, appState: state, now: build15Now)
        XCTAssertEqual(tasks.tasks.map(\.id), [original.id])

        var changed = original
        changed.date = build15MovedDay
        XCTAssertTrue(store.updateTodo(changed))
        XCTAssertTrue(tasks.tasks.isEmpty, "未来へ移したら「今日」から外れる")
        tasks.segment = .upcoming
        XCTAssertEqual(tasks.tasks.map(\.id), [original.id])
    }

    func testQuickAddRefineOffersDateForTodoAndKeepsSelectedDay() throws {
        let store = build15Store()
        let model = QuickAddViewModel(store: store, now: build15Now)
        let candidate = QuickAddCandidate(item: todo(day: build15Now), isSelected: true)
        model.candidates = [candidate]

        XCTAssertTrue(model.canChooseDate(candidate))
        model.setDate(TestDates.make(2031, 4, 3), for: candidate.id)
        XCTAssertEqual(model.candidates.first?.item.date, TestDates.make(2031, 4, 3))
        model.addSelected()
        XCTAssertEqual(store.items.first?.date, TestDates.make(2031, 4, 3))
    }

    func testUpdateTodoRejectsEmptyNonTodoAndMissingItem() {
        let original = todo()
        let store = build15Store(items: [original])
        var empty = original
        empty.title = "   "
        XCTAssertFalse(store.updateTodo(empty))

        let event = build15Event()
        XCTAssertFalse(store.updateTodo(event))

        var missing = original
        missing = LifeItem(id: UUID(), title: missing.title, kind: .todo, ownership: .personal, date: missing.date)
        XCTAssertFalse(store.updateTodo(missing))
        XCTAssertEqual(store.items, [original])
    }

    func testTodoEditSheetHasUnboundedDatePickerAndKeepsOtherKindsUnchanged() throws {
        let source = try build15Source("LifeOS/Features/Sharing/SharedItemComponents.swift")
        XCTAssertTrue(source.contains("if item.kind == .todo"))
        XCTAssertTrue(source.contains("DatePicker(\"日付\", selection: $todoDate, displayedComponents: .date)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"todo.dueDate\")"))
        XCTAssertFalse(source.contains("in: Date()..."), "将来日の上限を付けない")
        XCTAssertTrue(source.contains("store.updateTodo(updated)"))
    }
}
