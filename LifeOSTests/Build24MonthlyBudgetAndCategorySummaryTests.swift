import XCTest
@testable import LifeOS

// Build 24（2026-11-10）：月の予算・カテゴリー別の予算・今日画面の MONEY とのつなぎ込み。
// docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md
// 本物の Firestore・ネットワークは使わない（わが家の予算は、この下の偽物の保存先）。
// ルールの動き（メンバーだけ・形・金額・カテゴリーの合計）は firebase/functions/test/emulator/rules.test.js、
// わが家の削除・アカウント削除は accountDeletion.test.js、ルールの形は test/unit/monthlyBudgets.test.js で確かめる。

private let build24Now = TestDates.make(2026, 11, 10, 12, 0)
private let november = BudgetMonth(year: 2026, month: 11)!
private let october = BudgetMonth(year: 2026, month: 10)!

private func build24Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func build24CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

// MARK: - 偽物のわが家の予算の保存先（わが家ごとの文書。メンバーの端末どうしで同じものを見る）

private final class Build24BudgetCloud {
    /// groupID → 月のキー → 文書
    var documents: [String: [String: [String: Any]]] = [:]
    var listeners: [UUID: (groupID: String, onChange: ([SharedMonthlyBudgetSnapshot]) -> Void)] = [:]
    /// 次の書き込みを断る
    var failure: SharedItemsFailure?

    func snapshots(_ groupID: String) -> [SharedMonthlyBudgetSnapshot] {
        (documents[groupID] ?? [:])
            .compactMap { SharedMonthlyBudgetPayload.snapshot(documentID: $0.key, data: $0.value) }
            .sorted { $0.month < $1.month }
    }

    func broadcast(_ groupID: String) {
        let current = snapshots(groupID)
        for listener in listeners.values where listener.groupID == groupID {
            listener.onChange(current)
        }
    }
}

private final class Build24BudgetsBackend: SharedMonthlyBudgetsBackend {
    let cloud: Build24BudgetCloud
    let uid: String
    private(set) var listenCount = 0
    private(set) var removedListenerCount = 0
    private(set) var sentFields: [[String: Any]] = []
    private(set) var deletes: [String] = []

    var activeListenerCount: Int { listenCount - removedListenerCount }
    var writeCount: Int { sentFields.count + deletes.count }

    init(cloud: Build24BudgetCloud, uid: String) {
        self.cloud = cloud
        self.uid = uid
    }

    func listen(groupID: String, onChange: @escaping ([SharedMonthlyBudgetSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        let id = UUID()
        cloud.listeners[id] = (groupID, onChange)
        onChange(cloud.snapshots(groupID))
        return RepositoryObservation { [weak self] in
            self?.cloud.listeners[id] = nil
            self?.removedListenerCount += 1
        }
    }

    func set(groupID: String, month: BudgetMonth, fields: [String: Any], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentFields.append(fields)
        if let failure = cloud.failure {
            completion(failure)
            return
        }
        var data = fields
        data["updatedBy"] = uid
        data["updatedAt"] = Date()
        cloud.documents[groupID, default: [:]][month.key] = data
        completion(nil)
        cloud.broadcast(groupID)
    }

    func delete(groupID: String, month: BudgetMonth, completion: @escaping (SharedItemsFailure?) -> Void) {
        deletes.append(month.key)
        if let failure = cloud.failure {
            completion(failure)
            return
        }
        cloud.documents[groupID]?[month.key] = nil
        completion(nil)
        cloud.broadcast(groupID)
    }
}

/// わが家のメンバーの1台（端末の置き場・共有の支出・予算・お金の画面・今日の画面）
private struct Build24Device {
    let store: LifeStore
    let expenses: FakeSharedExpensesBackend
    let budgets: Build24BudgetsBackend
    let service: SharedExpensesService
    let appState: AppState
    let money: MoneyViewModel

    func today(now: Date = build24Now) -> TodayViewModel {
        TodayViewModel(store: store, appState: appState, now: now)
    }

    @discardableResult
    func addPersonal(_ title: String, _ amount: Int, _ category: ExpenseCategory = .food, on date: Date = build24Now) -> Expense {
        let expense = Expense(title: title, amount: amount, category: category, date: date)
        store.addExpense(expense, destination: .personal)
        return expense
    }

    @discardableResult
    func addShared(_ title: String, _ amount: Int, _ category: ExpenseCategory = .food, on date: Date = build24Now) -> Expense {
        let expense = Expense(title: title, amount: amount, category: category, date: date, ownership: .shared)
        store.addExpense(expense, destination: .household)
        return expense
    }

    /// お金の画面から予算を保存する（入力欄の文字で）
    @discardableResult
    func saveBudget(_ scope: BudgetScope, total: String, categories: [ExpenseCategory: String] = [:]) -> BudgetInputError? {
        money.startEditingBudget(scope)
        guard var draft = money.budgetDraft else { return .notEditable("入力の画面が開かない") }
        draft.totalText = total
        for (category, text) in categories { draft.categoryTexts[category] = text }
        return money.saveBudget(draft)
    }
}

private func household(_ groupID: String = "group-build24", kinds: [SharedSpaceKind] = [.todo, .shopping, .money]) -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家", sharedKinds: kinds, isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: groupID
    )
}

private func makeDevice(cloud: Build24BudgetCloud = Build24BudgetCloud(), uid: String = "alice", store: LifeStore? = nil,
                        joined: HouseholdSummary? = household(), usageStyle: UsageStyle = .shared) -> Build24Device {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    let expenses = FakeSharedExpensesBackend()
    let budgets = Build24BudgetsBackend(cloud: cloud, uid: uid)
    let service = SharedExpensesService(backend: expenses, budgetsBackend: budgets)
    service.attach(store)
    service.apply(household: joined, isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = usageStyle
    let money = MoneyViewModel(store: store, appState: appState, now: build24Now)
    return Build24Device(store: store, expenses: expenses, budgets: budgets, service: service, appState: appState, money: money)
}

private func plan(_ total: Int, _ categories: [ExpenseCategory: Int] = [:]) -> MonthlyBudgetPlan {
    MonthlyBudgetPlan(totalAmount: total, categoryAmounts: categories)
}

private func expense(_ amount: Int, _ category: ExpenseCategory = .food, on date: Date = build24Now, ownership: Ownership = .personal, id: UUID = UUID()) -> Expense {
    Expense(id: id, title: "架空の支出", amount: amount, category: category, date: date, ownership: ownership)
}

// MARK: - 1. 保存先（1〜6・10・14）

final class Build24BudgetStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build24-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 1：自分だけの月の予算を保存する（端末に残り、次に起動しても読める）
    func testPersonalBudgetIsSaved() throws {
        let device = makeDevice(store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        XCTAssertNil(device.saveBudget(.personal, total: "120,000", categories: [.food: "40000", .dailyGoods: "0"]))
        XCTAssertNil(device.money.budgetDraft, "保存したら閉じる")
        let saved = try XCTUnwrap(device.store.monthlyBudget(for: november, scope: .personal))
        XCTAssertEqual(saved, plan(120_000, [.food: 40_000, .dailyGoods: 0]))
        XCTAssertNil(saved.amount(for: .diningOut), "空のカテゴリーは未設定（0円とは別）")
        let reloaded = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(reloaded.monthlyBudget(for: november, scope: .personal), saved)
        XCTAssertNil(reloaded.monthlyBudget(for: october, scope: .personal), "ほかの月は未設定のまま")
    }

    /// 2：自分だけの予算は Firestore（わが家の保存先）へ送らない
    func testPersonalBudgetIsNotSent() throws {
        let device = makeDevice(store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        XCTAssertNil(device.saveBudget(.personal, total: "50000"))
        XCTAssertEqual(device.budgets.writeCount, 0)
        XCTAssertEqual(device.expenses.writeCount, 0)
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .household), "わが家の予算にはならない")
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(file.contains("monthlyBudgets"), "端末には保存する")
        // わが家の予算は端末に保存しない（端末の記録は自分だけの予算の1件だけ）
        XCTAssertNil(device.saveBudget(.household, total: "88888"))
        device.addPersonal("保存させるための支出", 100)
        let data = try Data(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let saved = try XCTUnwrap(json["monthlyBudgets"] as? [String: Any])
        XCTAssertEqual(saved.keys.sorted(), ["2026-11"])
        XCTAssertEqual((saved["2026-11"] as? [String: Any])?["totalAmount"] as? Int, 50_000, "わが家の予算は life-store.json に入れない")
        XCTAssertNil(json["householdMonthlyBudgets"])
    }

    /// 3・10：わが家の予算を保存する（決まった項目だけを送る。変えた人・日時は窓口が入れる）
    func testHouseholdBudgetIsSavedWithFixedFields() throws {
        let device = makeDevice()
        XCTAssertNil(device.saveBudget(.household, total: "120000", categories: [.food: "40000", .dailyGoods: "0"]))
        let fields = try XCTUnwrap(device.budgets.sentFields.first)
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "monthKey", "totalAmount", "categoryAmounts"])
        XCTAssertEqual(fields["schemaVersion"] as? Int, 1)
        XCTAssertEqual(fields["monthKey"] as? String, "2026-11")
        XCTAssertEqual(fields["totalAmount"] as? Int, 120_000)
        XCTAssertEqual(fields["categoryAmounts"] as? [String: Int], ["food": 40_000, "dailyGoods": 0], "サーバーのテストの見本と同じ")
        XCTAssertEqual(Set(SharedMonthlyBudgetPayload.fieldNames), Set(fields.keys).union(["updatedBy", "updatedAt"]))
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .household), plan(120_000, [.food: 40_000, .dailyGoods: 0]))
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .personal), "自分だけの予算にはならない")
        let backend = build24CodeOnly(try build24Source("LifeOS/Core/Sharing/FirestoreSharedMonthlyBudgetsBackend.swift"))
        XCTAssertTrue(backend.contains("data[\"updatedBy\"] = uid"))
        XCTAssertTrue(backend.contains("data[\"updatedAt\"] = FieldValue.serverTimestamp()"))
        XCTAssertFalse(backend.contains("createdAt"))
    }

    /// 4：パートナー側にも反映し、パートナーも変えられる（変えた人の UID は画面に出さない）
    func testPartnerSeesAndEditsHouseholdBudget() throws {
        let cloud = Build24BudgetCloud()
        let alice = makeDevice(cloud: cloud, uid: "alice")
        let bob = makeDevice(cloud: cloud, uid: "bob")
        XCTAssertNil(alice.saveBudget(.household, total: "100000"))
        XCTAssertEqual(bob.store.monthlyBudget(for: november, scope: .household)?.totalAmount, 100_000)
        XCTAssertTrue(bob.money.canEditBudget(.household), "パートナーも変えられる")
        XCTAssertNil(bob.saveBudget(.household, total: "90000", categories: [.food: "30000"]))
        XCTAssertEqual(alice.store.monthlyBudget(for: november, scope: .household), plan(90_000, [.food: 30_000]))
        let spoken = alice.money.budgetSpokenLabel(alice.money.budgetSummary(for: .household))
        XCTAssertFalse(spoken.contains("bob") || spoken.contains("alice"), "変えた人の UID を出さない")
    }

    /// 5・39：わが家に参加していない・サインインしていない・退出したあとは、わが家の予算を読めず、変えられない
    func testNonMemberAndSignedOutCannotUseHouseholdBudget() {
        let cloud = Build24BudgetCloud()
        let alice = makeDevice(cloud: cloud)
        XCTAssertNil(alice.saveBudget(.household, total: "100000"))
        let outsider = makeDevice(cloud: cloud, uid: "mallory", joined: nil)
        XCTAssertNil(outsider.store.monthlyBudget(for: november, scope: .household))
        XCTAssertFalse(outsider.money.canEditBudget(.household))
        XCTAssertEqual(outsider.store.setMonthlyBudget(plan(1000), for: november, scope: .household), .notEditable(ExpenseSharingBlock.notJoined.message))
        XCTAssertEqual(outsider.budgets.writeCount, 0)
        XCTAssertEqual(outsider.budgets.listenCount, 0, "参加していなければ見張らない")
        // 退出・サインアウト：見張りをやめ、わが家の予算の表示を消す（自分だけの予算は残す）
        XCTAssertNil(alice.saveBudget(.personal, total: "30000"))
        alice.service.apply(household: nil, isSignedIn: true)
        XCTAssertNil(alice.store.monthlyBudget(for: november, scope: .household))
        XCTAssertEqual(alice.budgets.activeListenerCount, 0)
        XCTAssertFalse(alice.money.canEditBudget(.household))
        XCTAssertEqual(alice.store.monthlyBudget(for: november, scope: .personal)?.totalAmount, 30_000)
        let signedOut = makeDevice(cloud: cloud)
        signedOut.service.apply(household: household(), isSignedIn: false)
        XCTAssertNil(signedOut.store.monthlyBudget(for: november, scope: .household))
        XCTAssertFalse(signedOut.money.canEditBudget(.household))
    }

    /// 6：ほかのわが家の予算は読めない（わが家が変わったら、前のわが家の予算を消す）
    func testOtherHouseholdBudgetsAreSeparate() {
        let cloud = Build24BudgetCloud()
        let alice = makeDevice(cloud: cloud)
        XCTAssertNil(alice.saveBudget(.household, total: "100000"))
        let other = makeDevice(cloud: cloud, uid: "mallory", joined: household("group-other"))
        XCTAssertNil(other.store.monthlyBudget(for: november, scope: .household))
        XCTAssertNil(other.saveBudget(.household, total: "5000"))
        XCTAssertEqual(alice.store.monthlyBudget(for: november, scope: .household)?.totalAmount, 100_000, "ほかのわが家の変更は届かない")
        alice.service.apply(household: household("group-other"), isSignedIn: true)
        XCTAssertEqual(alice.store.monthlyBudget(for: november, scope: .household)?.totalAmount, 5000, "見ているわが家の予算だけ")
        XCTAssertEqual(alice.budgets.activeListenerCount, 1, "見張りは1つだけ")
    }

    /// 14：予算を解除する（自分だけ・わが家。カテゴリーの予算も一緒に。支出は消さない）
    func testRemovingBudgets() throws {
        let device = makeDevice()
        device.addPersonal("架空マート", 1200)
        XCTAssertNil(device.saveBudget(.personal, total: "30000", categories: [.food: "10000"]))
        XCTAssertNil(device.saveBudget(.household, total: "80000"))
        device.money.startEditingBudget(.personal)
        let personal = try XCTUnwrap(device.money.budgetDraft)
        XCTAssertTrue(personal.isExisting)
        XCTAssertNil(device.money.removeBudget(personal))
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .personal))
        device.money.startEditingBudget(.household)
        XCTAssertNil(device.money.removeBudget(try XCTUnwrap(device.money.budgetDraft)))
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .household))
        XCTAssertEqual(device.budgets.deletes, ["2026-11"])
        XCTAssertEqual(device.store.expenses.count, 1, "支出は消さない")
        XCTAssertFalse(device.money.budgetSummary(for: .personal).hasBudget)
    }

    /// わが家の予算の保存が断られたら、元の予算に戻し、理由を出す
    func testHouseholdSaveFailureRestoresPrevious() {
        let cloud = Build24BudgetCloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.saveBudget(.household, total: "100000"))
        cloud.failure = .permissionDenied
        XCTAssertNil(device.saveBudget(.household, total: "200000"))
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .household)?.totalAmount, 100_000, "元に戻す")
        XCTAssertEqual(device.service.notice, "わが家の予算を保存できませんでした（権限がありません）。元の内容に戻しました。")
    }

    /// 家計簿の共有がオフなら、わが家の予算を新しく作れない。すでにある予算は変えられ、解除できる（共有の支出と同じ）
    func testMoneySharingOffKeepsExistingBudget() {
        let cloud = Build24BudgetCloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.saveBudget(.household, total: "100000"))
        device.service.apply(household: household(kinds: [.todo, .shopping]), isSignedIn: true)
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .household)?.totalAmount, 100_000, "オフにしても予算は消さない")
        XCTAssertTrue(device.money.canEditBudget(.household), "すでにある予算は変えられる")
        device.money.showNextMonth()
        XCTAssertFalse(device.money.canEditBudget(.household), "新しい月は作れない")
        XCTAssertEqual(device.money.budgetNote(for: .household), ExpenseSharingBlock.moneyOff.message)
        XCTAssertEqual(device.store.setMonthlyBudget(plan(1000), for: november.next, scope: .household), .notEditable(ExpenseSharingBlock.moneyOff.message))
    }

    /// 以前の保存データ（予算の項目が無い・壊れた予算の記録）も読める。支出は失わない
    func testOldAndBrokenSavedDataStillLoads() throws {
        let first = LifeStore.persistent(startEmptyIfNoSavedData: true)
        first.addExpense(Expense(title: "以前の支出", amount: 1500, category: .food, date: build24Now), destination: .personal)
        first.setMonthlyBudget(plan(30_000), for: november, scope: .personal)
        let url = temporaryDirectory.appendingPathComponent(LifeStore.fileName)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["monthlyBudgets"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let old = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(old.expenses.map(\.title), ["以前の支出"])
        XCTAssertNil(old.monthlyBudget(for: november, scope: .personal), "以前のデータは予算なし")
        // 壊れた記録：読めない月・正しくない金額だけを飛ばす
        json["monthlyBudgets"] = [
            "2026-11": ["totalAmount": 30000, "categoryAmounts": ["food": 10000]],
            "2026-13": ["totalAmount": 1000, "categoryAmounts": [:]],
            "2026-10": ["totalAmount": -5, "categoryAmounts": [:]],
            "2026-09": ["totalAmount": "abc"],
            "2026-08": ["totalAmount": 1000, "categoryAmounts": ["food": 2000]]
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let broken = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(broken.expenses.map(\.title), ["以前の支出"], "支出は失わない")
        XCTAssertEqual(broken.personalMonthlyBudgets.keys.sorted(), ["2026-11"])
        json["monthlyBudgets"] = ["not", "a", "map"]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertEqual(LifeStore.persistent(startEmptyIfNoSavedData: true).expenses.count, 1, "形の違う記録でもファイル全体は読める")
    }
}

// MARK: - 2. 入力の決まり（7〜13・33・34）

final class Build24BudgetInputTests: XCTestCase {
    /// 7：月のキー（YYYY-MM・2000〜2099年）
    func testMonthKeys() {
        XCTAssertEqual(november.key, "2026-11")
        XCTAssertEqual(BudgetMonth(year: 2027, month: 1)?.key, "2027-01")
        XCTAssertEqual(BudgetMonth(key: "2026-11"), november)
        for key in ["2026-13", "2026-00", "2026-1", "26-11", "2026/11", "2026-11-01", "abcd-ef", ""] {
            XCTAssertNil(BudgetMonth(key: key), key)
        }
        XCTAssertFalse(BudgetMonth(key: "1999-12")!.isStorable)
        XCTAssertFalse(BudgetMonth(key: "2100-01")!.isStorable)
        XCTAssertTrue(BudgetMonth(key: "2000-01")!.isStorable)
        let store = LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
        XCTAssertEqual(store.setMonthlyBudget(plan(1000), for: BudgetMonth(key: "1999-12")!, scope: .personal), .invalidMonth)
        // 受け取った文書：文書の ID と monthKey が違う・範囲外の月は使わない
        let data: [String: Any] = ["schemaVersion": 1, "monthKey": "2026-11", "totalAmount": 1000, "categoryAmounts": [String: Any]()]
        XCTAssertNotNil(SharedMonthlyBudgetPayload.snapshot(documentID: "2026-11", data: data))
        XCTAssertNil(SharedMonthlyBudgetPayload.snapshot(documentID: "2026-12", data: data))
        XCTAssertNil(SharedMonthlyBudgetPayload.snapshot(documentID: "1999-11", data: data.merging(["monthKey": "1999-11"]) { $1 }))
        XCTAssertNil(SharedMonthlyBudgetPayload.fields(for: plan(1000), month: BudgetMonth(key: "2100-01")!))
    }

    /// 8：金額の下限・上限（月の予算 1〜999,999,999 円・カテゴリー 0〜999,999,999 円）
    func testAmountBounds() {
        XCTAssertEqual(BudgetAmountInput.parse("1", allowsZero: false), .success(1))
        XCTAssertEqual(BudgetAmountInput.parse("999,999,999", allowsZero: false), .success(999_999_999))
        XCTAssertEqual(BudgetAmountInput.parse("1000000000", allowsZero: false), .failure(.tooLarge))
        XCTAssertEqual(BudgetAmountInput.parse("0", allowsZero: false), .failure(.zeroNotAllowed), "月の予算は1円から")
        XCTAssertEqual(BudgetAmountInput.parse("0", allowsZero: true), .success(0), "カテゴリーは0円も設定できる")
        XCTAssertEqual(BudgetAmountInput.parse("", allowsZero: true), .success(nil), "空は未設定（0円とは別）")
        XCTAssertEqual(plan(0).validationError, .total(.zeroNotAllowed))
        XCTAssertEqual(plan(1_000_000_000).validationError, .total(.tooLarge))
        XCTAssertEqual(plan(999_999_999, [.food: 999_999_999]).validationError, nil)
        XCTAssertEqual(plan(1000, [.food: -1]).validationError, .category(.food, .negative))
        var draft = MonthlyBudgetDraft(month: november, scope: .personal, plan: nil)
        XCTAssertEqual(draft.validated(), .failure(.totalMissing))
        draft.totalText = "0"
        XCTAssertEqual(draft.problem?.message, "月の予算：1円以上で入れてください。")
    }

    /// 9：負の数・小数・文字は拒否（全角・カンマ・「円」「¥」は読める）
    func testNegativeDecimalAndTextAreRejected() {
        for text in ["-1", "−1000", "－500", "▲100"] {
            XCTAssertEqual(BudgetAmountInput.parse(text, allowsZero: true), .failure(.negative), text)
        }
        for text in ["1.5", "1000.0", "１．５"] {
            XCTAssertEqual(BudgetAmountInput.parse(text, allowsZero: true), .failure(.decimal), text)
        }
        for text in ["abc", "1万", "12a", "1e3", "千円", "1.2.3a"] {
            XCTAssertEqual(BudgetAmountInput.parse(text, allowsZero: true), .failure(.notNumber), text)
        }
        XCTAssertEqual(BudgetAmountInput.parse("１２０，０００円", allowsZero: false), .success(120_000))
        XCTAssertEqual(BudgetAmountInput.parse("¥ 3,000", allowsZero: false), .success(3000))
        var draft = MonthlyBudgetDraft(month: november, scope: .personal, plan: nil)
        draft.totalText = "50000"
        draft.categoryTexts[.food] = "1.5"
        XCTAssertEqual(draft.problem?.message, "食費の予算：小数は使えません。円単位の整数で入れてください。")
        draft.categoryTexts[.food] = "abc"
        XCTAssertEqual(draft.problem?.message, "食費の予算：数字で入れてください。")
    }

    /// 11：決まったカテゴリーだけ（決まっていないカテゴリーの予算は保存しない・受け取っても使わない）
    func testOnlyKnownCategories() {
        XCTAssertEqual(MonthlyBudgetPlan(totalAmount: 1000, rawCategoryAmounts: ["travel": 100]).validationError, .unknownCategory)
        let data: [String: Any] = ["schemaVersion": 1, "monthKey": "2026-11", "totalAmount": 1000, "categoryAmounts": ["travel": 100]]
        XCTAssertNil(SharedMonthlyBudgetPayload.snapshot(documentID: "2026-11", data: data))
        let floatData: [String: Any] = ["schemaVersion": 1, "monthKey": "2026-11", "totalAmount": 1000, "categoryAmounts": ["food": 1.5]]
        XCTAssertNil(SharedMonthlyBudgetPayload.snapshot(documentID: "2026-11", data: floatData), "小数のカテゴリーは使わない")
        let draft = MonthlyBudgetDraft(month: november, scope: .personal, plan: nil)
        XCTAssertEqual(Set(draft.categoryTexts.keys), Set(ExpenseCategory.allCases), "入力欄は今までのカテゴリーだけ")
    }

    /// 12：カテゴリーの予算の合計は月の予算以下（超えたら保存せず、日本語で理由を出す）
    func testCategoryTotalMustNotExceedTotal() {
        let device = makeDevice()
        let error = device.saveBudget(.personal, total: "100000", categories: [.food: "60000", .other: "40001"])
        XCTAssertEqual(error, .categoriesExceedTotal(sum: 100_001, total: 100_000))
        XCTAssertEqual(error?.message, "カテゴリーの予算の合計（¥100,001）が、月の予算（¥100,000）を超えています。合計が月の予算以下になるように直してください。")
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .personal), "保存しない")
        XCTAssertNotNil(device.money.budgetDraft, "画面は開いたまま")
        XCTAssertNil(device.saveBudget(.personal, total: "100000", categories: [.food: "60000", .other: "40000"]), "同じ額なら保存できる")
        XCTAssertEqual(device.store.setMonthlyBudget(plan(1000, [.food: 2000]), for: november, scope: .household), .categoriesExceedTotal(sum: 2000, total: 1000))
        XCTAssertEqual(device.budgets.writeCount, 0, "正しくない予算は送らない")
    }

    /// 13：予算が未設定（「今月の予算を設定」。残り・目安は出さない）
    func testUnsetBudget() throws {
        let device = makeDevice()
        device.addPersonal("架空マート", 1500)
        let summary = device.money.budgetSummary(for: .personal)
        XCTAssertFalse(summary.hasBudget)
        XCTAssertEqual(summary.spent, 1500)
        XCTAssertNil(summary.remaining)
        XCTAssertNil(summary.usageRatio)
        XCTAssertNil(summary.dailyAllowance)
        XCTAssertEqual(summary.statusText, "予算は未設定です")
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MonthlyBudgetViews.swift"))
        XCTAssertTrue(view.contains("\"今月の予算を設定\""))
        XCTAssertTrue(view.contains("Text(\"予算は未設定です\")"))
    }

    /// 33：0 で割らない（月の予算は1円以上・カテゴリー 0 円は割合を出さない・残り0日は目安を出さない）
    func testNoDivisionByZero() {
        let line = BudgetCategoryLine(category: .food, budget: 0, spent: 500)
        XCTAssertNil(line.usageRatio)
        XCTAssertEqual(line.remaining, -500)
        let pastMonth = MonthlyBudgetCalculator.summary(month: october, scope: .personal, plan: plan(10_000), expenses: [expense(3000, on: TestDates.make(2026, 10, 5))], today: build24Now)
        XCTAssertEqual(pastMonth.daysRemaining, 0)
        XCTAssertNil(pastMonth.dailyAllowance, "過ぎた月は目安を出さない")
        XCTAssertEqual(pastMonth.usageRatio, 0.3)
    }

    /// 34：あふれない（大きな金額を足しても、入力の桁が多くても落ちない）
    func testNoOverflow() {
        XCTAssertEqual(MonthlyBudgetCalculator.saturatingAdd(Int.max, 1), Int.max)
        XCTAssertEqual(MonthlyBudgetCalculator.saturatingAdd(Int.min, -1), Int.min)
        XCTAssertEqual(BudgetAmountInput.parse("99999999999999999999999999", allowsZero: true), .failure(.tooLarge))
        XCTAssertEqual(BudgetAmountInput.parse("0000000000000000000001", allowsZero: true), .success(1), "先頭の0は桁に数えない")
        let many = (0..<20).map { _ in expense(999_999_999) }
        let summary = MonthlyBudgetCalculator.summary(month: november, scope: .personal, plan: plan(999_999_999), expenses: many, today: build24Now)
        XCTAssertEqual(summary.spent, 999_999_999 * 20)
        XCTAssertEqual(summary.overAmount, 999_999_999 * 19)
        XCTAssertEqual(summary.barRatio, 1)
        XCTAssertNotNil(summary.usagePercentText)
        let huge = MonthlyBudgetPlan(totalAmount: 999_999_999, rawCategoryAmounts: Dictionary(uniqueKeysWithValues: ExpenseCategory.allCases.map { ($0.rawValue, 999_999_999) }))
        XCTAssertEqual(huge.validationError, .categoriesExceedTotal(sum: 999_999_999 * 6, total: 999_999_999))
    }
}

// MARK: - 3. 月とカテゴリーの集計（15〜34）

final class Build24AggregationTests: XCTestCase {
    /// 15：過去の月（月を移すと、その月の予算と実績。過去の予算は残る。翌月へ自動でコピーしない）
    func testPastMonthsAndNoAutomaticCopy() throws {
        let device = makeDevice()
        device.addPersonal("10月の支出", 4000, on: TestDates.make(2026, 10, 15, 10))
        device.addPersonal("11月の支出", 1000)
        device.money.showPreviousMonth()
        XCTAssertEqual(device.money.displayedMonth, october)
        XCTAssertFalse(device.money.isShowingCurrentMonth)
        XCTAssertNil(device.saveBudget(.personal, total: "20000"))
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 4000)
        XCTAssertEqual(device.money.budgetSummary(for: .personal).plan?.totalAmount, 20_000)
        device.money.showCurrentMonth()
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 1000)
        XCTAssertNil(device.money.budgetSummary(for: .personal).plan, "翌月へ自動でコピーしない")
        // 「前月の予算をコピー」：欄に入れるだけ。「保存」を押したときだけ保存する
        device.money.startEditingBudget(.personal)
        var draft = try XCTUnwrap(device.money.budgetDraft)
        let previous = try XCTUnwrap(device.money.previousMonthPlan(for: draft))
        draft.fill(from: previous)
        XCTAssertEqual(draft.totalText, "20000")
        XCTAssertNil(device.store.monthlyBudget(for: november, scope: .personal), "コピーしただけでは保存しない")
        XCTAssertNil(device.money.saveBudget(draft))
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .personal)?.totalAmount, 20_000)
        XCTAssertEqual(device.store.monthlyBudget(for: october, scope: .personal)?.totalAmount, 20_000, "過去の予算は残る")
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MonthlyBudgetViews.swift"))
        XCTAssertTrue(view.contains("Button(\"前月の予算をコピー\")"))
    }

    /// 16：月末・年末年始（12月31日は12月、1月1日は1月。年をまたいで移れる）
    func testMonthEndAndNewYear() {
        let december = BudgetMonth(year: 2026, month: 12)!
        XCTAssertEqual(december.next.key, "2027-01")
        XCTAssertEqual(BudgetMonth(year: 2027, month: 1)!.previous.key, "2026-12")
        XCTAssertTrue(december.contains(TestDates.make(2026, 12, 31, 23, 59)))
        XCTAssertFalse(december.contains(TestDates.make(2027, 1, 1, 0, 0)))
        XCTAssertEqual(BudgetMonth(date: TestDates.make(2027, 1, 1, 0, 0)).key, "2027-01")
        let expenses = [expense(1000, on: TestDates.make(2026, 12, 31, 23, 59)), expense(2000, on: TestDates.make(2027, 1, 1, 0, 0))]
        XCTAssertEqual(MonthlyBudgetCalculator.summary(month: december, scope: .personal, plan: nil, expenses: expenses, today: build24Now).spent, 1000)
        XCTAssertEqual(MonthlyBudgetCalculator.daysRemaining(in: december, today: TestDates.make(2026, 12, 31, 23, 0)), 1, "月末は今日だけ")
        XCTAssertEqual(MonthlyBudgetCalculator.daysRemaining(in: november, today: TestDates.make(2026, 11, 30, 8, 0)), 1)
        let device = makeDevice()
        for _ in 0..<2 { device.money.showNextMonth() }
        XCTAssertEqual(device.money.displayedMonth.key, "2027-01")
    }

    /// 17：うるう年（2028年2月は29日）
    func testLeapYear() {
        XCTAssertEqual(BudgetMonth(year: 2028, month: 2)!.dayCount(), 29)
        XCTAssertEqual(BudgetMonth(year: 2026, month: 2)!.dayCount(), 28)
        XCTAssertEqual(BudgetMonth(year: 2000, month: 2)!.dayCount(), 29)
        XCTAssertTrue(BudgetMonth(year: 2028, month: 2)!.contains(TestDates.make(2028, 2, 29, 12)))
        XCTAssertEqual(MonthlyBudgetCalculator.daysRemaining(in: BudgetMonth(year: 2028, month: 2)!, today: TestDates.make(2028, 2, 1, 9)), 29)
    }

    /// 18・19：支出の日付の月で数える（作った日では数えない：11月に入れた10月の支出は10月）
    func testCountsByExpenseDateNotCreationDate() {
        let device = makeDevice()
        device.addPersonal("10月末の支出", 3000, on: TestDates.make(2026, 10, 31, 22))
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 0, "11月には数えない")
        device.money.showPreviousMonth()
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 3000)
    }

    /// 20・21・22：自分だけの予算は自分だけの支出、共有の予算は共有の支出。「すべて」でも予算を混ぜない（2枚のカード）
    func testScopesAreNotMixed() {
        let device = makeDevice()
        device.addPersonal("自分のランチ", 1000, .diningOut)
        device.addShared("共有のスーパー", 3000, .food)
        XCTAssertNil(device.saveBudget(.personal, total: "20000"))
        XCTAssertNil(device.saveBudget(.household, total: "50000"))
        device.appState.scope = .all
        XCTAssertEqual(device.money.budgetScopes, [.personal, .household], "2枚のカード")
        let personal = device.money.budgetSummary(for: .personal)
        let shared = device.money.budgetSummary(for: .household)
        XCTAssertEqual(personal.spent, 1000)
        XCTAssertEqual(personal.plan?.totalAmount, 20_000)
        XCTAssertEqual(shared.spent, 3000)
        XCTAssertEqual(shared.plan?.totalAmount, 50_000)
        XCTAssertEqual(personal.remaining, 19_000)
        XCTAssertEqual(shared.remaining, 47_000)
        device.appState.scope = .mine
        XCTAssertEqual(device.money.budgetSummaries.map(\.scope), [.personal])
        device.appState.scope = .shared
        XCTAssertEqual(device.money.budgetSummaries.map(\.scope), [.household])
        device.appState.usageStyle = .solo
        XCTAssertEqual(device.money.budgetScopes, [.personal], "一人で使う設定は自分だけ")
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(view.contains("ForEach(viewModel.budgetSummaries) { summary in"))
        XCTAssertFalse(view.contains("総予算"))
    }

    /// 23：カテゴリー別の集計（予算のあるカテゴリーは予算・残り・割合、無いカテゴリーは使った金額だけ）
    func testCategoryLines() throws {
        let device = makeDevice()
        device.addPersonal("スーパー", 6000, .food)
        device.addPersonal("電車", 400, .transport)
        XCTAssertNil(device.saveBudget(.personal, total: "50000", categories: [.food: "20000", .dailyGoods: "5000"]))
        let lines = device.money.budgetSummary(for: .personal).categoryLines
        XCTAssertEqual(lines.map(\.category), [.food, .dailyGoods, .transport], "決まった順。予算か支出があるカテゴリーだけ")
        let food = try XCTUnwrap(lines.first)
        XCTAssertEqual(food.budget, 20_000)
        XCTAssertEqual(food.spent, 6000)
        XCTAssertEqual(food.remaining, 14_000)
        XCTAssertEqual(food.usageRatio, 0.3)
        XCTAssertEqual(MonthlyBudgetCard.categoryDetail(food, budget: 20_000), "予算 ¥20,000・残り ¥14,000・30%")
        let transport = lines[2]
        XCTAssertNil(transport.budget)
        XCTAssertEqual(transport.spent, 400)
        XCTAssertNil(transport.remaining)
        XCTAssertEqual(lines[1].spent, 0)
        XCTAssertTrue(device.money.categorySpokenLabel(transport).contains("予算は未設定"))
    }

    /// 24・25：支出のカテゴリーを変えると集計も変わる。支出を消すと集計から外れる
    func testCategoryChangeAndDeletion() throws {
        let device = makeDevice()
        var spending = device.addPersonal("架空マート", 2000, .food)
        XCTAssertNil(device.saveBudget(.personal, total: "10000", categories: [.food: "5000"]))
        spending.category = .dailyGoods
        XCTAssertTrue(device.store.updateExpense(spending))
        let lines = device.money.budgetSummary(for: .personal).categoryLines
        XCTAssertEqual(lines.first { $0.category == .food }?.spent, 0)
        XCTAssertEqual(lines.first { $0.category == .dailyGoods }?.spent, 2000)
        device.money.requestDelete(spending)
        XCTAssertTrue(device.money.confirmDelete())
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 0)
        XCTAssertEqual(device.money.budgetSummary(for: .personal).remaining, 10_000)
    }

    /// 26・27：自分だけ⇔共有を変えても、両方の集計が重ならずに変わる（変えている途中も1回だけ）
    func testDestinationChangeMovesWithoutDuplicates() {
        let device = makeDevice()
        let spending = device.addPersonal("架空マート", 2500)
        device.expenses.holdsCompletion = true
        XCTAssertTrue(device.store.changeExpenseDestination(spending.id, to: .household))
        let duringPersonal = device.money.budgetSummary(for: .personal).spent
        let duringShared = device.money.budgetSummary(for: .household).spent
        XCTAssertEqual(duringPersonal + duringShared, 2500, "途中も1回だけ")
        device.expenses.heldCompletions.forEach { $0(nil) }
        device.expenses.holdsCompletion = false
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 0)
        XCTAssertEqual(device.money.budgetSummary(for: .household).spent, 2500)
        XCTAssertTrue(device.store.changeExpenseDestination(spending.id, to: .personal))
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 2500)
        XCTAssertEqual(device.money.budgetSummary(for: .household).spent, 0)
        // 同じ支出が2回渡されても1回だけ数える
        let id = UUID()
        let twice = [expense(1000, id: id), expense(1000, id: id)]
        XCTAssertEqual(MonthlyBudgetCalculator.summary(month: november, scope: .personal, plan: nil, expenses: twice, today: build24Now).spent, 1000)
    }

    /// 28・29・30：予算内の残り・予算を上回ったとき（責めない言い方）・使った割合
    func testRemainingOverAndRatio() throws {
        let within = MonthlyBudgetCalculator.summary(month: november, scope: .personal, plan: plan(120_000), expenses: [expense(30_000)], today: build24Now)
        XCTAssertEqual(within.remaining, 90_000)
        XCTAssertNil(within.overAmount)
        XCTAssertEqual(within.statusText, "残り ¥90,000")
        XCTAssertEqual(within.usageRatio, 0.25)
        XCTAssertEqual(within.usagePercentText, "25%")
        XCTAssertEqual(within.barRatio, 0.25)
        let over = MonthlyBudgetCalculator.summary(month: november, scope: .personal, plan: plan(10_000), expenses: [expense(12_500)], today: build24Now)
        XCTAssertEqual(over.overAmount, 2500)
        XCTAssertEqual(over.statusText, "予算を¥2,500上回っています")
        XCTAssertEqual(over.usagePercentText, "125%")
        XCTAssertEqual(over.barRatio, 1, "線は1まで（強い色・強い警告にしない）")
        XCTAssertNil(over.dailyAllowance)
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MonthlyBudgetViews.swift"))
        for word in [".red", "Color.red", "超過", "危険", "使いすぎ", "警告", "注意してください"] {
            XCTAssertFalse(view.contains(word), word)
        }
    }

    /// 31・32：残りの日数（今日を含む）と、1日あたりの目安（残り÷日数の参考の値。おすすめにしない）
    func testDaysRemainingAndDailyAllowance() throws {
        let summary = MonthlyBudgetCalculator.summary(month: november, scope: .personal, plan: plan(120_000), expenses: [expense(30_000)], today: build24Now)
        XCTAssertEqual(summary.daysRemaining, 21, "11月10日から30日まで（今日を含む）")
        XCTAssertEqual(summary.dailyAllowance, 90_000 / 21)
        XCTAssertEqual(MonthlyBudgetCalculator.daysRemaining(in: BudgetMonth(year: 2026, month: 12)!, today: build24Now), 31, "先の月はその月の日数")
        XCTAssertEqual(MonthlyBudgetCalculator.daysRemaining(in: october, today: build24Now), 0, "過ぎた月は0日")
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MonthlyBudgetViews.swift"))
        XCTAssertTrue(view.contains("1日あたりの目安"))
        XCTAssertTrue(view.contains("残りの予算を日数で割った参考の値です"))
        for word in ["おすすめ", "使いましょう", "節約しましょう", "投資", "アドバイス"] {
            XCTAssertFalse(view.contains(word), word)
        }
    }
}

// MARK: - 4. 今日の画面・削除・ログ・今までの機能（35〜45）

final class Build24TodayAndCompatibilityTests: XCTestCase {
    /// 35：今日の画面の MONEY は、お金の画面と同じ値（今月・範囲ごと。以前の見本の固定値は使わない）
    func testTodayMatchesMoneyScreen() {
        let device = makeDevice()
        device.addPersonal("自分のランチ", 1000, .diningOut)
        device.addPersonal("先月", 9999, on: TestDates.make(2026, 10, 30))
        device.addShared("共有のスーパー", 3000, .food, on: TestDates.make(2026, 11, 3))
        XCTAssertNil(device.saveBudget(.personal, total: "20000"))
        let today = device.today()
        device.appState.scope = .mine
        XCTAssertEqual(today.monthSpending, device.money.budgetSummary(for: .personal).spent)
        XCTAssertEqual(today.monthSpending, 1000)
        XCTAssertEqual(today.todaySpending, 1000)
        XCTAssertEqual(today.budgetText, "予算 残り ¥19,000")
        XCTAssertEqual(today.budgetRatio, device.money.budgetSummary(for: .personal).barRatio)
        device.appState.scope = .shared
        XCTAssertEqual(today.monthSpending, 3000)
        XCTAssertEqual(today.budgetText, "今月の予算は未設定")
        XCTAssertNil(today.budgetRatio)
        device.appState.scope = .all
        XCTAssertEqual(today.monthSpending, 4000, "合計の支出")
        XCTAssertEqual(today.budgetText, "自分 残り ¥19,000・共有 予算未設定", "予算は分けて短く（足さない）")
        XCTAssertNil(today.budgetRatio, "「すべて」では予算の線を出さない")
        XCTAssertFalse(today.budgetText.contains("総予算"))
        XCTAssertTrue(today.moneySpokenLabel.contains("今月の支出 4,000円"))
        let source = build24CodeOnly((try? build24Source("LifeOS/Features/Today/TodayViewModel.swift")) ?? "")
        XCTAssertFalse(source.contains("store.budget.spent"), "以前の見本の固定値は使わない")
    }

    /// 36：MONEY をタップすると「お金」の画面を開く
    func testTappingMoneyOpensMoneyTab() throws {
        let device = makeDevice()
        let today = device.today()
        device.appState.selectedTab = .today
        today.openMoney()
        XCTAssertEqual(device.appState.selectedTab, .money)
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Today/TodayView.swift"))
        XCTAssertTrue(view.contains("viewModel.openMoney()"))
        XCTAssertTrue(view.contains(".accessibilityHint(\"お金の画面を開きます\")"))
        XCTAssertTrue(view.contains(".lineLimit(1)"), "予算の一言は1行")
    }

    /// 37・38：わが家の削除・アカウント削除（サインアウト）では、端末のわが家の予算の表示も消す（サーバー側は Emulator のテスト）
    func testHouseholdRemovalClearsSharedBudgetsOnly() {
        let device = makeDevice()
        XCTAssertNil(device.saveBudget(.personal, total: "20000"))
        XCTAssertNil(device.saveBudget(.household, total: "50000"))
        device.service.apply(household: nil, isSignedIn: false)
        XCTAssertTrue(device.store.householdMonthlyBudgets.isEmpty)
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .personal)?.totalAmount, 20_000, "自分だけの予算は残す")
        XCTAssertEqual(device.service.activeBudgetsListenerCount, 0)
    }

    /// 見張りは1つだけ（わが家の情報が何度届いても・画面を開き直しても増えない）
    func testSingleBudgetListener() {
        let device = makeDevice()
        for _ in 0..<5 { device.service.apply(household: household(), isSignedIn: true) }
        _ = (0..<10).map { _ in MoneyViewModel(store: device.store, appState: device.appState, now: build24Now).budgetSummaries }
        XCTAssertEqual(device.budgets.listenCount, 1)
        XCTAssertEqual(device.budgets.activeListenerCount, 1)
        XCTAssertEqual(device.service.activeBudgetsListenerCount, 1)
    }

    /// 40：予算・金額・商品名をログに出さない。Analytics・Crashlytics・外部の通信を足さない
    func testNoLoggingOrAnalytics() throws {
        for path in [
            "LifeOS/Core/Models/MonthlyBudgetPlan.swift",
            "LifeOS/Core/Sharing/SharedMonthlyBudgets.swift",
            "LifeOS/Core/Sharing/FirestoreSharedMonthlyBudgetsBackend.swift",
            "LifeOS/Core/Sharing/SharedExpenses.swift",
            "LifeOS/Core/Store/LifeStore.swift",
            "LifeOS/Features/Money/MonthlyBudgetViews.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift",
            "LifeOS/Features/Today/TodayView.swift",
            "LifeOS/Features/Today/TodayViewModel.swift"
        ] {
            let code = build24CodeOnly(try build24Source(path))
            for word in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "Analytics", "Crashlytics", "URLSession", "URLRequest"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        let project = try build24Source("LifeOS.xcodeproj/project.pbxproj")
        let products = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("productName = Firebase") }
        XCTAssertEqual(products.count, 6, "Firebase の部品を足していない（Analytics・Crashlytics なし）")
    }

    /// VoiceOver・44pt・キーボード（Build 22 と同じ閉じ方）・保存とキャンセルは1回のタップ
    func testAccessibilityAndKeyboard() throws {
        let view = build24CodeOnly(try build24Source("LifeOS/Features/Money/MonthlyBudgetViews.swift"))
        XCTAssertTrue(view.contains(".lifeKeyboardDismissal()"))
        XCTAssertTrue(view.contains(".lifeKeyboardDoneButton { focusedField = nil }"))
        XCTAssertTrue(view.contains(".keyboardType(.numberPad)"))
        XCTAssertTrue(view.contains("ToolbarItem(placement: .confirmationAction)"))
        XCTAssertTrue(view.contains("ToolbarItem(placement: .cancellationAction)"))
        XCTAssertTrue(view.contains(".accessibilityLabel(viewModel.budgetSpokenLabel(summary))"))
        XCTAssertTrue(view.contains(".frame(minHeight: LifeSpacing.minTapTarget)"))
        let money = build24CodeOnly(try build24Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains(".accessibilityLabel(\"前の月\")"))
        XCTAssertTrue(money.contains(".accessibilityLabel(\"次の月\")"))
        XCTAssertTrue(money.contains(".frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)"))
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        let device = makeDevice()
        XCTAssertNil(device.saveBudget(.personal, total: "120000"))
        let spoken = device.money.budgetSpokenLabel(device.money.budgetSummary(for: .personal))
        XCTAssertTrue(spoken.contains("残り 120,000円"))
        XCTAssertTrue(spoken.contains("1日あたりの目安"))
        device.money.startEditingBudget(.personal)
        device.money.cancelBudgetEditing()
        XCTAssertNil(device.money.budgetDraft, "キャンセルで閉じる（予算は変えない）")
        XCTAssertEqual(device.store.monthlyBudget(for: november, scope: .personal)?.totalAmount, 120_000)
    }

    /// 41：Build 23 の検索・購入履歴は今までどおり
    func testBuild23SearchStillWorks() {
        let device = makeDevice()
        let milk = ExpenseLineItem(name: "牛乳", unitPrice: 198, amount: 198)
        let spending = Expense(title: "まちの八百屋", amount: 198, category: .food, date: build24Now)
        device.store.addExpense(spending, destination: .personal, lineItems: [milk])
        device.money.searchText = "牛乳"
        XCTAssertEqual(device.money.searchResults.map(\.id), [spending.id])
        XCTAssertEqual(device.money.purchaseHistory(for: device.money.historyTarget(for: milk)).purchaseCount, 1)
        device.money.clearSearch()
        XCTAssertFalse(device.money.isSearching)
    }

    /// 42：Build 21 の商品明細は今までどおり
    func testBuild21LineItemsStillWork() throws {
        let device = makeDevice()
        let spending = Expense(title: "まちの八百屋", amount: 698, category: .food, date: build24Now)
        device.store.addExpense(spending, destination: .personal, lineItems: [
            ExpenseLineItem(name: "牛乳", amount: 198), ExpenseLineItem(name: "ティッシュ", quantity: 2, unitPrice: 250, amount: 500, sortOrder: 1)
        ])
        XCTAssertEqual(device.money.lineItems(for: spending).map(\.name), ["牛乳", "ティッシュ"])
        XCTAssertEqual(device.money.lineItemComparison(for: spending), .matched(total: 698))
        let milk = try XCTUnwrap(device.money.lineItems(for: spending).first)
        XCTAssertNil(device.money.deleteLineItem(milk, in: spending))
        XCTAssertEqual(device.money.lineItems(for: spending).map(\.name), ["ティッシュ"])
    }

    /// 43：レシート・保証書の読み取りは今までどおり
    func testReceiptAndWarrantyOCRStillWork() {
        let proposal = ReceiptFieldExtractor.extract(from: ["まちの八百屋", "牛乳 ¥198", "小計 ¥198", "合計 ¥198", "お預り ¥1,000", "お釣り ¥802"], today: build24Now)
        XCTAssertEqual(proposal.amount, 198)
        let warranty = WarrantyFieldExtractor.extract(from: [WarrantyRecognizedLine(text: "型番 AB-123")])
        XCTAssertEqual(warranty.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
    }

    /// 44・45：Build 番号は4か所とも 24。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    func testBuildNumberIs24() throws {
        let project = try build24Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 24;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build24Source("docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md").contains("Build 16 は欠番"))
    }
}
