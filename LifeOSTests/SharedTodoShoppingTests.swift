import XCTest
@testable import LifeOS

// わが家で共有する ToDo・買い物（2026-10-28。Build 7 第2段階）のテスト。docs/SHARED_TODO_SHOPPING_FOUNDATION.md
// ネットワーク・実際の Firestore は使わない。Firestore の代わりに、2台の端末から使える「偽物のサーバー」を使う。

/// 偽物のサーバー（Firestore の groups/{groupID}/items の代わり。Security Rules の主な決まりも真似する）
final class FakeSharedServer {
    /// 文書（ID → 内容）と、作った順
    private(set) var documents: [UUID: [String: Any]] = [:]
    private(set) var order: [UUID] = []
    /// わが家の設定でオンの種類
    var enabledKinds: Set<String> = ["todo", "shopping"]
    /// 権限が無い（退出したあとなど）
    var deniesEverything = false
    /// わが家のメンバー（nil なら確かめない）。Security Rules と同じく、作成者・更新者がメンバーでなければ断る（2026-10-28 Build 9）
    var memberUIDs: Set<String>?
    fileprivate var clients: [WeakClient] = []

    fileprivate struct WeakClient {
        weak var backend: FakeSharedItemsBackend?
    }

    var count: Int { documents.count }

    func title(of id: UUID) -> String? { documents[id]?["title"] as? String }
    func createdBy(of id: UUID) -> String? { documents[id]?["createdBy"] as? String }
    func updatedBy(of id: UUID) -> String? { documents[id]?["updatedBy"] as? String }

    fileprivate func create(id: UUID, data: [String: Any]) -> SharedItemsFailure? {
        if deniesEverything { return .permissionDenied }
        if let memberUIDs, !memberUIDs.contains((data["createdBy"] as? String) ?? "") { return .permissionDenied }
        // 同じ ID がすでにある（作成日時を変える上書きは Rules が断る）・オフの種類・ToDo と買い物以外は断る
        guard documents[id] == nil,
              let kind = data["kind"] as? String, ["todo", "shopping"].contains(kind), enabledKinds.contains(kind),
              data["schemaVersion"] as? Int == 1 else {
            return .permissionDenied
        }
        documents[id] = data
        order.append(id)
        broadcast()
        return nil
    }

    fileprivate func update(id: UUID, data: [String: Any]) -> SharedItemsFailure? {
        if deniesEverything { return .permissionDenied }
        if let memberUIDs, !memberUIDs.contains((data["updatedBy"] as? String) ?? "") { return .permissionDenied }
        guard var current = documents[id] else { return .other }
        for (key, value) in data { current[key] = value }
        documents[id] = current
        broadcast()
        return nil
    }

    fileprivate func delete(id: UUID) -> SharedItemsFailure? {
        if deniesEverything { return .permissionDenied }
        documents[id] = nil
        order.removeAll { $0 == id }
        broadcast()
        return nil
    }

    fileprivate func broadcast() {
        clients.compactMap(\.backend).forEach { $0.emit() }
    }

    fileprivate func confirmedSnapshots() -> [SharedItemSnapshot] {
        order.compactMap { id in
            documents[id].flatMap { SharedItemPayload.item(documentID: id.uuidString, data: $0) }
                .map { SharedItemSnapshot(item: $0, isConfirmed: true) }
        }
    }
}

/// 偽物の Firestore の窓口（1台の端末ぶん）。オフラインのあいだは端末にためて、つながったら送る
final class FakeSharedItemsBackend: SharedItemsBackend {
    let server: FakeSharedServer
    let uid: String
    var isOnline = true
    /// 送った内容（作成・変更）
    private(set) var sentCreates: [(id: UUID, fields: [String: SharedItemValue])] = []
    private(set) var sentUpdates: [(id: UUID, fields: [String: SharedItemValue])] = []
    private(set) var sentDeletes: [UUID] = []
    private var pending: [(id: UUID, apply: () -> SharedItemsFailure?, completion: (SharedItemsFailure?) -> Void, local: [String: Any]?)] = []
    private var onChange: (([SharedItemSnapshot]) -> Void)?
    private var onError: ((SharedItemsFailure) -> Void)?

    init(server: FakeSharedServer, uid: String) {
        self.server = server
        self.uid = uid
    }

    var totalCalls: Int { sentCreates.count + sentUpdates.count + sentDeletes.count }

    func listen(groupID: String, onChange: @escaping ([SharedItemSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        self.onChange = onChange
        self.onError = onError
        server.clients.append(.init(backend: self))
        if server.deniesEverything {
            onError(.permissionDenied)
        } else {
            emit()
        }
        return RepositoryObservation { [weak self] in
            self?.onChange = nil
            self?.onError = nil
        }
    }

    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentCreates.append((id, fields))
        let data = resolve(fields)
        enqueue(id: id, local: data, apply: { [server] in server.create(id: id, data: data) }, completion: completion)
    }

    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentUpdates.append((id, fields))
        let data = resolve(fields)
        enqueue(id: id, local: nil, apply: { [server] in server.update(id: id, data: data) }, completion: completion)
    }

    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        sentDeletes.append(id)
        enqueue(id: id, local: nil, apply: { [server] in server.delete(id: id) }, completion: completion)
    }

    /// 通信が戻った：ためていた変更を順に送る
    func goOnline() {
        isOnline = true
        let queued = pending
        pending = []
        for operation in queued {
            let failure = operation.apply()
            operation.completion(failure)
        }
        emit()
    }

    private func enqueue(id: UUID, local: [String: Any]?, apply: @escaping () -> SharedItemsFailure?, completion: @escaping (SharedItemsFailure?) -> Void) {
        if isOnline {
            let failure = apply()
            completion(failure)
            if failure != nil { emit() }
        } else {
            pending.append((id, apply, completion, local))
            emit()
        }
    }

    /// 端末から見える一覧（サーバーの内容＋まだ送っていない自分の作成）
    fileprivate func emit() {
        var snapshots = server.confirmedSnapshots()
        for operation in pending {
            guard let local = operation.local, !snapshots.contains(where: { $0.item.id == operation.id }),
                  let item = SharedItemPayload.item(documentID: operation.id.uuidString, data: local) else { continue }
            snapshots.append(SharedItemSnapshot(item: item, isConfirmed: false))
        }
        onChange?(snapshots)
    }

    func failListening(_ failure: SharedItemsFailure) {
        onError?(failure)
    }

    /// サーバーから空の一覧が届いた（最初の一覧・一時的な空の一覧の代わり。2026-10-28 Build 9）
    func emitEmptySnapshot() {
        onChange?([])
    }

    /// サーバーの文書の作成者（テストで、操作した本人の UID が入るかを確かめる）
    func createdBy(_ id: UUID) -> String? {
        server.createdBy(of: id)
    }

    private func resolve(_ fields: [String: SharedItemValue]) -> [String: Any] {
        var data: [String: Any] = [:]
        for (key, value) in fields {
            switch value {
            case .string(let text): data[key] = text
            case .bool(let flag): data[key] = flag
            case .int(let number): data[key] = number
            case .date(let date): data[key] = date
            case .null: data[key] = NSNull()
            case .serverTimestamp: data[key] = TestDates.friday
            case .currentUser: data[key] = uid
            }
        }
        return data
    }
}

/// テストの準備：端末1台（置き場・共有の窓口・わが家）
private struct Device {
    let store: LifeStore
    let backend: FakeSharedItemsBackend
    let service: SharedItemsService

    init(server: FakeSharedServer, uid: String, items: [LifeItem] = [], joined: Bool = true, kinds: [SharedSpaceKind] = [.todo, .shopping]) {
        store = LifeStore(items: items, expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
        backend = FakeSharedItemsBackend(server: server, uid: uid)
        service = SharedItemsService(backend: backend)
        service.attach(store)
        if joined {
            service.apply(household: Self.household(kinds: kinds))
        }
    }

    static func household(kinds: [SharedSpaceKind] = [.todo, .shopping], groupID: String = "group-a") -> HouseholdSummary {
        HouseholdSummary(name: "わが家", sharedKinds: kinds, isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)], groupID: groupID)
    }
}

private func todo(_ title: String, ownership: Ownership = .personal) -> LifeItem {
    LifeItem(title: title, kind: .todo, ownership: ownership, date: LifeCalendar.startOfDay(TestDates.friday), assignee: .me)
}

private func shopping(_ title: String) -> LifeItem {
    LifeItem(title: title, kind: .shopping, ownership: .personal, date: LifeCalendar.startOfDay(TestDates.friday), assignee: .me, softTime: .onTheWayHome)
}

final class SharedItemPayloadTests: XCTestCase {
    /// テスト3：送る項目は決まったものだけ（柔らかい時間・暮らしメモリー・担当・端末の持ち主の区別は送らない）
    func testCreateFieldsAreMinimal() throws {
        var item = shopping("牛乳を買う")
        item.memoryID = UUID()
        item.assignee = .partner
        let fields = try XCTUnwrap(SharedItemPayload.createFields(for: item))
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "kind", "title", "date", "hasTime", "isCompleted", "assigneeUID", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertEqual(fields["schemaVersion"], .int(1))
        XCTAssertEqual(fields["kind"], .string("shopping"))
        XCTAssertEqual(fields["assigneeUID"], .null, "担当はいまは送らない（null）")
        XCTAssertEqual(fields["createdBy"], .currentUser)
        XCTAssertEqual(fields["createdAt"], .serverTimestamp, "作成日時はサーバーの時刻")
        XCTAssertEqual(fields["updatedAt"], .serverTimestamp)

        item.deferredTo = TestDates.saturday
        XCTAssertEqual(SharedItemPayload.createFields(for: item)?["deferredTo"], .date(TestDates.saturday))
    }

    /// 変えるときは、種類・作成者・作成日時・担当・schemaVersion を送らない（変えない）
    func testUpdateFieldsKeepImmutableFields() throws {
        let fields = try XCTUnwrap(SharedItemPayload.updateFields(for: todo("書類を出す")))
        XCTAssertEqual(Set(fields.keys), ["title", "date", "hasTime", "isCompleted", "deferredTo", "droppedAt", "updatedBy", "updatedAt"])
        XCTAssertEqual(fields["updatedBy"], .currentUser)
        XCTAssertEqual(fields["deferredTo"], .null)
    }

    /// ToDo・買い物以外（予定・家事・支払・習慣）や、名前が空の項目は送らない
    func testOnlyTodoAndShopping() {
        for kind in [LifeItemKind.event, .chore, .payment, .habit] {
            let item = LifeItem(title: "a", kind: kind, ownership: .shared, date: TestDates.friday)
            XCTAssertNil(SharedItemPayload.createFields(for: item), kind.rawValue)
            XCTAssertNil(SharedItemPayload.updateFields(for: item), kind.rawValue)
        }
        XCTAssertNil(SharedItemPayload.createFields(for: todo("   ")))
        XCTAssertEqual(HouseholdItemPolicy.kinds, [.todo, .shopping])
    }

    /// 名前は上限（200）まで
    func testTitleIsTrimmedAndLimited() {
        XCTAssertEqual(SharedItemPayload.title("  牛乳  "), "牛乳")
        XCTAssertEqual(SharedItemPayload.title(String(repeating: "あ", count: 250)).unicodeScalars.count, 200)
    }

    /// 受け取った文書を読む（知らない種類・形の違うもの・UUID でない ID は出さない。持ち主は共有・担当なし）
    func testParseDocument() throws {
        let id = UUID()
        let data: [String: Any] = ["kind": "todo", "title": "書類", "date": TestDates.friday, "hasTime": false, "isCompleted": true, "assigneeUID": NSNull(), "createdBy": "someone"]
        let item = try XCTUnwrap(SharedItemPayload.item(documentID: id.uuidString, data: data))
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.ownership, .shared)
        XCTAssertNil(item.assignee)
        XCTAssertTrue(item.isCompleted)
        XCTAssertNil(SharedItemPayload.item(documentID: "not-a-uuid", data: data))
        var event = data
        event["kind"] = "event"
        XCTAssertNil(SharedItemPayload.item(documentID: id.uuidString, data: event))
        var noDate = data
        noDate["date"] = nil
        XCTAssertNil(SharedItemPayload.item(documentID: id.uuidString, data: noDate))
    }
}

final class SharedTodoShoppingSyncTests: XCTestCase {
    /// テスト1：既存の個人データ（以前の端末の中の「共有」の項目も）は、自動でアップロードしない
    func testExistingDataIsNotUploaded() {
        let server = FakeSharedServer()
        let items = [todo("個人のToDo"), todo("以前の共有", ownership: .shared), shopping("牛乳を買う")]
        let device = Device(server: server, uid: "alice", items: items)
        XCTAssertEqual(device.backend.totalCalls, 0, "わが家に参加しても何も送らない")
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(device.store.items.map(\.id), items.map(\.id), "端末の項目はそのまま")
        XCTAssertTrue(device.store.householdItems.isEmpty)
    }

    /// テスト2：新しい項目の保存先の初期値は「自分だけ」（なんでも追加・買い物・保存先の選択）
    @MainActor
    func testNewItemsDefaultToPersonal() {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice")
        XCTAssertEqual(SaveDestination.initial, .personal)

        let quickAdd = QuickAddViewModel(store: device.store, now: TestDates.friday)
        XCTAssertEqual(quickAdd.destination, .personal)
        XCTAssertTrue(quickAdd.canChooseDestination, "わが家に参加していれば選べる")
        quickAdd.inputText = "書類を出す"
        XCTAssertTrue(quickAdd.quickAdd(.todo))
        quickAdd.inputText = "牛乳とティッシュ"
        XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared))

        let shoppingModel = ShoppingViewModel(store: device.store, appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(shoppingModel.destination, .personal)
        shoppingModel.add(FrequentPurchase(title: "卵", categories: [.food]))

        XCTAssertEqual(device.backend.totalCalls, 0, "選ばなければ送らない")
        XCTAssertTrue(device.store.items.allSatisfy { $0.ownership == .personal })
        XCTAssertEqual(device.store.items.count, 4)
    }

    /// AI・自動の分類は「共有」を選ばない（「妻と」があっても自分だけ）
    @MainActor
    func testAutomaticClassificationNeverShares() {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice")
        let quickAdd = QuickAddViewModel(store: device.store, now: TestDates.friday)
        quickAdd.inputText = "妻と旅行相談"
        quickAdd.addAsSuggested(usageStyle: .shared)
        quickAdd.inputText = "夫と牛乳買う"
        quickAdd.refine(usageStyle: .shared)
        XCTAssertEqual(quickAdd.destination, .personal, "詳しく整えるの保存先も自分だけのまま")
        quickAdd.addSelected()
        XCTAssertEqual(device.backend.totalCalls, 0)
        XCTAssertTrue(device.store.items.allSatisfy { $0.ownership == .personal })

        // 以前に「共有」で修正したメモでも、項目は自分の項目になる
        var edited = InboxClassifier.suggest(for: "旅行の相談")
        edited.ownership = .shared
        XCTAssertEqual(edited.makeItem(today: TestDates.friday).ownership, .personal)
    }

    /// テスト3：「わが家で共有」を選んだ ToDo・買い物だけを送る（予定などは自分だけに保存）
    @MainActor
    func testOnlyExplicitTodoAndShoppingAreSent() throws {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice")
        let event = LifeItem(title: "歯医者", kind: .event, ownership: .personal, date: TestDates.friday)
        let shared = device.store.add([todo("書類を出す"), shopping("牛乳を買う"), event], destination: .household)
        XCTAssertEqual(shared, 2)
        XCTAssertEqual(device.backend.sentCreates.count, 2)
        XCTAssertEqual(server.count, 2)
        XCTAssertEqual(device.store.items.map(\.title), ["歯医者"], "予定は自分だけ")
        XCTAssertEqual(device.store.items.first?.ownership, .personal)
        let created = try XCTUnwrap(device.backend.sentCreates.first)
        XCTAssertEqual(created.fields["kind"], .string("todo"))

        // なんでも追加で「わが家で共有」を選んだとき
        let quickAdd = QuickAddViewModel(store: device.store, now: TestDates.friday)
        quickAdd.destination = .household
        quickAdd.inputText = "電池"
        XCTAssertTrue(quickAdd.quickAdd(.shopping))
        quickAdd.inputText = "19時 美容院"
        XCTAssertTrue(quickAdd.quickAdd(.event))
        XCTAssertEqual(device.backend.sentCreates.count, 3, "予定は送らない")
        XCTAssertTrue(device.store.items.contains { $0.title == "美容院" && $0.ownership == .personal })
    }

    /// テスト4：2台で追加・編集・完了・未完了・削除が反映される（自分の変更も二重に出ない）
    func testTwoDevicesStayInSync() throws {
        let server = FakeSharedServer()
        let alice = Device(server: server, uid: "alice")
        let bob = Device(server: server, uid: "bob")

        alice.store.add([todo("書類を出す")], destination: .household)
        let id = try XCTUnwrap(alice.store.householdItems.first?.id)
        XCTAssertEqual(alice.store.householdItems.count, 1, "自分の追加を二重に出さない")
        XCTAssertEqual(alice.store.visibleItems.filter { $0.id == id }.count, 1)
        XCTAssertEqual(bob.store.householdItems.map(\.title), ["書類を出す"])
        XCTAssertTrue(bob.store.isHouseholdItem(id))
        XCTAssertTrue(bob.store.items.isEmpty, "相手の端末の個人データには入らない")

        bob.store.rename(id, to: "書類を出す（市役所）")
        XCTAssertEqual(alice.store.householdItems.first?.title, "書類を出す（市役所）")

        alice.store.toggleCompletion(of: id, at: TestDates.friday)
        XCTAssertEqual(bob.store.householdItems.first?.isCompleted, true)
        bob.store.toggleCompletion(of: id, at: TestDates.friday)
        XCTAssertEqual(alice.store.householdItems.first?.isCompleted, false, "未完了に戻すのも反映")

        alice.store.deleteItem(id)
        XCTAssertTrue(bob.store.householdItems.isEmpty)
        XCTAssertTrue(alice.store.householdItems.isEmpty)
        XCTAssertEqual(server.count, 0)
    }

    /// 今日画面：個人と共有を一緒に出し、「自分」「共有」で絞り込める。共有マークを付ける
    func testTodayMixesAndFilters() throws {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice", items: [todo("個人のToDo")])
        device.store.add([todo("共有のToDo")], destination: .household)
        let day = TestDates.friday
        XCTAssertEqual(Set(device.store.items(on: day, scope: .all).map(\.title)), ["個人のToDo", "共有のToDo"])
        XCTAssertEqual(device.store.items(on: day, scope: .mine).map(\.title), ["個人のToDo"])
        XCTAssertEqual(device.store.items(on: day, scope: .shared).map(\.title), ["共有のToDo"])

        let state = AppState()
        let today = TodayViewModel(store: device.store, appState: state, now: day)
        let sharedItem = try XCTUnwrap(device.store.householdItems.first)
        XCTAssertTrue(today.isShared(sharedItem))
        XCTAssertFalse(today.isShared(try XCTUnwrap(device.store.items.first)))
    }

    /// テスト8：通信できないとき・断られたとき、個人データを消さない
    func testNetworkFailureKeepsPersonalData() throws {
        let server = FakeSharedServer()
        let personal = todo("ゴミの日を確認")
        let device = Device(server: server, uid: "alice", items: [personal])

        // オフライン：共有の追加は端末にたまって表示され、個人データはそのまま
        device.backend.isOnline = false
        device.store.add([shopping("牛乳を買う")], destination: .household)
        XCTAssertEqual(device.store.householdItems.map(\.title), ["牛乳を買う"])
        XCTAssertEqual(server.count, 0)
        XCTAssertEqual(device.store.items.map(\.id), [personal.id])
        // つながったら送られる（1件だけ）
        device.backend.goOnline()
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(device.store.householdItems.count, 1)

        // 断られた（種類がオフにされていた など）：新しく作った項目は「自分だけ」として端末に残す
        server.enabledKinds = ["shopping"]
        device.store.add([todo("書類を出す")], destination: .household)
        XCTAssertTrue(device.store.items.contains { $0.title == "書類を出す" && $0.ownership == .personal }, "消さずに自分だけに残す")
        XCTAssertNotNil(device.service.notice)
        XCTAssertEqual(device.store.items.filter { $0.title == "ゴミの日を確認" }.count, 1)

        // 読めなくなった（退出など）：共有の表示だけ消え、個人データは残る
        device.backend.failListening(.permissionDenied)
        XCTAssertTrue(device.store.householdItems.isEmpty)
        XCTAssertTrue(device.store.items.contains { $0.id == personal.id })
    }

    /// 共有への変換：サーバーに保存できてから、端末の個人項目を片付ける。断られたら端末の項目が残る
    func testConversionRemovesLocalOnlyAfterServerConfirms() throws {
        let server = FakeSharedServer()
        let local = shopping("牛乳を買う")
        let device = Device(server: server, uid: "alice", items: [local])

        device.backend.isOnline = false
        XCTAssertTrue(device.store.convertToHousehold(local.id))
        XCTAssertTrue(device.store.items.contains { $0.id == local.id }, "保存が確かめられるまで消さない")
        XCTAssertEqual(device.store.visibleItems.filter { $0.id == local.id }.count, 1, "二重に出さない")
        XCTAssertTrue(device.store.isHouseholdItem(local.id))

        device.backend.goOnline()
        XCTAssertFalse(device.store.items.contains { $0.id == local.id }, "サーバーに保存できたので片付けた")
        XCTAssertEqual(device.store.householdItems.map(\.id), [local.id], "同じ ID のまま共有になった")
        XCTAssertNil(device.store.householdItems.first?.softTime, "柔らかい時間は送らない")

        // 断られた変換：端末の項目がそのまま残る
        server.enabledKinds = []
        let other = todo("書類を出す")
        device.store.add([other])
        device.service.apply(household: Device.household(kinds: [.todo, .shopping]))
        XCTAssertTrue(device.store.convertToHousehold(other.id))
        XCTAssertTrue(device.store.items.contains { $0.id == other.id }, "断られても端末の項目は残る")
        XCTAssertFalse(device.store.isHouseholdItem(other.id))
    }

    /// テスト9：同じ操作をくり返しても重複しない
    func testRepeatedOperationsDoNotDuplicate() throws {
        let server = FakeSharedServer()
        let local = todo("書類を出す")
        let device = Device(server: server, uid: "alice", items: [local])
        device.backend.isOnline = false
        XCTAssertTrue(device.store.convertToHousehold(local.id))
        XCTAssertFalse(device.store.convertToHousehold(local.id), "変換中にもう一度押しても送らない")
        device.backend.goOnline()
        XCTAssertFalse(device.store.convertToHousehold(local.id), "もう共有になっている")
        XCTAssertEqual(device.backend.sentCreates.count, 1)
        XCTAssertEqual(server.count, 1)

        // 同じ一覧が何度届いても1件ずつ
        device.backend.goOnline()
        device.backend.goOnline()
        XCTAssertEqual(device.store.householdItems.count, 1)
        XCTAssertEqual(device.store.visibleItems.filter { $0.id == local.id }.count, 1)

        // 買い物の重複（共有の買い物に同じ品名があれば追加しない）
        XCTAssertEqual(device.store.addShopping(["牛乳"], destination: .household, now: TestDates.friday), 1)
        XCTAssertEqual(device.store.addShopping(["牛乳"], destination: .household, now: TestDates.friday), 0)
        XCTAssertEqual(device.store.addShopping(["牛乳"], destination: .personal, now: TestDates.friday), 0)
        XCTAssertEqual(device.store.addShopping(["卵", "卵"], destination: .personal, now: TestDates.friday), 1)
    }

    /// テスト10（アプリ側）：種類をオフにすると新しい共有は選べないが、すでにある共有項目は消えない
    func testTurningKindOffKeepsExistingItems() {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice")
        device.store.add([todo("書類を出す")], destination: .household)
        XCTAssertTrue(device.store.canShareInHousehold(.todo))

        server.enabledKinds = ["shopping"]
        device.service.apply(household: Device.household(kinds: [.shopping]))
        XCTAssertFalse(device.store.canShareInHousehold(.todo))
        XCTAssertTrue(device.store.canShareInHousehold(.shopping))
        XCTAssertEqual(device.store.householdItems.map(\.title), ["書類を出す"], "すでにある共有項目は残る")
        XCTAssertEqual(server.count, 1)
        // オフの種類で「わが家で共有」を選んでも、自分だけに保存する
        device.store.add([todo("別のToDo")], destination: .household)
        XCTAssertEqual(server.count, 1)
        XCTAssertTrue(device.store.items.contains { $0.title == "別のToDo" && $0.ownership == .personal })
    }

    /// わが家に参加していない・退出した・削除した：選べない。共有の表示を消す（個人データは残す）
    func testNotJoinedOrLeft() {
        let server = FakeSharedServer()
        let device = Device(server: server, uid: "alice", items: [todo("個人")], joined: false)
        XCTAssertFalse(device.store.canShareInHousehold(.todo))
        XCTAssertEqual(device.store.add([todo("共有にしたい")], destination: .household), 0)
        XCTAssertEqual(device.backend.totalCalls, 0)

        device.service.apply(household: Device.household())
        device.store.add([todo("共有")], destination: .household)
        XCTAssertEqual(device.store.householdItems.count, 1)
        device.service.apply(household: nil)
        XCTAssertTrue(device.store.householdItems.isEmpty)
        XCTAssertEqual(Set(device.store.items.map(\.title)), ["個人", "共有にしたい"])
        XCTAssertFalse(device.store.canShareInHousehold(.todo))

        // Firebase に接続していないとき
        let offline = SharedItemsService(backend: nil)
        let store = LifeStore.empty()
        offline.attach(store)
        offline.apply(household: Device.household())
        XCTAssertFalse(store.canShareInHousehold(.todo))
    }

    /// 「あとで」「もうやらない」「元に戻す」も共有項目に反映し、端末の個人データにはしない
    func testPostponeDropAndUndoOnSharedItem() throws {
        let server = FakeSharedServer()
        let alice = Device(server: server, uid: "alice")
        let bob = Device(server: server, uid: "bob")
        alice.store.add([todo("書類を出す")], destination: .household)
        let item = try XCTUnwrap(alice.store.householdItems.first)

        alice.store.reschedule(item.id, to: TestDates.saturday)
        XCTAssertEqual(bob.store.householdItems.first?.deferredTo, TestDates.saturday)
        alice.store.restore(item)
        XCTAssertNil(bob.store.householdItems.first?.deferredTo)
        alice.store.drop(item.id, at: TestDates.friday)
        XCTAssertNotNil(bob.store.householdItems.first?.droppedAt)
        XCTAssertTrue(alice.store.items.isEmpty)

        // 追加の「元に戻す」：共有の保存先から消す
        alice.store.add([shopping("電池を買う")], destination: .household)
        let battery = try XCTUnwrap(alice.store.householdItems.first { $0.title == "電池を買う" })
        alice.store.removeItems(withIDs: [battery.id])
        XCTAssertFalse(bob.store.householdItems.contains { $0.id == battery.id })
    }

    /// テスト7（アプリ側）：個人項目の操作では、共有の保存先へ何も送らない（通知の処理は Firestore の書き込みでしか動かない）
    func testPersonalOperationsSendNothing() {
        let server = FakeSharedServer()
        let item = todo("個人のToDo")
        let device = Device(server: server, uid: "alice", items: [item])
        device.store.toggleCompletion(of: item.id, at: TestDates.friday)
        device.store.reschedule(item.id, to: TestDates.saturday)
        device.store.rename(item.id, to: "個人のToDo（変更）")
        device.store.drop(item.id, at: TestDates.friday)
        device.store.deleteItem(item.id)
        device.store.add([todo("もう1件")], destination: .personal)
        XCTAssertEqual(device.backend.totalCalls, 0)
        XCTAssertEqual(server.count, 0)
    }
}

/// ソースの確認：既存データの一括アップロードの仕組みを、アプリから使っていない
final class SharedTodoShoppingSourceTests: XCTestCase {
    func testNoBulkMigrationInApp() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("LifeOS"), includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        var checked = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            checked += 1
            if url.lastPathComponent != "SharedMigrationPlan.swift" {
                XCTAssertFalse(text.contains("SharedMigrationPlan"), "\(url.lastPathComponent)：一括の移行を使わない")
            }
            if url.lastPathComponent != "SharedSyncPolicy.swift" {
                XCTAssertFalse(text.contains("syncableItems("), "\(url.lastPathComponent)：まとめて送る項目を選ばない")
            }
        }
        try XCTSkipIf(checked == 0, "アプリのソースを読めない環境のため、確認を省きます")
    }
}


// MARK: - Build 9（2026-10-28）：パートナーの共有項目が消える・届かない不具合の修正。docs/PARTNER_SHARED_ITEM_SYNC_FIX.md

final class PartnerSharedItemSyncTests: XCTestCase {
    /// オーナーとパートナーは同じ処理で保存する。両方向で ToDo・買い物の追加・名前の変更が届き、作成者・更新者は操作した本人
    func testOwnerAndMemberSyncBothDirections() throws {
        let server = FakeSharedServer()
        server.memberUIDs = ["owner-uid", "member-uid"]
        let owner = Device(server: server, uid: "owner-uid")
        let member = Device(server: server, uid: "member-uid")

        // パートナー → オーナー（ToDo と買い物）
        member.store.add([todo("書類を出す"), shopping("洗剤を買う")], destination: .household)
        XCTAssertEqual(Set(owner.store.householdItems.map(\.title)), ["書類を出す", "洗剤を買う"])
        XCTAssertEqual(Set(member.store.householdItems.map(\.title)), ["書類を出す", "洗剤を買う"], "保存できたので、パートナーの画面にも残る")
        XCTAssertTrue(member.store.items.isEmpty, "自分だけには移らない")
        XCTAssertNil(member.service.notice)
        let memberItem = try XCTUnwrap(member.store.householdItems.first { $0.title == "書類を出す" })
        XCTAssertEqual(member.backend.createdBy(memberItem.id), "member-uid", "作成者はパートナー本人（オーナーの UID を使わない）")

        // オーナー → パートナー
        owner.store.add([shopping("牛乳を買う")], destination: .household)
        XCTAssertTrue(member.store.householdItems.contains { $0.title == "牛乳を買う" })
        let ownerItem = try XCTUnwrap(owner.store.householdItems.first { $0.title == "牛乳を買う" })
        XCTAssertEqual(owner.backend.createdBy(ownerItem.id), "owner-uid")

        // 名前の変更も両方向。更新者は操作した本人
        member.store.rename(ownerItem.id, to: "低脂肪牛乳を買う")
        XCTAssertTrue(owner.store.householdItems.contains { $0.title == "低脂肪牛乳を買う" })
        XCTAssertEqual(server.updatedBy(of: ownerItem.id), "member-uid")
        owner.store.rename(memberItem.id, to: "書類を出す（市役所）")
        XCTAssertTrue(member.store.householdItems.contains { $0.title == "書類を出す（市役所）" })
        XCTAssertEqual(server.updatedBy(of: memberItem.id), "owner-uid")
        XCTAssertEqual(server.createdBy(of: memberItem.id), "member-uid", "作成者は変わらない")
    }

    /// 共有の保存が断られた：項目を消さず「自分だけ」に残し、「共有できなかったため、自分だけに保存しました」を出す。相手には届かない
    func testRejectedCreateKeepsItemAsPersonalWithNotice() throws {
        let server = FakeSharedServer()
        server.memberUIDs = ["owner-uid"]   // パートナーがメンバーとして認められない状態（実機の再現）
        let owner = Device(server: server, uid: "owner-uid")
        let member = Device(server: server, uid: "member-uid")

        member.store.add([todo("書類を出す")], destination: .household)
        let kept = try XCTUnwrap(member.store.items.first { $0.title == "書類を出す" }, "消さない")
        XCTAssertEqual(kept.ownership, .personal, "自分だけの項目として残す")
        XCTAssertFalse(member.store.isHouseholdItem(kept.id))
        XCTAssertEqual(member.service.notice, "共有できなかったため、自分だけに保存しました（権限がありません）。")
        XCTAssertEqual(member.service.lastFailure, .permissionDenied)
        XCTAssertEqual(server.count, 0, "保存されていないので、通知の処理も動かない")
        XCTAssertTrue(owner.store.householdItems.isEmpty)
        XCTAssertEqual(member.store.items.filter { $0.title == "書類を出す" }.count, 1, "重複しない")

        // 買い物も同じ
        member.store.add([shopping("洗剤を買う")], destination: .household)
        XCTAssertTrue(member.store.items.contains { $0.title == "洗剤を買う" && $0.ownership == .personal })

        // あとから空の一覧が届いても、退避した項目は消えない
        member.backend.emitEmptySnapshot()
        XCTAssertEqual(member.store.items.count, 2)
    }

    /// 結果が届く前に空の一覧（最初の一覧・一時的な空）が届いても、送信待ちの共有項目を画面から消さない
    func testEmptySnapshotDoesNotDropPendingCreate() throws {
        let server = FakeSharedServer()
        let member = Device(server: server, uid: "member-uid")
        member.backend.isOnline = false
        member.store.add([todo("書類を出す")], destination: .household)
        let pending = try XCTUnwrap(member.store.householdItems.first)

        member.backend.emitEmptySnapshot()
        XCTAssertTrue(member.store.isHouseholdItem(pending.id), "空の一覧でも消さない")
        XCTAssertEqual(member.store.visibleItems.filter { $0.id == pending.id }.count, 1)

        member.backend.goOnline()
        XCTAssertEqual(server.count, 1)
        member.backend.emitEmptySnapshot()
        // 保存が確かめられたあとは、サーバーの一覧に従う（ここでは空の一覧の直後でも、次の一覧で戻る）
        member.backend.goOnline()
        XCTAssertEqual(member.store.householdItems.map(\.id), [pending.id])
    }

    /// 断られて「自分だけ」に退避した項目を、あとで共有し直しても重複しない
    func testRetryAfterFailureDoesNotDuplicate() throws {
        let server = FakeSharedServer()
        server.memberUIDs = ["owner-uid"]
        let owner = Device(server: server, uid: "owner-uid")
        let member = Device(server: server, uid: "member-uid")
        member.store.add([todo("書類を出す")], destination: .household)
        let kept = try XCTUnwrap(member.store.items.first)

        // 原因が直った（パートナーがメンバーとして認められた）あと、編集で「わが家で共有」に戻す
        server.memberUIDs = ["owner-uid", "member-uid"]
        member.service.dismissNotice()
        XCTAssertTrue(member.store.convertToHousehold(kept.id))
        XCTAssertFalse(member.store.items.contains { $0.id == kept.id }, "保存できたので端末の項目を片付けた")
        XCTAssertEqual(member.store.visibleItems.filter { $0.title == "書類を出す" }.count, 1)
        XCTAssertEqual(owner.store.householdItems.filter { $0.title == "書類を出す" }.count, 1)
        XCTAssertEqual(server.count, 1)
        XCTAssertFalse(member.store.convertToHousehold(kept.id), "2回目は送らない")
        XCTAssertNil(member.service.notice)
    }

    /// 理由ごとのお知らせ（UID・エラーの文を出さない）
    func testFailureNotices() {
        XCTAssertEqual(SharedItemsFailure.permissionDenied.fallbackNotice, "共有できなかったため、自分だけに保存しました（権限がありません）。")
        XCTAssertEqual(SharedItemsFailure.notSignedIn.fallbackNotice, "共有できなかったため、自分だけに保存しました（サインインの確認ができません）。")
        XCTAssertEqual(SharedItemsFailure.unavailable.fallbackNotice, "共有できなかったため、自分だけに保存しました（通信できません）。")
        for failure in [SharedItemsFailure.permissionDenied, .notSignedIn, .unavailable, .other] {
            for word in ["uid", "UID", "token", "Firebase", "Error"] {
                XCTAssertFalse(failure.fallbackNotice.contains(word), "\(failure)：\(word)")
            }
        }
    }

    /// 共有の状態の確認：結果を日本語の行で出す（番号だけ。UID は出さない）。接続していなければ「未確認」
    @MainActor
    func testDiagnosisLines() async {
        let check = SharedSyncCheck(isSignedIn: true, tokenRefresh: .ok, groupRead: .ok, memberDocument: .missing, itemsRead: .failed(code: 7), serverKinds: ["todo", "shopping"])
        XCTAssertEqual(check.lines, [
            "サインイン：OK",
            "サインインの更新：OK",
            "わが家の読み取り：OK",
            "メンバーの登録：見つかりません",
            "共有項目の読み取り：失敗（コード 7）",
            "サーバーの共有する種類：ToDo・買い物",
        ])
        let service = SharedItemsService(backend: nil)
        await service.runDiagnosis()
        XCTAssertEqual(service.diagnosis, .notAvailable)
    }

    /// 画面にお知らせを出す場所がある（以前は、お知らせを作っても出していなかった）
    func testNoticeIsShownOnScreen() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let tab = try? String(contentsOf: root.appendingPathComponent("LifeOS/App/MainTabView.swift"), encoding: .utf8) else {
            throw XCTSkip("ソースを読めない環境のため、確認を省きます")
        }
        XCTAssertTrue(tab.contains("if let notice = sharedItems.notice"))
        XCTAssertTrue(tab.contains("SharedSyncNoticeBanner(message: notice)"))
    }
}

/// 通知の端末の登録は、それぞれの人の UID の下だけ（Firestore の窓口がサインインの情報から場所を決める。偽物で同じ動きを確かめる）
final class PushDeviceOwnershipTests: XCTestCase {
    /// サインインしている人の UID の下に書く偽物（Firestore の窓口と同じ決まり）
    final class UIDScopedRegistry: PushDeviceRegistry {
        let currentUID: () -> String?
        private(set) var documents: [String: [String: PushDeviceRecord]] = [:]

        init(currentUID: @escaping () -> String?) { self.currentUID = currentUID }

        func save(deviceID: String, record: PushDeviceRecord) async throws {
            guard let uid = currentUID() else { throw SharedItemsFailure.notSignedIn }
            documents[uid, default: [:]][deviceID] = record
        }

        func remove(deviceID: String) async throws {
            guard let uid = currentUID() else { throw SharedItemsFailure.notSignedIn }
            documents[uid]?[deviceID] = nil
        }
    }

    @MainActor
    func testEachUserRegistersUnderOwnUID() async {
        let ownerRegistry = UIDScopedRegistry { "owner-uid" }
        let memberRegistry = UIDScopedRegistry { "member-uid" }
        for (registry, token) in [(ownerRegistry, "tokenowner"), (memberRegistry, "tokenmember")] {
            let permission = FakePushPermission()
            permission.current = .authorized
            let tokens = FakePushTokens()
            tokens.token = token
            let service = SharedPushService(preferenceStore: FakePushPreferenceStore(), permission: permission, tokens: tokens, registry: registry)
            await service.updateContext(isSignedIn: true, isJoined: true)
            await service.setReceives(true)
            XCTAssertEqual(service.status, .registered)
        }
        XCTAssertEqual(Array(ownerRegistry.documents.keys), ["owner-uid"])
        XCTAssertEqual(Array(memberRegistry.documents.keys), ["member-uid"])
        XCTAssertEqual(ownerRegistry.documents["owner-uid"]?.values.first?.token, "tokenowner")
        XCTAssertEqual(memberRegistry.documents["member-uid"]?.values.first?.token, "tokenmember")
    }
}
