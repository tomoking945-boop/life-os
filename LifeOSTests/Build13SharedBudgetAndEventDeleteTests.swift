import XCTest
@testable import LifeOS

// Build 13（2026-11-01）：家計簿の支出を「自分だけ／わが家で共有」から選ぶ・カレンダーの予定を確認して削除する。
// docs/BUILD_13_SHARED_HOUSEHOLD_BUDGET_AND_EVENT_DELETE.md
// 本物の Firestore・ネットワークは使わない（共有の支出の窓口は偽物）。

/// 偽物の共有の支出の窓口（Firestore の代わり。呼ばれた回数と送った項目を記録する）
final class FakeSharedExpensesBackend: SharedExpensesBackend {
    private(set) var creates: [(id: UUID, fields: [String: SharedItemValue])] = []
    private(set) var updates: [(id: UUID, fields: [String: SharedItemValue])] = []
    private(set) var deletes: [UUID] = []
    private(set) var listenCount = 0
    private(set) var removedListenerCount = 0
    private(set) var listenedGroupIDs: [String] = []
    /// 書き込みの結果（nil なら成功）
    var failure: SharedItemsFailure?
    /// true なら結果を返さない（オフラインのあいだと同じ）
    var holdsCompletion = false
    private(set) var heldCompletions: [(SharedItemsFailure?) -> Void] = []
    private var onChange: (([SharedExpenseSnapshot]) -> Void)?

    var writeCount: Int { creates.count + updates.count + deletes.count }
    var activeListenerCount: Int { listenCount - removedListenerCount }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        listenedGroupIDs.append(groupID)
        self.onChange = onChange
        return RepositoryObservation { [weak self] in
            self?.removedListenerCount += 1
            self?.onChange = nil
        }
    }

    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        creates.append((id, fields))
        finish(completion)
    }

    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        updates.append((id, fields))
        finish(completion)
    }

    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        deletes.append(id)
        finish(completion)
    }

    private func finish(_ completion: @escaping (SharedItemsFailure?) -> Void) {
        if holdsCompletion {
            heldCompletions.append(completion)
        } else {
            completion(failure)
        }
    }

    /// 見張りに一覧を届ける（Firestore からの受信と同じ）
    func emit(_ expenses: [Expense], confirmed: Bool = true) {
        onChange?(expenses.map { SharedExpenseSnapshot(expense: $0, isConfirmed: confirmed) })
    }
}

private func emptyStore() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

/// 2026年11月10日（火）9:00
private let november10 = TestDates.make(2026, 11, 10, 9, 0)

private func household(money: Bool = true, groupID: String? = "group-a") -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家",
        sharedKinds: money ? [.todo, .shopping, .money] : [.todo, .shopping],
        isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: groupID
    )
}

private struct SharedSetup {
    let store: LifeStore
    let service: SharedExpensesService
    let backend: FakeSharedExpensesBackend
}

private func makeShared(money: Bool = true) -> SharedSetup {
    let store = emptyStore()
    let backend = FakeSharedExpensesBackend()
    let service = SharedExpensesService(backend: backend)
    service.attach(store)
    service.apply(household: household(money: money), isSignedIn: true)
    return SharedSetup(store: store, service: service, backend: backend)
}

private func expense(_ title: String, _ amount: Int, _ category: ExpenseCategory = .food, on date: Date = november10, ownership: Ownership = .personal) -> Expense {
    Expense(title: title, amount: amount, category: category, date: date, ownership: ownership)
}

// MARK: - 保存の形・個人データ

final class SharedExpenseStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build13-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 以前の支出（保存先の項目が無い）は、すべて「自分だけ」として読める
    func testOldExpensesDecodeAsPersonal() throws {
        let old = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","title":"スーパー","amount":3520,"category":"food","date":815000000}]"#
        let decoded = try JSONDecoder().decode([Expense].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].ownership, .personal)
        XCTAssertEqual(decoded[0].amount, 3520)
        // 新しい形も読み書きできる
        let roundTrip = try JSONDecoder().decode(Expense.self, from: JSONEncoder().encode(expense("ランチ", 1200, .diningOut)))
        XCTAssertEqual(roundTrip.ownership, .personal)
        XCTAssertEqual(roundTrip.title, "ランチ")
    }

    /// 端末の保存ファイルは壊れない。保存されている支出は、すべて「自分だけ」として読む
    func testPersistedExpensesStayPersonalAfterRelaunch() {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        store.add(expense("スーパー", 3520))
        store.add(expense("念のため共有の印つき", 100, ownership: .shared))
        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(relaunched.expenses.map(\.title), ["スーパー", "念のため共有の印つき"])
        XCTAssertTrue(relaunched.expenses.allSatisfy { $0.ownership == .personal }, "端末にあるのは自分だけの支出")
    }

    /// 共有の支出は life-store.json に保存しない（起動中だけ。Firestore から読み直す）
    func testSharedExpensesAreNotWrittenToLifeStoreFile() throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let backend = FakeSharedExpensesBackend()
        let service = SharedExpensesService(backend: backend)
        service.attach(store)
        service.apply(household: household(), isSignedIn: true)

        XCTAssertTrue(store.addExpense(expense("共有の夕食の材料", 4321), destination: .household))
        backend.emit(store.householdExpenses)
        store.add(expense("自分のランチ", 980))
        XCTAssertEqual(store.visibleExpenses(scope: .all).count, 2)

        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertFalse(file.contains("共有の夕食の材料"), "共有の支出を端末のファイルに書かない")
        XCTAssertTrue(file.contains("自分のランチ"))

        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(relaunched.expenses.map(\.title), ["自分のランチ"], "共有の支出は個人として二重に残らない")
        XCTAssertTrue(relaunched.householdExpenses.isEmpty)
    }
}

// MARK: - 共有の支出：送る・送らない

final class SharedExpenseSyncTests: XCTestCase {
    /// 新しい支出の保存先の初期値は、必ず「自分だけ」
    func testNewExpenseDefaultsToPersonal() {
        let draft = ExpenseDraft(newOn: november10)
        XCTAssertEqual(draft.destination, .personal)
        let setup = makeShared()
        let money = MoneyViewModel(store: setup.store, appState: AppState(), now: november10)
        money.startAdding()
        XCTAssertEqual(money.draft?.destination, .personal)
        XCTAssertEqual(SaveDestination.initial, .personal)
    }

    /// 自分だけの支出の追加・変更・削除では、Firestore を呼ばない
    func testPersonalExpensesNeverTouchFirestore() throws {
        let setup = makeShared()
        let lunch = expense("ランチ", 1200, .diningOut)
        XCTAssertFalse(setup.store.addExpense(lunch, destination: .personal))
        setup.store.add(expense("スーパー", 3520))
        var changed = lunch
        changed.amount = 1500
        XCTAssertTrue(setup.store.updateExpense(changed))
        XCTAssertTrue(setup.store.deleteExpense(lunch.id))
        XCTAssertEqual(setup.backend.writeCount, 0, "個人の支出は送らない")
        XCTAssertEqual(setup.store.expenses.map(\.title), ["スーパー"])
    }

    /// 明示的に「わが家で共有」を選んだときだけ送る。送るのは決まった項目だけ（レシート・メモ・予算は送らない）
    func testOnlyExplicitHouseholdChoiceSendsFixedFields() throws {
        let setup = makeShared()
        let dinner = expense("夕食の材料", 4321, .food)
        XCTAssertTrue(setup.store.addExpense(dinner, destination: .household))
        XCTAssertEqual(setup.backend.creates.count, 1)
        let fields = try XCTUnwrap(setup.backend.creates.first?.fields)
        XCTAssertEqual(setup.backend.creates.first?.id, dinner.id, "文書の ID は支出の UUID")
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "title", "amount", "category", "date", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertEqual(fields["amount"], .int(4321))
        XCTAssertEqual(fields["category"], .string("food"))
        XCTAssertEqual(fields["createdBy"], .currentUser)
        XCTAssertEqual(fields["createdAt"], .serverTimestamp)
        for key in ["receipt", "receiptImage", "memo", "budget", "email", "device", "ownership"] {
            XCTAssertNil(fields[key], key)
        }
        let update = try XCTUnwrap(SharedExpensePayload.updateFields(for: dinner))
        XCTAssertEqual(Set(update.keys), ["title", "amount", "category", "date", "updatedBy", "updatedAt"], "作成者・作成日時・版は送らない")
        XCTAssertTrue(setup.store.expenses.isEmpty, "共有の支出を個人として二重に保存しない")
        XCTAssertEqual(setup.store.visibleExpenses(scope: .shared).map(\.id), [dinner.id])
    }

    /// 共有できない内容（タイトルが空・金額が範囲外）は送らない
    func testInvalidExpensesAreNotSent() {
        XCTAssertNil(SharedExpensePayload.createFields(for: expense("   ", 100)))
        XCTAssertNil(SharedExpensePayload.createFields(for: expense("ランチ", 0)))
        XCTAssertNil(SharedExpensePayload.createFields(for: expense("ランチ", 1_000_000_000)))
        XCTAssertNotNil(SharedExpensePayload.createFields(for: expense("ランチ", 999_999_999)))
        let longTitle = String(repeating: "あ", count: 250)
        if case .string(let title)? = SharedExpensePayload.createFields(for: expense(longTitle, 1))?["title"] {
            XCTAssertEqual(title.count, 200)
        } else {
            XCTFail("タイトルが無い")
        }
    }

    /// 同じ共有の一覧を100回受け取っても、増えない・入れ替えない・書き戻さない
    func testSameSnapshotHundredTimesDoesNotDuplicate() {
        let setup = makeShared()
        let shared = [expense("家賃の一部", 50_000, .other, ownership: .shared), expense("スーパー", 3520, ownership: .shared)]
        for _ in 0..<100 {
            setup.backend.emit(shared)
            setup.backend.emit(shared, confirmed: false)
        }
        XCTAssertEqual(setup.store.householdExpenses.count, 2)
        XCTAssertEqual(setup.store.householdExpenseUpdateCount, 1, "同じ内容なら入れ替えない（印の変化だけで描き直さない）")
        XCTAssertEqual(setup.backend.writeCount, 0, "受け取った一覧で書き込まない")
        XCTAssertEqual(setup.store.visibleExpenses(scope: .all).count, 2)
    }

    /// 見張りは同じわが家につき最大1つ。わが家が変わると古い見張りを外す
    func testListenerIsAtMostOne() {
        let setup = makeShared()
        for _ in 0..<100 {
            setup.service.apply(household: household(), isSignedIn: true)
        }
        XCTAssertEqual(setup.service.listenStartCount, 1)
        XCTAssertEqual(setup.backend.activeListenerCount, 1)
        XCTAssertEqual(setup.service.activeListenerCount, 1)
        // 家計簿のオン・オフでは見張りを作り直さない
        setup.service.apply(household: household(money: false), isSignedIn: true)
        XCTAssertEqual(setup.backend.listenCount, 1)
        // わが家が変わった
        setup.service.apply(household: household(groupID: "group-b"), isSignedIn: true)
        XCTAssertEqual(setup.backend.listenCount, 2)
        XCTAssertEqual(setup.backend.activeListenerCount, 1)
        XCTAssertEqual(setup.backend.listenedGroupIDs, ["group-a", "group-b"])
    }

    /// サインアウト・退出・わが家の削除で見張りは0。共有の支出の表示も消える（個人の支出は残る）
    func testListenerStopsOnSignOutLeaveAndDelete() {
        for leave in [
            { (s: SharedExpensesService) in s.apply(household: nil, isSignedIn: false) },   // サインアウト
            { (s: SharedExpensesService) in s.apply(household: nil, isSignedIn: true) },    // 退出・わが家の削除
            { (s: SharedExpensesService) in s.apply(household: household(groupID: nil), isSignedIn: true) },
            { (s: SharedExpensesService) in s.apply(household: household(), isSignedIn: false) },
        ] {
            let setup = makeShared()
            setup.store.add(expense("自分のランチ", 980))
            setup.backend.emit([expense("共有のスーパー", 3520, ownership: .shared)])
            XCTAssertEqual(setup.store.householdExpenses.count, 1)
            leave(setup.service)
            XCTAssertEqual(setup.backend.activeListenerCount, 0)
            XCTAssertEqual(setup.service.activeListenerCount, 0)
            XCTAssertTrue(setup.store.householdExpenses.isEmpty)
            XCTAssertEqual(setup.store.expenses.map(\.title), ["自分のランチ"], "個人の支出は消さない")
            XCTAssertNotNil(setup.service.expenseSharingBlock)
        }
    }

    /// 共有に失敗したら「自分だけ」として残す。2件にしない。理由を出す（UID・トークンは出さない）
    func testShareFailureKeepsOnePersonalCopy() {
        for failure in [SharedItemsFailure.permissionDenied, .notSignedIn, .unavailable, .other] {
            let setup = makeShared()
            setup.backend.failure = failure
            let dinner = expense("夕食の材料", 4321)
            XCTAssertTrue(setup.store.addExpense(dinner, destination: .household))
            XCTAssertEqual(setup.store.expenses.map(\.id), [dinner.id], "\(failure)")
            XCTAssertEqual(setup.store.expenses.first?.ownership, .personal)
            XCTAssertTrue(setup.store.householdExpenses.isEmpty)
            XCTAssertEqual(setup.store.visibleExpenses(scope: .all).count, 1, "2件にしない")
            XCTAssertEqual(setup.service.notice, failure.fallbackNotice)
            XCTAssertTrue(setup.service.notice?.hasPrefix("共有できなかったため、自分だけに保存しました") == true)
            // 同じ失敗がもう一度届いても、2件にしない
            setup.store.sharedExpenseCreateFailed(dinner, convertingPersonal: false)
            XCTAssertEqual(setup.store.expenses.count, 1)
            for word in ["uid", "UID", "token", "Firebase", "error"] {
                XCTAssertFalse(setup.service.notice?.contains(word) == true, word)
            }
        }
    }

    /// オフラインで作った共有の支出：結果が届くまで表示し、空の一覧が届いても消さない。重ならない
    func testOfflineCreateStaysVisibleOnce() {
        let setup = makeShared()
        setup.backend.holdsCompletion = true
        let dinner = expense("夕食の材料", 4321)
        setup.store.addExpense(dinner, destination: .household)
        setup.backend.emit([])
        XCTAssertEqual(setup.store.visibleExpenses(scope: .all).map(\.id), [dinner.id])
        var shared = dinner
        shared.ownership = .shared
        setup.backend.emit([shared], confirmed: false)
        XCTAssertEqual(setup.store.visibleExpenses(scope: .all).count, 1)
        XCTAssertEqual(setup.store.pendingSharedExpenseCreateCount, 1)
        setup.backend.heldCompletions.first?(nil)
        XCTAssertEqual(setup.store.pendingSharedExpenseCreateCount, 0)
        XCTAssertTrue(setup.store.expenses.isEmpty)
    }

    /// 「すべて／自分／共有」の内容
    func testScopeContents() {
        let setup = makeShared()
        let mine = expense("自分のランチ", 980, .diningOut)
        setup.store.add(mine)
        let ours = expense("共有のスーパー", 3520, .food, ownership: .shared)
        setup.backend.emit([ours])
        XCTAssertEqual(Set(setup.store.visibleExpenses(scope: .all).map(\.id)), [mine.id, ours.id])
        XCTAssertEqual(setup.store.visibleExpenses(scope: .mine).map(\.id), [mine.id])
        XCTAssertEqual(setup.store.visibleExpenses(scope: .shared).map(\.id), [ours.id])
    }

    /// 表示している範囲ごとの、今月の合計とカテゴリーの合計（ほかの月は入れない。二重に数えない）
    func testScopeTotals() {
        let setup = makeShared()
        setup.store.add(expense("自分のランチ", 1_000, .diningOut))
        setup.store.add(expense("自分のスーパー", 2_000, .food))
        setup.store.add(expense("先月の支出", 9_999, .food, on: TestDates.make(2026, 10, 31, 12)))
        setup.backend.emit([
            expense("共有のスーパー", 3_000, .food, ownership: .shared),
            expense("共有の電車", 400, .transport, ownership: .shared),
        ])
        let appState = AppState()
        appState.usageStyle = .shared
        let money = MoneyViewModel(store: setup.store, appState: appState, now: november10)

        money.scope = .all
        XCTAssertEqual(money.spent, 6_400)
        XCTAssertEqual(money.categoryTotals, [
            ExpenseCategoryTotal(category: .food, amount: 5_000),
            ExpenseCategoryTotal(category: .diningOut, amount: 1_000),
            ExpenseCategoryTotal(category: .transport, amount: 400),
        ])
        money.scope = .mine
        XCTAssertEqual(money.spent, 3_000)
        XCTAssertEqual(money.categoryTotals, [
            ExpenseCategoryTotal(category: .food, amount: 2_000),
            ExpenseCategoryTotal(category: .diningOut, amount: 1_000),
        ])
        money.scope = .shared
        XCTAssertEqual(money.spent, 3_400)
        XCTAssertEqual(money.categoryTotals, [
            ExpenseCategoryTotal(category: .food, amount: 3_000),
            ExpenseCategoryTotal(category: .transport, amount: 400),
        ])
        XCTAssertEqual(money.budget, setup.store.budget.budget, "予算は端末の設定")
        XCTAssertEqual(money.remaining, money.budget - 3_400)
        XCTAssertEqual(money.expenses.count, 2)

        // 一人モードでは「すべて」
        appState.usageStyle = .solo
        XCTAssertEqual(money.spent, 6_400)
        XCTAssertEqual(money.sharingBlock, .soloMode)
    }

    /// 個人と共有の編集・削除は、その支出の保存先にだけ反映する
    func testEditAndDeleteGoOnlyToTheirDestination() throws {
        let setup = makeShared()
        let mine = expense("自分のランチ", 980)
        setup.store.add(mine)
        let ours = expense("共有のスーパー", 3520, ownership: .shared)
        setup.backend.emit([ours])

        var editedMine = mine
        editedMine.title = "自分のディナー"
        XCTAssertTrue(setup.store.updateExpense(editedMine))
        XCTAssertEqual(setup.backend.updates.count, 0, "個人の変更は送らない")
        XCTAssertEqual(setup.store.expenses.first?.title, "自分のディナー")

        var editedOurs = ours
        editedOurs.amount = 4980
        XCTAssertTrue(setup.store.updateExpense(editedOurs))
        XCTAssertEqual(setup.backend.updates.map(\.id), [ours.id])
        XCTAssertEqual(setup.backend.updates.first?.fields["amount"], .int(4980))
        XCTAssertEqual(setup.store.expenses.count, 1, "共有の変更は端末に保存しない")

        XCTAssertTrue(setup.store.deleteExpense(ours.id))
        XCTAssertEqual(setup.backend.deletes, [ours.id])
        XCTAssertTrue(setup.store.deleteExpense(mine.id))
        XCTAssertEqual(setup.backend.deletes, [ours.id], "個人の削除は送らない")
        XCTAssertTrue(setup.store.visibleExpenses(scope: .all).isEmpty)
    }

    /// 家計簿がオフ：新しく共有できない（理由を出す）。すでにある共有の支出は変更・削除できる
    func testMoneyOffBlocksNewSharingButAllowsEdits() {
        let setup = makeShared(money: false)
        XCTAssertEqual(setup.store.expenseSharingBlock, .moneyOff)
        XCTAssertFalse(setup.store.addExpense(expense("スーパー", 3520), destination: .household))
        XCTAssertEqual(setup.backend.creates.count, 0)
        XCTAssertEqual(setup.store.expenses.count, 1, "自分だけに保存する")

        let ours = expense("共有の電車", 400, .transport, ownership: .shared)
        setup.backend.emit([ours])
        XCTAssertTrue(setup.store.canEditSharedExpenses)
        var edited = ours
        edited.amount = 420
        XCTAssertTrue(setup.store.updateExpense(edited))
        XCTAssertTrue(setup.store.deleteExpense(ours.id))
        XCTAssertEqual(setup.backend.updates.count, 1)
        XCTAssertEqual(setup.backend.deletes.count, 1)
    }

    /// 「わが家で共有」を選べない理由（日本語。UID などは出さない）
    func testSharingBlockReasons() {
        let notJoined = SharedExpensesService(backend: FakeSharedExpensesBackend())
        notJoined.apply(household: nil, isSignedIn: true)
        XCTAssertEqual(notJoined.expenseSharingBlock, .notJoined)
        let signedOut = SharedExpensesService(backend: FakeSharedExpensesBackend())
        signedOut.apply(household: household(), isSignedIn: false)
        XCTAssertEqual(signedOut.expenseSharingBlock, .notSignedIn)
        XCTAssertEqual(SharedExpensesService(backend: nil).expenseSharingBlock, .notConnected)
        XCTAssertEqual(emptyStore().expenseSharingBlock, .notConnected)
        XCTAssertNil(makeShared().service.expenseSharingBlock)
        for block in [ExpenseSharingBlock.soloMode, .notConnected, .notSignedIn, .notJoined, .moneyOff] {
            XCTAssertFalse(block.message.isEmpty)
            for word in ["uid", "UID", "token", "Firebase", "error"] {
                XCTAssertFalse(block.message.contains(word), "\(block) \(word)")
            }
        }
    }

    /// 自分だけ → 共有：保存が確かめられてから端末の支出を消す。失敗したら自分だけのまま
    func testConvertPersonalToShared() {
        let success = makeShared()
        success.backend.holdsCompletion = true
        let lunch = expense("ランチ", 1200, .diningOut)
        success.store.add(lunch)
        XCTAssertTrue(success.store.changeExpenseDestination(lunch.id, to: .household))
        XCTAssertEqual(success.store.expenses.map(\.id), [lunch.id], "結果が届くまで端末の支出は消さない")
        XCTAssertEqual(success.store.visibleExpenses(scope: .all).count, 1, "二重に数えない")
        success.backend.heldCompletions.first?(nil)
        XCTAssertTrue(success.store.expenses.isEmpty)
        XCTAssertEqual(success.store.visibleExpenses(scope: .shared).map(\.id), [lunch.id])

        let failure = makeShared()
        failure.backend.failure = .unavailable
        failure.store.add(lunch)
        XCTAssertTrue(failure.store.changeExpenseDestination(lunch.id, to: .household))
        XCTAssertEqual(failure.store.expenses.map(\.id), [lunch.id], "失敗したら自分だけのまま")
        XCTAssertTrue(failure.store.householdExpenses.isEmpty)
        XCTAssertEqual(failure.service.notice, SharedItemsFailure.unavailable.fallbackNotice)
    }

    /// 共有 → 自分だけ：先に端末へ保存してから共有を消す。失敗したら端末の写しを片付け、共有のまま（失わない・2件にしない）
    func testConvertSharedToPersonal() {
        let success = makeShared()
        let ours = expense("共有のスーパー", 3520, ownership: .shared)
        success.backend.emit([ours])
        XCTAssertTrue(success.store.changeExpenseDestination(ours.id, to: .personal))
        XCTAssertEqual(success.store.expenses.map(\.id), [ours.id])
        XCTAssertEqual(success.store.expenses.first?.ownership, .personal)
        XCTAssertEqual(success.backend.deletes, [ours.id])
        XCTAssertEqual(success.store.visibleExpenses(scope: .all).count, 1)

        let failure = makeShared()
        failure.backend.failure = .permissionDenied
        failure.backend.emit([ours])
        XCTAssertTrue(failure.store.changeExpenseDestination(ours.id, to: .personal))
        XCTAssertTrue(failure.store.expenses.isEmpty, "端末の写しを片付ける")
        XCTAssertEqual(failure.store.visibleExpenses(scope: .shared).map(\.id), [ours.id], "共有のまま残す")
        XCTAssertEqual(failure.store.visibleExpenses(scope: .all).count, 1)
        XCTAssertTrue(failure.service.notice?.contains("共有のまま残しています") == true)
    }

    /// 編集画面の保存：内容を直して保存先を変える（MoneyViewModel）
    func testMoneyEditorSavesToTheRightPlace() throws {
        let setup = makeShared()
        let appState = AppState()
        appState.usageStyle = .shared
        let money = MoneyViewModel(store: setup.store, appState: appState, now: november10)

        money.startAdding()
        var draft = try XCTUnwrap(money.draft)
        draft.title = "  ドラッグストア  "
        draft.amountText = "１，２００円"
        draft.category = .dailyGoods
        XCTAssertEqual(draft.amount, 1200)
        XCTAssertTrue(money.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.title), ["ドラッグストア"])
        XCTAssertEqual(setup.backend.writeCount, 0, "初期値のままなら共有しない")

        let saved = try XCTUnwrap(setup.store.expenses.first)
        money.startEditing(saved)
        draft = try XCTUnwrap(money.draft)
        XCTAssertTrue(money.canChoose(.household, in: draft))
        draft.destination = .household
        draft.amountText = "1300"
        XCTAssertTrue(money.save(draft))
        XCTAssertEqual(setup.backend.creates.first?.fields["amount"], .int(1300))
        XCTAssertTrue(setup.store.expenses.isEmpty)

        // 金額・タイトルが正しくなければ保存しない
        money.startAdding()
        var bad = try XCTUnwrap(money.draft)
        bad.title = "x"
        for text in ["", "0", "-5", "abc", "1000000000", "12.5"] {
            bad.amountText = text
            XCTAssertFalse(bad.canSave, text)
            XCTAssertFalse(money.save(bad), text)
        }
        bad.title = "   "
        bad.amountText = "100"
        XCTAssertFalse(money.save(bad))
    }

    /// 削除は確認してから。キャンセルなら何も変えない
    func testMoneyDeleteNeedsConfirmation() throws {
        let setup = makeShared()
        let mine = expense("自分のランチ", 980)
        setup.store.add(mine)
        let money = MoneyViewModel(store: setup.store, appState: AppState(), now: november10)
        money.requestDelete(mine)
        XCTAssertEqual(money.pendingDeletion?.id, mine.id)
        money.cancelDelete()
        XCTAssertEqual(setup.store.expenses.count, 1)
        money.requestDelete(mine)
        XCTAssertTrue(money.confirmDelete())
        XCTAssertTrue(setup.store.expenses.isEmpty)
    }

    /// なんでも追加の支出は、初期状態では自分だけ。保存先で「わが家で共有」を選んだときだけ共有
    func testQuickAddExpenseDefaultsToPersonal() {
        let setup = makeShared()
        let quickAdd = QuickAddViewModel(store: setup.store, now: november10)
        XCTAssertEqual(quickAdd.destination, .personal)
        quickAdd.inputText = "ランチ 1200"
        XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared))
        XCTAssertEqual(setup.store.expenses.map(\.amount), [1200])
        XCTAssertEqual(setup.backend.writeCount, 0)

        quickAdd.inputText = "ランチ 1500"
        XCTAssertTrue(quickAdd.quickAdd(.expense))
        XCTAssertEqual(setup.backend.writeCount, 0)

        XCTAssertTrue(quickAdd.canChooseDestination)
        quickAdd.destination = .household
        quickAdd.inputText = "スーパー 3520"
        XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared))
        XCTAssertEqual(setup.backend.creates.count, 1, "利用者が選んだときだけ共有")
        XCTAssertEqual(setup.backend.creates.first?.fields["amount"], .int(3520))

        // 一人モードでは、選んでいても共有しない
        quickAdd.destination = .household
        quickAdd.inputText = "カフェ 600"
        XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .solo))
        XCTAssertEqual(setup.backend.creates.count, 1)
    }
}

// MARK: - 予定の削除

final class EventDeletionTests: XCTestCase {
    private func event(_ title: String, hour: Int? = nil, on day: Date = TestDates.make(2026, 11, 20)) -> LifeItem {
        if let hour {
            return LifeItem(title: title, kind: .event, ownership: .personal, date: LifeCalendar.date(on: day, hour: hour, minute: 0), hasTime: true, assignee: .me)
        }
        return LifeItem(title: title, kind: .event, ownership: .personal, date: LifeCalendar.startOfDay(day), assignee: .me)
    }

    private func item(_ title: String, _ kind: LifeItemKind, on day: Date = TestDates.make(2026, 11, 20)) -> LifeItem {
        LifeItem(title: title, kind: kind, ownership: .personal, date: LifeCalendar.startOfDay(day), assignee: .me)
    }

    /// 削除は確認してから。キャンセルなら何も変えない
    func testDeleteNeedsConfirmationAndCancelChangesNothing() throws {
        let store = emptyStore()
        let dentist = event("歯医者", hour: 10)
        store.add([dentist])
        let calendar = CalendarViewModel(store: store, appState: AppState(), now: november10)
        calendar.select(dentist.date)

        calendar.requestDeleteEvent(dentist)
        XCTAssertEqual(calendar.eventPendingDeletion?.id, dentist.id, "押しただけでは消さない")
        XCTAssertEqual(store.items.count, 1)
        calendar.cancelDeleteEvent()
        XCTAssertNil(calendar.eventPendingDeletion)
        XCTAssertEqual(store.items.count, 1, "キャンセルなら何も変えない")
        XCTAssertFalse(calendar.confirmDeleteEvent(), "確認が出ていなければ消さない")

        calendar.requestDeleteEvent(dentist)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(calendar.selectedItems.isEmpty, "カレンダーからすぐ消える")
    }

    /// 選んだ予定1件だけを消す。ToDo・買い物・家事は消さない
    func testDeletesOnlyTheSelectedEvent() {
        let store = emptyStore()
        let first = event("歯医者", hour: 10)
        let second = event("美容院", hour: 15)
        let todo = item("書類を出す", .todo)
        let shopping = item("牛乳を買う", .shopping)
        let chore = item("ゴミ出し", .chore)
        store.add([first, second, todo, shopping, chore])
        let calendar = CalendarViewModel(store: store, appState: AppState(), now: november10)

        XCTAssertFalse(calendar.canDeleteEvent(todo))
        calendar.requestDeleteEvent(todo)
        XCTAssertNil(calendar.eventPendingDeletion, "予定でない項目は、ここから消さない")
        for other in [todo, shopping, chore] {
            XCTAssertFalse(store.deleteEvent(other.id), other.title)
        }
        XCTAssertFalse(store.deleteEvent(UUID()))

        calendar.requestDeleteEvent(first)
        XCTAssertTrue(calendar.confirmDeleteEvent())
        XCTAssertEqual(Set(store.items.map(\.id)), [second.id, todo.id, shopping.id, chore.id])
    }

    /// 削除したあとアプリを開き直しても戻らない
    func testDeletedEventStaysDeletedAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Build13-event-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = directory
        defer {
            LocalStorage.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let dentist = event("歯医者", hour: 10)
        let keep = event("美容院", hour: 15)
        store.add([dentist, keep])
        XCTAssertTrue(store.deleteEvent(dentist.id))
        let relaunched = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(relaunched.items.map(\.id), [keep.id])
    }

    /// 「今日」と「カレンダー」の両方から消える
    func testDeletedEventDisappearsFromTodayAndCalendar() {
        let store = emptyStore()
        let day = TestDates.make(2026, 11, 20)
        let dentist = event("歯医者", hour: 18, on: day)
        store.add([dentist, item("書類を出す", .todo, on: day)])
        let appState = AppState()
        let today = TodayViewModel(store: store, appState: appState, now: LifeCalendar.date(on: day, hour: 8, minute: 0))
        XCTAssertTrue((today.focusItems + today.restItems).contains { $0.id == dentist.id })

        let calendar = CalendarViewModel(store: store, appState: appState, now: november10)
        calendar.select(day)
        calendar.requestDeleteEvent(dentist)
        calendar.confirmDeleteEvent()
        XCTAssertFalse((today.focusItems + today.restItems).contains { $0.id == dentist.id }, "今日から消える")
        XCTAssertEqual(calendar.selectedItems.map(\.title), ["書類を出す"], "カレンダーから消え、ToDo は残る")
    }

    /// 削除した予定の通知は、予約し直しで取り消され、残らない
    func testDeletedEventNotificationIsRemoved() async {
        let store = emptyStore()
        let dentist = event("歯医者", hour: 10, on: TestDates.make(2026, 11, 20))
        let other = event("美容院", hour: 15, on: TestDates.make(2026, 11, 20))
        store.add([dentist, other])
        let center = FakeNotificationCenter()
        let service = LifeNotificationService(center: center)
        let now = november10
        await service.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: store.items, eventRemindersEnabled: true, now: now)
        let dentistID = "\(LifeNotificationPlanner.identifierPrefix)event.\(dentist.id.uuidString)"
        let otherID = "\(LifeNotificationPlanner.identifierPrefix)event.\(other.id.uuidString)"
        XCTAssertTrue(center.pending.contains(dentistID))

        XCTAssertTrue(store.deleteEvent(dentist.id))
        await service.resync(warranties: [], isPremium: false, warrantyRemindersEnabled: false, items: store.items, eventRemindersEnabled: true, now: now)
        XCTAssertFalse(center.pending.contains(dentistID), "削除した予定の通知は残らない")
        XCTAssertTrue(center.pending.contains(otherID), "ほかの予定の通知は残る")
    }

    /// 画面：削除の入口・確認の文言・VoiceOver の「予定を削除」がある。予定の編集は足していない。
    /// Build 14（2026-11-01）：Build 13 のスワイプ（LifeSwipeDeleteRow）は実機で「削除」を押しても消えなかったため、
    /// 行の右側のごみ箱ボタンに置き換えた。確かめる内容もボタンに合わせた（docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md）
    func testCalendarSourceHasSwipeConfirmationAndVoiceOverAction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let view = try? String(contentsOf: root.appendingPathComponent("LifeOS/Features/Calendar/CalendarView.swift"), encoding: .utf8) else {
            throw XCTSkip("ソースを読めない環境のため、確認を省きます")
        }
        XCTAssertTrue(view.contains("CalendarEventDeleteButton(title: item.title) {\n                                viewModel.requestDeleteEvent(item)"), "ごみ箱ボタンで確認を出す")
        XCTAssertTrue(view.contains(".accessibilityLabel(\"予定を削除\")"), "VoiceOver から削除できる")
        XCTAssertTrue(view.contains("\"この予定を削除しますか？\""))
        XCTAssertTrue(view.contains("Button(\"予定を削除\", role: .destructive)"), "破壊的な操作（赤）")
        XCTAssertTrue(view.contains("Button(\"キャンセル\", role: .cancel)"))
        XCTAssertFalse(view.contains("LifeSwipeDeleteRow"), "壊れていたスワイプは使わない（操作を二重にしない）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("LifeOS/DesignSystem/Components/LifeSwipeDeleteRow.swift").path), "使わなくなったスワイプの部品は消した")
        XCTAssertFalse(view.contains("updateEvent"), "予定の編集は Build 14 でも足さない")
    }
}
