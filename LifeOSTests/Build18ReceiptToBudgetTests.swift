import UniformTypeIdentifiers
import XCTest
@testable import LifeOS

// Build 18（2026-11-02）：レシートを撮る・選ぶ → この iPhone の中で読み取る（Apple Vision）→ 支出の候補 →
// 確認・修正して「保存」を押したときだけ家計簿に入る。docs/BUILD_18_RECEIPT_TO_BUDGET.md
// 本物の Firestore・ネットワーク・外部の AI は使わない（共有の支出は Build13 の FakeSharedExpensesBackend）。

/// 2026年11月10日（火）9:00
private let build18Now = TestDates.make(2026, 11, 10, 9, 0)

private func build18Store() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func build18Household(money: Bool = true) -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家",
        sharedKinds: money ? [.todo, .shopping, .money] : [.todo, .shopping],
        isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build18"
    )
}

/// 偽物の文字認識（読み取った行を返す・失敗する・時間がかかる）
private struct FakeReceiptRecognizer: ReceiptTextRecognizing {
    enum Failure: Error { case unreadable }
    var lines: [String]?
    var delayNanoseconds: UInt64 = 0

    func recognizeLines(in imageData: Data) async throws -> [String] {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        guard let lines else { throw Failure.unreadable }
        return lines
    }
}

/// よくあるスーパーのレシート
private let supermarketReceipt = [
    "いらっしゃいませ",
    "スーパーマルエツ 新宿店",
    "東京都新宿区西新宿1-2-3",
    "TEL 03-1234-5678",
    "登録番号 T1234567890123",
    "2026年11月2日(月) 18:42",
    "レジ#3 担当 0012",
    "牛乳 ¥198",
    "食パン ¥250",
    "小計 ¥448",
    "(内消費税 ¥33)",
    "合計 ¥483",
    "お預り ¥1,000",
    "お釣り ¥517",
    "カード番号 **** **** **** 1234"
]

private struct ReceiptSetup {
    let store: LifeStore
    let backend: FakeSharedExpensesBackend
    let service: SharedExpensesService
    let appState: AppState
    let viewModel: MoneyViewModel
}

private func makeReceiptSetup(lines: [String]? = supermarketReceipt, money: Bool = true, delay: UInt64 = 0, store: LifeStore = build18Store()) -> ReceiptSetup {
    let backend = FakeSharedExpensesBackend()
    let service = SharedExpensesService(backend: backend)
    service.attach(store)
    service.apply(household: build18Household(money: money), isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = .shared
    appState.scope = .all
    let viewModel = MoneyViewModel(
        store: store,
        appState: appState,
        now: build18Now,
        receiptRecognizer: FakeReceiptRecognizer(lines: lines, delayNanoseconds: delay)
    )
    return ReceiptSetup(store: store, backend: backend, service: service, appState: appState, viewModel: viewModel)
}

/// 読み取りに渡す写真（PNG）
private let receiptImage = WarrantyTestImages.text(["合計 ¥483"])

private func extract(_ lines: [String]) -> ReceiptExtractionProposal {
    ReceiptFieldExtractor.extract(from: lines, today: build18Now)
}

private func build18Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

// MARK: - 1. 合計金額

final class Build18ReceiptAmountTests: XCTestCase {
    /// 1：合計の見出しの近く（同じ行・次の行）の金額を選ぶ
    func testPicksAmountNearTotalLabel() {
        XCTAssertEqual(extract(supermarketReceipt).amount, 483)
        XCTAssertEqual(extract(["お買上金額", "¥1,080", "お預り", "¥2,000"]).amount, 1080, "見出しの次の行の金額")
        XCTAssertEqual(extract(["お支払額 ¥2,500"]).amount, 2500)
        XCTAssertEqual(extract(["ご請求額 3,300円"]).amount, 3300)
        XCTAssertEqual(extract(["総合計 ¥12,345-"]).amount, 12345, "末尾の「-」")
    }

    /// 2：小計より合計を優先する
    func testTotalWinsOverSubtotal() {
        let proposal = extract(["小計 ¥1,000", "外税 ¥100", "合計 ¥1,100"])
        XCTAssertEqual(proposal.amount, 1100)
        XCTAssertNil(extract(["小計 ¥1,000"]).amount, "小計だけなら合計にしない")
    }

    /// 3：お預り・お釣り・消費税を合計にしない
    func testDepositChangeAndTaxAreNotTotal() {
        XCTAssertEqual(extract(["合計 ¥483", "お預り ¥10,000", "お釣り ¥9,517", "消費税 ¥44"]).amount, 483)
        let onlyOthers = extract(["お預り ¥10,000", "お釣り ¥9,517", "消費税等 ¥44", "値引 ¥100", "合計点数 3点"])
        XCTAssertNil(onlyOthers.amount)
        XCTAssertEqual(onlyOthers.amountIssue, .notFound)
        XCTAssertNil(extract(["合計点数 3点"]).amount, "点数は金額にしない")
    }

    /// 4：電話番号・郵便番号・カード番号・時刻・番号を金額にしない
    func testPhonePostalCardAndTimeAreNotAmounts() {
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "TEL 03-1234-5678"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "〒160-0023"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "1234-5678-9012-3456"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "**** **** **** 1234"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "18:42"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "2026/11/02"), [])
        XCTAssertEqual(ReceiptFieldExtractor.amounts(in: "0312345678"), [], "10桁以上は金額にしない")
        XCTAssertNil(extract(["合計", "03-1234-5678"]).amount, "合計の下が電話番号なら金額にしない")
        XCTAssertNil(extract(["合計 12:30"]).amount)
        XCTAssertEqual(extract(["カード 1234-5678-9012-3456", "合計 980"]).amount, 980)
    }

    /// 5：カンマ・円・￥・¥・全角の数字を読める
    func testReadsCommaYenSignsAndFullWidthDigits() {
        XCTAssertEqual(extract(["合計 1,234円"]).amount, 1234)
        XCTAssertEqual(extract(["合計 ¥1,234"]).amount, 1234)
        XCTAssertEqual(extract(["合計 ￥1,234"]).amount, 1234)
        XCTAssertEqual(extract(["合計　￥１，２３４"]).amount, 1234, "全角")
        XCTAssertEqual(extract(["合計 \\3,300"]).amount, 3300, "円記号がバックスラッシュで読まれたとき")
        XCTAssertEqual(extract(["合計 980"]).amount, 980)
        XCTAssertEqual(extract(["合計 999,999,999円"]).amount, 999_999_999, "上限")
        XCTAssertNil(extract(["合計 1,000,000,000円"]).amount, "上限を超える金額は使わない")
    }

    /// 6：英語の TOTAL を読める（SUBTOTAL・TAX は合計にしない）
    func testReadsEnglishTotal() {
        XCTAssertEqual(extract(["SUBTOTAL 1000", "TAX 100", "TOTAL 1100"]).amount, 1100)
        XCTAssertEqual(extract(["Total ¥2,200"]).amount, 2200)
        XCTAssertNil(extract(["SUB TOTAL 1000"]).amount)
    }

    /// 7：複数の合計の候補は安全に扱う（同じ金額なら使う。強い見出しを優先。違う金額なら空）
    func testMultipleTotalCandidatesAreHandledSafely() {
        XCTAssertEqual(extract(["合計 1,000", "合計 1,000"]).amount, 1000, "同じ金額のくり返し")
        XCTAssertEqual(extract(["合計 1,000", "総合計 1,080"]).amount, 1080, "「総合計」を優先")
        let ambiguous = extract(["合計 1,000", "合計 2,000"])
        XCTAssertNil(ambiguous.amount, "決められないときは推測しない")
        XCTAssertEqual(ambiguous.amountIssue, .ambiguous)
        XCTAssertTrue(ambiguous.notes.contains(ReceiptAmountIssue.ambiguous.message))
    }

    /// 8：合計を判断できなければ金額は空（いちばん大きい数字などで推測しない）
    func testUnknownTotalLeavesAmountEmpty() {
        let proposal = extract(["牛乳 198", "パン 250", "お預り 1,000"])
        XCTAssertNil(proposal.amount)
        XCTAssertEqual(proposal.amountIssue, .notFound)
        XCTAssertTrue(proposal.notes.contains(ReceiptAmountIssue.notFound.message))
        XCTAssertNil(extract([]).amount)
    }
}

// MARK: - 2. 日付・店名・カテゴリー

final class Build18ReceiptFieldTests: XCTestCase {
    /// 9：西暦・和暦の日付を読める
    func testReadsWesternAndJapaneseDates() {
        XCTAssertEqual(extract(["2026年11月2日(月) 18:42"]).date, TestDates.make(2026, 11, 2))
        XCTAssertEqual(extract(["2026/11/02 18:42"]).date, TestDates.make(2026, 11, 2))
        XCTAssertEqual(extract(["2026-11-03"]).date, TestDates.make(2026, 11, 3))
        XCTAssertEqual(extract(["令和8年11月4日"]).date, TestDates.make(2026, 11, 4))
        XCTAssertEqual(extract(["R8.11.5 12:00"]).date, TestDates.make(2026, 11, 5))
        XCTAssertEqual(extract(["２０２６年１１月６日"]).date, TestDates.make(2026, 11, 6), "全角")
        XCTAssertTrue(extract(["2026/11/02"]).isDateFromReceipt)
        // 有効期限の日付は購入日にしない
        XCTAssertEqual(extract(["ポイント有効期限 2027/03/31", "2026/11/07"]).date, TestDates.make(2026, 11, 7))
    }

    /// 10：存在しない日付は使わない（別の日に直さない）。読めなければ今日
    func testNonexistentDateIsNotAdopted() {
        let proposal = extract(["2026/02/30 12:00", "合計 500"])
        XCTAssertEqual(proposal.date, LifeCalendar.startOfDay(build18Now), "今日を初期値にする")
        XCTAssertNotEqual(proposal.date, TestDates.make(2026, 3, 2), "3月2日などに直さない")
        XCTAssertFalse(proposal.isDateFromReceipt)
        XCTAssertTrue(proposal.notes.contains("日付を読み取れなかったため、今日にしました。"))
        XCTAssertEqual(extract(["令和8年2月29日"]).date, LifeCalendar.startOfDay(build18Now), "2026年に2月29日は無い")
        XCTAssertEqual(extract(["2026/13/01"]).date, LifeCalendar.startOfDay(build18Now))
    }

    /// 11：店名の候補を作る（あいさつ・住所・電話番号・登録番号・見出しは店名にしない）
    func testStoreNameCandidate() {
        let proposal = extract(supermarketReceipt)
        XCTAssertEqual(proposal.title, "スーパーマルエツ 新宿店")
        XCTAssertTrue(proposal.isTitleFromReceipt)
        XCTAssertEqual(extract(["領収書", "カフェ・ド・テスト", "TEL 06-1111-2222"]).title, "カフェ・ド・テスト")
        XCTAssertEqual(extract(["**** 薬局テスト ****", "合計 300"]).title, "薬局テスト")
        XCTAssertEqual(extract(["店名：まちの八百屋", "合計 300"]).title, "まちの八百屋")
        for notName in ["TEL 03-1234-5678", "東京都新宿区西新宿1-2-3", "登録番号 T1234567890123", "いらっしゃいませ", "毎度ありがとうございます", "www.example.jp", "No.123456"] {
            XCTAssertFalse(extract([notName]).isTitleFromReceipt, notName)
        }
    }

    /// 12：店名が無ければ「レシート」
    func testFallbackTitleIsReceipt() {
        let proposal = extract(["2026/11/02", "合計 500"])
        XCTAssertEqual(proposal.title, "レシート")
        XCTAssertEqual(ReceiptFieldExtractor.fallbackTitle, "レシート")
        XCTAssertFalse(proposal.isTitleFromReceipt)
        XCTAssertEqual(extract([]).title, "レシート")
    }

    /// 13：確かな手掛かりがあるときのカテゴリーの候補
    func testCategoryCandidates() {
        XCTAssertEqual(extract(supermarketReceipt).category, .food, "スーパー")
        XCTAssertEqual(extract(["ラーメン一番", "合計 900"]).category, .diningOut)
        XCTAssertEqual(extract(["スターバックス コーヒー", "合計 600"]).category, .diningOut)
        XCTAssertEqual(extract(["ENEOS 新宿SS", "レギュラー 30L", "合計 5,000"]).category, .transport)
        XCTAssertEqual(extract(["○○タクシー", "運賃 1,500"]).category, .transport)
        XCTAssertEqual(extract(["ドラッグストアテスト", "合計 700"]).category, .dailyGoods)
        XCTAssertEqual(extract(["カインズ 練馬店", "合計 2,000"]).category, .dailyGoods)
    }

    /// 14：判断できなければ「その他」（手掛かりが無い・2種類以上ある）
    func testUndeterminedCategoryIsOther() {
        XCTAssertEqual(extract(["テスト商店", "合計 500"]).category, .other)
        XCTAssertEqual(extract(["スーパーテスト", "イートイン ラーメン", "合計 800"]).category, .other, "食費と外食の両方の手掛かり")
        XCTAssertEqual(extract([]).category, .other)
    }
}

// MARK: - 3. 確認画面と保存

final class Build18ReceiptFlowTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build18-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 15：レシートから作った新しい支出の保存先は「自分だけ」。候補が入り、保存するまで支出は作らない
    @MainActor
    func testReceiptDraftDefaultsToPersonalAndDoesNotSaveUntilConfirmed() async throws {
        let setup = makeReceiptSetup()
        XCTAssertTrue(setup.viewModel.canStartReceiptScan)
        setup.viewModel.startReceiptScan()
        XCTAssertTrue(setup.viewModel.isChoosingReceiptSource, "撮るか選ぶかを出す")

        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertTrue(setup.viewModel.isReadingReceipt)
        XCTAssertFalse(setup.viewModel.canStartReceiptScan)
        await setup.viewModel.waitForReceiptReading()

        let draft = try XCTUnwrap(setup.viewModel.draft)
        XCTAssertTrue(draft.isNew)
        XCTAssertTrue(draft.isFromReceipt)
        XCTAssertEqual(draft.destination, .personal, "初期値は必ず自分だけ")
        XCTAssertEqual(draft.title, "スーパーマルエツ 新宿店")
        XCTAssertEqual(draft.amount, 483)
        XCTAssertEqual(draft.category, .food)
        XCTAssertEqual(draft.date, TestDates.make(2026, 11, 2))
        XCTAssertFalse(setup.viewModel.isReadingReceipt)
        XCTAssertTrue(setup.store.expenses.isEmpty, "保存するまで家計簿に入れない")
        XCTAssertEqual(setup.backend.writeCount, 0)
    }

    /// 16：利用者が「わが家で共有」を選んだときだけ共有する（共有する項目は今までの9項目だけ）
    @MainActor
    func testSharesOnlyWhenUserChooses() async throws {
        let personal = makeReceiptSetup()
        personal.viewModel.readReceipt(receiptImage, contentType: .png)
        await personal.viewModel.waitForReceiptReading()
        XCTAssertTrue(personal.viewModel.save(try XCTUnwrap(personal.viewModel.draft)))
        XCTAssertEqual(personal.backend.writeCount, 0, "自分だけは送らない")
        XCTAssertEqual(personal.store.expenses.count, 1)

        let shared = makeReceiptSetup()
        shared.viewModel.readReceipt(receiptImage, contentType: .png)
        await shared.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(shared.viewModel.draft)
        draft.destination = .household
        XCTAssertTrue(shared.viewModel.save(draft))
        XCTAssertEqual(shared.backend.creates.count, 1)
        let fields = try XCTUnwrap(shared.backend.creates.first?.fields)
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "title", "amount", "category", "date", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertEqual(fields["amount"], .int(483))
        XCTAssertTrue(shared.store.expenses.isEmpty, "共有の支出を個人として二重に保存しない")

        // 家計簿がオフなら選んでも共有しない
        let off = makeReceiptSetup(money: false)
        off.viewModel.readReceipt(receiptImage, contentType: .png)
        await off.viewModel.waitForReceiptReading()
        var offDraft = try XCTUnwrap(off.viewModel.draft)
        XCTAssertFalse(off.viewModel.canChoose(.household, in: offDraft))
        offDraft.destination = .household
        XCTAssertTrue(off.viewModel.save(offDraft))
        XCTAssertEqual(off.backend.writeCount, 0)
        XCTAssertEqual(off.store.expenses.count, 1)
    }

    /// 17：キャンセルでは支出を保存しない（確認画面のキャンセル・読み取り中のキャンセル）
    @MainActor
    func testCancelDoesNotSave() async throws {
        let setup = makeReceiptSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertNotNil(setup.viewModel.draft)
        setup.viewModel.cancelEditing()
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertTrue(setup.store.expenses.isEmpty)

        // 読み取り中にキャンセル：あとから結果が届いても画面を開かない・保存しない
        let slow = makeReceiptSetup(delay: 300_000_000)
        slow.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertTrue(slow.viewModel.isReadingReceipt)
        slow.viewModel.cancelReceiptReading()
        XCTAssertFalse(slow.viewModel.isReadingReceipt)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(slow.viewModel.draft, "キャンセルのあとに届いた結果は捨てる")
        XCTAssertTrue(slow.store.expenses.isEmpty)
        XCTAssertEqual(slow.backend.writeCount, 0)
        XCTAssertTrue(slow.viewModel.canStartReceiptScan, "もう一度始められる")
    }

    /// 18：保存で支出を1件だけ作り、お金の画面の合計・カテゴリーの合計・一覧にすぐ出る
    @MainActor
    func testSaveCreatesExactlyOneExpense() async throws {
        let setup = makeReceiptSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(setup.viewModel.draft)
        draft.title = "マルエツ"
        draft.amountText = "500"
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertEqual(setup.store.expenses.count, 1)
        XCTAssertEqual(setup.store.expenses.first?.title, "マルエツ", "利用者が直した内容で保存")
        XCTAssertEqual(setup.store.expenses.first?.amount, 500)
        XCTAssertEqual(setup.store.expenses.first?.ownership, .personal)
        XCTAssertEqual(setup.viewModel.spent, 500)
        XCTAssertEqual(setup.viewModel.categoryTotals, [ExpenseCategoryTotal(category: .food, amount: 500)])
        XCTAssertEqual(setup.viewModel.expenses.map(\.title), ["マルエツ"])
    }

    /// 19：保存を続けて押しても2件作らない（読み取りも二重に始めない）
    @MainActor
    func testDoubleTapDoesNotCreateTwo() async throws {
        let setup = makeReceiptSetup(delay: 100_000_000)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        setup.viewModel.startReceiptScan()
        XCTAssertFalse(setup.viewModel.isChoosingReceiptSource, "読み取り中は始めない")
        await setup.viewModel.waitForReceiptReading()
        let draft = try XCTUnwrap(setup.viewModel.draft)
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertFalse(setup.viewModel.save(draft), "同じ下書きの2回目は保存しない")
        XCTAssertEqual(setup.store.expenses.count, 1)

        // 共有でも2件にしない
        let shared = makeReceiptSetup()
        shared.viewModel.readReceipt(receiptImage, contentType: .png)
        await shared.viewModel.waitForReceiptReading()
        var sharedDraft = try XCTUnwrap(shared.viewModel.draft)
        sharedDraft.destination = .household
        XCTAssertTrue(shared.viewModel.save(sharedDraft))
        XCTAssertFalse(shared.viewModel.save(sharedDraft))
        XCTAssertEqual(shared.backend.creates.count, 1)
        XCTAssertEqual(shared.store.visibleExpenses(scope: .all).count, 1)
    }

    /// 20：読み取りに失敗しても手入力できる（金額が空・不正なら保存できず、理由がある）
    @MainActor
    func testRecognitionFailureStillAllowsManualEntry() async throws {
        let setup = makeReceiptSetup(lines: nil)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(setup.viewModel.draft, "失敗しても追加画面を開く")
        XCTAssertEqual(draft.title, "レシート")
        XCTAssertEqual(draft.amountText, "")
        XCTAssertEqual(draft.destination, .personal)
        XCTAssertEqual(draft.receiptNotes, ["読み取れませんでした。手入力できます。"])
        XCTAssertFalse(draft.canSave, "金額が空なら保存できない")
        XCTAssertFalse(setup.viewModel.save(draft))
        draft.amountText = "0"
        XCTAssertFalse(draft.canSave, "0円は保存できない")
        draft.amountText = "1,000,000,000"
        XCTAssertFalse(draft.canSave, "上限を超えると保存できない")
        draft.amountText = "１，２００円"
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.amount), [1200])

        // 文字が1つも読めなかったときも同じ
        let empty = makeReceiptSetup(lines: ["", "  "])
        empty.viewModel.readReceipt(receiptImage, contentType: .png)
        await empty.viewModel.waitForReceiptReading()
        XCTAssertEqual(empty.viewModel.draft?.receiptNotes, ["読み取れませんでした。手入力できます。"])
        // 合計が分からないときは金額を空にして理由を出す
        let noTotal = makeReceiptSetup(lines: ["テスト商店", "牛乳 198"])
        noTotal.viewModel.readReceipt(receiptImage, contentType: .png)
        await noTotal.viewModel.waitForReceiptReading()
        XCTAssertEqual(noTotal.viewModel.draft?.amountText, "")
        XCTAssertTrue(noTotal.viewModel.draft?.receiptNotes.contains(ReceiptAmountIssue.notFound.message) == true)
    }

    /// 21：写真・読み取った全文を保存しない（端末のファイルにも、下書きにも）
    @MainActor
    func testImageAndFullTextAreNotPersisted() async throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeReceiptSetup(store: store)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        let draft = try XCTUnwrap(setup.viewModel.draft)
        // 下書きに入るのは4つの候補と一言だけ（全文は持たない）
        let draftText = Mirror(reflecting: draft).children.map { "\($0.value)" }.joined(separator: "\n")
        for ocrOnly in ["いらっしゃいませ", "03-1234-5678", "T1234567890123", "お預り", "お釣り", "食パン"] {
            XCTAssertFalse(draftText.contains(ocrOnly), ocrOnly)
        }
        XCTAssertTrue(setup.viewModel.save(draft))
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        for ocrOnly in ["いらっしゃいませ", "03-1234-5678", "T1234567890123", "お預り", "牛乳", "食パン"] {
            XCTAssertFalse(file.contains(ocrOnly), "端末のファイルに読み取った全文を書かない：\(ocrOnly)")
        }
        XCTAssertFalse(file.contains(receiptImage.base64EncodedString().prefix(40)), "写真を書かない")
        // フォルダにも写真のファイルを作らない
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertEqual(files.filter { $0.lowercased().hasSuffix(".png") || $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".heic") }, [])
    }

    /// 22：Firestore へ写真・読み取った全文を送らない（共有しても、支出の9項目だけ）
    @MainActor
    func testFirestoreReceivesNoImageOrFullText() async throws {
        let setup = makeReceiptSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(setup.viewModel.draft)
        draft.destination = .household
        XCTAssertTrue(setup.viewModel.save(draft))
        let fields = try XCTUnwrap(setup.backend.creates.first?.fields)
        XCTAssertEqual(fields.count, 9)
        let values = fields.values.map { "\($0)" }.joined(separator: "\n")
        for ocrOnly in ["いらっしゃいませ", "03-1234-5678", "T1234567890123", "お預り", "牛乳", "食パン", "小計"] {
            XCTAssertFalse(values.contains(ocrOnly), ocrOnly)
        }
        for key in ["receipt", "receiptImage", "image", "photo", "ocr", "text", "memo"] {
            XCTAssertNil(fields[key], key)
        }
        // 読み取りの処理は、Firebase の窓口を使わない
        let recognizer = try build18Source("LifeOS/Core/Utilities/ReceiptTextRecognizer.swift")
        XCTAssertFalse(recognizer.contains("Firebase"))
        XCTAssertFalse(recognizer.contains("URLSession"))
    }

    /// 23：ログに店名・金額・全文を出さない（レシートの部品・お金の画面に、ログの呼び出しが無い）
    func testNoLoggingInReceiptFlow() throws {
        for path in [
            "LifeOS/Core/Utilities/ReceiptFieldExtractor.swift",
            "LifeOS/Core/Utilities/ReceiptTextRecognizer.swift",
            "LifeOS/Core/Utilities/WarrantyTextRecognizer.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift"
        ] {
            let source = try build18Source(path)
            for call in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump("] {
                XCTAssertFalse(source.contains(call), "\(path)：\(call)")
            }
        }
    }

    /// 26：保存・キャンセルのあと、写真と読み取った結果をメモリに持ち続けない
    @MainActor
    func testImageAndResultsAreReleasedAfterSaveOrCancel() async throws {
        func heldPayloads(_ viewModel: MoneyViewModel) -> [String] {
            Mirror(reflecting: viewModel).children.compactMap { child in
                switch child.value {
                case is Data, is [Data], is [String], is [WarrantyRecognizedLine], is ReceiptExtractionProposal:
                    return child.label ?? "?"
                default:
                    return nil
                }
            }
        }
        let setup = makeReceiptSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertTrue(setup.viewModel.isHoldingReceiptWork)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertFalse(setup.viewModel.isHoldingReceiptWork, "読み取りが終わったら処理を手放す")
        XCTAssertEqual(heldPayloads(setup.viewModel), [])
        XCTAssertTrue(setup.viewModel.save(try XCTUnwrap(setup.viewModel.draft)))
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertEqual(heldPayloads(setup.viewModel), [])

        let slow = makeReceiptSetup(delay: 300_000_000)
        slow.viewModel.readReceipt(receiptImage, contentType: .png)
        slow.viewModel.cancelReceiptReading()
        XCTAssertFalse(slow.viewModel.isHoldingReceiptWork, "キャンセルしたら処理を手放す")
        XCTAssertEqual(heldPayloads(slow.viewModel), [])
        // 写真は画面の状態にも残さない（カメラの画面が閉じたら読み取りへ渡して手放す）
        let view = try build18Source("LifeOS/Features/Money/MoneyView.swift")
        XCTAssertTrue(view.contains("capturedReceipt = nil\n        viewModel.readReceipt(captured.data, contentType: captured.type)"))
        XCTAssertTrue(view.contains("defer { receiptPhotoItem = nil }"))
    }
}

// MARK: - 4. 写真・カメラ・失敗

final class Build18ReceiptImageTests: XCTestCase {
    /// HEIC・JPEG・PNG だけ。25MB を超える・未対応の形式・読めないデータは読み取らない（アプリは止まらない）
    func testValidatesSizeAndFormat() {
        XCTAssertNil(ReceiptTextRecognizer.validate(receiptImage), "PNG（中身から判定）")
        XCTAssertNil(ReceiptTextRecognizer.validate(receiptImage, contentType: .png))
        XCTAssertNil(ReceiptTextRecognizer.validate(receiptImage, contentType: .jpeg))
        XCTAssertNil(ReceiptTextRecognizer.validate(receiptImage, contentType: .heic))
        XCTAssertEqual(ReceiptTextRecognizer.validate(receiptImage, contentType: .gif), .unsupportedType)
        XCTAssertEqual(ReceiptTextRecognizer.validate(receiptImage, contentType: .pdf), .unsupportedType)
        XCTAssertEqual(ReceiptTextRecognizer.validate(Data(count: Int(ReceiptTextRecognizer.maxBytes) + 1), contentType: .jpeg), .tooLarge)
        XCTAssertEqual(ReceiptTextRecognizer.maxBytes, 25 * 1024 * 1024)
        XCTAssertEqual(ReceiptTextRecognizer.validate(Data("not an image".utf8)), .unreadable)
        XCTAssertEqual(ReceiptTextRecognizer.validate(Data()), .unreadable)
    }

    /// 28：カメラを使えない・許可されていない・写真を読み込めない・大きすぎる・形式が違うときも落ちず、手入力できる
    @MainActor
    func testCameraDeniedMissingAndPhotoLoadFailureDoNotCrash() async throws {
        // カメラの画面は、使えない・許可されていないときに理由を出す（保証書と同じ部品）
        let camera = try build18Source("LifeOS/Features/Documents/Warranty/WarrantyCameraView.swift")
        XCTAssertTrue(camera.contains("case .denied:"))
        XCTAssertTrue(camera.contains("case .unavailable:"))
        XCTAssertTrue(camera.contains("guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }"))

        let cases: [(ReceiptImageError, Data?, UTType?)] = [
            (.loadFailed, nil, nil),
            (.tooLarge, Data(count: Int(ReceiptTextRecognizer.maxBytes) + 1), .jpeg),
            (.unsupportedType, receiptImage, .gif),
            (.unreadable, Data("broken".utf8), nil)
        ]
        for (error, data, type) in cases {
            let setup = makeReceiptSetup()
            if let data {
                setup.viewModel.readReceipt(data, contentType: type)
            } else {
                setup.viewModel.receiptImageFailed(error)
            }
            XCTAssertFalse(setup.viewModel.isReadingReceipt, "\(error)：読み取りを始めない")
            let draft = try XCTUnwrap(setup.viewModel.draft, "\(error)：手入力の画面を開く")
            XCTAssertEqual(draft.receiptNotes, [error.message])
            XCTAssertEqual(draft.title, "レシート")
            XCTAssertEqual(draft.destination, .personal)
            XCTAssertTrue(setup.store.expenses.isEmpty)
        }
        XCTAssertEqual(ReceiptImageError.unreadable.message, "読み取れませんでした。手入力できます。")
    }

    /// 27：VoiceOver のラベル・44pt 以上の操作領域・撮影の案内
    func testAccessibilityAndTapTargets() throws {
        let view = try build18Source("LifeOS/Features/Money/MoneyView.swift")
        XCTAssertTrue(view.contains("LifeButton(\"レシートを読み取る\", systemImage: \"doc.text.viewfinder\", kind: .secondary)"))
        XCTAssertTrue(view.contains(".accessibilityHint(\"レシートを撮るか写真から選んで、この iPhone の中で読み取ります\")"))
        XCTAssertTrue(view.contains("Button(\"カメラで撮る\")"))
        XCTAssertTrue(view.contains("Button(\"写真から選ぶ\")"))
        XCTAssertTrue(view.contains("Button(\"キャンセル\", role: .cancel) {}"))
        XCTAssertTrue(view.contains("Text(\"このiPhoneの中でレシートを読み取っています…\")"))
        XCTAssertTrue(view.contains(".accessibilityLabel(\"レシートの読み取りをキャンセル\")"))
        XCTAssertTrue(view.contains(".frame(minWidth: LifeSpacing.minTapTarget * 2, minHeight: LifeSpacing.minTapTarget)"))
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        XCTAssertGreaterThanOrEqual(LifeSpacing.buttonHeight, 44, "LifeButton の高さ")
        XCTAssertTrue(view.contains("WarrantyCameraView(guide: WarrantyCameraView.receiptGuide)"))
        XCTAssertTrue(view.contains("matching: .images"))
    }
}

// MARK: - 5. 既存の機能

final class Build18RegressionTests: XCTestCase {
    /// 24：保証書の文字の読み取り・撮影の案内は今までどおり
    func testWarrantyRecognitionStillWorks() async throws {
        XCTAssertEqual(WarrantyCameraView.warrantyGuide, "保証書・レシート・製品ラベルを枠いっぱいに", "保証書の案内は変えない")
        let camera = try build18Source("LifeOS/Features/Documents/Warranty/WarrantyEditorView.swift")
        XCTAssertTrue(camera.contains("WarrantyCameraView { data, type in"), "保証書は今までの呼び出しのまま（案内は既定の文言）")
        let proposal = WarrantyFieldExtractor.extract(from: [
            WarrantyRecognizedLine(text: "型番 AB-123"),
            WarrantyRecognizedLine(text: "お買上げ日 2026/10/13")
        ])
        XCTAssertEqual(proposal.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
        XCTAssertEqual(proposal.fields.first { $0.kind == .purchaseDate }?.date, TestDates.make(2026, 10, 13))
        // 端末内の Vision の読み取りも落ちない・外へ通信しない
        NetworkSpyProtocol.requestedURLs = []
        URLProtocol.registerClass(NetworkSpyProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkSpyProtocol.self) }
        _ = try? await WarrantyTextRecognizer.proposal(for: [WarrantyTestImages.text(["型番 AB-123"])])
        _ = try? await ReceiptTextRecognizer().recognizeLines(in: WarrantyTestImages.text(["合計 ¥483"]))
        XCTAssertEqual(NetworkSpyProtocol.requestedURLs, [])
    }

    /// 25：自分だけ・共有の支出の編集・削除・保存先の変更は今までどおり
    @MainActor
    func testExistingExpenseEditDeleteAndDestinationChangeStillWork() throws {
        let setup = makeReceiptSetup()
        let viewModel = setup.viewModel
        viewModel.startAdding()
        var draft = try XCTUnwrap(viewModel.draft)
        XCTAssertFalse(draft.isFromReceipt, "ふつうの追加はレシートの下書きではない")
        draft.title = "ランチ"
        draft.amountText = "980"
        XCTAssertTrue(viewModel.save(draft))
        let lunch = try XCTUnwrap(setup.store.expenses.first)

        // 編集
        viewModel.startEditing(lunch)
        var edit = try XCTUnwrap(viewModel.draft)
        edit.amountText = "1,080"
        XCTAssertTrue(viewModel.save(edit))
        XCTAssertEqual(setup.store.expenses.first?.amount, 1080)
        XCTAssertEqual(setup.store.expenses.count, 1, "編集で2件にしない")

        // 自分だけ → 共有
        viewModel.startEditing(try XCTUnwrap(setup.store.expenses.first))
        var toShared = try XCTUnwrap(viewModel.draft)
        toShared.destination = .household
        XCTAssertTrue(viewModel.save(toShared))
        XCTAssertEqual(setup.backend.creates.count, 1)

        // 共有の支出の削除
        let shared = try XCTUnwrap(setup.store.visibleExpenses(scope: .shared).first)
        viewModel.requestDelete(shared)
        XCTAssertTrue(viewModel.confirmDelete())
        XCTAssertEqual(setup.backend.deletes.count, 1)
    }

    /// Build 18・Version 1.0・暗号化の設定。Build 16 は欠番のまま（記録を残す）
    func testBuildNumberIs18() throws {
        let project = try build18Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 18;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        let build17 = try build18Source("docs/BUILD_17_EVENT_DESTINATION_SWITCH.md")
        XCTAssertTrue(build17.contains("Build 16 は欠番"))
    }
}
