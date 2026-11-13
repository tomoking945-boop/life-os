import XCTest
@testable import LifeOS

// Build 25（2026-11-11）：固定費・定期支出。docs/BUILD_25_RECURRING_EXPENSES.md
// 本物の Firestore・ネットワークは使わない（わが家の定期支出は、この下の偽物の保存先。2台の iPhone で同じものを見る）。
// ルールの動き（メンバーだけ・形・同じ月は1件だけ・追加済みは消せない）は firebase/functions/test/emulator/rules.test.js、
// わが家の削除・アカウント削除は accountDeletion.test.js、通知しないことは functions.test.js、
// ルールの形は test/unit/recurringExpenses.test.js で確かめる。

private let build25Now = TestDates.make(2026, 11, 20, 12, 0)
private let november = BudgetMonth(year: 2026, month: 11)!
private let december = BudgetMonth(year: 2026, month: 12)!
private let october = BudgetMonth(year: 2026, month: 10)!

private func build25Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func build25CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

/// 送る値を、Firestore から届く値の形にする（本人の UID・サーバーの時刻は窓口が入れる）
private func build25Data(_ fields: [String: SharedItemValue], uid: String) -> [String: Any] {
    var data: [String: Any] = [:]
    for (key, value) in fields {
        switch value {
        case .string(let text): data[key] = text
        case .bool(let flag): data[key] = flag
        case .int(let number): data[key] = number
        case .date(let date): data[key] = date
        case .null: data[key] = NSNull()
        case .serverTimestamp: data[key] = Date()
        case .currentUser: data[key] = uid
        }
    }
    return data
}

// MARK: - 偽物のわが家（設定・月ごとの状態・共有の支出。Security Rules と同じく、同じ月の2回目は断る）

private final class Build25Cloud {
    /// groupID → 文書の ID → 文書
    var templates: [String: [String: [String: Any]]] = [:]
    var occurrences: [String: [String: [String: Any]]] = [:]
    var expenses: [String: [String: [String: Any]]] = [:]
    var templateListeners: [UUID: (groupID: String, onChange: ([RecurringExpenseTemplate]) -> Void)] = [:]
    var occurrenceListeners: [UUID: (groupID: String, onChange: ([RecurringOccurrence]) -> Void)] = [:]
    /// 共有の支出の見張り（各 iPhone の偽物の窓口へ届ける）
    var expenseFeeds: [(groupID: String, backend: FakeSharedExpensesBackend)] = []
    /// 次の書き込みを断る
    var failure: SharedItemsFailure?
    /// true なら書き込みをためる（2台で同時に押したとき：どちらもサーバーに届く前に送る）
    var holdsCommits = false
    private(set) var heldCommits: [() -> Void] = []
    /// 1回の書き込みで支出と状態を一緒に作った回数
    private(set) var batchCount = 0

    func templateList(_ groupID: String) -> [RecurringExpenseTemplate] {
        (templates[groupID] ?? [:])
            .compactMap { SharedRecurringExpensePayload.template(documentID: $0.key, data: $0.value) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func occurrenceList(_ groupID: String) -> [RecurringOccurrence] {
        (occurrences[groupID] ?? [:])
            .compactMap { SharedRecurringExpensePayload.occurrence(documentID: $0.key, data: $0.value) }
            .sorted { $0.id < $1.id }
    }

    func expenseList(_ groupID: String) -> [Expense] {
        (expenses[groupID] ?? [:])
            .compactMap { SharedExpensePayload.expense(documentID: $0.key, data: $0.value) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func broadcast(_ groupID: String) {
        let templates = templateList(groupID)
        for listener in templateListeners.values where listener.groupID == groupID { listener.onChange(templates) }
        let occurrences = occurrenceList(groupID)
        for listener in occurrenceListeners.values where listener.groupID == groupID { listener.onChange(occurrences) }
        let expenses = expenseList(groupID)
        for feed in expenseFeeds where feed.groupID == groupID { feed.backend.emit(expenses) }
    }

    func run(_ commit: @escaping () -> Void) {
        if holdsCommits {
            heldCommits.append(commit)
        } else {
            commit()
        }
    }

    func releaseHeldCommits() {
        let commits = heldCommits
        heldCommits = []
        holdsCommits = false
        commits.forEach { $0() }
    }

    func countBatch() { batchCount += 1 }
}

private final class Build25RecurringBackend: SharedRecurringExpensesBackend {
    let cloud: Build25Cloud
    let uid: String
    private(set) var listenCount = 0
    private(set) var removedListenerCount = 0
    private(set) var sentTemplateFields: [[String: SharedItemValue]] = []
    private(set) var sentOccurrenceFields: [[String: SharedItemValue]] = []
    private(set) var sentExpenseFields: [[String: SharedItemValue]] = []
    private(set) var deletes: [String] = []

    var activeListenerCount: Int { listenCount - removedListenerCount }
    var writeCount: Int { sentTemplateFields.count + sentOccurrenceFields.count + deletes.count }

    init(cloud: Build25Cloud, uid: String) {
        self.cloud = cloud
        self.uid = uid
    }

    func listenTemplates(groupID: String, onChange: @escaping ([RecurringExpenseTemplate]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        let id = UUID()
        cloud.templateListeners[id] = (groupID, onChange)
        onChange(cloud.templateList(groupID))
        return RepositoryObservation { [weak self] in
            self?.cloud.templateListeners[id] = nil
            self?.removedListenerCount += 1
        }
    }

    func listenOccurrences(groupID: String, onChange: @escaping ([RecurringOccurrence]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        let id = UUID()
        cloud.occurrenceListeners[id] = (groupID, onChange)
        onChange(cloud.occurrenceList(groupID))
        return RepositoryObservation { [weak self] in
            self?.cloud.occurrenceListeners[id] = nil
            self?.removedListenerCount += 1
        }
    }

    func createTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentTemplateFields.append(fields)
        let cloud = self.cloud
        let uid = self.uid
        cloud.run {
            if let failure = cloud.failure { return completion(failure) }
            guard cloud.templates[groupID]?[id.uuidString] == nil else { return completion(.permissionDenied) }
            cloud.templates[groupID, default: [:]][id.uuidString] = build25Data(fields, uid: uid)
            completion(nil)
            cloud.broadcast(groupID)
        }
    }

    func updateTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentTemplateFields.append(fields)
        let cloud = self.cloud
        let uid = self.uid
        cloud.run {
            if let failure = cloud.failure { return completion(failure) }
            guard var data = cloud.templates[groupID]?[id.uuidString] else { return completion(.permissionDenied) }
            for (key, value) in build25Data(fields, uid: uid) { data[key] = value }
            cloud.templates[groupID]?[id.uuidString] = data
            completion(nil)
            cloud.broadcast(groupID)
        }
    }

    func createSkippedOccurrence(groupID: String, occurrenceID: String, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        sentOccurrenceFields.append(fields)
        let cloud = self.cloud
        let uid = self.uid
        cloud.run {
            if let failure = cloud.failure { return completion(failure) }
            guard cloud.occurrences[groupID]?[occurrenceID] == nil else { return completion(.permissionDenied) }
            cloud.occurrences[groupID, default: [:]][occurrenceID] = build25Data(fields, uid: uid)
            completion(nil)
            cloud.broadcast(groupID)
        }
    }

    func deleteSkippedOccurrence(groupID: String, occurrenceID: String, completion: @escaping (SharedItemsFailure?) -> Void) {
        deletes.append(occurrenceID)
        let cloud = self.cloud
        cloud.run {
            if let failure = cloud.failure { return completion(failure) }
            // Security Rules と同じ：消せるのは「今月は追加しない」だけ
            guard cloud.occurrences[groupID]?[occurrenceID]?["status"] as? String == "skipped" else { return completion(.permissionDenied) }
            cloud.occurrences[groupID]?[occurrenceID] = nil
            completion(nil)
            cloud.broadcast(groupID)
        }
    }

    func createExpenseWithOccurrence(
        groupID: String,
        expenseID: UUID,
        expenseFields: [String: SharedItemValue],
        occurrenceID: String,
        occurrenceFields: [String: SharedItemValue],
        completion: @escaping (SharedItemsFailure?) -> Void
    ) {
        sentExpenseFields.append(expenseFields)
        sentOccurrenceFields.append(occurrenceFields)
        let cloud = self.cloud
        let uid = self.uid
        cloud.run {
            if let failure = cloud.failure { return completion(failure) }
            // 1回の書き込み：同じ月の記録・同じ支出がすでにあれば、全部を断る（片方だけは作らない）
            guard cloud.occurrences[groupID]?[occurrenceID] == nil,
                  cloud.expenses[groupID]?[expenseID.uuidString] == nil else { return completion(.permissionDenied) }
            cloud.expenses[groupID, default: [:]][expenseID.uuidString] = build25Data(expenseFields, uid: uid)
            cloud.occurrences[groupID, default: [:]][occurrenceID] = build25Data(occurrenceFields, uid: uid)
            cloud.countBatch()
            completion(nil)
            cloud.broadcast(groupID)
        }
    }
}

/// わが家のメンバーの1台（端末の置き場・共有の支出・定期支出・お金の画面）
private struct Build25Device {
    let store: LifeStore
    let expenses: FakeSharedExpensesBackend
    let recurring: Build25RecurringBackend
    let service: SharedExpensesService
    let appState: AppState
    let money: MoneyViewModel

    func today(now: Date = build25Now) -> TodayViewModel {
        TodayViewModel(store: store, appState: appState, now: now)
    }

    /// お金の画面から定期支出を登録する（入力欄の文字で）
    @discardableResult
    func register(_ title: String = "家賃", amount: String = "85000", category: ExpenseCategory = .other, dueDay: Int = 27,
                  start: BudgetMonth = november, destination: SaveDestination = .personal) -> RecurringExpenseError? {
        money.startAddingRecurring()
        guard var draft = money.recurringDraft else { return .notEditable("入力の画面が開かない") }
        draft.title = title
        draft.amountText = amount
        draft.category = category
        draft.dueDay = dueDay
        draft.startMonth = start
        draft.destination = destination
        return money.saveRecurring(draft)
    }

    func templates(_ scope: BudgetScope) -> [RecurringExpenseTemplate] {
        store.recurringTemplates(scope: scope)
    }

    func candidate(_ scope: BudgetScope, month: BudgetMonth = november) -> RecurringCandidate? {
        money.displayedMonth = month
        return money.recurringCandidates(for: scope).first
    }

    /// 「今月分を追加」→ 確認画面の「保存」（日付・金額を直すこともできる）
    @discardableResult
    func addThisMonth(_ scope: BudgetScope, month: BudgetMonth = november, editing: ((inout ExpenseDraft) -> Void)? = nil) -> Bool {
        guard let candidate = candidate(scope, month: month) else { return false }
        money.startRecurringExpense(candidate)
        guard var draft = money.draft else { return false }
        editing?(&draft)
        return money.save(draft)
    }
}

private func household(_ groupID: String = "group-build25", kinds: [SharedSpaceKind] = [.todo, .shopping, .money], isOwner: Bool = true) -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家", sharedKinds: kinds, isOwner: isOwner,
        members: [HouseholdMember(role: .owner, isSelf: isOwner), HouseholdMember(role: .member, isSelf: !isOwner)],
        groupID: groupID
    )
}

private func makeDevice(cloud: Build25Cloud = Build25Cloud(), uid: String = "alice", store: LifeStore? = nil,
                        joined: HouseholdSummary? = household(), usageStyle: UsageStyle = .shared, now: Date = build25Now) -> Build25Device {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    let expenses = FakeSharedExpensesBackend()
    let recurring = Build25RecurringBackend(cloud: cloud, uid: uid)
    let service = SharedExpensesService(backend: expenses, recurringBackend: recurring)
    service.attach(store)
    service.apply(household: joined, isSignedIn: true)
    cloud.expenseFeeds.append((joined?.groupID ?? "", expenses))
    expenses.emit(cloud.expenseList(joined?.groupID ?? ""))
    let appState = AppState()
    appState.usageStyle = usageStyle
    let money = MoneyViewModel(store: store, appState: appState, now: now)
    return Build25Device(store: store, expenses: expenses, recurring: recurring, service: service, appState: appState, money: money)
}

private func template(_ title: String = "家賃", amount: Int = 85_000, dueDay: Int = 27, start: String = "2026-11", isActive: Bool = true,
                      ownership: Ownership = .personal, id: UUID = UUID()) -> RecurringExpenseTemplate {
    RecurringExpenseTemplate(id: id, title: title, expectedAmount: amount, category: .other, dueDay: dueDay, startMonthKey: start,
                             isActive: isActive, ownership: ownership)
}

private func day(_ date: Date) -> Int {
    LifeCalendar.calendar.component(.day, from: date)
}

// MARK: - 1. 保存先（1〜4・38・45）

final class Build25RecurringStorageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build25-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 1：自分だけの定期支出は端末（life-store.json）に保存し、次に起動しても読める（設定と月ごとの状態）
    func testPersonalRecurringIsSavedOnDevice() throws {
        let device = makeDevice(store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        XCTAssertNil(device.register())
        XCTAssertNil(device.money.recurringDraft, "保存したら閉じる")
        let saved = try XCTUnwrap(device.templates(.personal).first)
        XCTAssertEqual(saved.title, "家賃")
        XCTAssertEqual(saved.expectedAmount, 85_000)
        XCTAssertEqual(saved.ownership, .personal, "保存先の初期値は自分だけ")
        XCTAssertNil(device.store.skipRecurring(templateID: saved.id, month: december))
        let reloaded = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(reloaded.recurringTemplates(scope: .personal), [saved])
        XCTAssertEqual(reloaded.recurringOccurrences(scope: .personal).values.map(\.status), [.skipped])
        XCTAssertTrue(reloaded.recurringTemplates(scope: .household).isEmpty)
    }

    /// 2：自分だけの定期支出は Firestore（わが家の保存先）へ送らない。わが家の定期支出は life-store.json に入れない
    func testPersonalRecurringIsNotSent() throws {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud, store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        XCTAssertNil(device.register("携帯代", amount: "3,980", destination: .personal))
        XCTAssertTrue(device.addThisMonth(.personal))
        XCTAssertEqual(device.recurring.writeCount, 0, "自分だけの定期支出は送らない")
        XCTAssertEqual(device.expenses.writeCount, 0, "作った支出も自分だけ")
        XCTAssertTrue(cloud.templates.isEmpty && cloud.occurrences.isEmpty && cloud.expenses.isEmpty)
        // わが家の定期支出を作っても、端末のファイルには入らない
        XCTAssertNil(device.register("わが家の家賃", destination: .household))
        device.store.addExpense(Expense(title: "保存させるための支出", amount: 100, category: .food, date: build25Now), destination: .personal)
        let data = try Data(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(json["recurringExpenses"] as? [String: Any])
        let templates = try XCTUnwrap(records["templates"] as? [[String: Any]])
        XCTAssertEqual(templates.compactMap { $0["title"] as? String }, ["携帯代"])
        XCTAssertEqual((records["occurrences"] as? [[String: Any]])?.count, 1)
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertFalse(file.contains("わが家の家賃"), "わが家の定期支出は life-store.json に入れない")
    }

    /// 38：端末に保存できなかったときは、支出も「追加済み」も元に戻す（候補は未確認のまま）
    func testDeviceSaveFailureRollsBack() throws {
        let device = makeDevice(store: LifeStore.persistent(startEmptyIfNoSavedData: true))
        XCTAssertNil(device.register())
        let saved = try XCTUnwrap(device.templates(.personal).first)
        // 保存先をファイルにして、書き込みを失敗させる
        let blocker = temporaryDirectory.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        LocalStorage.directoryOverride = blocker
        XCTAssertFalse(device.addThisMonth(.personal))
        XCTAssertEqual(device.money.draftMessage, RecurringExpenseError.saveFailed.message, "理由を出す")
        XCTAssertNotNil(device.money.draft, "確認画面は開いたまま")
        XCTAssertTrue(device.store.expenses.isEmpty, "支出は作らない")
        XCTAssertTrue(device.store.recurringOccurrences(scope: .personal).isEmpty, "追加済みにしない")
        XCTAssertEqual(device.candidate(.personal)?.state, .unconfirmed)
        XCTAssertEqual(device.store.skipRecurring(templateID: saved.id, month: november), .saveFailed)
        XCTAssertTrue(device.store.recurringOccurrences(scope: .personal).isEmpty)
        var edited = saved
        edited.expectedAmount = 90_000
        XCTAssertEqual(device.store.saveRecurringTemplate(edited), .saveFailed)
        XCTAssertEqual(device.templates(.personal).first?.expectedAmount, 85_000, "設定も元のまま")
        LocalStorage.directoryOverride = temporaryDirectory
        device.money.cancelEditing()
        XCTAssertTrue(device.addThisMonth(.personal), "保存できるようになったら追加できる")
        XCTAssertEqual(device.store.expenses.count, 1)
    }

    /// 45：以前の保存データ（定期支出の項目が無い・壊れた記録）も読める。支出・予算は失わない
    func testOldAndBrokenSavedDataStillLoads() throws {
        let first = LifeStore.persistent(startEmptyIfNoSavedData: true)
        first.addExpense(Expense(title: "以前の支出", amount: 1500, category: .food, date: build25Now), destination: .personal)
        first.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 30_000, categoryAmounts: [:]), for: november, scope: .personal)
        let valid = template()
        XCTAssertNil(first.saveRecurringTemplate(valid))
        let url = temporaryDirectory.appendingPathComponent(LifeStore.fileName)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["recurringExpenses"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let old = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(old.expenses.map(\.title), ["以前の支出"])
        XCTAssertEqual(old.monthlyBudget(for: november, scope: .personal)?.totalAmount, 30_000)
        XCTAssertTrue(old.recurringTemplates(scope: .personal).isEmpty, "以前のデータは定期支出なし")
        // 壊れた記録：読めない設定・正しくない状態だけを飛ばす
        let id = valid.id.uuidString
        json["recurringExpenses"] = [
            "templates": [
                ["id": id, "title": "家賃", "expectedAmount": 85000, "category": "other", "dueDay": 27, "startMonthKey": "2026-11", "isActive": true, "ownership": "personal"],
                ["id": UUID().uuidString, "title": "", "expectedAmount": 100, "category": "other", "dueDay": 1, "startMonthKey": "2026-11", "isActive": true, "ownership": "personal"],
                ["id": UUID().uuidString, "title": "壊れた金額", "expectedAmount": "abc"],
                ["id": UUID().uuidString, "title": "支払日", "expectedAmount": 100, "category": "other", "dueDay": 40, "startMonthKey": "2026-11", "isActive": true, "ownership": "personal"],
                "not a template"
            ],
            "occurrences": [
                ["templateID": id, "monthKey": "2026-11", "status": "skipped"],
                ["templateID": id, "monthKey": "2026-13", "status": "skipped"],
                ["templateID": id, "monthKey": "2026-10", "status": "created"],
                ["templateID": UUID().uuidString, "monthKey": "2026-12", "status": "skipped"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let broken = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(broken.expenses.map(\.title), ["以前の支出"], "支出は失わない")
        XCTAssertEqual(broken.recurringTemplates(scope: .personal).map(\.title), ["家賃"])
        XCTAssertEqual(Array(broken.recurringOccurrences(scope: .personal).keys), ["\(id)_2026-11"], "正しい記録だけ")
        json["recurringExpenses"] = ["not", "a", "map"]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let wrongShape = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(wrongShape.expenses.count, 1, "形の違う記録でもファイル全体は読める")
        XCTAssertTrue(wrongShape.recurringTemplates(scope: .personal).isEmpty)
    }
}

// MARK: - 2. 入力の決まり（7〜14）

final class Build25RecurringInputTests: XCTestCase {
    /// 7：名前は空・81文字・改行・制御文字を断る（前後の空白は除く。80文字・絵文字は通る）
    func testTitleRules() throws {
        XCTAssertEqual(RecurringExpenseInput.titleProblem(""), .titleMissing)
        XCTAssertEqual(RecurringExpenseInput.titleProblem("   "), .titleMissing)
        XCTAssertEqual(RecurringExpenseInput.titleProblem(String(repeating: "あ", count: 81)), .titleTooLong)
        XCTAssertNil(RecurringExpenseInput.titleProblem(String(repeating: "あ", count: 80)))
        XCTAssertEqual(RecurringExpenseInput.titleProblem("家賃\n駐車場"), .titleHasControlCharacters)
        XCTAssertEqual(RecurringExpenseInput.titleProblem("家\t賃"), .titleHasControlCharacters, "タブ（前後の空白は除くが、中の制御文字は断る）")
        XCTAssertEqual(RecurringExpenseInput.titleProblem("家\u{0007}賃"), .titleHasControlCharacters)
        XCTAssertEqual(RecurringExpenseInput.titleProblem("家\u{2028}賃"), .titleHasControlCharacters, "行の区切り")
        XCTAssertNil(RecurringExpenseInput.titleProblem("👨‍👩‍👧 動画サブスク"), "絵文字は使える")
        XCTAssertEqual(RecurringExpenseInput.trimmedTitle("  家賃  "), "家賃")
        for error in [RecurringExpenseError.titleMissing, .titleTooLong, .titleHasControlCharacters] {
            XCTAssertFalse(error.message.isEmpty, "日本語で理由を出す")
        }
        var draft = RecurringExpenseDraft(newIn: november)
        draft.title = "家賃\n"
        draft.amountText = "85000"
        XCTAssertEqual(try draft.validated().get().title, "家賃", "末尾の改行は除いて保存")
    }

    /// 8：金額は 0・負・小数・上限超え・文字を断る
    func testAmountRejectsInvalidValues() {
        for text in ["0", "-1", "-500", "1.5", "85000.0", "1000000000", "九千円", "abc", "1e3"] {
            guard case .failure = RecurringExpenseInput.amount(text) else {
                return XCTFail("\(text) を断る")
            }
        }
        XCTAssertEqual(RecurringExpenseInput.amount(""), .failure(.amountMissing))
        XCTAssertEqual(RecurringExpenseInput.amount("999999999"), .success(999_999_999))
        XCTAssertEqual(RecurringExpenseInput.amount("1"), .success(1))
        let invalid = template(amount: 0)
        XCTAssertNotNil(invalid.validationError)
        XCTAssertNotNil(template(amount: 1_000_000_000).validationError)
        XCTAssertNotNil(template(amount: -1).validationError)
    }

    /// 9：全角数字・カンマ・「円」「¥」は読む
    func testAmountReadsFullwidthAndCommas() {
        XCTAssertEqual(RecurringExpenseInput.amount("８５，０００"), .success(85_000))
        XCTAssertEqual(RecurringExpenseInput.amount("85,000円"), .success(85_000))
        XCTAssertEqual(RecurringExpenseInput.amount("¥3,980"), .success(3_980))
        XCTAssertEqual(RecurringExpenseInput.amount(" 1200 "), .success(1_200))
    }

    /// 10：支払日は 1〜31 だけ。開始月は 2000年1月〜2099年12月
    func testDueDayAndStartMonth() {
        XCTAssertNil(template(dueDay: 1).validationError)
        XCTAssertNil(template(dueDay: 31).validationError)
        XCTAssertEqual(template(dueDay: 0).validationError, .invalidDueDay)
        XCTAssertEqual(template(dueDay: 32).validationError, .invalidDueDay)
        XCTAssertEqual(template(start: "1999-12").validationError, .invalidMonth)
        XCTAssertEqual(template(start: "2100-01").validationError, .invalidMonth)
        XCTAssertEqual(template(start: "2026-13").validationError, .invalidMonth)
        XCTAssertNil(template(start: "2000-01").validationError)
        XCTAssertNil(template(start: "2099-12").validationError)
    }

    /// 11：31日の設定は、2月には2月の最終日（2027年は28日）
    func testDayThirtyOneInFebruaryUsesLastDay() {
        let rent = template(dueDay: 31, start: "2026-01")
        XCTAssertEqual(day(rent.dueDate(in: BudgetMonth(year: 2027, month: 2)!)), 28)
        XCTAssertEqual(day(rent.dueDate(in: BudgetMonth(year: 2027, month: 1)!)), 31)
        XCTAssertEqual(day(template(dueDay: 29, start: "2026-01").dueDate(in: BudgetMonth(year: 2027, month: 2)!)), 28)
    }

    /// 12：うるう年の2月は29日
    func testLeapYearFebruary() {
        let rent = template(dueDay: 31, start: "2026-01")
        XCTAssertEqual(day(rent.dueDate(in: BudgetMonth(year: 2028, month: 2)!)), 29)
        XCTAssertEqual(day(template(dueDay: 29, start: "2026-01").dueDate(in: BudgetMonth(year: 2028, month: 2)!)), 29)
        XCTAssertEqual(day(rent.dueDate(in: BudgetMonth(year: 2100 - 4, month: 2)!)), 29, "2096年もうるう年")
    }

    /// 13：30日の月（4月・6月・9月・11月）は30日
    func testThirtyDayMonths() {
        let rent = template(dueDay: 31, start: "2026-01")
        for month in [4, 6, 9, 11] {
            XCTAssertEqual(day(rent.dueDate(in: BudgetMonth(year: 2026, month: month)!)), 30, "\(month)月")
        }
        XCTAssertEqual(day(template(dueDay: 30, start: "2026-01").dueDate(in: november)), 30)
    }

    /// 14：年末・年始（12月の次は翌年1月。月ごとに1件ずつ）
    func testYearEndAndNewYear() {
        let rent = template(dueDay: 31, start: "2026-12")
        let january = december.next
        XCTAssertEqual(january.key, "2027-01")
        let dec = RecurringExpenseSchedule.candidates(templates: [rent], occurrences: [:], month: december)
        let jan = RecurringExpenseSchedule.candidates(templates: [rent], occurrences: [:], month: january)
        XCTAssertEqual(dec.count, 1)
        XCTAssertEqual(jan.count, 1)
        XCTAssertEqual(LifeCalendar.calendar.component(.year, from: dec[0].dueDate), 2026)
        XCTAssertEqual(LifeCalendar.calendar.component(.year, from: jan[0].dueDate), 2027)
        XCTAssertEqual(day(dec[0].dueDate), 31)
        XCTAssertNotEqual(dec[0].id, jan[0].id, "月が違えば別の候補")
        XCTAssertEqual(jan[0].id, "\(rent.id.uuidString)_2027-01")
    }
}

// MARK: - 3. 候補（15〜19・31・32・36・37）

final class Build25RecurringCandidateTests: XCTestCase {
    /// 15：開始月より前の月には候補を出さない
    func testNoCandidatesBeforeStartMonth() {
        let device = makeDevice()
        XCTAssertNil(device.register(start: december))
        XCTAssertNil(device.candidate(.personal, month: november), "開始月（12月）より前")
        XCTAssertEqual(device.candidate(.personal, month: december)?.state, .unconfirmed)
        // 一覧には「開始前」として出す（編集できるように）
        device.money.displayedMonth = november
        XCTAssertEqual(device.money.recurringRows(for: .personal).map(\.stateText), ["2026年12月から"])
    }

    /// 16：停止中は新しい候補を出さない（一覧には「停止中」と文字で出す）
    func testNoCandidatesWhilePaused() throws {
        let device = makeDevice()
        XCTAssertNil(device.register())
        let saved = try XCTUnwrap(device.templates(.personal).first)
        XCTAssertNil(device.money.pauseRecurring(saved))
        XCTAssertNil(device.candidate(.personal, month: november))
        XCTAssertNil(device.candidate(.personal, month: december))
        XCTAssertEqual(device.money.recurringRows(for: .personal).map(\.stateText), ["停止中"])
        XCTAssertTrue(device.today().recurringToReview.isEmpty, "今日の画面にも出さない")
    }

    /// 17：再開したら、再開した月から候補を出す（止めていたあいだの月の候補は出さない）
    func testCandidatesResumeFromResumeMonth() throws {
        let device = makeDevice()
        XCTAssertNil(device.register(start: BudgetMonth(year: 2026, month: 8)!))
        let saved = try XCTUnwrap(device.templates(.personal).first)
        XCTAssertNil(device.money.pauseRecurring(saved))
        let paused = try XCTUnwrap(device.templates(.personal).first)
        XCTAssertNil(device.money.resumeRecurring(paused))
        let resumed = try XCTUnwrap(device.templates(.personal).first)
        XCTAssertTrue(resumed.isActive)
        XCTAssertEqual(resumed.startMonthKey, "2026-11", "再開した月（今月）から")
        XCTAssertNil(device.candidate(.personal, month: october), "止めていたあいだの月は出さない")
        XCTAssertEqual(device.candidate(.personal, month: november)?.state, .unconfirmed)
        XCTAssertEqual(device.candidate(.personal, month: december)?.state, .unconfirmed)
        // 開始月が先の設定は、再開しても開始月のまま
        XCTAssertNil(device.register("来年の保険", start: BudgetMonth(year: 2027, month: 4)!))
        let later = try XCTUnwrap(device.templates(.personal).first { $0.title == "来年の保険" })
        XCTAssertNil(device.money.pauseRecurring(later))
        XCTAssertNil(device.money.resumeRecurring(try XCTUnwrap(device.recordedTemplate(later.id))))
        XCTAssertEqual(device.recordedTemplate(later.id)?.startMonthKey, "2027-04")
    }

    /// 18：候補は支出ではない（予算・カテゴリー・今月の合計・検索に入れない）
    func testCandidatesAreNotExpenses() {
        let device = makeDevice()
        XCTAssertNil(device.register("動画サブスク", amount: "1490", category: .subscription))
        XCTAssertEqual(device.candidate(.personal)?.state, .unconfirmed)
        XCTAssertEqual(device.money.spent, 0)
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 0)
        XCTAssertTrue(device.money.categoryTotals.isEmpty)
        XCTAssertTrue(device.money.expenses.isEmpty)
        device.money.searchText = "動画サブスク"
        XCTAssertTrue(device.money.searchResults.isEmpty, "検索に入れない")
        XCTAssertEqual(device.today().monthSpending, 0, "今日の画面の MONEY にも入れない")
    }

    /// 19・35：保存したあとだけ支出になり、予算・カテゴリー別・今日の MONEY・検索に入る
    func testIncludedOnlyAfterSave() throws {
        let device = makeDevice()
        device.store.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 100_000, categoryAmounts: [.subscription: 5_000]), for: november, scope: .personal)
        XCTAssertNil(device.register("動画サブスク", amount: "1490", category: .subscription, dueDay: 20))
        let candidate = try XCTUnwrap(device.candidate(.personal))
        device.money.startRecurringExpense(candidate)
        let draft = try XCTUnwrap(device.money.draft)
        XCTAssertEqual(draft.title, "動画サブスク", "名前・金額・カテゴリー・支払予定日・保存先を入れておく")
        XCTAssertEqual(draft.amount, 1490)
        XCTAssertEqual(draft.category, .subscription)
        XCTAssertEqual(day(draft.date), 20)
        XCTAssertEqual(draft.destination, .personal)
        XCTAssertEqual(device.money.spent, 0, "確認画面を開いただけでは支出にならない")
        device.money.cancelEditing()
        XCTAssertTrue(device.store.expenses.isEmpty, "キャンセルなら作らない")
        XCTAssertEqual(device.candidate(.personal)?.state, .unconfirmed)
        XCTAssertTrue(device.addThisMonth(.personal))
        XCTAssertEqual(device.store.expenses.count, 1)
        XCTAssertEqual(device.candidate(.personal)?.state, .created, "追加済み")
        XCTAssertEqual(device.money.spent, 1490)
        let summary = device.money.budgetSummary(for: .personal)
        XCTAssertEqual(summary.spent, 1490)
        XCTAssertEqual(summary.remaining, 100_000 - 1490)
        XCTAssertEqual(summary.categoryLines.first { $0.category == .subscription }?.spent, 1490)
        XCTAssertEqual(device.today().monthSpending, 1490)
        device.money.searchText = "動画サブスク"
        XCTAssertEqual(device.money.searchResults.count, 1)
    }

    /// 31・32：表示の範囲（すべて・自分・共有）。「すべて」でも同じ候補・同じ支出は1回だけ
    func testScopesAndNoDuplicatesInAll() {
        let device = makeDevice()
        XCTAssertNil(device.register("携帯代", amount: "3980", destination: .personal))
        XCTAssertNil(device.register("家賃", amount: "85000", destination: .household))
        device.money.scope = .all
        XCTAssertEqual(device.money.recurringScopes, [.personal, .household], "自分だけ・わが家で共有を分けて出す")
        XCTAssertEqual(device.money.recurringRows(for: .personal).map(\.template.title), ["携帯代"])
        XCTAssertEqual(device.money.recurringRows(for: .household).map(\.template.title), ["家賃"])
        device.money.scope = .mine
        XCTAssertEqual(device.money.recurringScopes, [.personal])
        device.money.scope = .shared
        XCTAssertEqual(device.money.recurringScopes, [.household])
        device.money.scope = .all
        XCTAssertTrue(device.addThisMonth(.personal))
        XCTAssertTrue(device.addThisMonth(.household))
        XCTAssertEqual(device.money.expenses.count, 2, "「すべて」でも1件ずつ")
        XCTAssertEqual(Set(device.money.expenses.map(\.id)).count, 2)
        XCTAssertEqual(device.money.recurringCandidates(for: .personal).count, 1)
        XCTAssertEqual(device.money.recurringCandidates(for: .household).count, 1)
        // 一人で使う設定は自分だけ
        let solo = makeDevice(usageStyle: .solo)
        XCTAssertEqual(solo.money.recurringScopes, [.personal])
        XCTAssertFalse(solo.money.canChooseHouseholdRecurring)
    }

    /// 36：支出の日付の月で数える（11月分を11月の中で日付を変えても11月の予算に入る）
    func testCountedInMonthOfExpenseDate() {
        let device = makeDevice()
        XCTAssertNil(device.register(dueDay: 27))
        XCTAssertTrue(device.addThisMonth(.personal) { draft in
            draft.date = TestDates.make(2026, 11, 3)
            draft.amountText = "86,000"
        })
        let saved = device.store.expenses.first
        XCTAssertEqual(saved?.amount, 86_000, "金額は確認画面で直せる")
        XCTAssertEqual(saved.map { day($0.date) }, 3)
        device.money.displayedMonth = november
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 86_000)
        device.money.displayedMonth = december
        XCTAssertEqual(device.money.budgetSummary(for: .personal).spent, 0)
    }

    /// 37：対象の月の外の日付は保存しない（理由を出す。支出も追加済みも作らない）
    func testDateOutsideTargetMonthIsNotSaved() {
        let device = makeDevice()
        XCTAssertNil(device.register())
        XCTAssertFalse(device.addThisMonth(.personal) { draft in
            draft.date = TestDates.make(2026, 12, 1)
        })
        XCTAssertEqual(device.money.draftMessage, RecurringExpenseError.dateOutsideMonth(november).message)
        XCTAssertTrue(device.money.draftMessage?.contains("2026年11月") == true)
        XCTAssertTrue(device.store.expenses.isEmpty)
        XCTAssertEqual(device.candidate(.personal)?.state, .unconfirmed)
        XCTAssertFalse(device.addThisMonth(.personal) { draft in draft.date = TestDates.make(2026, 10, 31) })
        XCTAssertTrue(device.store.expenses.isEmpty)
        // 範囲（DatePicker の選べる日）は対象の月の1日〜最終日
        let range = november.dayRange()
        XCTAssertEqual(day(range.lowerBound), 1)
        XCTAssertEqual(day(range.upperBound), 30)
    }
}

// MARK: - 4. 重複を防ぐ（20〜24）

final class Build25RecurringDuplicateTests: XCTestCase {
    /// 20：自分だけ：保存を2回押しても支出は1件だけ（同じ月の2回目は断る）
    func testPersonalDoublePressCreatesOneExpense() throws {
        let device = makeDevice()
        XCTAssertNil(device.register())
        let candidate = try XCTUnwrap(device.candidate(.personal))
        device.money.startRecurringExpense(candidate)
        let draft = try XCTUnwrap(device.money.draft)
        XCTAssertTrue(device.money.save(draft))
        XCTAssertFalse(device.money.save(draft), "2回目")
        XCTAssertEqual(device.store.expenses.count, 1)
        // 同じ月をもう一度開いても（別の支出 ID でも）作らない
        let template = try XCTUnwrap(device.templates(.personal).first)
        let another = Expense(title: "家賃", amount: 85_000, category: .other, date: TestDates.make(2026, 11, 27))
        XCTAssertEqual(device.store.addRecurringExpense(another, templateID: template.id, month: november), .alreadyProcessed)
        XCTAssertEqual(device.store.expenses.count, 1)
        device.money.startRecurringExpense(try XCTUnwrap(device.candidate(.personal)))
        XCTAssertNil(device.money.draft, "追加済みの月は確認画面を開かない")
    }

    /// 21：わが家で共有：2台で同時に「今月分を追加」しても、支出は1件だけ（2台目は断られ、追加済みになる）
    func testSharedSimultaneousPressesCreateOneExpense() throws {
        let cloud = Build25Cloud()
        let alice = makeDevice(cloud: cloud, uid: "alice")
        let bob = makeDevice(cloud: cloud, uid: "bob", joined: household(isOwner: false))
        XCTAssertNil(alice.register(destination: .household))
        XCTAssertEqual(bob.candidate(.household)?.state, .unconfirmed, "パートナーにも候補が出る")
        cloud.holdsCommits = true
        XCTAssertTrue(alice.addThisMonth(.household))
        XCTAssertTrue(bob.addThisMonth(.household))
        XCTAssertEqual(cloud.heldCommits.count, 2, "どちらもサーバーに届く前に送った")
        cloud.releaseHeldCommits()
        XCTAssertEqual(cloud.expenseList("group-build25").count, 1, "わが家の支出は1件だけ")
        XCTAssertEqual(cloud.occurrenceList("group-build25").count, 1)
        XCTAssertEqual(cloud.batchCount, 1)
        for device in [alice, bob] {
            XCTAssertEqual(device.store.householdExpenses.count, 1, "どちらの画面でも1件")
            XCTAssertEqual(device.candidate(.household)?.state, .created, "どちらの画面でも追加済み")
            XCTAssertTrue(device.store.expenses.isEmpty, "自分だけの支出にもならない")
        }
        XCTAssertNotNil(bob.service.notice, "断られたことを日本語で知らせる")
        XCTAssertTrue(bob.service.notice?.contains("支出は作っていません") == true)
    }

    /// 22：共有の支出と「追加済み」は1回の書き込みで一緒に送る（決まった項目だけ）
    func testSharedWriteSendsExpenseAndOccurrenceTogether() throws {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.register(destination: .household))
        let templateFields = try XCTUnwrap(device.recurring.sentTemplateFields.first)
        XCTAssertEqual(Set(templateFields.keys), Set(SharedRecurringExpensePayload.templateFieldNames), "11項目")
        XCTAssertEqual(SharedRecurringExpensePayload.templateFieldNames.count, 11)
        XCTAssertEqual(templateFields["createdBy"], .currentUser)
        XCTAssertEqual(templateFields["createdAt"], .serverTimestamp)
        XCTAssertEqual(templateFields["title"], .string("家賃"))
        XCTAssertEqual(templateFields["expectedAmount"], .int(85_000))
        XCTAssertTrue(device.addThisMonth(.household))
        XCTAssertEqual(cloud.batchCount, 1, "1回の書き込み")
        XCTAssertEqual(device.recurring.sentExpenseFields.count, 1)
        XCTAssertEqual(device.expenses.creates.count, 0, "ふつうの共有の支出の作成は使わない（失敗したときに自分だけへ回さないため）")
        let occurrenceFields = try XCTUnwrap(device.recurring.sentOccurrenceFields.last)
        XCTAssertEqual(Set(occurrenceFields.keys), Set(SharedRecurringExpensePayload.occurrenceFieldNames), "7項目")
        XCTAssertEqual(SharedRecurringExpensePayload.occurrenceFieldNames.count, 7)
        XCTAssertEqual(occurrenceFields["status"], .string("created"))
        XCTAssertEqual(occurrenceFields["monthKey"], .string("2026-11"))
        let expenseID = try XCTUnwrap(device.store.householdExpenses.first?.id)
        XCTAssertEqual(occurrenceFields["expenseID"], .string(expenseID.uuidString))
        XCTAssertEqual(occurrenceFields["processedBy"], .currentUser)
        XCTAssertEqual(occurrenceFields["processedAt"], .serverTimestamp)
        let expenseFields = try XCTUnwrap(device.recurring.sentExpenseFields.first)
        XCTAssertEqual(Set(expenseFields.keys), ["schemaVersion", "title", "amount", "category", "date", "createdBy", "updatedBy", "createdAt", "updatedAt"], "ふつうの共有の支出と同じ形")
        XCTAssertEqual(cloud.occurrences["group-build25"]?.keys.first, "\(device.templates(.household)[0].id.uuidString)_2026-11", "文書の ID は設定の ID と月")
    }

    /// 23・24：共有の保存が断られたら、支出は作らない・自分だけにも変えない。候補は未確認のまま（理由を出す）
    func testSharedFailureCreatesNothingAndKeepsCandidate() throws {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.register(destination: .household))
        cloud.failure = .unavailable
        XCTAssertTrue(device.addThisMonth(.household), "確認画面は閉じる（結果はあとで届く）")
        XCTAssertTrue(device.store.householdExpenses.isEmpty, "共有の支出を作らない")
        XCTAssertTrue(device.store.expenses.isEmpty, "自分だけの支出にもしない")
        XCTAssertEqual(device.candidate(.household)?.state, .unconfirmed, "候補は未確認のまま")
        XCTAssertTrue(device.service.notice?.contains("支出は作っていません") == true)
        XCTAssertTrue(cloud.expenses.isEmpty && cloud.occurrences.isEmpty)
        // 送信中（結果待ち）は追加済みに見え、同じ月を2回押せない。断られたら未確認に戻る
        cloud.failure = nil
        cloud.holdsCommits = true
        XCTAssertTrue(device.addThisMonth(.household))
        XCTAssertEqual(device.candidate(.household)?.state, .created)
        XCTAssertFalse(device.addThisMonth(.household), "結果待ちのあいだに2回目は押せない")
        cloud.failure = .permissionDenied
        cloud.releaseHeldCommits()
        XCTAssertEqual(device.candidate(.household)?.state, .unconfirmed)
        XCTAssertTrue(device.store.householdExpenses.isEmpty)
        XCTAssertTrue(device.store.expenses.isEmpty)
        // 家計簿の共有がオフなら、そもそも作らない（自分だけに回さない）
        cloud.failure = nil
        device.service.apply(household: household(kinds: [.todo]), isSignedIn: true)
        XCTAssertFalse(device.money.canAddRecurring(try XCTUnwrap(device.candidate(.household))))
        let template = try XCTUnwrap(device.templates(.household).first)
        let expense = Expense(title: "家賃", amount: 85_000, category: .other, date: TestDates.make(2026, 11, 27), ownership: .shared)
        XCTAssertEqual(device.store.addRecurringExpense(expense, templateID: template.id, month: november), .notEditable(ExpenseSharingBlock.moneyOff.recurringMessage))
        XCTAssertTrue(device.store.expenses.isEmpty)
    }
}

// MARK: - 5. 今月は追加しない・追加済み・停止（25〜30）

final class Build25RecurringSkipAndPauseTests: XCTestCase {
    /// 25・26：「今月は追加しない」は確認してから。支出は作らない。「未確認に戻す」で取り消せる（パートナーにも届く）
    func testSkipAndUndo() throws {
        let cloud = Build25Cloud()
        let alice = makeDevice(cloud: cloud, uid: "alice")
        let bob = makeDevice(cloud: cloud, uid: "bob", joined: household(isOwner: false))
        XCTAssertNil(alice.register(destination: .household))
        let candidate = try XCTUnwrap(alice.candidate(.household))
        alice.money.confirmRecurringSkip(candidate)
        XCTAssertEqual(alice.money.pendingRecurringSkip, candidate, "すぐには変えず、確認を出す")
        XCTAssertEqual(alice.candidate(.household)?.state, .unconfirmed)
        XCTAssertNil(alice.money.skipRecurring(candidate))
        XCTAssertNil(alice.money.pendingRecurringSkip)
        XCTAssertEqual(alice.candidate(.household)?.state, .skipped)
        XCTAssertEqual(bob.candidate(.household)?.state, .skipped, "パートナーにも届く")
        XCTAssertTrue(cloud.expenses.isEmpty, "支出は作らない")
        XCTAssertEqual(alice.money.budgetSummary(for: .household).spent, 0)
        XCTAssertTrue(alice.today().recurringToReview.isEmpty, "今日の画面にも出さない")
        // パートナーが未確認に戻す
        let skipped = try XCTUnwrap(bob.candidate(.household))
        XCTAssertNil(bob.money.undoRecurringSkip(skipped))
        XCTAssertEqual(bob.candidate(.household)?.state, .unconfirmed)
        XCTAssertEqual(alice.candidate(.household)?.state, .unconfirmed)
        // 自分だけでも同じ
        XCTAssertNil(alice.register("携帯代", destination: .personal))
        let personal = try XCTUnwrap(alice.candidate(.personal))
        XCTAssertNil(alice.money.skipRecurring(personal))
        XCTAssertEqual(alice.candidate(.personal)?.state, .skipped)
        XCTAssertNil(alice.money.undoRecurringSkip(try XCTUnwrap(alice.candidate(.personal))))
        XCTAssertEqual(alice.candidate(.personal)?.state, .unconfirmed)
    }

    /// 27・28：追加済みは未確認に戻せない。作った支出を消しても候補は戻らない（二重に登録しない）
    func testCreatedCannotBeUndoneAndDeletingExpenseDoesNotRestoreCandidate() throws {
        let device = makeDevice()
        XCTAssertNil(device.register())
        XCTAssertTrue(device.addThisMonth(.personal))
        let created = try XCTUnwrap(device.candidate(.personal))
        XCTAssertEqual(device.money.undoRecurringSkip(created), .cannotUndoCreated)
        XCTAssertEqual(device.candidate(.personal)?.state, .created)
        XCTAssertFalse(RecurringExpenseError.cannotUndoCreated.message.isEmpty)
        let expenseID = try XCTUnwrap(device.store.expenses.first?.id)
        XCTAssertTrue(device.store.deleteExpense(expenseID))
        XCTAssertTrue(device.store.expenses.isEmpty)
        XCTAssertEqual(device.candidate(.personal)?.state, .created, "支出を消しても追加済みのまま")
        XCTAssertFalse(device.addThisMonth(.personal))
        XCTAssertTrue(device.store.expenses.isEmpty)
        // 共有でも同じ
        let cloud = Build25Cloud()
        let shared = makeDevice(cloud: cloud)
        XCTAssertNil(shared.register(destination: .household))
        XCTAssertTrue(shared.addThisMonth(.household))
        XCTAssertEqual(shared.money.undoRecurringSkip(try XCTUnwrap(shared.candidate(.household))), .cannotUndoCreated)
        XCTAssertTrue(shared.recurring.deletes.isEmpty, "追加済みを消しに行かない")
    }

    /// 29：設定を編集しても、作った支出は変わらない（未確認の月と先の候補にだけ反映）
    func testTemplateEditDoesNotChangePastExpenses() throws {
        let device = makeDevice()
        XCTAssertNil(device.register(amount: "85000"))
        XCTAssertTrue(device.addThisMonth(.personal))
        let template = try XCTUnwrap(device.templates(.personal).first)
        device.money.startEditingRecurring(template)
        var draft = try XCTUnwrap(device.money.recurringDraft)
        XCTAssertFalse(draft.isNew)
        draft.amountText = "90,000"
        draft.title = "家賃（更新後）"
        XCTAssertNil(device.money.saveRecurring(draft))
        XCTAssertEqual(device.store.expenses.first?.amount, 85_000, "作った支出は変わらない")
        XCTAssertEqual(device.store.expenses.first?.title, "家賃")
        XCTAssertEqual(device.candidate(.personal, month: november)?.state, .created)
        XCTAssertEqual(device.candidate(.personal, month: december)?.template.expectedAmount, 90_000, "先の候補には反映")
        device.money.startRecurringExpense(try XCTUnwrap(device.candidate(.personal, month: december)))
        XCTAssertEqual(device.money.draft?.amount, 90_000)
        XCTAssertEqual(device.money.draft?.title, "家賃（更新後）")
        // 保存先はあとから変えない（案内を出す）
        device.money.cancelEditing()
        device.money.startEditingRecurring(try XCTUnwrap(device.templates(.personal).first))
        var moved = try XCTUnwrap(device.money.recurringDraft)
        XCTAssertTrue(device.money.recurringDestinationNote(for: moved).contains("停止して、新しく作って"))
        moved.destination = .household
        XCTAssertNil(device.money.saveRecurring(moved))
        XCTAssertEqual(device.templates(.personal).count, 1, "保存先は自分だけのまま")
        XCTAssertTrue(device.templates(.household).isEmpty)
        let sharedCopy = RecurringExpenseTemplate(id: moved.id, title: "家賃", expectedAmount: 1, category: .other, dueDay: 1,
                                                  startMonthKey: "2026-11", isActive: true, ownership: .shared)
        XCTAssertEqual(device.store.saveRecurringTemplate(sharedCopy), .notEditable("保存先は変えられません。"))
    }

    /// 30：停止しても、作った支出・追加済み・今月は追加しないの記録は消さない
    func testPauseKeepsPastExpensesAndRecords() throws {
        let device = makeDevice()
        XCTAssertNil(device.register(start: october))
        XCTAssertTrue(device.addThisMonth(.personal, month: october))
        let november = try XCTUnwrap(device.candidate(.personal, month: Build25Month.november))
        XCTAssertNil(device.money.skipRecurring(november))
        XCTAssertNil(device.money.pauseRecurring(try XCTUnwrap(device.templates(.personal).first)))
        XCTAssertEqual(device.store.expenses.count, 1, "作った支出は消さない")
        XCTAssertEqual(device.candidate(.personal, month: october)?.state, .created, "記録は残る")
        XCTAssertEqual(device.candidate(.personal, month: Build25Month.november)?.state, .skipped)
        XCTAssertNil(device.candidate(.personal, month: december), "新しい月の候補は出さない")
        device.money.displayedMonth = october
        XCTAssertEqual(device.money.recurringRows(for: .personal).first?.stateText, "追加済み（停止中）")
        XCTAssertEqual(device.store.recurringOccurrences(scope: .personal).count, 2)
    }
}

/// 同じ名前の引数とぶつからないように月を呼ぶ
private enum Build25Month {
    static let november = BudgetMonth(year: 2026, month: 11)!
}

private extension Build25Device {
    func recordedTemplate(_ id: UUID) -> RecurringExpenseTemplate? {
        store.recurringTemplate(id: id)
    }
}

// MARK: - 6. わが家で共有（3〜6・39〜42）

final class Build25RecurringSharingTests: XCTestCase {
    /// 3・4：共有の設定はパートナーに届き、パートナーも編集・停止・再開できる
    func testSharedTemplateReachesPartnerWhoCanEdit() throws {
        let cloud = Build25Cloud()
        let alice = makeDevice(cloud: cloud, uid: "alice")
        let bob = makeDevice(cloud: cloud, uid: "bob", joined: household(isOwner: false))
        XCTAssertNil(alice.register("家賃", amount: "85000", destination: .household))
        let received = try XCTUnwrap(bob.templates(.household).first)
        XCTAssertEqual(received.title, "家賃")
        XCTAssertEqual(received.expectedAmount, 85_000)
        XCTAssertTrue(received.isShared)
        XCTAssertTrue(bob.money.canActOnRecurring(received))
        bob.money.startEditingRecurring(received)
        var draft = try XCTUnwrap(bob.money.recurringDraft)
        draft.amountText = "86000"
        XCTAssertNil(bob.money.saveRecurring(draft))
        XCTAssertEqual(alice.templates(.household).first?.expectedAmount, 86_000, "パートナーの編集が届く")
        XCTAssertNil(bob.money.pauseRecurring(try XCTUnwrap(bob.templates(.household).first)))
        XCTAssertEqual(alice.templates(.household).first?.isActive, false)
        XCTAssertNil(alice.candidate(.household))
        XCTAssertNil(alice.money.resumeRecurring(try XCTUnwrap(alice.templates(.household).first)))
        XCTAssertEqual(bob.templates(.household).first?.isActive, true)
        XCTAssertEqual(bob.candidate(.household)?.state, .unconfirmed)
        // 編集のときは作成者・作成日時を送らない（変えない）
        let update = try XCTUnwrap(bob.recurring.sentTemplateFields.first)
        XCTAssertNil(update["createdBy"])
        XCTAssertNil(update["createdAt"])
        XCTAssertNil(update["schemaVersion"])
        XCTAssertEqual(update["updatedBy"], .currentUser)
        XCTAssertEqual(update["updatedAt"], .serverTimestamp)
    }

    /// 3：共有の保存が断られたら、元の内容に戻す（新しい設定は消す）
    func testSharedTemplateFailureRestores() throws {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud)
        cloud.failure = .permissionDenied
        XCTAssertNil(device.register(destination: .household))
        XCTAssertTrue(device.templates(.household).isEmpty, "作れなかった設定は残さない")
        XCTAssertNotNil(device.service.notice)
        cloud.failure = nil
        XCTAssertNil(device.register(destination: .household))
        let saved = try XCTUnwrap(device.templates(.household).first)
        cloud.failure = .unavailable
        var edited = saved
        edited.expectedAmount = 1
        XCTAssertNil(device.store.saveRecurringTemplate(edited))
        XCTAssertEqual(device.templates(.household).first?.expectedAmount, 85_000, "元に戻す")
    }

    /// 5・6：わが家に入っていない・サインインしていない・一人で使う設定では、共有の定期支出を作れない（理由を出す）
    func testNonMembersCannotUseSharedRecurring() {
        let notJoined = makeDevice(joined: nil)
        XCTAssertFalse(notJoined.money.canChooseHouseholdRecurring)
        XCTAssertEqual(notJoined.register(destination: .household), .notEditable(ExpenseSharingBlock.notJoined.recurringMessage))
        XCTAssertTrue(notJoined.templates(.household).isEmpty)
        XCTAssertEqual(notJoined.recurring.writeCount, 0)
        XCTAssertEqual(notJoined.recurring.listenCount, 0, "見張りも始めない")
        let solo = makeDevice(usageStyle: .solo)
        XCTAssertEqual(solo.register(destination: .household), .notEditable(ExpenseSharingBlock.soloMode.recurringMessage))
        XCTAssertFalse(ExpenseSharingBlock.soloMode.recurringMessage.contains("自分だけに保存します"), "定期支出は自分だけに切り替えない")
        XCTAssertFalse(ExpenseSharingBlock.notConnected.recurringMessage.contains("自分だけに保存します"))
        // 別のわが家の記録は見えない（見張るのは自分のわが家だけ）
        let cloud = Build25Cloud()
        let other = makeDevice(cloud: cloud, uid: "mallory", joined: household("group-other"))
        let alice = makeDevice(cloud: cloud, uid: "alice")
        XCTAssertNil(alice.register(destination: .household))
        XCTAssertTrue(other.templates(.household).isEmpty)
        let signedOut = SharedExpensesService(backend: FakeSharedExpensesBackend(), recurringBackend: Build25RecurringBackend(cloud: cloud, uid: "x"))
        let store = LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
        signedOut.attach(store)
        signedOut.apply(household: household(), isSignedIn: false)
        XCTAssertTrue(store.recurringTemplates(scope: .household).isEmpty)
        XCTAssertNotNil(store.householdRecurringBlock)
    }

    /// 家計簿の共有がオフ：新しく作れない。すでにある設定は編集・停止できる
    func testMoneyOffBlocksCreateButAllowsEdit() throws {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.register(destination: .household))
        device.service.apply(household: household(kinds: [.todo, .shopping]), isSignedIn: true)
        XCTAssertFalse(device.money.canChooseHouseholdRecurring)
        XCTAssertEqual(device.register("新しい保険", destination: .household), .notEditable(ExpenseSharingBlock.moneyOff.recurringMessage))
        let saved = try XCTUnwrap(device.templates(.household).first)
        XCTAssertNil(device.money.pauseRecurring(saved), "すでにある設定は変えられる")
        XCTAssertEqual(cloud.templateList("group-build25").first?.isActive, false)
    }

    /// 39：見張りは設定・状態で1つずつ（わが家の情報が何度届いても・画面を開き直しても増えない）
    func testListenersDoNotIncrease() {
        let device = makeDevice()
        for _ in 0..<5 { device.service.apply(household: household(), isSignedIn: true) }
        _ = (0..<10).map { _ in MoneyViewModel(store: device.store, appState: device.appState, now: build25Now).recurringRows(for: .household) }
        _ = (0..<10).map { _ in device.today().recurringToReview }
        XCTAssertEqual(device.recurring.listenCount, 2, "設定と状態で1つずつ")
        XCTAssertEqual(device.recurring.activeListenerCount, 2)
        XCTAssertEqual(device.service.activeRecurringListenerCount, 2)
    }

    /// 40：サインアウト・退出・わが家の削除で見張りをやめ、共有の定期支出の表示を消す（自分だけの定期支出は残す）
    func testListenersRemovedOnSignOutLeaveAndDelete() {
        let cloud = Build25Cloud()
        let device = makeDevice(cloud: cloud)
        XCTAssertNil(device.register("携帯代", destination: .personal))
        XCTAssertNil(device.register("家賃", destination: .household))
        XCTAssertNil(device.money.skipRecurring(device.money.recurringCandidates(for: .household)[0]))
        // サインアウト
        device.service.apply(household: household(), isSignedIn: false)
        XCTAssertEqual(device.recurring.activeListenerCount, 0)
        XCTAssertEqual(device.service.activeRecurringListenerCount, 0)
        XCTAssertTrue(device.templates(.household).isEmpty)
        XCTAssertTrue(device.store.recurringOccurrences(scope: .household).isEmpty)
        XCTAssertEqual(device.templates(.personal).map(\.title), ["携帯代"], "自分だけの定期支出は残す")
        // また参加したら1つずつ
        device.service.apply(household: household(), isSignedIn: true)
        XCTAssertEqual(device.recurring.activeListenerCount, 2)
        XCTAssertEqual(device.templates(.household).map(\.title), ["家賃"])
        // 退出・わが家の削除（わが家が無くなる）
        device.service.apply(household: nil, isSignedIn: true)
        XCTAssertEqual(device.recurring.activeListenerCount, 0)
        XCTAssertTrue(device.templates(.household).isEmpty)
        XCTAssertEqual(device.templates(.personal).count, 1)
        // 権限が無くなった（メンバーでなくなった）ときも消す
        device.service.apply(household: household(), isSignedIn: true)
        device.store.clearHouseholdRecurringExpenses()
        XCTAssertTrue(device.templates(.household).isEmpty)
    }
}

// MARK: - 7. 今日の画面（33・34・43）

final class Build25RecurringTodayTests: XCTestCase {
    /// 33：今月の未確認で、支払日を過ぎた・今日・7日以内のものだけ（件数だけを出す。名前・金額は出さない）
    func testTodayShowsOnlyCurrentMonthDueSoon() throws {
        let device = makeDevice()
        XCTAssertNil(device.register("過ぎた", dueDay: 10))
        XCTAssertNil(device.register("今日", dueDay: 20))
        XCTAssertNil(device.register("7日後", dueDay: 27))
        XCTAssertNil(device.register("8日後", dueDay: 28))
        XCTAssertNil(device.register("来月から", dueDay: 1, start: december))
        let today = device.today()
        XCTAssertEqual(Set(today.recurringToReview.map(\.template.title)), ["過ぎた", "今日", "7日後"])
        let text = try XCTUnwrap(today.recurringReviewText)
        XCTAssertEqual(text, "未確認 3件・支払日を過ぎた 1件・今日が支払日 1件")
        for word in ["円", "85", "7日後", "8日後"] {
            XCTAssertFalse(text.contains(word), "名前・金額は出さない：\(word)")
        }
        // 追加済み・今月は追加しないにしたら出さない
        XCTAssertTrue(device.addThisMonth(.personal) { _ in })
        let skipTarget = try XCTUnwrap(device.money.recurringCandidates(for: .personal).first { $0.state == .unconfirmed })
        XCTAssertNil(device.money.skipRecurring(skipTarget))
        XCTAssertEqual(device.today().recurringToReview.count, 1)
        // 月末から見た翌月の候補は出さない（今月だけ）
        let monthEnd = device.today(now: TestDates.make(2026, 11, 28, 9, 0))
        XCTAssertFalse(monthEnd.recurringToReview.contains { $0.month != november })
        // 何も無ければ出さない
        XCTAssertNil(makeDevice().today().recurringReviewText)
    }

    /// 34：タップで「お金」の画面を開く。自動で保存しない
    func testTodayOpensMoney() {
        let device = makeDevice()
        XCTAssertNil(device.register(dueDay: 20))
        device.appState.selectedTab = .today
        let today = device.today()
        XCTAssertNotNil(today.recurringReviewText)
        today.openMoney()
        XCTAssertEqual(device.appState.selectedTab, .money)
        XCTAssertTrue(device.store.expenses.isEmpty, "自動で支出を作らない")
        XCTAssertTrue(device.store.recurringOccurrences(scope: .personal).isEmpty)
    }

    /// 43：プッシュ通知・ローカル通知・通知の許可を使わない（Functions も変えない）
    func testNoNotifications() throws {
        for path in [
            "LifeOS/Core/Models/RecurringExpense.swift",
            "LifeOS/Core/Sharing/SharedRecurringExpenses.swift",
            "LifeOS/Core/Sharing/FirestoreSharedRecurringExpensesBackend.swift",
            "LifeOS/Features/Money/RecurringExpenseViews.swift",
            "LifeOS/Features/Today/TodayViewModel.swift",
            "LifeOS/Features/Today/TodayView.swift"
        ] {
            let code = build25CodeOnly(try build25Source(path))
            for word in ["UNUserNotificationCenter", "requestAuthorization", "UNNotificationRequest", "UNCalendarNotificationTrigger",
                         "registerForRemoteNotifications", "Messaging.messaging"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        let functions = try build25Source("firebase/functions/index.js")
        XCTAssertFalse(functions.contains("recurringExpense"), "Functions は定期支出を扱わない")
        let view = build25CodeOnly(try build25Source("LifeOS/Features/Today/TodayView.swift"))
        XCTAssertTrue(view.contains("viewModel.openMoney()"))
    }
}

// MARK: - 8. ログ・画面・既存機能（44・46〜50）

final class Build25RecurringSafetyTests: XCTestCase {
    /// 44：名前・金額・UID・グループの ID をログに出さない。Analytics・Crashlytics・外部の通信を足さない
    func testNoLoggingOrAnalytics() throws {
        for path in [
            "LifeOS/Core/Models/RecurringExpense.swift",
            "LifeOS/Core/Sharing/SharedRecurringExpenses.swift",
            "LifeOS/Core/Sharing/FirestoreSharedRecurringExpensesBackend.swift",
            "LifeOS/Core/Sharing/SharedExpenses.swift",
            "LifeOS/Core/Store/LifeStore.swift",
            "LifeOS/Features/Money/RecurringExpenseViews.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift",
            "LifeOS/Features/Today/TodayView.swift",
            "LifeOS/Features/Today/TodayViewModel.swift"
        ] {
            let code = build25CodeOnly(try build25Source(path))
            for word in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "Analytics", "Crashlytics", "URLSession", "URLRequest"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        let backend = build25CodeOnly(try build25Source("LifeOS/Core/Sharing/FirestoreSharedRecurringExpensesBackend.swift"))
        XCTAssertFalse(backend.contains("localizedDescription"), "エラーの中身を出さない")
        XCTAssertTrue(backend.contains("FirestoreAccessGate.shared.whenOpen"))
        XCTAssertTrue(backend.contains("self.db.batch()"), "共有の支出と追加済みは1回の書き込み")
        let project = try build25Source("LifeOS.xcodeproj/project.pbxproj")
        let products = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("productName = Firebase") }
        XCTAssertEqual(products.count, 6, "Firebase の部品を足していない")
    }

    /// 送るのは決まった項目だけ（メール・表示名・端末・トークン・レシート・明細・自分だけの定期支出は送らない）
    func testPayloadSendsOnlyFixedFields() {
        let shared = template(ownership: .shared)
        let fields = SharedRecurringExpensePayload.createTemplateFields(for: shared) ?? [:]
        XCTAssertEqual(Set(fields.keys), Set(SharedRecurringExpensePayload.templateFieldNames))
        for word in ["email", "displayName", "device", "token", "receipt", "lineItems", "memo", "ownership"] {
            XCTAssertNil(fields[word], word)
        }
        XCTAssertNil(SharedRecurringExpensePayload.createTemplateFields(for: template(ownership: .personal)), "自分だけの設定は送らない")
        XCTAssertNil(SharedRecurringExpensePayload.createTemplateFields(for: template(amount: 0, ownership: .shared)), "正しくない設定は送らない")
        let skipped = RecurringOccurrence(templateID: shared.id, monthKey: "2026-11", status: .skipped, expenseID: nil)
        XCTAssertEqual(SharedRecurringExpensePayload.occurrenceFields(for: skipped)?["expenseID"], .null)
        XCTAssertNil(SharedRecurringExpensePayload.occurrenceFields(for: RecurringOccurrence(templateID: shared.id, monthKey: "2026-11", status: .created, expenseID: nil)))
        XCTAssertNil(SharedRecurringExpensePayload.occurrenceFields(for: RecurringOccurrence(templateID: shared.id, monthKey: "2026-11", status: .skipped, expenseID: UUID())))
        // 受け取り：文書の ID と中身が合わないもの・形の違うものは表示しない
        let data: [String: Any] = ["schemaVersion": 1, "templateID": shared.id.uuidString, "monthKey": "2026-11", "status": "skipped", "expenseID": NSNull()]
        XCTAssertNotNil(SharedRecurringExpensePayload.occurrence(documentID: "\(shared.id.uuidString)_2026-11", data: data))
        XCTAssertNil(SharedRecurringExpensePayload.occurrence(documentID: "\(shared.id.uuidString)_2026-12", data: data))
        XCTAssertNil(SharedRecurringExpensePayload.template(documentID: "rent", data: [:]))
        XCTAssertNil(SharedRecurringExpensePayload.template(documentID: shared.id.uuidString, data: [
            "schemaVersion": 1, "title": "家賃\n", "expectedAmount": 1, "category": "other", "dueDay": 1, "startMonthKey": "2026-11", "isActive": true
        ]), "改行入りの名前は表示しない")
    }

    /// 46〜48：Build 24 の予算・Build 23 の検索と購入履歴・レシートと商品明細は今までどおり
    func testExistingFeaturesStillWork() {
        let device = makeDevice()
        device.store.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 50_000, categoryAmounts: [.food: 20_000]), for: november, scope: .personal)
        device.store.addExpense(Expense(title: "まちの八百屋", amount: 698, category: .food, date: build25Now), destination: .personal,
                                lineItems: [ExpenseLineItem(name: "牛乳", amount: 198), ExpenseLineItem(name: "ティッシュ", amount: 500)])
        XCTAssertNil(device.register())
        XCTAssertTrue(device.addThisMonth(.personal))
        let summary = device.money.budgetSummary(for: .personal)
        XCTAssertEqual(summary.spent, 698 + 85_000)
        XCTAssertEqual(summary.categoryLines.first { $0.category == .food }?.spent, 698)
        device.money.searchText = "牛乳"
        XCTAssertEqual(device.money.searchResults.count, 1, "商品明細で検索できる")
        device.money.searchText = ""
        let milk = device.store.lineItems(for: device.store.expenses.first { $0.title == "まちの八百屋" }!.id).first!
        XCTAssertEqual(device.money.purchaseHistory(for: device.money.historyTarget(for: milk)).records.count, 1, "購入履歴")
        let proposal = ReceiptFieldExtractor.extract(from: ["まちの八百屋", "牛乳 ¥198", "小計 ¥198", "合計 ¥198", "お預り ¥1,000", "お釣り ¥802"], today: build25Now)
        XCTAssertEqual(proposal.amount, 198, "レシートの読み取り")
        // ふつうの「支出を追加」は今までどおり（自分だけが初期値。定期支出の決まりは入らない）
        device.money.startAdding()
        XCTAssertNil(device.money.draft?.recurring)
        XCTAssertEqual(device.money.draft?.destination, .personal)
    }

    /// 49：VoiceOver・44pt・キーボード（Build 22 と同じ閉じ方）・状態は文字で
    func testAccessibilityAndKeyboard() throws {
        let view = build25CodeOnly(try build25Source("LifeOS/Features/Money/RecurringExpenseViews.swift"))
        XCTAssertTrue(view.contains(".lifeKeyboardDismissal()"))
        XCTAssertTrue(view.contains(".lifeKeyboardDoneButton { focusedField = nil }"))
        XCTAssertTrue(view.contains("@FocusState private var focusedField"))
        XCTAssertTrue(view.contains(".keyboardType(.numberPad)"))
        XCTAssertTrue(view.contains(".frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)"))
        XCTAssertTrue(view.contains(".accessibilityLabel(viewModel.recurringSpokenLabel(row))"))
        XCTAssertTrue(view.contains("Text(\"\\(row.stateText)"), "状態は文字で出す")
        for identifier in ["money.recurring.add", "money.recurring.addThisMonth", "money.recurring.skip", "money.recurring.undoSkip",
                           "money.recurring.edit", "money.recurring.pause", "money.recurring.resume", "money.recurring.save"] {
            XCTAssertTrue(view.contains("\"\(identifier)\""), identifier)
        }
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        let money = build25CodeOnly(try build25Source("LifeOS/Features/Money/MoneyView.swift"))
        let budget = try XCTUnwrap(money.range(of: "budgetSection\n"))
        let recurring = try XCTUnwrap(money.range(of: "RecurringExpensesSection(viewModel: viewModel)"))
        let add = try XCTUnwrap(money.range(of: "LifeButton(\"支出を追加\""))
        XCTAssertLessThan(budget.lowerBound, recurring.lowerBound, "予算のカードの下")
        XCTAssertLessThan(recurring.lowerBound, add.lowerBound, "追加ボタンの上")
        XCTAssertTrue(money.contains("\"今月は追加しませんか？\""), "今月は追加しないは確認してから")
        XCTAssertTrue(money.contains("in: recurring.month.dayRange()"), "日付は対象の月の中だけ")
        let today = build25CodeOnly(try build25Source("LifeOS/Features/Today/TodayView.swift"))
        XCTAssertTrue(today.contains("Text(\"定期支出を確認\")"))
        XCTAssertTrue(today.contains(".accessibilityIdentifier(\"today.recurringReview\")"))
        // 状態の文字
        XCTAssertEqual(RecurringCandidateState.unconfirmed.label, "未確認")
        XCTAssertEqual(RecurringCandidateState.created.label, "追加済み")
        XCTAssertEqual(RecurringCandidateState.skipped.label, "今月は追加しない")
    }

    /// 50：Build 番号は4か所とも同じで 25 以上。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    /// （2026-11-13 Build 26：Build 番号を 26 に上げたため「25 ちょうど」から「4か所とも同じで 25 以上」に変えた。
    ///  Build 26 ちょうどは Build26MonthlySpendingReportTests.testBuildNumberIs26 で確かめる）
    func testBuildNumberIs25() throws {
        let project = try build25Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let versions = lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(Set(versions).count, 1, "4か所とも同じ")
        let number = Int(versions.first?.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = ", with: "").replacingOccurrences(of: ";", with: "") ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(number, 25)
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build25Source("docs/BUILD_25_RECURRING_EXPENSES.md").contains("Build 16 は欠番"))
    }
}
