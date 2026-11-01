import XCTest
@testable import LifeOS

// Build 16（2026-11-02）：既存の予定の編集で、保存先（自分だけ／わが家で共有）を安全に変える。
// docs/BUILD_16_EVENT_DESTINATION_SWITCH.md
// - UUID は変えない（2件にしない）。相手の端末に重複を作らない
// - 自分だけ → 共有：端末へ保存してから同じ UUID で作成。確かめられるまで端末の予定を消さない
// - 共有 → 自分だけ：確認してから、端末へ先に保存し、保存できたら共有の予定を1回だけ消す
// 本物の Firestore・ネットワークは使わない（偽物は SharedTodoShoppingTests.swift の FakeSharedServer・FakeSharedItemsBackend）。

private let build16Now = TestDates.make(2026, 11, 2, 9, 0)
private let build16Day = TestDates.make(2026, 11, 20)
private let build16MovedDay = TestDates.make(2027, 3, 5)

private func build16Store(items: [LifeItem] = []) -> LifeStore {
    LifeStore(items: items, expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func build16Household(kinds: [SharedSpaceKind] = [.event, .todo, .shopping]) -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家",
        sharedKinds: kinds,
        isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build16"
    )
}

private func build16Event(_ title: String = "歯医者", hour: Int = 10, on day: Date = build16Day) -> LifeItem {
    LifeItem(title: title, kind: .event, ownership: .personal, date: LifeCalendar.date(on: day, hour: hour, minute: 0), hasTime: true, assignee: .me)
}

/// 端末1台（置き場・共有の窓口・わが家・画面の状態）
private struct Build16Device {
    let store: LifeStore
    let backend: FakeSharedItemsBackend
    let service: SharedItemsService
    let appState: AppState

    init(server: FakeSharedServer, uid: String, store: LifeStore = build16Store(), kinds: [SharedSpaceKind] = [.event, .todo, .shopping]) {
        self.store = store
        backend = FakeSharedItemsBackend(server: server, uid: uid)
        service = SharedItemsService(backend: backend)
        service.attach(store)
        service.apply(household: build16Household(kinds: kinds))
        appState = AppState()
        appState.usageStyle = .shared
    }

    func calendar() -> CalendarViewModel {
        CalendarViewModel(store: store, appState: appState, now: build16Now)
    }
}

private func eventServer() -> FakeSharedServer {
    let server = FakeSharedServer()
    server.enabledKinds = ["event", "todo", "shopping"]
    return server
}

/// 編集画面を開き、タイトル・日時・保存先を変えた下書き
private func editedDraft(
    _ calendar: CalendarViewModel,
    for item: LifeItem,
    title: String = "健康診断",
    day: Date = build16MovedDay,
    hour: Int = 15,
    destination: SaveDestination
) throws -> NewEventDraft {
    calendar.startEditingEvent(item)
    var draft = try XCTUnwrap(calendar.eventEditSession?.draft)
    draft.title = title
    draft.date = day
    draft.isAllDay = false
    draft.time = LifeCalendar.date(on: day, hour: hour, minute: 0)
    draft.destination = destination
    return draft
}

private func build16Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

// MARK: - 1. 編集画面の保存先

final class Build16EditDestinationScreenTests: XCTestCase {
    /// 編集画面に保存先が出る（追加と同じ部品）。「自分だけ」への確認の文言
    func testEditSheetShowsDestinationAndConfirmationTexts() throws {
        let sheet = try build16Source("LifeOS/Features/Calendar/CalendarEventSheet.swift")
        XCTAssertTrue(sheet.contains("Picker(\"保存先\", selection: $draft.destination)"))
        XCTAssertFalse(sheet.contains("if purpose == .add {\n"), "保存先を追加のときだけに限らない")
        XCTAssertTrue(sheet.contains(".disabled(sharingBlock != nil)"))
        XCTAssertTrue(sheet.contains("let originalDestination: SaveDestination?"))
        let view = try build16Source("LifeOS/Features/Calendar/CalendarView.swift")
        XCTAssertTrue(view.contains("sharingBlock: viewModel.editSharingBlock,"))
        XCTAssertTrue(view.contains("originalDestination: session.originalDestination"))
        XCTAssertTrue(view.contains("\"自分だけの予定に変更しますか？\""))
        XCTAssertTrue(view.contains("Text(\"変更すると、この予定はパートナーのカレンダーから削除されます。\")"))
        XCTAssertTrue(view.contains("Button(\"自分だけに変更\", role: .destructive)"))
        XCTAssertTrue(view.contains("Button(\"キャンセル\", role: .cancel) { viewModel.cancelPersonalConversion() }"))
        // 新規追加の保存先はこれまでどおり（初期値は自分だけ）
        XCTAssertTrue(view.contains("CalendarEventSheet(draft: draft, sharingBlock: viewModel.eventSharingBlock)"))
        XCTAssertEqual(NewEventDraft(day: build16Day).destination, .personal)
        // 説明の文
        XCTAssertEqual(CalendarEventSheet.editFooter(from: .household, to: .personal), "保存するときに確認します。変更すると、この予定はパートナーのカレンダーから削除されます。")
        XCTAssertTrue(CalendarEventSheet.editFooter(from: .personal, to: .household).contains("この iPhone の予定は消しません"))
    }

    /// 今の保存先が初期選択される（自分だけ／わが家で共有）。端末の古い「共有」の印ではなく、実際に共有しているかで決める
    func testCurrentDestinationIsInitiallySelected() throws {
        let server = eventServer()
        let personal = build16Event("自分の予定")
        let device = Build16Device(server: server, uid: "alice", store: build16Store(items: [personal]))
        let calendar = device.calendar()

        calendar.startEditingEvent(personal)
        XCTAssertEqual(calendar.eventEditSession?.originalDestination, .personal)
        XCTAssertEqual(calendar.eventEditSession?.draft.destination, .personal)
        XCTAssertNil(calendar.editSharingBlock)

        XCTAssertEqual(device.store.add([build16Event("共有の予定")], destination: .household), 1)
        let shared = try XCTUnwrap(device.store.householdEvents.first)
        calendar.startEditingEvent(shared)
        XCTAssertEqual(calendar.eventEditSession?.originalDestination, .household)
        XCTAssertEqual(calendar.eventEditSession?.draft.destination, .household)

        // 以前の版の端末の中の「共有」の印の予定（Firestore には無い）は「自分だけ」として始める
        var legacy = build16Event("以前の印")
        legacy.ownership = .shared
        let legacyStore = build16Store(items: [legacy])
        let legacyCalendar = CalendarViewModel(store: legacyStore, appState: AppState(), now: build16Now)
        legacyCalendar.startEditingEvent(legacy)
        XCTAssertEqual(legacyCalendar.eventEditSession?.draft.destination, .personal)
        XCTAssertEqual(device.backend.sentDeletes.count, 0)
    }

    /// 保存先を変えない編集は、これまでどおり（自分だけは端末だけ、共有は同じ文書を1回更新）
    func testEditWithoutDestinationChangeWorksAsBefore() throws {
        let server = eventServer()
        let personal = build16Event("自分の予定")
        let device = Build16Device(server: server, uid: "alice", store: build16Store(items: [personal]))
        let calendar = device.calendar()

        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: personal, title: "自分の予定（変更）", destination: .personal)))
        XCTAssertEqual(device.store.items.map(\.title), ["自分の予定（変更）"])
        XCTAssertEqual(device.store.items.first?.id, personal.id)
        XCTAssertEqual(device.backend.totalCalls, 0, "自分だけの予定は Firestore を呼ばない")

        device.store.add([build16Event("共有の予定")], destination: .household)
        let shared = try XCTUnwrap(device.store.householdEvents.first)
        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, title: "共有の予定（変更）", destination: .household)))
        XCTAssertEqual(device.backend.sentUpdates.count, 1)
        XCTAssertEqual(device.backend.sentCreates.count, 1, "最初の共有の作成だけ")
        XCTAssertTrue(device.backend.sentDeletes.isEmpty)
        XCTAssertEqual(server.title(of: shared.id), "共有の予定（変更）")
        XCTAssertEqual(server.createdBy(of: shared.id), "alice", "作成者は変えない")
        XCTAssertEqual(device.store.items.count, 1, "共有の予定を個人に複製しない")
        XCTAssertNil(calendar.eventEditSession)
        XCTAssertNil(calendar.eventEditError)
    }
}

// MARK: - 2. 自分だけ → わが家で共有

final class Build16PersonalToSharedTests: XCTestCase {
    /// 同じ UUID で作成を1回。相手の端末に出て、確かめられたあと端末の予定を片付ける
    func testPersonalToSharedCreatesOnceWithSameUUIDAndAppearsOnPartner() throws {
        let server = eventServer()
        server.memberUIDs = ["alice", "bob"]
        let original = build16Event("自分の歯医者")
        let alice = Build16Device(server: server, uid: "alice", store: build16Store(items: [original]))
        let bob = Build16Device(server: server, uid: "bob")
        let calendar = alice.calendar()

        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: original, destination: .household)))
        XCTAssertEqual(alice.backend.sentCreates.count, 1, "作成は1回")
        XCTAssertEqual(alice.backend.sentCreates.first?.id, original.id, "新しい UUID を作らない")
        XCTAssertEqual(alice.backend.sentCreates.first?.fields["title"], .string("健康診断"), "編集後の内容で作る")
        XCTAssertEqual(alice.backend.sentCreates.first?.fields["date"], .date(LifeCalendar.date(on: build16MovedDay, hour: 15, minute: 0)))
        XCTAssertEqual(Set(try XCTUnwrap(alice.backend.sentCreates.first?.fields).keys),
                       ["schemaVersion", "kind", "title", "date", "hasTime", "isCompleted", "assigneeUID", "createdBy", "updatedBy", "createdAt", "updatedAt"],
                       "保存する項目は増やさない")
        XCTAssertEqual(server.count, 1)
        XCTAssertTrue(alice.store.items.isEmpty, "サーバーで確かめられたので、端末の予定を片付けた")
        XCTAssertEqual(alice.store.householdEvents.map(\.id), [original.id])
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)
        // 相手の端末に1件だけ出る
        XCTAssertEqual(bob.store.householdEvents.map(\.id), [original.id])
        XCTAssertEqual(bob.store.householdEvents.first?.title, "健康診断")
        XCTAssertTrue(bob.store.items.isEmpty)
        XCTAssertNil(calendar.eventEditSession)
    }

    /// サーバーで確かめられるまで、端末の自分だけの予定を消さない（オフライン）。復帰しても重複しない
    func testPersonalDataStaysUntilServerConfirmsAndNoDuplicateAfterReconnect() throws {
        let server = eventServer()
        let original = build16Event("自分の歯医者")
        let alice = Build16Device(server: server, uid: "alice", store: build16Store(items: [original]))
        let bob = Build16Device(server: server, uid: "bob")
        alice.backend.isOnline = false
        let calendar = alice.calendar()

        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: original, destination: .household)))
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(alice.store.items.map(\.id), [original.id], "確かめられるまで端末の予定を消さない")
        XCTAssertEqual(alice.store.items.first?.title, "健康診断", "編集後の内容を端末に先に保存")
        XCTAssertEqual(alice.store.items.first?.ownership, .personal)
        // 端末の予定と送信待ちの共有の予定が同じ UUID で両方あっても、画面には1件
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)
        XCTAssertEqual(alice.store.items(on: build16MovedDay, scope: .all).count, 1)
        XCTAssertEqual(alice.store.notificationItems.filter { $0.id == original.id }.count, 1)
        alice.backend.emitEmptySnapshot()
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)

        alice.backend.goOnline()
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(alice.backend.sentCreates.count, 1, "復帰しても作り直さない")
        XCTAssertTrue(alice.store.items.isEmpty)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)
        XCTAssertEqual(bob.store.householdEvents.count, 1)
        for _ in 0..<20 { alice.backend.emitCurrent() }
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)
    }

    /// 共有に失敗したら、編集後の予定が「自分だけ」として1件だけ残り、理由が出る
    func testShareFailureKeepsOneEditedPersonalEvent() throws {
        let server = FakeSharedServer()
        server.enabledKinds = ["todo", "shopping"] // サーバーは予定を断る（相手が直前にオフにした など）
        let original = build16Event("自分の歯医者")
        let alice = Build16Device(server: server, uid: "alice", store: build16Store(items: [original]))
        let calendar = alice.calendar()

        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: original, destination: .household)))
        XCTAssertEqual(alice.backend.sentCreates.count, 1)
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(alice.store.items.count, 1, "1件だけ残す")
        XCTAssertEqual(alice.store.items.first?.id, original.id)
        XCTAssertEqual(alice.store.items.first?.title, "健康診断", "編集後の内容で残す")
        XCTAssertEqual(alice.store.items.first?.ownership, .personal)
        XCTAssertTrue(alice.store.householdItems.isEmpty)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == original.id }.count, 1)
        XCTAssertNotNil(alice.service.notice, "画面に理由を出す")
    }

    /// わが家の設定で予定がオフなら、自分だけ → 共有はできない（理由を出し、何も送らない）
    func testPersonalToSharedIsBlockedWhenEventSharingIsOff() throws {
        let server = FakeSharedServer()
        let original = build16Event("自分の歯医者")
        let alice = Build16Device(server: server, uid: "alice", store: build16Store(items: [original]), kinds: [.todo, .shopping])
        let calendar = alice.calendar()
        calendar.startEditingEvent(original)
        XCTAssertEqual(calendar.editSharingBlock, .eventOff, "選べない理由")

        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: original, destination: .household)))
        XCTAssertEqual(calendar.eventEditError, EventSharingBlock.eventOff.message)
        XCTAssertNotNil(calendar.eventEditSession, "編集画面は閉じない")
        XCTAssertEqual(alice.backend.totalCalls, 0)
        XCTAssertEqual(alice.store.items, [original], "何も変えない")
        // 置き場に直接頼んでも断る
        var changed = original
        changed.title = "変えない"
        XCTAssertEqual(alice.store.saveEvent(changed, destination: .household), .failed(EventSharingBlock.eventOff.message))
        XCTAssertEqual(alice.store.items, [original])
        // サインインしていない・参加していないときも選べない
        let notSignedIn = Build16Device(server: server, uid: "carol", store: build16Store(items: [original]))
        notSignedIn.service.updateSignIn(false)
        let other = notSignedIn.calendar()
        other.startEditingEvent(original)
        XCTAssertEqual(other.editSharingBlock, .notSignedIn)
    }
}

// MARK: - 3. わが家で共有 → 自分だけ

final class Build16SharedToPersonalTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build16-\(UUID().uuidString)")
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

    /// 確認のキャンセルでは何も変わらない（端末にも Firestore にも）
    func testCancelConfirmationChangesNothing() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice")
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        let callsBefore = alice.backend.totalCalls
        let calendar = alice.calendar()

        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)), "まず確認を出す")
        XCTAssertNotNil(calendar.pendingPersonalConversionDraft)
        XCTAssertNotNil(calendar.eventEditSession, "編集画面はそのまま")
        XCTAssertEqual(alice.backend.totalCalls, callsBefore, "確認するまで何も送らない")
        XCTAssertTrue(alice.store.items.isEmpty, "確認するまで端末にも保存しない")

        calendar.cancelPersonalConversion()
        XCTAssertNil(calendar.pendingPersonalConversionDraft)
        XCTAssertNotNil(calendar.eventEditSession)
        XCTAssertFalse(calendar.confirmPersonalConversion(), "キャンセルのあとは変えない")
        XCTAssertEqual(alice.backend.totalCalls, callsBefore)
        XCTAssertEqual(alice.store.householdEvents.map(\.title), ["共有の歯医者"])
        XCTAssertTrue(alice.store.items.isEmpty)
        XCTAssertEqual(server.title(of: shared.id), "共有の歯医者")
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 0)
    }

    /// 端末へ保存したあとで、共有の予定を1回だけ消す。相手の端末から消え、自分の端末には1件だけ残る
    func testSharedToPersonalSavesOnDeviceFirstThenDeletesOnce() throws {
        let server = eventServer()
        server.memberUIDs = ["alice", "bob"]
        let alice = Build16Device(server: server, uid: "alice", store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        let bob = Build16Device(server: server, uid: "bob")
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        let calendar = alice.calendar()

        // 削除がサーバーに届く前の状態を見るため、いったんオフライン
        alice.backend.isOnline = false
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        XCTAssertNil(calendar.eventEditSession)

        // 1. 端末に先に保存されている（編集後の内容・同じ UUID・自分だけ）
        let file = try savedFile()
        XCTAssertTrue(file.contains("健康診断"))
        XCTAssertTrue(file.contains(shared.id.uuidString))
        XCTAssertTrue(file.contains("personalConversionIDs"), "変更の途中であることも端末に残す")
        XCTAssertEqual(alice.store.items.map(\.id), [shared.id])
        XCTAssertEqual(alice.store.items.first?.ownership, .personal)
        // 2. 共有の予定の削除は1回だけ送った（まだ届いていない）
        XCTAssertEqual(alice.backend.sentDeletes, [shared.id])
        XCTAssertEqual(server.count, 1)
        // 一時的に個人・共有の両方があっても、画面には1件（自分だけの方）
        XCTAssertTrue(alice.store.householdItems.isEmpty)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        XCTAssertEqual(alice.store.items(on: build16MovedDay, scope: .mine).map(\.id), [shared.id])
        XCTAssertTrue(alice.store.items(on: build16MovedDay, scope: .shared).isEmpty)
        XCTAssertEqual(alice.store.notificationItems.filter { $0.id == shared.id }.count, 1)
        for _ in 0..<20 { alice.backend.emitCurrent() }
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        XCTAssertEqual(alice.store.items.count, 1, "同じ UUID の共有の予定が届いても、端末の予定を片付けない")
        XCTAssertEqual(alice.backend.sentDeletes.count, 1, "くり返し消さない")

        // 3. 復帰：削除が届き、相手から消える。自分には1件だけ
        alice.backend.goOnline()
        XCTAssertEqual(server.count, 0)
        XCTAssertTrue(bob.store.householdEvents.isEmpty, "相手のカレンダーから消える")
        XCTAssertEqual(alice.store.items.map(\.title), ["健康診断"])
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 0)
        XCTAssertEqual(alice.backend.sentDeletes.count, 1)
        XCTAssertTrue(alice.backend.sentCreates.count == 1, "新しく作り直さない")
        XCTAssertFalse(try savedFile().contains("personalConversionIDs"), "終わったら印を消す")

        // 開き直しても1件
        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let again = Build16Device(server: server, uid: "alice", store: relaunched)
        XCTAssertEqual(again.store.items.map(\.id), [shared.id])
        XCTAssertTrue(again.store.householdItems.isEmpty)
    }

    /// 予定の共有がオフでも、共有 → 自分だけはできる（削除は種類の設定を見ない）
    func testSharedToPersonalWorksWhenEventSharingIsOff() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice")
        let bob = Build16Device(server: server, uid: "bob")
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        server.enabledKinds = ["todo", "shopping"]
        alice.service.apply(household: build16Household(kinds: [.todo, .shopping]))
        let calendar = alice.calendar()
        calendar.startEditingEvent(shared)
        XCTAssertNil(calendar.editSharingBlock, "共有している予定は、オフでも自分だけへ戻せる")

        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        XCTAssertEqual(alice.backend.sentDeletes, [shared.id])
        XCTAssertEqual(server.count, 0)
        XCTAssertTrue(bob.store.householdEvents.isEmpty)
        XCTAssertEqual(alice.store.items.map(\.title), ["健康診断"])
        XCTAssertEqual(alice.store.items.first?.ownership, .personal)
        XCTAssertNil(alice.service.notice)
    }

    /// 削除に失敗しても予定を失わない。同じ UUID の共有の予定が届いても、画面には自分だけの1件。次の起動で1回だけ消し直す
    func testDeleteFailureKeepsEventAndRetriesOnceAfterRelaunch() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice", store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        let calendar = alice.calendar()

        server.deniesEverything = true
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        XCTAssertEqual(alice.backend.sentDeletes, [shared.id])
        XCTAssertEqual(server.count, 1, "サーバーの共有の予定は残っている")
        XCTAssertNotNil(alice.service.notice, "消せなかった理由を出す")
        XCTAssertEqual(alice.store.items.map(\.title), ["健康診断"], "予定を失わない")
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 1)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        for _ in 0..<10 { alice.backend.emitCurrent() }
        XCTAssertEqual(alice.store.items.count, 1)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        XCTAssertEqual(alice.backend.sentDeletes.count, 1, "同じ起動の中ではくり返さない")

        // 開き直す（通信も戻った）：印を読み、共有の予定がまだあれば1回だけ消す
        server.deniesEverything = false
        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(relaunched.pendingPersonalConversionCount, 1)
        let again = Build16Device(server: server, uid: "alice", store: relaunched)
        XCTAssertEqual(again.backend.sentDeletes, [shared.id])
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(relaunched.items.map(\.title), ["健康診断"])
        XCTAssertEqual(relaunched.items.first?.id, shared.id)
        XCTAssertEqual(relaunched.pendingPersonalConversionCount, 0)
        XCTAssertEqual(relaunched.visibleItems.filter { $0.id == shared.id }.count, 1)
    }

    /// 端末に保存できなかったら、共有の予定を消さない（何も変えない）
    func testDeviceSaveFailureDoesNotDeleteSharedEvent() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice", store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        // 保存先をふつうのファイルにして、保存できない状態にする
        let blocker = temporaryDirectory.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        LocalStorage.directoryOverride = blocker

        let calendar = alice.calendar()
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertFalse(calendar.confirmPersonalConversion())
        XCTAssertEqual(calendar.eventEditError, EventSaveOutcome.deviceSaveFailedMessage)
        XCTAssertNotNil(calendar.eventEditSession, "編集画面は閉じない")
        XCTAssertTrue(alice.backend.sentDeletes.isEmpty, "共有の予定を消さない")
        XCTAssertEqual(server.count, 1)
        XCTAssertTrue(alice.store.items.isEmpty)
        XCTAssertEqual(alice.store.householdEvents.map(\.title), ["共有の歯医者"], "共有のまま残す")
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 0)
    }

    /// オフラインで共有 → 自分だけにして、復帰しても重複しない（相手にも自分にも）
    func testOfflineSharedToPersonalDoesNotDuplicateAfterReconnect() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice")
        let bob = Build16Device(server: server, uid: "bob")
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        alice.backend.isOnline = false
        let calendar = alice.calendar()
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        alice.backend.emitEmptySnapshot()
        alice.backend.emitCurrent()
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)

        alice.backend.goOnline()
        for _ in 0..<5 { alice.backend.emitCurrent(); bob.backend.emitCurrent() }
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        XCTAssertEqual(alice.store.items.count, 1)
        XCTAssertTrue(bob.store.householdEvents.isEmpty)
        XCTAssertTrue(bob.store.items.isEmpty)
        XCTAssertEqual(alice.backend.sentDeletes.count, 1)
        XCTAssertEqual(alice.backend.sentCreates.count, 1)
    }

    /// 片付けの途中の印が残っていても、共有の予定がもう無ければ、もう一度「わが家で共有」にできる（2件にしない）
    func testStaleMarkerDoesNotBlockSharingAgain() throws {
        let server = eventServer()
        let alice = Build16Device(server: server, uid: "alice", store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        alice.store.add([build16Event("共有の歯医者")], destination: .household)
        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        server.deniesEverything = true
        let calendar = alice.calendar()
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 1)

        // まだサーバーに共有の予定がある：重ねて作らない
        server.deniesEverything = false
        let personal = try XCTUnwrap(alice.store.items.first)
        XCTAssertEqual(alice.store.saveEvent(personal, destination: .household), .failed(EventSaveOutcome.conversionInProgressMessage))
        XCTAssertEqual(alice.backend.sentCreates.count, 1)

        // 相手が共有の予定を消した（削除の結果だけ届かなかったのと同じ）：もう一度共有できる
        let bob = Build16Device(server: server, uid: "bob")
        XCTAssertTrue(bob.store.deleteEvent(shared.id))
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(alice.store.saveEvent(personal, destination: .household), .sharingStarted)
        XCTAssertEqual(server.count, 1)
        XCTAssertTrue(alice.store.items.isEmpty)
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == shared.id }.count, 1)
        XCTAssertEqual(alice.store.pendingPersonalConversionCount, 0)
    }
}

// MARK: - 4. 通知・保存の形・Build

final class Build16NotificationAndBuildTests: XCTestCase {
    /// 保存先を変えても、ローカル通知は同じ識別子のまま、変更後の日時へ移る（2件にならない）
    func testLocalReminderMovesToEditedTimeAcrossDestinationChanges() throws {
        let server = eventServer()
        let original = build16Event("自分の歯医者", hour: 10)
        let alice = Build16Device(server: server, uid: "alice", store: build16Store(items: [original]))
        let before = try XCTUnwrap(LifeNotificationPlanner.eventRequests(items: alice.store.notificationItems, now: build16Now).first)

        let calendar = alice.calendar()
        XCTAssertTrue(calendar.saveEditedEvent(try editedDraft(calendar, for: original, hour: 15, destination: .household)))
        let afterShared = LifeNotificationPlanner.eventRequests(items: alice.store.notificationItems, now: build16Now)
        XCTAssertEqual(afterShared.count, 1)
        XCTAssertEqual(afterShared.first?.identifier, before.identifier)
        XCTAssertEqual(afterShared.first?.fireDate, LifeCalendar.date(on: build16MovedDay, hour: 14, minute: 50))

        let shared = try XCTUnwrap(alice.store.householdEvents.first)
        XCTAssertFalse(calendar.saveEditedEvent(try editedDraft(calendar, for: shared, day: build16Day, hour: 18, destination: .personal)))
        XCTAssertTrue(calendar.confirmPersonalConversion())
        let afterPersonal = LifeNotificationPlanner.eventRequests(items: alice.store.notificationItems, now: build16Now)
        XCTAssertEqual(afterPersonal.count, 1)
        XCTAssertEqual(afterPersonal.first?.identifier, before.identifier)
        XCTAssertEqual(afterPersonal.first?.fireDate, LifeCalendar.date(on: build16Day, hour: 17, minute: 50))
    }

    /// Firestore に新しい項目を足していない・新しい書き込みの種類を足していない（作成・更新・削除だけ）
    func testNoNewFirestoreFieldsOrWrites() throws {
        let source = try build16Source("LifeOS/Core/Sharing/HouseholdItems.swift")
        XCTAssertTrue(source.contains("backend.delete(groupID: groupID, id: id)"))
        let event = LifeItem(title: "歯医者", kind: .event, ownership: .shared, date: build16Day, hasTime: true)
        XCTAssertEqual(Set(try XCTUnwrap(SharedItemPayload.createFields(for: event)).keys),
                       ["schemaVersion", "kind", "title", "date", "hasTime", "isCompleted", "assigneeUID", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertEqual(Set(try XCTUnwrap(SharedItemPayload.updateFields(for: event)).keys),
                       ["title", "date", "hasTime", "isCompleted", "deferredTo", "droppedAt", "updatedBy", "updatedAt"])
    }

    /// Build 16（アプリとテスト、Debug と Release の4か所）。Version 1.0・暗号化の設定は変えない
    func testBuildNumberIs16InAllFourSettings() throws {
        let project = try build16Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 16;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
    }
}
