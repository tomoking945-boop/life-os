import XCTest
@testable import LifeOS

// Build 14（2026-11-01）：予定の削除の実機の不具合を直す・カレンダーから作る予定を「わが家で共有」にできるようにする。
// docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md
// 本物の Firestore・ネットワークは使わない（共有項目の窓口は SharedTodoShoppingTests.swift の偽物 FakeSharedServer・FakeSharedItemsBackend）。

/// 2026年11月10日（火）9:00
private let november10 = TestDates.make(2026, 11, 10, 9, 0)
/// 予定の日：2026年11月20日（金）
private let eventDay = TestDates.make(2026, 11, 20)

private func emptyStore() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func household(kinds: [SharedSpaceKind] = [.event, .todo, .shopping], groupID: String = "group-a") -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家",
        sharedKinds: kinds,
        isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: groupID
    )
}

/// 端末1台（置き場・共有の窓口・わが家・画面の状態）
private struct EventDevice {
    let store: LifeStore
    let backend: FakeSharedItemsBackend
    let service: SharedItemsService
    let appState: AppState

    init(server: FakeSharedServer, uid: String, store: LifeStore = emptyStore(), kinds: [SharedSpaceKind]? = [.event, .todo, .shopping]) {
        self.store = store
        backend = FakeSharedItemsBackend(server: server, uid: uid)
        service = SharedItemsService(backend: backend)
        service.attach(store)
        if let kinds {
            service.apply(household: household(kinds: kinds))
        }
        appState = AppState()
        appState.usageStyle = .shared
    }

    func calendar(now: Date = november10) -> CalendarViewModel {
        CalendarViewModel(store: store, appState: appState, now: now)
    }

    func today(on day: Date = eventDay) -> TodayViewModel {
        TodayViewModel(store: store, appState: appState, now: LifeCalendar.date(on: day, hour: 8, minute: 0))
    }
}

/// 予定の下書き（カレンダーの「予定を追加」と同じ）
private func draft(_ title: String, hour: Int? = 10, on day: Date = eventDay, destination: SaveDestination? = nil) -> NewEventDraft {
    var draft = NewEventDraft(day: day)
    draft.title = title
    if let hour {
        draft.isAllDay = false
        draft.time = LifeCalendar.date(on: day, hour: hour, minute: 0)
    }
    if let destination { draft.destination = destination }
    return draft
}

private func personalEvent(_ title: String, hour: Int = 10, on day: Date = eventDay) -> LifeItem {
    LifeItem(title: title, kind: .event, ownership: .personal, date: LifeCalendar.date(on: day, hour: hour, minute: 0), hasTime: true, assignee: .me)
}

private func personalItem(_ title: String, _ kind: LifeItemKind, on day: Date = eventDay) -> LifeItem {
    LifeItem(title: title, kind: kind, ownership: .personal, date: LifeCalendar.startOfDay(day), assignee: .me)
}

private func notificationID(_ id: UUID) -> String {
    "\(LifeNotificationPlanner.identifierPrefix)event.\(id.uuidString)"
}

private func sourceRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func readSource(_ path: String) throws -> String {
    guard let text = try? String(contentsOf: sourceRoot().appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

// MARK: - 1. 予定の削除（ごみ箱ボタン）

final class Build14EventDeleteButtonTests: XCTestCase {
    /// ごみ箱ボタン：trash・44×44 ポイント以上・「予定を削除」・UI テスト用の識別子。押すと確認を出すだけ
    func testDeleteButtonSourceIsReliableButton() throws {
        let view = try readSource("LifeOS/Features/Calendar/CalendarView.swift")
        let start = try XCTUnwrap(view.range(of: "struct CalendarEventDeleteButton: View {"))
        let end = try XCTUnwrap(view.range(of: "/// 予定の行（チェックなし・時刻付き）。"))
        let button = String(view[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(button.contains("Button(action: action)"), "ふつうの Button（スワイプ・重なりに頼らない）")
        XCTAssertTrue(button.contains("Image(systemName: \"trash\")"))
        XCTAssertTrue(button.contains(".frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)"))
        XCTAssertTrue(button.contains(".frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)"))
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        XCTAssertTrue(button.contains(".accessibilityLabel(\"予定を削除\")"))
        XCTAssertTrue(button.contains(".accessibilityIdentifier(Self.accessibilityIdentifier)"))
        XCTAssertEqual(CalendarEventDeleteButton.accessibilityIdentifier, "calendar.deleteEvent")
        XCTAssertFalse(button.contains("deleteEvent("), "ボタンは消さない（確認を出すだけ）")
        // 行の右側に置き、押すと確認を出す
        XCTAssertTrue(view.contains("CalendarEventDeleteButton(title: item.title) {\n                                viewModel.requestDeleteEvent(item)"))
        // 壊れていたスワイプは呼んでいない（説明のコメントに名前が残っていても、呼び出し「LifeSwipeDeleteRow(」が無いことを確かめる）
        XCTAssertFalse(view.contains("LifeSwipeDeleteRow("), "スワイプの部品を呼ばない（操作を二重にしない）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceRoot().appendingPathComponent("LifeOS/DesignSystem/Components/LifeSwipeDeleteRow.swift").path), "使わなくなったスワイプの部品は消した")
        // 削除ボタンの中に、ボタンに重なるタップの受け手を置かない（Build 13 の原因）
        XCTAssertFalse(button.contains(".onTapGesture"), "削除ボタンにタップの受け手を重ねない")
        XCTAssertFalse(button.contains("Gesture("), "削除ボタンに独自のジェスチャーを付けない")
    }

    /// 削除ボタン → 確認の状態になる（まだ消さない）
    func testDeleteButtonShowsConfirmation() {
        let store = emptyStore()
        let dentist = personalEvent("歯医者")
        store.add([dentist])
        let device = EventDevice(server: FakeSharedServer(), uid: "alice", store: store)
        let calendar = device.calendar()
        calendar.select(eventDay)

        calendar.requestDeleteEvent(dentist)
        XCTAssertEqual(calendar.eventPendingDeletion?.id, dentist.id)
        XCTAssertEqual(store.items.map(\.id), [dentist.id], "押しただけでは消さない")
        XCTAssertEqual(device.backend.totalCalls, 0)
    }

    /// キャンセルでは何も変えない
    func testCancelKeepsEvent() {
        let store = emptyStore()
        let dentist = personalEvent("歯医者")
        store.add([dentist])
        let device = EventDevice(server: FakeSharedServer(), uid: "alice", store: store)
        let calendar = device.calendar()
        calendar.select(eventDay)

        calendar.requestDeleteEvent(dentist)
        calendar.cancelDeleteEvent()
        XCTAssertNil(calendar.eventPendingDeletion)
        XCTAssertFalse(calendar.confirmDeleteEvent(), "確認が閉じたあとは消さない")
        XCTAssertEqual(store.items.map(\.id), [dentist.id])
        XCTAssertEqual(calendar.selectedItems.map(\.id), [dentist.id])
        XCTAssertEqual(device.backend.totalCalls, 0)
    }

    /// 自分だけの予定を消せる（端末から。Firestore は呼ばない）
    func testPersonalEventDelete() {
        let store = emptyStore()
        let dentist = personalEvent("歯医者")
        store.add([dentist])
        let device = EventDevice(server: FakeSharedServer(), uid: "alice", store: store)
        let calendar = device.calendar()

        calendar.requestDeleteEvent(dentist)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(device.backend.totalCalls, 0, "自分だけの予定の削除は Firestore を呼ばない")
    }

    /// 共有の予定を消すと、Firestore の削除を1回だけ呼ぶ（相手の端末からも消える）
    func testSharedEventDeleteCallsFirestoreOnce() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        let shared = try XCTUnwrap(alice.store.householdItems.first)
        XCTAssertEqual(bob.store.householdEvents.map(\.id), [shared.id])

        let calendar = alice.calendar()
        calendar.requestDeleteEvent(shared)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertEqual(alice.backend.sentDeletes, [shared.id], "削除は1回だけ")
        XCTAssertEqual(server.count, 0)
        XCTAssertTrue(alice.store.householdItems.isEmpty)
        XCTAssertTrue(bob.store.householdItems.isEmpty, "相手の端末からも消える")
        XCTAssertTrue(alice.store.items.isEmpty, "自分だけの予定として残さない")

        // もう一度押しても、2回目の削除は送らない（もう無い）
        calendar.requestDeleteEvent(shared)
        XCTAssertFalse(calendar.confirmDeleteEvent())
        XCTAssertEqual(alice.backend.sentDeletes.count, 1)
    }

    /// 消すのは選んだ1件だけ。ToDo・買い物・家事・共有の ToDo・ほかの予定は残る
    func testOtherItemsRemain() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let store = emptyStore()
        let keepEvent = personalEvent("美容院", hour: 15)
        let todo = personalItem("書類を出す", .todo)
        let shopping = personalItem("牛乳を買う", .shopping)
        let chore = personalItem("ゴミ出し", .chore)
        store.add([keepEvent, todo, shopping, chore])
        let alice = EventDevice(server: server, uid: "alice", store: store)
        alice.store.add([personalItem("共有のToDo", .todo)], destination: .household)
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        XCTAssertTrue(alice.calendar().saveEvent(draft("共有の旅行", hour: nil, destination: .household)))
        let target = try XCTUnwrap(alice.store.householdItems.first { $0.title == "歯医者" })

        let calendar = alice.calendar()
        for other in [todo, shopping, chore] {
            XCTAssertFalse(calendar.canDeleteEvent(other), other.title)
            calendar.requestDeleteEvent(other)
            XCTAssertNil(calendar.eventPendingDeletion)
            XCTAssertFalse(alice.store.deleteEvent(other.id), other.title)
        }
        let sharedTodo = try XCTUnwrap(alice.store.householdItems.first { $0.kind == .todo })
        XCTAssertFalse(alice.store.deleteEvent(sharedTodo.id), "共有の ToDo は予定の削除では消さない")

        calendar.requestDeleteEvent(target)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertEqual(Set(alice.store.items.map(\.id)), [keepEvent.id, todo.id, shopping.id, chore.id])
        XCTAssertEqual(Set(alice.store.householdItems.map(\.title)), ["共有のToDo", "共有の旅行"])
        XCTAssertEqual(alice.backend.sentDeletes, [target.id])
        XCTAssertEqual(server.count, 2)
    }

    /// 今日とカレンダーの両方から消える（自分の端末も、相手の端末も）
    func testRemovedFromTodayAndCalendar() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", hour: 18, destination: .household)))
        let personal = personalEvent("自分の予定", hour: 12)
        alice.store.add([personal])
        let shared = try XCTUnwrap(alice.store.householdEvents.first)

        let aliceToday = alice.today()
        let bobToday = bob.today()
        let aliceCalendar = alice.calendar()
        let bobCalendar = bob.calendar()
        aliceCalendar.select(eventDay)
        bobCalendar.select(eventDay)
        XCTAssertTrue((aliceToday.focusItems + aliceToday.restItems).contains { $0.id == shared.id })
        XCTAssertTrue((bobToday.focusItems + bobToday.restItems).contains { $0.id == shared.id })
        XCTAssertTrue(bobCalendar.selectedItems.contains { $0.id == shared.id })

        aliceCalendar.requestDeleteEvent(shared)
        XCTAssertTrue(aliceCalendar.confirmDeleteEvent())
        for (today, calendar) in [(aliceToday, aliceCalendar), (bobToday, bobCalendar)] {
            XCTAssertFalse((today.focusItems + today.restItems).contains { $0.id == shared.id }, "今日から消える")
            XCTAssertFalse(calendar.selectedItems.contains { $0.id == shared.id }, "カレンダーから消える")
            XCTAssertEqual(calendar.itemCount(on: eventDay), calendar === aliceCalendar ? 1 : 0)
        }
        XCTAssertTrue(aliceCalendar.selectedItems.contains { $0.id == personal.id }, "ほかの予定は残る")

        // 自分だけの予定も、今日とカレンダーの両方から消える
        aliceCalendar.requestDeleteEvent(personal)
        XCTAssertTrue(aliceCalendar.confirmDeleteEvent())
        XCTAssertTrue(aliceCalendar.selectedItems.isEmpty)
        XCTAssertFalse((aliceToday.focusItems + aliceToday.restItems).contains { $0.id == personal.id })
    }

    /// 削除した予定のローカル通知は残らない（自分だけの予定も、共有の予定も。相手の端末でも）
    func testNoLocalNotificationLeftAfterDelete() async throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        let personal = personalEvent("自分の歯医者", hour: 9)
        let keep = personalEvent("美容院", hour: 15)
        alice.store.add([personal, keep])
        XCTAssertTrue(alice.calendar().saveEvent(draft("共有の歯医者", hour: 11, destination: .household)))
        let shared = try XCTUnwrap(alice.store.householdEvents.first)

        let aliceCenter = FakeNotificationCenter()
        let bobCenter = FakeNotificationCenter()
        let aliceService = LifeNotificationService(center: aliceCenter)
        let bobService = LifeNotificationService(center: bobCenter)
        func resync() async {
            await aliceService.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: alice.store.notificationItems, eventRemindersEnabled: true, now: november10)
            await bobService.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: bob.store.notificationItems, eventRemindersEnabled: true, now: november10)
        }
        await resync()
        XCTAssertTrue(aliceCenter.pending.isSuperset(of: [notificationID(personal.id), notificationID(keep.id), notificationID(shared.id)]))
        XCTAssertTrue(bobCenter.pending.contains(notificationID(shared.id)), "共有の予定は相手の iPhone でも、その iPhone の設定で予約")

        let calendar = alice.calendar()
        calendar.requestDeleteEvent(shared)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        calendar.requestDeleteEvent(personal)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        await resync()
        XCTAssertFalse(aliceCenter.pending.contains(notificationID(shared.id)))
        XCTAssertFalse(aliceCenter.pending.contains(notificationID(personal.id)))
        XCTAssertFalse(bobCenter.pending.contains(notificationID(shared.id)), "相手の iPhone にも残らない")
        XCTAssertTrue(aliceCenter.pending.contains(notificationID(keep.id)), "ほかの予定の通知は残る")
    }

    /// 共有の予定の通知は、その iPhone の「今日の予定のお知らせ」がオフなら予約しない
    func testSharedEventNotificationFollowsEachDeviceSetting() async throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        XCTAssertTrue(alice.calendar().saveEvent(draft("共有の歯医者", hour: 11, destination: .household)))
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        let center = FakeNotificationCenter()
        let service = LifeNotificationService(center: center)
        await service.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: bob.store.notificationItems, eventRemindersEnabled: false, now: november10)
        XCTAssertFalse(center.pending.contains(notificationID(shared.id)))
        await service.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: bob.store.notificationItems, eventRemindersEnabled: true, now: november10)
        XCTAssertTrue(center.pending.contains(notificationID(shared.id)))
    }

    /// アプリの通知の予約し直しは、端末の項目＋共有の予定を使う（MainTabView のきっかけにも共有の予定を入れる）
    func testNotificationWiringIncludesSharedEvents() throws {
        let service = try readSource("LifeOS/Core/Notifications/LifeNotificationService.swift")
        XCTAssertTrue(service.contains("items: store.notificationItems,"))
        let tab = try readSource("LifeOS/App/MainTabView.swift")
        XCTAssertTrue(tab.contains("items: store.notificationItems,"))
        XCTAssertTrue(tab.contains("sharedItems.updateSignIn(auth.account != nil)"))
    }
}

// MARK: - 2. 再起動・端末の保存

final class Build14PersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build14-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func savedFile() throws -> String {
        try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
    }

    /// 削除した予定は、アプリを開き直しても戻らない（自分だけの予定も、共有の予定も）
    func testDeletedEventsStayGoneAfterRelaunch() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let device = EventDevice(server: server, uid: "alice", store: store)
        let personal = personalEvent("自分の歯医者")
        let keep = personalEvent("美容院", hour: 15)
        store.add([personal, keep])
        XCTAssertTrue(device.calendar().saveEvent(draft("共有の歯医者", hour: 11, destination: .household)))
        XCTAssertTrue(device.calendar().saveEvent(draft("共有の旅行", hour: nil, destination: .household)))
        let shared = try XCTUnwrap(store.householdItems.first { $0.title == "共有の歯医者" })

        let calendar = device.calendar()
        calendar.requestDeleteEvent(personal)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        calendar.requestDeleteEvent(shared)
        XCTAssertTrue(calendar.confirmDeleteEvent())

        // 開き直す：端末の保存と、Firestore（偽物）から読み直した共有の予定
        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let again = EventDevice(server: server, uid: "alice", store: relaunched)
        XCTAssertEqual(relaunched.items.map(\.id), [keep.id], "自分だけの予定は戻らない")
        XCTAssertEqual(again.store.householdItems.map(\.title), ["共有の旅行"], "共有の予定も戻らない（残りは Firestore から読み直す）")
        XCTAssertEqual(again.backend.listenStartCount, 1)
    }

    /// 共有の予定は life-store.json に保存しない（起動中だけ。Firestore から読み直す）
    func testSharedEventsAreNotWrittenToLifeStoreFile() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let device = EventDevice(server: server, uid: "alice", store: store)
        XCTAssertTrue(device.calendar().saveEvent(draft("共有の結婚記念日", hour: nil, destination: .household)))
        XCTAssertTrue(device.calendar().saveEvent(draft("自分の歯医者")))
        XCTAssertEqual(store.items(on: eventDay, scope: .all).count, 2)

        let file = try savedFile()
        XCTAssertFalse(file.contains("共有の結婚記念日"), "共有の予定を端末のファイルに書かない")
        XCTAssertTrue(file.contains("自分の歯医者"))

        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(relaunched.items.map(\.title), ["自分の歯医者"], "共有の予定は個人として二重に残らない")
        XCTAssertTrue(relaunched.householdItems.isEmpty)
    }
}

// MARK: - 3. 予定の保存先

final class Build14EventDestinationTests: XCTestCase {
    /// 新しい予定の保存先の初期値は「自分だけ」（シートを開いたときも）
    func testNewEventDestinationDefaultsToPersonal() throws {
        XCTAssertEqual(NewEventDraft(day: eventDay).destination, .personal)
        let device = EventDevice(server: FakeSharedServer(), uid: "alice")
        let calendar = device.calendar()
        XCTAssertNil(calendar.eventSharingBlock, "共有できる状態でも")
        calendar.startAddingEvent()
        XCTAssertEqual(calendar.eventDraft?.destination, .personal, "自動で共有を選ばない")
        let sheet = try readSource("LifeOS/Features/Calendar/CalendarEventSheet.swift")
        XCTAssertTrue(sheet.contains("Picker(\"保存先\", selection: $draft.destination)"))
        XCTAssertTrue(sheet.contains(".disabled(sharingBlock != nil)"), "共有できないときは選べない")
        XCTAssertTrue(sheet.contains("if let sharingBlock { return sharingBlock.message }"), "選べない理由を出す")
    }

    /// 自分だけの予定は Firestore を呼ばない
    func testPersonalEventsNeverCallFirestore() {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let device = EventDevice(server: server, uid: "alice")
        let calendar = device.calendar()
        XCTAssertTrue(calendar.saveEvent(draft("歯医者")))
        XCTAssertTrue(calendar.saveEvent(draft("旅行", hour: nil, destination: .personal)))
        XCTAssertEqual(device.backend.totalCalls, 0)
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(device.store.items.count, 2)
        XCTAssertTrue(device.store.items.allSatisfy { $0.ownership == .personal && $0.kind == .event })
        XCTAssertTrue(device.store.householdItems.isEmpty)
    }

    /// 利用者が「わが家で共有」を選んだときだけ Firestore へ送る。送るのは決まった項目だけ
    func testOnlyExplicitHouseholdChoiceSendsFixedFields() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let device = EventDevice(server: server, uid: "alice")
        let calendar = device.calendar()
        XCTAssertTrue(calendar.saveEvent(draft("自分の予定")))
        XCTAssertEqual(device.backend.totalCalls, 0)

        XCTAssertTrue(calendar.saveEvent(draft("  歯医者  ", hour: 10, destination: .household)))
        XCTAssertEqual(device.backend.sentCreates.count, 1)
        let sent = try XCTUnwrap(device.backend.sentCreates.first)
        XCTAssertEqual(Set(sent.fields.keys), ["schemaVersion", "kind", "title", "date", "hasTime", "isCompleted", "assigneeUID", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertEqual(sent.fields["kind"], .string("event"))
        XCTAssertEqual(sent.fields["title"], .string("歯医者"))
        XCTAssertEqual(sent.fields["hasTime"], .bool(true))
        XCTAssertEqual(sent.fields["date"], .date(LifeCalendar.date(on: eventDay, hour: 10, minute: 0)))
        XCTAssertEqual(sent.fields["isCompleted"], .bool(false))
        XCTAssertEqual(sent.fields["assigneeUID"], .null)
        XCTAssertEqual(sent.fields["createdBy"], .currentUser)
        XCTAssertEqual(sent.fields["updatedBy"], .currentUser)
        XCTAssertEqual(sent.fields["createdAt"], .serverTimestamp)
        XCTAssertEqual(sent.fields["updatedAt"], .serverTimestamp)
        // 決まった項目の名前に、送らない情報の名前が入っていない。
        // （"uid" は決まった項目の assigneeUID と重なるため、部分一致の一覧には入れない。UID の値は下で別に確かめる）
        for word in ["memo", "note", "location", "email", "device", "token", "calendar", "ownership", "softTime", "memoryID"] {
            XCTAssertFalse(sent.fields.keys.contains { $0.lowercased().contains(word.lowercased()) }, word)
        }
        // 実際の UID（この端末は "alice"）を、値としてアプリから送っていない（作成者・更新者は .currentUser で、Firebase の窓口が入れる）
        XCTAssertFalse(sent.fields.values.contains(.string("alice")), "UID の文字を値として送らない")
        for (key, value) in sent.fields {
            if case .string(let text) = value {
                XCTAssertFalse(text.contains("alice"), "\(key)：UID の文字を値に含めない")
            }
        }
        // 文書の ID は予定の UUID（同じ UUID なら1件のまま）
        XCTAssertEqual(sent.id, device.store.householdEvents.first?.id)
        XCTAssertFalse(device.store.items.contains { $0.id == sent.id }, "端末の個人データには入れない")

        // 終日の予定は「時刻なし」で送る
        XCTAssertTrue(calendar.saveEvent(draft("旅行", hour: nil, destination: .household)))
        XCTAssertEqual(device.backend.sentCreates.last?.fields["hasTime"], .bool(false))
        XCTAssertEqual(device.backend.sentCreates.last?.fields["date"], .date(LifeCalendar.startOfDay(eventDay)))
    }

    /// なんでも追加の予定は、「わが家で共有」を選んでいても自分だけ（Build 14 では、予定の共有はカレンダーからだけ）
    @MainActor
    func testQuickAddEventsStayPersonal() {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let device = EventDevice(server: server, uid: "alice")
        let quickAdd = QuickAddViewModel(store: device.store, now: TestDates.friday)
        quickAdd.destination = .household
        quickAdd.inputText = "19時 美容院"
        XCTAssertTrue(quickAdd.quickAdd(.event))
        quickAdd.inputText = "明日10時 歯医者"
        XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared))
        XCTAssertTrue(device.backend.sentCreates.allSatisfy { $0.fields["kind"] != .string("event") }, "予定は送らない")
        XCTAssertTrue(device.store.householdEvents.isEmpty)
        XCTAssertTrue(device.store.items.filter { $0.kind == .event }.allSatisfy { $0.ownership == .personal })
        // ToDo・買い物は、これまでどおり選んだ保存先へ
        quickAdd.destination = .household
        quickAdd.inputText = "電池"
        XCTAssertTrue(quickAdd.quickAdd(.shopping))
        XCTAssertEqual(device.backend.sentCreates.last?.fields["kind"], .string("shopping"))
    }

    /// 予定がオフなら新しく共有できない（選べない理由を出し、選んでいても自分だけに保存）
    func testEventOffBlocksNewSharing() {
        let server = FakeSharedServer()
        let device = EventDevice(server: server, uid: "alice", kinds: [.todo, .shopping])
        let calendar = device.calendar()
        XCTAssertEqual(calendar.eventSharingBlock, .eventOff)
        XCTAssertEqual(EventSharingBlock.eventOff.message, "わが家の設定で「予定」がオフのため、共有できません。")
        XCTAssertTrue(calendar.saveEvent(draft("歯医者", destination: .household)))
        XCTAssertEqual(device.backend.totalCalls, 0)
        XCTAssertEqual(device.store.items.map(\.title), ["歯医者"])
        XCTAssertEqual(device.store.items.first?.ownership, .personal)
        XCTAssertFalse(device.store.canShareInHousehold(.event))
    }

    /// 選べない理由：サインインしていない・わが家に参加していない・準備ができていない・一人モード
    func testSharingBlockReasons() {
        let server = FakeSharedServer()
        let notJoined = EventDevice(server: server, uid: "alice", kinds: nil)
        XCTAssertEqual(notJoined.calendar().eventSharingBlock, .notJoined)
        notJoined.service.updateSignIn(false)
        XCTAssertEqual(notJoined.calendar().eventSharingBlock, .notSignedIn)
        XCTAssertEqual(EventSharingBlock.notSignedIn.message, "Appleでサインインして、わが家に参加すると共有できます。")
        XCTAssertEqual(EventSharingBlock.notJoined.message, "わが家に参加すると共有できます。")

        // Firebase に接続していない
        let offline = SharedItemsService(backend: nil)
        let store = emptyStore()
        offline.attach(store)
        XCTAssertEqual(store.eventSharingBlock, .notConnected)
        XCTAssertEqual(emptyStore().eventSharingBlock, .notConnected, "共有の窓口が無い")

        // 一人モード：共有を出さない
        let solo = EventDevice(server: server, uid: "alice")
        solo.appState.usageStyle = .solo
        let soloCalendar = solo.calendar()
        XCTAssertEqual(soloCalendar.eventSharingBlock, .soloMode)
        XCTAssertTrue(soloCalendar.saveEvent(draft("歯医者", destination: .household)))
        XCTAssertEqual(solo.backend.totalCalls, 0)

        // サインインして参加し、予定がオン：選べる
        let ready = EventDevice(server: server, uid: "alice")
        ready.service.updateSignIn(true)
        XCTAssertNil(ready.calendar().eventSharingBlock)
        for block in [EventSharingBlock.soloMode, .notConnected, .notSignedIn, .notJoined, .eventOff] {
            XCTAssertFalse(block.message.isEmpty)
        }
    }

    /// 予定をオフにしたあとも、すでにある共有の予定は消えず、削除できる
    func testDeleteStillWorksAfterEventOff() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        let shared = try XCTUnwrap(alice.store.householdEvents.first)

        // わが家の設定で予定をオフにした（同じわが家。見張りは作り直さない）
        server.enabledKinds = ["todo", "shopping"]
        alice.service.apply(household: household(kinds: [.todo, .shopping]))
        XCTAssertEqual(alice.store.householdEvents.map(\.id), [shared.id], "オフにしても勝手に消さない")
        XCTAssertEqual(alice.calendar().eventSharingBlock, .eventOff)
        XCTAssertEqual(alice.backend.listenStartCount, 1)

        let calendar = alice.calendar()
        XCTAssertTrue(calendar.canDeleteEvent(shared))
        calendar.requestDeleteEvent(shared)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertEqual(alice.backend.sentDeletes, [shared.id])
        XCTAssertEqual(server.count, 0)
        XCTAssertNil(alice.service.notice, "削除は断られない")
    }
}

// MARK: - 4. 2台での表示・重複・見張り・失敗

final class Build14SharedEventSyncTests: XCTestCase {
    /// 共有の予定は、相手の iPhone のカレンダー・今日・「すべて」・「共有」に出る（「自分」には出ない）
    func testSharedEventAppearsOnPartnerCalendarAndToday() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", hour: 18, destination: .household)))
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        XCTAssertEqual(shared.title, "歯医者")
        XCTAssertEqual(shared.ownership, .shared)
        XCTAssertTrue(shared.hasTime)
        XCTAssertTrue(bob.store.items.isEmpty, "相手の端末の個人データには入らない")

        let calendar = bob.calendar()
        calendar.select(eventDay)
        XCTAssertEqual(calendar.selectedItems.map(\.id), [shared.id])
        XCTAssertTrue(calendar.isShared(shared), "共有マーク")
        XCTAssertEqual(calendar.markerKinds(on: eventDay), [.event])
        let today = bob.today()
        XCTAssertTrue((today.focusItems + today.restItems).contains { $0.id == shared.id })

        XCTAssertEqual(bob.store.items(on: eventDay, scope: .all).map(\.id), [shared.id])
        XCTAssertEqual(bob.store.items(on: eventDay, scope: .shared).map(\.id), [shared.id])
        XCTAssertTrue(bob.store.items(on: eventDay, scope: .mine).isEmpty)

        // 自分の端末でも1件だけ（自分の追加を二重に出さない）
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        // 「共有」だけを見ているときに保存しても見える。「自分」だけを見ているときは「すべて」に戻す
        alice.appState.scope = .mine
        let aliceCalendar = alice.calendar()
        XCTAssertTrue(aliceCalendar.saveEvent(draft("旅行", hour: nil, destination: .household)))
        XCTAssertEqual(alice.appState.scope, .all)
    }

    /// 同じ共有の一覧を100回受け取っても、予定は重ならない（画面の描き直し・通知の予約し直しも起きない）
    func testSameSnapshotHundredTimesDoesNotDuplicate() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let bob = EventDevice(server: server, uid: "bob")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        let updates = bob.store.householdUpdateCount
        let notificationItems = bob.store.notificationItems
        for _ in 0..<100 {
            bob.backend.emitCurrent()
            alice.backend.emitCurrent()
        }
        XCTAssertEqual(bob.store.householdEvents.count, 1)
        XCTAssertEqual(alice.store.householdEvents.count, 1)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.kind == .event }.count, 1)
        XCTAssertEqual(bob.store.householdUpdateCount, updates, "同じ内容なら入れ替えない")
        XCTAssertEqual(bob.store.notificationItems, notificationItems, "通知の予約し直しのきっかけが変わらない（ループしない）")
        XCTAssertEqual(alice.store.pendingHouseholdCreateCount, 0)
        XCTAssertEqual(alice.backend.sentCreates.count, 1, "送り直さない")
        XCTAssertEqual(server.count, 1)
    }

    /// 同じ UUID の作成をくり返しても1件のまま（サーバーが2件目を断り、端末にも二重に出さない）
    func testSameUUIDNeverDuplicates() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        // 同じ UUID でもう一度送られた（再送）
        alice.service.createHouseholdItem(shared, convertingLocal: false)
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1, "同じ UUID は1件だけ")
        XCTAssertFalse(alice.store.items.contains { $0.id == shared.id }, "自分だけの写しも残らない（サーバーにある共有の予定が正本）")
    }

    /// 見張りは最大1つ（何度わが家を読み直しても・予定をオン・オフしても）
    func testAtMostOneListener() {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        for index in 0..<100 {
            alice.service.apply(household: household(kinds: index.isMultiple(of: 2) ? [.event, .todo, .shopping] : [.todo, .shopping]))
            alice.service.updateSignIn(true)
        }
        XCTAssertEqual(alice.backend.listenStartCount, 1)
        XCTAssertEqual(alice.backend.activeListenerCount, 1)
        XCTAssertEqual(alice.service.activeListenerCount, 1)
        XCTAssertEqual(alice.service.listenStartCount, 1)
        // 退出すると止まる
        alice.service.apply(household: nil)
        XCTAssertEqual(alice.backend.activeListenerCount, 0)
    }

    /// 共有に失敗したら、予定を消さず「自分だけ」の予定として1件だけ端末に残し、理由を出す
    func testShareFailureKeepsExactlyOnePersonalCopy() throws {
        let server = FakeSharedServer()
        // わが家の設定は予定オンのつもりだが、サーバーは断る（相手が直前にオフにした など）
        server.enabledKinds = ["todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        let calendar = alice.calendar()
        XCTAssertNil(calendar.eventSharingBlock)
        XCTAssertTrue(calendar.saveEvent(draft("歯医者", destination: .household)))

        XCTAssertEqual(alice.backend.sentCreates.count, 1)
        XCTAssertEqual(server.count, 0)
        XCTAssertTrue(alice.store.householdItems.isEmpty)
        XCTAssertEqual(alice.store.items.filter { $0.title == "歯医者" }.count, 1, "1件だけ残す")
        XCTAssertEqual(alice.store.items.first?.ownership, .personal)
        XCTAssertEqual(alice.store.items.first?.kind, .event)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.title == "歯医者" }.count, 1)
        XCTAssertNotNil(alice.service.notice, "理由を画面に出す")
        XCTAssertEqual(alice.store.pendingHouseholdCreateCount, 0)

        // そのあと同じ一覧を何度受け取っても増えない
        for _ in 0..<10 { alice.backend.emitCurrent() }
        XCTAssertEqual(alice.store.visibleItems.filter { $0.title == "歯医者" }.count, 1)

        // メンバーでない（退出した）・サインインしていないときも、断られて自分だけに1件
        let denied = FakeSharedServer()
        denied.enabledKinds = ["event", "todo", "shopping"]
        denied.deniesEverything = true
        let outsider = EventDevice(server: denied, uid: "mallory")
        XCTAssertTrue(outsider.calendar().saveEvent(draft("旅行", destination: .household)))
        XCTAssertEqual(denied.count, 0)
        XCTAssertEqual(outsider.store.items.filter { $0.title == "旅行" }.count, 1)
    }

    /// サーバーの決まり（偽物）：予定はメンバーでない・オフ・完了済み・担当ありなら作れない（Security Rules と同じ）
    func testFakeServerMirrorsRules() {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        server.memberUIDs = ["alice", "bob"]
        let mallory = EventDevice(server: server, uid: "mallory")
        XCTAssertTrue(mallory.calendar().saveEvent(draft("のぞき見", destination: .household)))
        XCTAssertEqual(server.count, 0, "メンバーでない人は作れない")
        let alice = EventDevice(server: server, uid: "alice")
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        XCTAssertEqual(server.count, 1)
    }

    /// 送信待ち（オフライン）の共有の予定も1件だけ見え、つながったら1回だけ送る
    func testOfflineCreateStaysVisibleOnce() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["event", "todo", "shopping"]
        let alice = EventDevice(server: server, uid: "alice")
        alice.backend.isOnline = false
        XCTAssertTrue(alice.calendar().saveEvent(draft("歯医者", destination: .household)))
        XCTAssertEqual(alice.store.householdEvents.count, 1)
        XCTAssertEqual(server.count, 0)
        alice.backend.emitEmptySnapshot()
        XCTAssertEqual(alice.store.householdEvents.count, 1, "最初の空の一覧で消さない")
        alice.backend.goOnline()
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(alice.store.householdEvents.count, 1)
        XCTAssertEqual(alice.store.pendingHouseholdCreateCount, 0)
    }
}

// MARK: - 5. わが家の設定・既存の機能

final class Build14HouseholdSettingsTests: XCTestCase {
    /// 予定は「今後対応」から同期できる種類へ。はじめの設定は ToDo・買い物だけ（予定を自動でオンにしない）
    func testEventIsToggleableButNotDefault() {
        XCTAssertEqual(SharedSpaceKind.syncSupported, [.event, .todo, .shopping, .money])
        XCTAssertFalse(SharedSpaceKind.comingSoon.contains(.event))
        XCTAssertEqual(SharedSpaceKind.defaultSelection, [.todo, .shopping])
        XCTAssertEqual(HouseholdItemPolicy.kinds, [.event, .todo, .shopping])
        XCTAssertFalse(HouseholdItemPolicy.kinds.contains(.chore), "家事は共有しない")
    }

    /// 設定画面：予定・ToDo・買い物・家計簿を切り替えられる。今後対応は家事・保証書・リスト・メモ
    func testSettingsTexts() throws {
        let settings = try readSource("LifeOS/Features/Profile/HouseholdSettingsView.swift")
        XCTAssertTrue(settings.contains("ForEach(SharedSpaceKind.syncSupported)"))
        XCTAssertTrue(settings.contains("家事・保証書・リスト・メモの共有は、今後のアップデートで対応します。"))
        XCTAssertFalse(settings.contains("予定・家事・保証書・リスト・メモの共有は"))
        let section = try readSource("LifeOS/Features/Profile/HouseholdSection.swift")
        XCTAssertFalse(section.contains("予定などの共有は今後対応します"))
        XCTAssertFalse(section.contains("予定・家事・保証書・リスト・メモの共有は"))
    }

    /// 予定を足しても、ToDo・買い物のプッシュ通知の決まりは変えない（サーバーの通知は ToDo・買い物だけ）
    func testPushPolicyUnchanged() throws {
        let policy = try readSource("firebase/functions/src/notificationPolicy.js")
        XCTAssertTrue(policy.contains("const NOTIFY_KINDS = Object.freeze(['todo', 'shopping']);"))
        let push = try readSource("LifeOS/Core/Notifications/SharedPushNotifications.swift")
        XCTAssertFalse(push.contains("case \"event\""), "アプリ側も予定の通知の行き先を足していない")
        XCTAssertTrue(push.contains("case \"todo\": self = .tasks(.today)"), "ToDo の通知の行き先は変えない")
        XCTAssertTrue(push.contains("case \"shopping\": self = .tasks(.shopping)"), "買い物の通知の行き先は変えない")
    }

    /// Build 14 では、家計簿用のレシートの読み取りを足さない（保証書の Vision の読み取りはそのまま）
    func testNoReceiptToExpenseFeature() throws {
        let money = try readSource("LifeOS/Features/Money/MoneyView.swift")
        XCTAssertFalse(money.contains("Vision"))
        XCTAssertFalse(money.contains("VNRecognizeTextRequest"))
        let moneyModel = try readSource("LifeOS/Features/Money/MoneyViewModel.swift")
        XCTAssertFalse(moneyModel.contains("Vision"))
        XCTAssertFalse(moneyModel.contains("receipt"))
    }
}
