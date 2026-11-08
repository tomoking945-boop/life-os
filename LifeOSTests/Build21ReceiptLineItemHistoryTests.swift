import XCTest
@testable import LifeOS

// Build 21（2026-11-08）：確認した商品明細を支出と一緒に保存し、詳細画面で見返し・修正・削除する。
// docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md
// 本物の Firestore・ネットワークは使わない（共有の支出・明細は、この下の偽物の保存先）。文字認識も偽物。
// ルールの動き（メンバーだけ・不要な項目の拒否・明細が残る支出の削除の拒否）は firebase/functions/test/emulator/rules.test.js、
// わが家の削除・アカウント削除は accountDeletion.test.js、1件ごとの形は test/unit/expenseLineItems.test.js で確かめる。

private let build21Now = TestDates.make(2026, 11, 8, 18, 0)

private func build21Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func build21CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

/// 支出と明細の書き込みの順番（両方の偽物が書く）
private final class Build21WriteLog {
    var entries: [String] = []
}

/// 偽物の共有の支出の保存先（書き込みの順番を記録する）
private final class Build21ExpensesBackend: SharedExpensesBackend {
    let log: Build21WriteLog
    private(set) var creates: [(id: UUID, fields: [String: SharedItemValue])] = []
    private(set) var deletes: [UUID] = []
    var createFailure: SharedItemsFailure?
    var deleteFailure: SharedItemsFailure?
    var holdsCompletion = false
    private(set) var heldCompletions: [(SharedItemsFailure?) -> Void] = []
    private var onChange: (([SharedExpenseSnapshot]) -> Void)?

    init(log: Build21WriteLog) {
        self.log = log
    }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        self.onChange = onChange
        return RepositoryObservation { [weak self] in self?.onChange = nil }
    }

    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        creates.append((id, fields))
        log.entries.append("expense.create")
        finish(completion, createFailure)
    }

    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        log.entries.append("expense.update")
        finish(completion, nil)
    }

    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        deletes.append(id)
        log.entries.append("expense.delete")
        finish(completion, deleteFailure)
    }

    private func finish(_ completion: @escaping (SharedItemsFailure?) -> Void, _ failure: SharedItemsFailure?) {
        if holdsCompletion { heldCompletions.append(completion) } else { completion(failure) }
    }

    func emit(_ expenses: [Expense]) {
        onChange?(expenses.map { SharedExpenseSnapshot(expense: $0, isConfirmed: true) })
    }
}

/// 偽物の商品明細の保存先
private final class Build21LineItemsBackend: SharedExpenseLineItemsBackend {
    let log: Build21WriteLog
    private(set) var sets: [(expenseID: UUID, rows: [String])] = []
    private(set) var deletes: [UUID] = []
    private(set) var listenCount = 0
    var setFailure: SharedItemsFailure?
    var deleteFailure: SharedItemsFailure?
    private var onChange: (([SharedExpenseLineItemsSnapshot]) -> Void)?

    init(log: Build21WriteLog) {
        self.log = log
    }

    var isListening: Bool { onChange != nil }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseLineItemsSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        self.onChange = onChange
        return RepositoryObservation { [weak self] in self?.onChange = nil }
    }

    func set(groupID: String, expenseID: UUID, rows: [String], completion: @escaping (SharedItemsFailure?) -> Void) {
        sets.append((expenseID, rows))
        log.entries.append("lineItems.set")
        completion(setFailure)
    }

    func delete(groupID: String, expenseID: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        deletes.append(expenseID)
        log.entries.append("lineItems.delete")
        completion(deleteFailure)
    }

    func emit(_ snapshots: [SharedExpenseLineItemsSnapshot]) {
        onChange?(snapshots)
    }
}

/// 偽物の文字認識（位置なしの行。Build 20 の読み取りで、店名・合計・商品明細の候補になる）
private struct Build21Recognizer: ReceiptTextRecognizing {
    var lines: [String]
    func recognizeLines(in imageData: Data) async throws -> [String] { lines }
}

/// 見本のレシート：店名・日時・牛乳 ¥198・ティッシュ 2点 × ¥250 ¥500・小計・合計 ¥698・お預り・お釣り
private let build21Receipt = [
    "いらっしゃいませ",
    "まちの八百屋",
    "TEL 03-1234-5678",
    "2026/11/08 18:42",
    "牛乳 ¥198",
    "ティッシュ 2点 × ¥250 ¥500",
    "小計 ¥698",
    "合計 ¥698",
    "お預り ¥1,000",
    "お釣り ¥302"
]

private struct Build21Setup {
    let store: LifeStore
    let log: Build21WriteLog
    let expenses: Build21ExpensesBackend
    let lineItems: Build21LineItemsBackend
    let service: SharedExpensesService
    let viewModel: MoneyViewModel
}

private func makeBuild21(store: LifeStore? = nil, receipt: [String] = build21Receipt) -> Build21Setup {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    let log = Build21WriteLog()
    let expenses = Build21ExpensesBackend(log: log)
    let lineItems = Build21LineItemsBackend(log: log)
    let service = SharedExpensesService(backend: expenses, lineItemsBackend: lineItems)
    service.attach(store)
    service.apply(household: HouseholdSummary(
        name: "わが家", sharedKinds: [.todo, .shopping, .money], isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build21"
    ), isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = .shared
    let viewModel = MoneyViewModel(store: store, appState: appState, now: build21Now, receiptRecognizer: Build21Recognizer(lines: receipt))
    return Build21Setup(store: store, log: log, expenses: expenses, lineItems: lineItems, service: service, viewModel: viewModel)
}

private let receiptImage = WarrantyTestImages.text(["合計 ¥698"])

private func item(_ name: String, quantity: Decimal? = nil, unitPrice: Int? = nil, amount: Int, id: UUID = UUID()) -> ExpenseLineItem {
    ExpenseLineItem(id: id, name: name, quantity: quantity, unitPrice: unitPrice, amount: amount)
}

private func sharedExpense(_ title: String = "スーパー", amount: Int = 698) -> Expense {
    Expense(title: title, amount: amount, category: .food, date: build21Now, ownership: .shared)
}

// MARK: - 1. 保存する明細・しない明細（1〜7・17・20）

final class Build21LineItemSavingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build21-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    @MainActor
    private func readDraft(_ setup: Build21Setup) async throws -> ExpenseDraft {
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        return try XCTUnwrap(setup.viewModel.draft)
    }

    /// 1：確認画面に残っている（確かめた）明細だけを、支出と一緒に保存する
    @MainActor
    func testConfirmedLineItemsAreSavedWithExpense() async throws {
        let setup = makeBuild21()
        var draft = try await readDraft(setup)
        XCTAssertEqual(draft.lineItems.map(\.name), ["牛乳", "ティッシュ"])
        draft.lineItems[0].name = "低脂肪牛乳"
        XCTAssertEqual(draft.lineItemProblems, [])
        let didSave = setup.viewModel.save(draft)
        XCTAssertTrue(didSave)
        let saved = try XCTUnwrap(setup.store.expenses.first)
        let items = setup.store.lineItems(for: saved.id)
        XCTAssertEqual(items.map(\.name), ["低脂肪牛乳", "ティッシュ"])
        XCTAssertEqual(items.map(\.amount), [198, 500])
        XCTAssertEqual(items.map(\.sortOrder), [0, 1])
        XCTAssertEqual(items[1].quantity, 2)
        XCTAssertEqual(items[1].unitPrice, 250)
        XCTAssertEqual(items.map(\.id), draft.lineItems.map(\.id), "明細ID は確認画面のまま")
    }

    /// 2：確認画面で消した明細は保存しない
    @MainActor
    func testRemovedCandidatesAreNotSaved() async throws {
        let setup = makeBuild21()
        var draft = try await readDraft(setup)
        let tissue = try XCTUnwrap(draft.lineItems.first { $0.name == "ティッシュ" })
        draft.removeLineItem(tissue.id)
        XCTAssertTrue(setup.viewModel.save(draft))
        let saved = try XCTUnwrap(setup.store.expenses.first)
        XCTAssertEqual(setup.store.lineItems(for: saved.id).map(\.name), ["牛乳"])
        // すべて消せば、明細なしの支出になる
        let empty = makeBuild21()
        var emptyDraft = try await readDraft(empty)
        for line in emptyDraft.lineItems { emptyDraft.removeLineItem(line.id) }
        XCTAssertTrue(empty.viewModel.save(emptyDraft))
        XCTAssertEqual(empty.store.lineItems(for: try XCTUnwrap(empty.store.expenses.first).id), [])
    }

    /// 3：50件まで保存でき、51件目は拒否する
    func testFiftyItemsAreSavedAndFiftyFirstIsRejected() throws {
        let drafts = (1...51).map { ReceiptLineItem(name: "商品\($0)", amount: $0) }
        let prepared = ExpenseLineItemRules.prepare(drafts)
        XCTAssertEqual(prepared.items.count, 50)
        XCTAssertEqual(prepared.problems, [ExpenseLineItemProblem(row: 51, issue: .tooMany)])
        XCTAssertTrue(prepared.problems[0].message.hasPrefix("51行目："))
        let store = makeBuild21().store
        let expense = Expense(title: "まとめ買い", amount: 1275, category: .food, date: build21Now)
        store.add(expense)
        let fifty = (1...50).map { item("商品\($0)", amount: $0) }
        XCTAssertEqual(try store.setLineItems(fifty, for: expense.id).get().count, 50)
        let fiftyOne = fifty + [item("商品51", amount: 51)]
        XCTAssertEqual(store.setLineItems(fiftyOne, for: expense.id), .failure(.tooMany))
        XCTAssertEqual(store.lineItems(for: expense.id).count, 50, "51件は保存しない（元の50件のまま）")
        XCTAssertEqual(ExpenseLineItemRules.maxCount, 50)
    }

    /// 4・5：空の商品名・80文字を超える商品名を拒否する（80文字ちょうどは保存できる。理由は日本語で出す）
    func testEmptyAndTooLongNamesAreRejected() throws {
        let drafts = [
            ReceiptLineItem(name: "  ", amount: 100),
            ReceiptLineItem(name: String(repeating: "あ", count: 81), amount: 100),
            ReceiptLineItem(name: String(repeating: "あ", count: 80), amount: 100),
            ReceiptLineItem(name: "牛\t乳\n", amount: 198)
        ]
        let prepared = ExpenseLineItemRules.prepare(drafts)
        XCTAssertEqual(prepared.problems.map(\.issue), [.emptyName, .nameTooLong])
        XCTAssertEqual(prepared.problems.map(\.row), [1, 2])
        XCTAssertEqual(prepared.items.map(\.name), [String(repeating: "あ", count: 80), "牛 乳"], "タブ・改行は空白にする")
        XCTAssertEqual(ExpenseLineItemIssue.emptyName.message, "商品名が空のため保存されません。商品名を入れるか、この明細を削除してください。")
        let store = makeBuild21().store
        let expense = Expense(title: "スーパー", amount: 198, category: .food, date: build21Now)
        store.add(expense)
        XCTAssertEqual(store.setLineItems([item("", amount: 198)], for: expense.id), .failure(.invalid(.emptyName)))
        XCTAssertEqual(store.setLineItems([item(String(repeating: "い", count: 81), amount: 198)], for: expense.id), .failure(.invalid(.nameTooLong)))
        XCTAssertEqual(store.lineItems(for: expense.id), [])
    }

    /// 6：正しくない数量・単価・金額を拒否する（小数の数量は小数3桁に四捨五入）
    func testInvalidQuantityUnitPriceAndAmountAreRejected() throws {
        let drafts = [
            ReceiptLineItem(id: UUID(), name: "数量0", quantity: nil, unitPrice: nil, amount: 100),
            ReceiptLineItem(name: "単価", amount: 100),
            ReceiptLineItem(name: "金額なし")
        ]
        var editable = drafts
        editable[0].quantityText = "0"
        editable[1].unitPriceText = "-5"
        let prepared = ExpenseLineItemRules.prepare(editable)
        XCTAssertEqual(prepared.problems.map(\.issue), [.invalidQuantity, .invalidUnitPrice, .invalidAmount])
        XCTAssertEqual(prepared.items, [])
        for text in ["0", "-1", "abc", "10000", "1,5", "0.0001"] {
            XCTAssertNil(ExpenseLineItemRules.quantity(from: text), text)
        }
        XCTAssertEqual(ExpenseLineItemRules.quantity(from: "２点"), 2)
        XCTAssertEqual(ExpenseLineItemRules.quantity(from: "1.5"), Decimal(string: "1.5"))
        XCTAssertEqual(ExpenseLineItemRules.quantity(from: "1.2345"), Decimal(string: "1.235"), "小数3桁に四捨五入")
        XCTAssertEqual(ExpenseLineItemRules.quantity(from: "0.0005"), Decimal(string: "0.001"))
        XCTAssertEqual(ExpenseLineItemRules.text(for: Decimal(string: "1.50")!), "1.5")
        for text in ["-1", "1000000000", "1.5", "abc", ""] {
            XCTAssertNil(ExpenseLineItemRules.yen(from: text), text)
        }
        XCTAssertEqual(ExpenseLineItemRules.yen(from: "０"), 0, "0円の明細は保存できる")
        XCTAssertEqual(ExpenseLineItemRules.yen(from: "¥1,980"), 1980)
        let original = item("牛乳", amount: 198)
        for (quantity, unit, amount, issue) in [("0", "", "198", ExpenseLineItemIssue.invalidQuantity), ("", "x", "198", .invalidUnitPrice), ("", "", "", .invalidAmount), ("", "", "1000000000", .invalidAmount)] {
            XCTAssertEqual(ExpenseLineItemRules.edited(original, name: "牛乳", quantityText: quantity, unitPriceText: unit, amountText: amount), .failure(.invalid(issue)))
        }
    }

    /// 7：手入力の支出は、明細なしで保存できる（詳細では「商品明細はありません」）
    @MainActor
    func testManualExpenseSavesWithoutLineItems() throws {
        let setup = makeBuild21()
        setup.viewModel.startAdding()
        var draft = try XCTUnwrap(setup.viewModel.draft)
        draft.title = "クリーニング"
        draft.amountText = "1200"
        XCTAssertTrue(setup.viewModel.save(draft))
        let saved = try XCTUnwrap(setup.store.expenses.first)
        XCTAssertEqual(setup.viewModel.lineItems(for: saved), [])
        XCTAssertEqual(setup.viewModel.lineItemComparison(for: saved), .noItems)
        XCTAssertEqual(setup.lineItems.sets.count, 0)
        let detail = try build21Source("LifeOS/Features/Money/ExpenseDetailView.swift")
        XCTAssertTrue(detail.contains("Text(\"商品明細はありません\")"))
    }

    /// 17：同じ保存操作をくり返しても、支出も明細も重ならない
    @MainActor
    func testRepeatedSaveDoesNotDuplicate() async throws {
        let setup = makeBuild21()
        var draft = try await readDraft(setup)
        draft.destination = .household
        let first = setup.viewModel.save(draft)
        let second = setup.viewModel.save(draft)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(setup.store.visibleExpenses(scope: .all).count, 1)
        XCTAssertEqual(setup.expenses.creates.count, 1)
        XCTAssertEqual(setup.lineItems.sets.count, 1, "明細の文書も1つ")
        // 端末への保存でも、同じ ID の支出は2件にしない
        let personal = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        let store = makeBuild21().store
        store.addExpense(personal, destination: .personal, lineItems: [item("牛乳", amount: 198)])
        store.addExpense(personal, destination: .personal, lineItems: [item("牛乳", amount: 198)])
        XCTAssertEqual(store.expenses.count, 1)
        XCTAssertEqual(store.lineItems(for: personal.id).count, 1)
    }

    /// 20：レシートの写真・読み取った全文・候補・信頼度・位置を保存しない（明細は決まった6項目だけ）
    @MainActor
    func testImageFullTextCandidatesAndConfidenceAreNotSaved() async throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeBuild21(store: store)
        let draft = try await readDraft(setup)
        XCTAssertTrue(setup.viewModel.save(draft))
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(file.contains("ティッシュ"), "確かめた明細は保存する")
        for notSaved in ["いらっしゃいませ", "03-1234-5678", "お預り", "お釣り", "選択非推奨", "storeCandidates", "amountCandidates",
                         "confidence", "boundingBox", "receiptNotes", receiptImage.base64EncodedString().prefix(40).description] {
            XCTAssertFalse(file.contains(notSaved), notSaved)
        }
        let saved = try XCTUnwrap(store.lineItems(for: try XCTUnwrap(store.expenses.first).id).first)
        XCTAssertEqual(Set(Mirror(reflecting: saved).children.compactMap(\.label)), ["id", "name", "quantity", "unitPrice", "amount", "sortOrder"])
        let expense = try XCTUnwrap(store.expenses.first)
        XCTAssertEqual(Set(Mirror(reflecting: expense).children.compactMap(\.label)), ["id", "title", "amount", "category", "date", "ownership"], "支出の項目は増やさない")
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        let imageSuffixes = [".jpg", ".jpeg", ".png", ".heic"]
        XCTAssertEqual(files.filter { name in imageSuffixes.contains { name.lowercased().hasSuffix($0) } }, [], "写真のファイルを作らない")
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined(separator: "\n")
        XCTAssertFalse(defaults.contains("ティッシュ"))
    }
}

// MARK: - 2. 端末の保存・古いデータ・修正の失敗（8・18・19）

final class Build21PersistenceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build21P-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 8：明細の無い古い保存データ（Build 20 まで）も読める。読めない明細の記録があっても、ほかのデータは読める
    func testOldDataAndBrokenRecordsStillLoad() throws {
        let first = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let old = Expense(title: "以前の支出", amount: 1500, category: .other, date: build21Now)
        let withItems = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        first.add(old)
        first.addExpense(withItems, destination: .personal, lineItems: [item("牛乳", amount: 198), item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500)])
        let url = temporaryDirectory.appendingPathComponent(LifeStore.fileName)
        // Build 20 までの形：expenseLineItems が無い
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let records = json.removeValue(forKey: "expenseLineItems")
        XCTAssertNotNil(records, "Build 21 は明細を保存する")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let reloadedOld = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(Set(reloadedOld.expenses.map(\.title)), ["以前の支出", "スーパー"], "古い形でも支出は読める（変えない・消さない）")
        XCTAssertEqual(reloadedOld.lineItems(for: old.id), [])
        XCTAssertEqual(reloadedOld.lineItems(for: withItems.id), [], "明細の無い古いデータは明細なし")

        // 読めない記録（壊れた明細・知らない支出・形の違う値）が混ざっていても、正しい記録とほかのデータは読める
        let goodItems: [[String: Any]] = [
            ["id": UUID().uuidString, "name": "牛乳", "amount": 198, "sortOrder": 0],
            ["id": "not-a-uuid", "name": "壊れた明細", "amount": 1],
            ["id": UUID().uuidString, "name": "ティッシュ", "quantity": "2", "unitPrice": 250, "amount": 500, "sortOrder": 1]
        ]
        let unknownItems: [[String: Any]] = [["id": UUID().uuidString, "name": "知らない支出", "amount": 1]]
        let brokenRecords: [Any] = [
            ["expenseID": withItems.id.uuidString, "items": goodItems] as [String: Any],
            ["expenseID": UUID().uuidString, "items": unknownItems] as [String: Any],
            ["expenseID": old.id.uuidString, "items": "壊れている"] as [String: Any],
            "記録ではない値"
        ]
        json["expenseLineItems"] = brokenRecords
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let reloaded = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(reloaded.expenses.count, 2)
        XCTAssertEqual(reloaded.lineItems(for: withItems.id).map(\.name), ["牛乳", "ティッシュ"])
        XCTAssertEqual(reloaded.lineItems(for: withItems.id).last?.quantity, 2)
        XCTAssertEqual(reloaded.lineItems(for: old.id), [])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("知らない支出"), "端末に無い支出の明細は残さない")
    }

    /// 自分だけの支出の明細は、アプリを開き直しても残る（端末の中だけ）
    func testPersonalLineItemsPersistAcrossLaunch() throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let expense = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        store.addExpense(expense, destination: .personal, lineItems: [item("量り売りのお米", quantity: Decimal(string: "1.5"), unitPrice: 400, amount: 600), item("おまけ", amount: 0)])
        let reloaded = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let items = reloaded.lineItems(for: expense.id)
        XCTAssertEqual(items.map(\.name), ["量り売りのお米", "おまけ"])
        XCTAssertEqual(items.first?.quantity, Decimal(string: "1.5"))
        let text = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(text.contains("\"quantity\":\"1.5\""), "数量は文字で保存する（小数の誤差を出さない）")
        // 支出を消すと明細も消える（明細だけを残さない）
        XCTAssertTrue(reloaded.deleteExpense(expense.id))
        XCTAssertEqual(reloaded.lineItems(for: expense.id), [])
        XCTAssertFalse(try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8).contains("量り売りのお米"))
    }

    /// 18：端末に保存できなかったときは、元の明細を失わない（理由を出す）
    func testPersonalEditFailureKeepsOriginal() throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let expense = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        let milk = item("牛乳", amount: 198)
        store.addExpense(expense, destination: .personal, lineItems: [milk, item("ティッシュ", amount: 500)])
        // 保存先をファイルにして、書き込みを失敗させる
        let blocker = temporaryDirectory.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        LocalStorage.directoryOverride = blocker
        var changed = milk
        changed.name = "低脂肪牛乳"
        XCTAssertEqual(store.updateLineItem(changed, in: expense.id), .failure(.storageFailed))
        XCTAssertEqual(store.lineItems(for: expense.id).map(\.name), ["牛乳", "ティッシュ"], "元の明細のまま")
        XCTAssertEqual(store.deleteLineItem(milk.id, in: expense.id), .failure(.storageFailed))
        XCTAssertEqual(store.lineItems(for: expense.id).count, 2)
        XCTAssertEqual(ExpenseLineItemSaveError.storageFailed.message, "この iPhone に保存できませんでした。元の内容のままです。")
        LocalStorage.directoryOverride = temporaryDirectory
        XCTAssertEqual(try store.updateLineItem(changed, in: expense.id).get().map(\.name), ["低脂肪牛乳", "ティッシュ"])
    }

    /// 19：明細の合計とレシートの合計（支出の金額）の一致・不一致・比較不能
    func testComparisonOfSavedLineItems() {
        let items = [item("牛乳", amount: 198), item("ティッシュ", amount: 500)]
        XCTAssertEqual(ReceiptLineItemComparison.compare(saved: items, receiptTotal: 698), .matched(total: 698))
        XCTAssertEqual(ReceiptLineItemComparison.compare(saved: items, receiptTotal: 733), .mismatched(itemsTotal: 698, receiptTotal: 733))
        XCTAssertEqual(ReceiptLineItemComparison.compare(saved: items, receiptTotal: nil), .insufficient)
        XCTAssertEqual(ReceiptLineItemComparison.compare(saved: [], receiptTotal: 698), .noItems)
        XCTAssertEqual(ReceiptLineItemComparison.matchedMessage, "商品明細の合計と一致しています")
        XCTAssertEqual(ReceiptLineItemComparison.mismatchedMessage, "値引き・税・読み取り違いなどにより、商品明細の合計とレシート合計が一致しません")
        XCTAssertTrue(ReceiptLineItemComparison.insufficientMessage.contains("比較不能"))
    }
}

// MARK: - 3. 自分だけ／共有（9〜17・18）

final class Build21SharedLineItemTests: XCTestCase {
    /// 9：自分だけの支出の明細は Firestore へ送らない
    func testPersonalLineItemsAreNotSent() {
        let setup = makeBuild21()
        let expense = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        setup.store.addExpense(expense, destination: .personal, lineItems: [item("牛乳", amount: 198)])
        XCTAssertEqual(setup.store.lineItems(for: expense.id).count, 1)
        XCTAssertEqual(setup.log.entries, [], "支出も明細も送らない")
        XCTAssertEqual(setup.store.householdExpenseLineItems, [:])
    }

    /// 10・12：共有の明細は、決まった2項目の形（rows）だけ。1件は5つの値だけ（写真・全文・候補・信頼度・UID は入らない）。
    /// サーバーのテスト（test/unit/expenseLineItems.test.js）と同じ見本の行になる
    func testSharedPayloadMatchesServerGoldenRows() throws {
        let items = [
            item("牛乳", amount: 198, id: try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))),
            item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500, id: try XCTUnwrap(UUID(uuidString: "0F8FAD5B-D9CB-469F-A165-70867728950E"))),
            item("量り売りのお米", quantity: Decimal(string: "1.5"), unitPrice: 400, amount: 600, id: try XCTUnwrap(UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7"))),
            item("おまけ", amount: 0, id: try XCTUnwrap(UUID(uuidString: "16FD2706-8BAF-433B-82EB-8C7FADA847DA")))
        ]
        XCTAssertEqual(SharedExpenseLineItemsPayload.rows(for: items), [
            "E621E1F8-C36C-495A-93FC-0C247A3E6E5F\t牛乳\t\t\t198",
            "0F8FAD5B-D9CB-469F-A165-70867728950E\tティッシュ\t2\t250\t500",
            "7C9E6679-7425-40DE-944B-E07FC1F90AE7\t量り売りのお米\t1.5\t400\t600",
            "16FD2706-8BAF-433B-82EB-8C7FADA847DA\tおまけ\t\t\t0"
        ])
        // 受け取った行は同じ明細に戻る（形の違う行は表示しない）
        let rows = try XCTUnwrap(SharedExpenseLineItemsPayload.rows(for: items))
        XCTAssertEqual(SharedExpenseLineItemsPayload.items(from: rows + ["bad\trow", "16FD2706-8BAF-433B-82EB-8C7FADA847DA\t重複\t\t\t1"]), items.enumerated().map { index, value in
            var copy = value
            copy.sortOrder = index
            return copy
        })
        XCTAssertNil(SharedExpenseLineItemsPayload.items(documentID: "abc", data: ["schemaVersion": 1, "rows": rows]))
        XCTAssertNil(SharedExpenseLineItemsPayload.items(documentID: UUID().uuidString, data: ["schemaVersion": 2, "rows": rows]))
        XCTAssertNil(SharedExpenseLineItemsPayload.rows(for: []), "明細が無ければ送らない（文書を消す）")
        XCTAssertNil(SharedExpenseLineItemsPayload.rows(for: (0...50).map { item("商品\($0)", amount: $0) }), "51件は送らない")
        let backend = build21CodeOnly(try build21Source("LifeOS/Core/Sharing/FirestoreSharedExpenseLineItemsBackend.swift"))
        XCTAssertTrue(backend.contains("\"schemaVersion\": SharedExpenseLineItemsPayload.schemaVersion,\n            \"rows\": rows,"))
    }

    /// 10：共有の支出の明細は、支出のあとに送る（ルールは支出がある明細だけを受け付ける）。相手の画面にも届く
    @MainActor
    func testSharedSaveSendsExpenseThenLineItems() throws {
        let setup = makeBuild21()
        let expense = sharedExpense()
        XCTAssertTrue(setup.store.addExpense(expense, destination: .household, lineItems: [item("牛乳", amount: 198), item("ティッシュ", amount: 500)]))
        XCTAssertEqual(setup.log.entries, ["expense.create", "lineItems.set"])
        XCTAssertEqual(setup.lineItems.sets.first?.rows.count, 2)
        XCTAssertEqual(setup.expenses.creates.first?.fields.count, 9, "支出は今までの9項目だけ")
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.name), ["牛乳", "ティッシュ"])
        XCTAssertTrue(setup.store.expenses.isEmpty, "共有の支出は端末に保存しない")
        // パートナーが直した明細が届く（同じ一覧なら入れ替えない）
        let changed = [item("低脂肪牛乳", amount: 200)]
        setup.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: expense.id, items: changed)])
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.name), ["低脂肪牛乳"])
        XCTAssertTrue(setup.lineItems.isListening)
        XCTAssertEqual(setup.service.activeLineItemsListenerCount, 1)
    }

    /// 11（アプリ側）：わが家に参加していない・退出したら、共有の明細は送らず、表示も消す
    func testNonMemberCannotSendOrSeeSharedLineItems() {
        let setup = makeBuild21()
        let expense = sharedExpense()
        setup.expenses.emit([expense])
        setup.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: expense.id, items: [item("牛乳", amount: 198)])])
        XCTAssertEqual(setup.store.lineItems(for: expense.id).count, 1)
        setup.service.apply(household: nil, isSignedIn: true)
        XCTAssertEqual(setup.store.householdExpenseLineItems, [:], "退出したら共有の明細を出さない")
        XCTAssertFalse(setup.lineItems.isListening)
        XCTAssertEqual(setup.service.activeLineItemsListenerCount, 0)
        let personal = Expense(title: "ランチ", amount: 900, category: .diningOut, date: build21Now)
        XCTAssertFalse(setup.store.addExpense(personal, destination: .household, lineItems: [item("定食", amount: 900)]), "共有できないときは自分だけ")
        XCTAssertEqual(setup.lineItems.sets.count, 0)
        XCTAssertEqual(setup.store.lineItems(for: personal.id).map(\.name), ["定食"])
    }

    /// 13：共有の支出を消すときは、明細を先に消してから支出を消す（明細だけが残らない）
    func testDeletingSharedExpenseDeletesLineItemsFirst() {
        let setup = makeBuild21()
        let expense = sharedExpense()
        setup.store.addExpense(expense, destination: .household, lineItems: [item("牛乳", amount: 198)])
        setup.log.entries = []
        XCTAssertTrue(setup.store.deleteExpense(expense.id))
        XCTAssertEqual(setup.log.entries, ["lineItems.delete", "expense.delete"])
        XCTAssertEqual(setup.store.lineItems(for: expense.id), [])
        XCTAssertNil(setup.store.householdExpenseLineItems[expense.id])
        // 支出の削除が断られたら、明細を元に戻す（失わない）
        let kept = makeBuild21()
        let other = sharedExpense("ドラッグストア", amount: 500)
        kept.store.addExpense(other, destination: .household, lineItems: [item("目薬", amount: 500)])
        kept.expenses.deleteFailure = .permissionDenied
        kept.log.entries = []
        kept.store.deleteExpense(other.id)
        XCTAssertEqual(kept.log.entries, ["lineItems.delete", "expense.delete", "lineItems.set"])
        XCTAssertEqual(kept.lineItems.sets.last?.rows.first?.contains("目薬"), true)
        XCTAssertNotNil(kept.service.notice)
    }

    /// 14（アプリ側）：わが家の削除・サインアウトで、共有の明細の表示も消える（端末の自分だけの明細は消さない）
    func testHouseholdRemovalClearsSharedLineItemsOnly() {
        let setup = makeBuild21()
        let mine = Expense(title: "自分のランチ", amount: 900, category: .diningOut, date: build21Now)
        setup.store.addExpense(mine, destination: .personal, lineItems: [item("定食", amount: 900)])
        let ours = sharedExpense()
        setup.expenses.emit([ours])
        setup.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: ours.id, items: [item("牛乳", amount: 198)])])
        setup.service.apply(household: nil, isSignedIn: false)
        XCTAssertEqual(setup.store.lineItems(for: ours.id), [])
        XCTAssertEqual(setup.store.lineItems(for: mine.id).map(\.name), ["定食"])
    }

    /// 15：自分だけ → 共有：明細を一緒に移し、重ならない（共有の保存が確かめられてから端末の明細を片付ける）
    @MainActor
    func testPersonalToSharedMovesLineItemsWithoutDuplicates() throws {
        let setup = makeBuild21()
        let expense = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        let items = [item("牛乳", amount: 198), item("ティッシュ", amount: 500)]
        setup.store.addExpense(expense, destination: .personal, lineItems: items)
        setup.expenses.holdsCompletion = true
        XCTAssertTrue(setup.store.changeExpenseDestination(expense.id, to: .household))
        XCTAssertEqual(setup.log.entries, ["expense.create", "lineItems.set"])
        XCTAssertEqual(setup.store.visibleExpenses(scope: .all).count, 1, "変えている途中も1件")
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.id), items.map(\.id), "明細も1組だけ")
        setup.expenses.heldCompletions.first?(nil)
        XCTAssertTrue(setup.store.expenses.isEmpty)
        XCTAssertEqual(setup.store.expenseLineItems[expense.id], nil, "端末の明細を片付けた")
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.id), items.map(\.id), "共有の方に同じ明細ID で残る")
        XCTAssertEqual(setup.lineItems.sets.count, 1)
        // 明細の保存が断られたら、共有の支出を取り消して自分だけに戻す（明細を失わない）
        let failed = makeBuild21()
        let other = Expense(title: "コンビニ", amount: 300, category: .food, date: build21Now)
        failed.store.addExpense(other, destination: .personal, lineItems: [item("おにぎり", amount: 300)])
        failed.lineItems.setFailure = .permissionDenied
        failed.store.changeExpenseDestination(other.id, to: .household)
        XCTAssertEqual(failed.log.entries, ["expense.create", "lineItems.set", "expense.delete"])
        XCTAssertEqual(failed.store.expenses.map(\.id), [other.id])
        XCTAssertEqual(failed.store.lineItems(for: other.id).map(\.name), ["おにぎり"])
        XCTAssertEqual(failed.store.visibleExpenses(scope: .all).count, 1)
    }

    /// 16：共有 → 自分だけ：明細を端末へ先に保存してから、共有の明細と支出を消す（失わない）。失敗したら共有のまま
    func testSharedToPersonalKeepsLineItems() {
        let setup = makeBuild21()
        let expense = sharedExpense()
        let items = [item("牛乳", amount: 198), item("ティッシュ", amount: 500)]
        setup.expenses.emit([expense])
        setup.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: expense.id, items: items)])
        XCTAssertTrue(setup.store.changeExpenseDestination(expense.id, to: .personal))
        XCTAssertEqual(setup.log.entries, ["lineItems.delete", "expense.delete"])
        XCTAssertEqual(setup.store.expenses.map(\.id), [expense.id])
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.id), items.map(\.id), "同じ明細ID のまま、自分だけに")
        XCTAssertEqual(setup.store.householdExpenseLineItems[expense.id], nil)
        // 支出の削除が断られたら、端末の写しを片付けて共有のまま（明細も元に戻す）
        let failed = makeBuild21()
        failed.expenses.emit([expense])
        failed.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: expense.id, items: items)])
        failed.expenses.deleteFailure = .unavailable
        failed.store.changeExpenseDestination(expense.id, to: .personal)
        XCTAssertTrue(failed.store.expenses.isEmpty)
        XCTAssertEqual(failed.store.lineItems(for: expense.id).map(\.id), items.map(\.id))
        XCTAssertEqual(failed.log.entries, ["lineItems.delete", "expense.delete", "lineItems.set"], "消えた明細を戻す")
        XCTAssertEqual(failed.store.visibleExpenses(scope: .all).count, 1)
    }

    /// 18：共有の明細の変更が断られたら、元の明細に戻す（理由を出す）
    func testSharedEditFailureRestoresOriginal() throws {
        let setup = makeBuild21()
        let expense = sharedExpense()
        let milk = item("牛乳", amount: 198)
        setup.expenses.emit([expense])
        setup.lineItems.emit([SharedExpenseLineItemsSnapshot(expenseID: expense.id, items: [milk])])
        setup.lineItems.setFailure = .permissionDenied
        var changed = milk
        changed.amount = 210
        _ = setup.store.updateLineItem(changed, in: expense.id)
        XCTAssertEqual(setup.store.lineItems(for: expense.id).map(\.amount), [198], "元の明細に戻る")
        XCTAssertTrue(setup.service.notice?.contains("元の内容に戻しました") == true)
        // 成功すれば反映される
        setup.lineItems.setFailure = nil
        XCTAssertEqual(try setup.store.updateLineItem(changed, in: expense.id).get().map(\.amount), [210])
        // 最後の1件を消すと、明細の文書を消す（支出は消さない）
        XCTAssertEqual(try setup.store.deleteLineItem(milk.id, in: expense.id).get(), [])
        XCTAssertEqual(setup.lineItems.deletes, [expense.id])
        XCTAssertEqual(setup.expenses.deletes, [], "支出は消さない")
    }
}

// MARK: - 4. 詳細画面・ログ・既存の機能・Build 番号（21〜24）

final class Build21DetailAndRegressionTests: XCTestCase {
    /// 詳細画面：支出をタップすると開く。明細の修正・1件の削除。「支出を編集」は詳細を閉じてから編集画面を開く
    @MainActor
    func testDetailScreenFlow() throws {
        let setup = makeBuild21()
        let expense = Expense(title: "スーパー", amount: 698, category: .food, date: build21Now)
        let milk = item("牛乳", amount: 198)
        setup.store.addExpense(expense, destination: .personal, lineItems: [milk, item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500)])
        setup.viewModel.showDetail(expense)
        XCTAssertEqual(setup.viewModel.detailTarget?.id, expense.id)
        XCTAssertEqual(setup.viewModel.lineItemsTotal(for: expense), 698)
        XCTAssertEqual(setup.viewModel.lineItemComparison(for: expense), .matched(total: 698))
        XCTAssertEqual(setup.viewModel.destinationLabel(for: expense), "自分だけ")
        XCTAssertEqual(setup.viewModel.updateLineItem(milk, in: expense, name: "", quantityText: "", unitPriceText: "", amountText: "198"), ExpenseLineItemIssue.emptyName.message)
        XCTAssertEqual(setup.viewModel.lineItems(for: expense).first?.name, "牛乳", "正しくない修正は反映しない")
        XCTAssertNil(setup.viewModel.updateLineItem(milk, in: expense, name: "低脂肪牛乳", quantityText: "1", unitPriceText: "200", amountText: "200"))
        XCTAssertEqual(setup.viewModel.lineItems(for: expense).first?.name, "低脂肪牛乳")
        XCTAssertEqual(setup.viewModel.lineItemComparison(for: expense), .mismatched(itemsTotal: 700, receiptTotal: 698))
        XCTAssertNil(setup.viewModel.deleteLineItem(milk, in: expense))
        XCTAssertEqual(setup.viewModel.lineItems(for: expense).map(\.name), ["ティッシュ"])
        XCTAssertEqual(setup.store.expenses.count, 1, "明細の削除では支出を消さない")
        setup.viewModel.editFromDetail()
        XCTAssertNil(setup.viewModel.detailTarget)
        XCTAssertNil(setup.viewModel.draft, "詳細が閉じ終わるまで編集画面を開かない")
        setup.viewModel.detailDidClose()
        XCTAssertEqual(setup.viewModel.draft?.id, expense.id)
        // 詳細を閉じただけなら編集画面は開かない
        setup.viewModel.cancelEditing()
        setup.viewModel.showDetail(expense)
        setup.viewModel.closeDetail()
        setup.viewModel.detailDidClose()
        XCTAssertNil(setup.viewModel.draft)
    }

    /// 21・UI：商品名・金額・UID をログに出さない。VoiceOver の説明と 44pt 以上の操作。色だけに頼らない
    func testNoLoggingAccessibilityAndTapTargets() throws {
        for path in [
            "LifeOS/Core/Models/ExpenseLineItem.swift",
            "LifeOS/Core/Sharing/SharedExpenseLineItems.swift",
            "LifeOS/Core/Sharing/FirestoreSharedExpenseLineItemsBackend.swift",
            "LifeOS/Core/Sharing/SharedExpenses.swift",
            "LifeOS/Core/Store/LifeStore.swift",
            "LifeOS/Features/Money/ExpenseDetailView.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift"
        ] {
            let code = build21CodeOnly(try build21Source(path))
            for word in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "Analytics", "Crashlytics", "URLSession", "VNRecognizeTextRequest"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        XCTAssertEqual(item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500).spokenLabel, "商品名 ティッシュ、数量 2、単価 250円、金額 500円")
        XCTAssertEqual(item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500).detailText, "2点 × ¥250")
        XCTAssertEqual(item("お米", quantity: Decimal(string: "1.5"), amount: 600).detailText, "1.5点")
        XCTAssertNil(item("牛乳", amount: 198).detailText)
        let detail = build21CodeOnly(try build21Source("LifeOS/Features/Money/ExpenseDetailView.swift"))
        for snippet in [
            ".accessibilityLabel(item.spokenLabel)",
            ".frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)",
            ".frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)",
            ".accessibilityLabel(\"\\(item.name)の明細を削除\")",
            "Text(viewModel.destinationLabel(for: expense))",
            "Label(comparison.message, systemImage:",
            "Text(\"商品明細はありません\")",
            "viewModel.editFromDetail()"
        ] {
            XCTAssertTrue(detail.contains(snippet), snippet)
        }
        let money = build21CodeOnly(try build21Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains("viewModel.showDetail(expense)"), "支出をタップすると詳細を開く")
        XCTAssertTrue(money.contains("ExpenseDetailSheet(viewModel: viewModel, expenseID: target.id)"))
        XCTAssertTrue(money.contains("ForEach(draft.lineItemProblems) { problem in"), "保存されない明細の理由を出す")
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
    }

    /// 22：保証書の文字の読み取りは今までどおり
    func testWarrantyOCRStillWorks() {
        let proposal = WarrantyFieldExtractor.extract(from: [
            WarrantyRecognizedLine(text: "型番 AB-123"),
            WarrantyRecognizedLine(text: "お買上げ日 2026/10/13", confidence: 0.9)
        ])
        XCTAssertEqual(proposal.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
        XCTAssertEqual(proposal.fields.first { $0.kind == .purchaseDate }?.date, TestDates.make(2026, 10, 13))
    }

    /// 23・24：Build 番号は4か所とも 21。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    func testBuildNumberIs21() throws {
        let project = try build21Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 21;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build21Source("docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md").contains("Build 16 は欠番"))
    }
}
