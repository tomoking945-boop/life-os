import XCTest
@testable import LifeOS

// Build 19（2026-11-04）：レシートの店名候補から正しい店名を選ぶ・カレンダーの予定を登録した人の色で表示する。
// docs/BUILD_19_RECEIPT_STORE_SELECTION_AND_CALENDAR_COLORS.md
// 本物の Firestore・ネットワークは使わない（共有項目は SharedTodoShoppingTests.swift の FakeSharedServer・FakeSharedItemsBackend、
// 共有の支出は Build13 の FakeSharedExpensesBackend）。

private let build19Now = TestDates.make(2026, 11, 10, 9, 0)
private let build19Day = TestDates.make(2026, 11, 20)

private func build19Store() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func build19Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func codeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

private func candidates(_ lines: [String]) -> [String] {
    ReceiptFieldExtractor.extract(from: lines, today: build19Now).storeCandidates
}

/// 店名の候補が複数あるレシート
private let multiStoreReceipt = [
    "いらっしゃいませ",
    "まちの八百屋",
    "八百八町そば 本店",
    "TEL 03-1234-5678",
    "東京都台東区浅草1-2-3",
    "三越 日本橋店",
    "登録番号 T1234567890123",
    "2026年11月2日(月) 18:42",
    "大根 198",
    "合計 ¥198"
]

/// 偽物の文字認識（読み取った行を返すだけ）
private struct Build19FakeRecognizer: ReceiptTextRecognizing {
    var lines: [String]
    func recognizeLines(in imageData: Data) async throws -> [String] { lines }
}

private struct Build19ReceiptSetup {
    let store: LifeStore
    let backend: FakeSharedExpensesBackend
    let service: SharedExpensesService
    let viewModel: MoneyViewModel
}

private func makeReceiptSetup(lines: [String] = multiStoreReceipt, store: LifeStore = build19Store()) -> Build19ReceiptSetup {
    let backend = FakeSharedExpensesBackend()
    let service = SharedExpensesService(backend: backend)
    service.attach(store)
    service.apply(household: HouseholdSummary(
        name: "わが家", sharedKinds: [.todo, .shopping, .money], isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build19"
    ), isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = .shared
    let viewModel = MoneyViewModel(store: store, appState: appState, now: build19Now, receiptRecognizer: Build19FakeRecognizer(lines: lines))
    return Build19ReceiptSetup(store: store, backend: backend, service: service, viewModel: viewModel)
}

private let receiptImage = WarrantyTestImages.text(["合計 ¥198"])

// MARK: - 1. 店名の候補（抽出）

final class Build19StoreCandidateExtractionTests: XCTestCase {
    /// 1：複数の店名の候補を、上から順に返す
    func testReturnsCandidatesTopToBottom() {
        XCTAssertEqual(candidates(multiStoreReceipt), ["まちの八百屋", "八百八町そば 本店", "三越 日本橋店"])
    }

    /// 2：最大5件
    func testAtMostFiveCandidates() {
        let lines = ["一の店", "二の店", "三の店", "四の店", "五の店", "六の店", "七の店"]
        XCTAssertEqual(candidates(lines), ["一の店", "二の店", "三の店", "四の店", "五の店"])
        XCTAssertEqual(ReceiptFieldExtractor.maxStoreCandidates, 5)
    }

    /// 3：同じ候補は1つだけ
    func testRemovesDuplicates() {
        XCTAssertEqual(candidates(["まちの八百屋", "まちの八百屋", "**** まちの八百屋 ****", "三越 日本橋店"]), ["まちの八百屋", "三越 日本橋店"])
    }

    /// 4：「店名：」「店舗名：」や前後の飾り文字を除く。40文字まで
    func testRemovesLabelsAndDecorations() {
        XCTAssertEqual(candidates(["店名：まちの八百屋", "店舗名: 三越 日本橋店", "【カフェ・ド・テスト】", "=== 薬局テスト ==="]),
                       ["まちの八百屋", "三越 日本橋店", "カフェ・ド・テスト", "薬局テスト"])
        let long = String(repeating: "あ", count: 50)
        XCTAssertEqual(candidates([long]).first?.count, 40)
    }

    /// 5：電話番号・郵便番号・住所・登録番号・レシート番号・レジ番号・日時・URL・あいさつは候補にしない
    func testExcludesContactNumbersDatesUrlsAndGreetings() {
        let notNames = [
            "TEL 03-1234-5678", "０３－１２３４－５６７８", "〒160-0023", "東京都新宿区西新宿1-2-3", "新宿区西新宿二丁目",
            "登録番号 T1234567890123", "インボイス T1234567890123", "レシート番号 0012", "レジ 3", "伝票 No.123", "取引番号 456",
            "18:42", "www.example.jp", "https://example.jp", "いらっしゃいませ", "毎度ありがとうございます", "またのご来店をお待ちしております"
        ]
        for line in notNames {
            XCTAssertEqual(candidates([line]), [], line)
        }
        XCTAssertEqual(candidates(["いらっしゃいませ", "TEL 03-1234-5678", "〒160-0023", "www.example.jp", "まちの八百屋"]), ["まちの八百屋"], "除いたあとに残る店名だけ")
    }

    /// 6：合計・小計・税・商品の明細は候補にしない（明細より下は探さない）
    func testExcludesTotalsAndItemDetails() {
        XCTAssertEqual(candidates(["まちの八百屋", "大根 198", "かぶ 2点", "下の店"]), ["まちの八百屋"], "明細から下は探さない")
        for line in ["小計", "消費税等", "内税", "商品明細", "合計点数", "合計"] {
            XCTAssertEqual(candidates([line]), [], line)
        }
        XCTAssertEqual(candidates(["まちの八百屋", "合計 ¥198", "下の店"]), ["まちの八百屋"])
        XCTAssertEqual(candidates(["まちの八百屋", "牛乳 1,980円", "下の店"]), ["まちの八百屋"])
    }

    /// 7：漢数字を含む店名を残す
    func testKeepsKanjiNumeralNames() {
        XCTAssertEqual(candidates(["まちの八百屋", "三越 日本橋店", "八百八町そば"]), ["まちの八百屋", "三越 日本橋店", "八百八町そば"])
    }

    /// 8：最初の有効な候補が、はじめのタイトル
    func testFirstValidCandidateIsInitialTitle() {
        let proposal = ReceiptFieldExtractor.extract(from: multiStoreReceipt, today: build19Now)
        XCTAssertEqual(proposal.title, "まちの八百屋")
        XCTAssertEqual(proposal.title, proposal.storeCandidates.first)
        XCTAssertTrue(proposal.isTitleFromReceipt)
    }

    /// 9：候補が無ければ「レシート」
    func testNoCandidateFallsBackToReceipt() {
        let proposal = ReceiptFieldExtractor.extract(from: ["2026/11/02", "合計 500"], today: build19Now)
        XCTAssertEqual(proposal.title, "レシート")
        XCTAssertEqual(proposal.storeCandidates, [])
        XCTAssertFalse(proposal.isTitleFromReceipt)
    }
}

// MARK: - 2. 店名の候補（確認画面・保存）

final class Build19StoreCandidateFlowTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build19-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    @MainActor
    private func readDraft(_ setup: Build19ReceiptSetup) async throws -> ExpenseDraft {
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        return try XCTUnwrap(setup.viewModel.draft)
    }

    /// 10：候補を選ぶとタイトルが変わる（候補に無い名前は選べない）。選んでいる候補が分かる
    @MainActor
    func testSelectingCandidateChangesTitle() async throws {
        var draft = try await readDraft(makeReceiptSetup())
        XCTAssertEqual(draft.storeCandidates, ["まちの八百屋", "八百八町そば 本店", "三越 日本橋店"])
        XCTAssertEqual(draft.title, "まちの八百屋")
        XCTAssertTrue(draft.isSelectedStoreCandidate("まちの八百屋"))
        draft.selectStoreCandidate("三越 日本橋店")
        XCTAssertEqual(draft.title, "三越 日本橋店")
        XCTAssertTrue(draft.isSelectedStoreCandidate("三越 日本橋店"))
        XCTAssertFalse(draft.isSelectedStoreCandidate("まちの八百屋"))
        draft.selectStoreCandidate("候補に無い店")
        XCTAssertEqual(draft.title, "三越 日本橋店", "候補に無い名前は選べない（手入力はタイトル欄で）")
    }

    /// 11・12：手入力で候補に無い名前にできる。保存するのは最後のタイトルだけ
    @MainActor
    func testManualTitleAndOnlyFinalTitleIsSaved() async throws {
        let setup = makeReceiptSetup()
        var draft = try await readDraft(setup)
        draft.selectStoreCandidate("八百八町そば 本店")
        draft.title = "八百八町そば（浅草）"
        XCTAssertFalse(draft.storeCandidates.contains(draft.title))
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.title), ["八百八町そば（浅草）"])
        XCTAssertEqual(setup.store.expenses.count, 1)
    }

    /// 13：候補の一覧・読み取った全文を保存しない（端末のファイルにも、支出にも）
    @MainActor
    func testCandidatesAndFullTextAreNotPersisted() async throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeReceiptSetup(store: store)
        var draft = try await readDraft(setup)
        draft.selectStoreCandidate("三越 日本橋店")
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertNil(setup.viewModel.draft, "確認画面を閉じたら候補ごと手放す")
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(file.contains("三越 日本橋店"), "選んだタイトルだけ保存する")
        for notSaved in ["まちの八百屋", "八百八町そば 本店", "いらっしゃいませ", "03-1234-5678", "大根", "storeCandidates"] {
            XCTAssertFalse(file.contains(notSaved), notSaved)
        }
        let saved = try XCTUnwrap(store.expenses.first)
        XCTAssertEqual(Set(Mirror(reflecting: saved).children.compactMap(\.label)), ["id", "title", "amount", "category", "date", "ownership"], "支出に候補を足していない")
        // 共有しても、送るのは今までの9項目だけ
        let shared = makeReceiptSetup()
        var sharedDraft = try await readDraft(shared)
        sharedDraft.destination = .household
        XCTAssertTrue(shared.viewModel.save(sharedDraft))
        let fields = try XCTUnwrap(shared.backend.creates.first?.fields)
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "title", "amount", "category", "date", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        XCTAssertFalse(fields.values.map { "\($0)" }.joined().contains("三越"), "選ばなかった候補を送らない")
    }

    /// 14：外部と通信しない（候補を作る・選ぶ・保存する）
    @MainActor
    func testNoNetworkAccess() async throws {
        NetworkSpyProtocol.requestedURLs = []
        URLProtocol.registerClass(NetworkSpyProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkSpyProtocol.self) }
        let setup = makeReceiptSetup()
        var draft = try await readDraft(setup)
        draft.selectStoreCandidate("三越 日本橋店")
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(NetworkSpyProtocol.requestedURLs, [])
        for path in ["LifeOS/Core/Utilities/ReceiptFieldExtractor.swift", "LifeOS/Features/Money/MoneyView.swift", "LifeOS/Features/Money/MoneyViewModel.swift"] {
            let code = codeOnly(try build19Source(path))
            for word in ["URLSession", "URLRequest", "Firestore.firestore", "import Firebase", "print(", "NSLog(", "os_log(", "Logger("] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
    }

    /// 15：キャンセルでは支出を作らない
    @MainActor
    func testCancelCreatesNothing() async throws {
        let setup = makeReceiptSetup()
        var draft = try await readDraft(setup)
        draft.selectStoreCandidate("三越 日本橋店")
        setup.viewModel.cancelEditing()
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertTrue(setup.store.expenses.isEmpty)
        XCTAssertEqual(setup.backend.writeCount, 0)
    }

    /// 16：二重に保存しない
    @MainActor
    func testDoubleSaveCreatesOne() async throws {
        let setup = makeReceiptSetup()
        var draft = try await readDraft(setup)
        draft.selectStoreCandidate("三越 日本橋店")
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertFalse(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.count, 1)
    }

    /// 確認画面：候補は縦に最大5件・選んだ候補にチェック・省略しても VoiceOver は全文・説明の文。候補が0件なら出さない
    func testEditorShowsCandidatesAccessibly() throws {
        let view = codeOnly(try build19Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(view.contains("if draft.isFromReceipt, !draft.storeCandidates.isEmpty {"))
        XCTAssertTrue(view.contains("ForEach(draft.storeCandidates, id: \\.self) { candidate in"))
        XCTAssertTrue(view.contains("draft.selectStoreCandidate(candidate)"))
        XCTAssertTrue(view.contains("Image(systemName: \"checkmark\")"))
        XCTAssertTrue(view.contains(".lineLimit(1)"))
        XCTAssertTrue(view.contains(".truncationMode(.tail)"))
        XCTAssertTrue(view.contains(".accessibilityLabel(candidate)"))
        XCTAssertTrue(view.contains(".accessibilityAddTraits(draft.isSelectedStoreCandidate(candidate) ? [.isSelected] : [])"))
        XCTAssertTrue(view.contains("Text(\"店名候補\")"))
        XCTAssertTrue(view.contains("Text(\"候補を選ぶか、上のタイトル欄に入力できます。\")"))
        XCTAssertTrue(view.contains(".frame(minHeight: LifeSpacing.minTapTarget)"))
        // ふつうの支出の追加には候補を出さない
        var plain = ExpenseDraft(newOn: build19Now)
        XCTAssertEqual(plain.storeCandidates, [])
        plain.selectStoreCandidate("まちの八百屋")
        XCTAssertEqual(plain.title, "")
        // 読み取れなかったときは候補0件・タイトルは「レシート」で手入力できる
        let failed = ExpenseDraft(receipt: nil, today: build19Now, failure: "読み取れませんでした。手入力できます。")
        XCTAssertEqual(failed.storeCandidates, [])
        XCTAssertEqual(failed.title, "レシート")
    }
}

// MARK: - 3. 予定を登録した人の色

/// 端末1台（共有項目）
private struct Build19Device {
    let store: LifeStore
    let backend: FakeSharedItemsBackend
    let service: SharedItemsService
    let appState: AppState

    init(server: FakeSharedServer, uid: String, store: LifeStore = build19Store()) {
        self.store = store
        backend = FakeSharedItemsBackend(server: server, uid: uid)
        service = SharedItemsService(backend: backend)
        service.attach(store)
        service.apply(household: HouseholdSummary(
            name: "わが家", sharedKinds: [.event, .todo, .shopping], isOwner: true,
            members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
            groupID: "group-build19"
        ))
        appState = AppState()
        appState.usageStyle = .shared
        appState.scope = .all
    }

    func calendar() -> CalendarViewModel {
        CalendarViewModel(store: store, appState: appState, now: build19Now)
    }

    func today() -> TodayViewModel {
        TodayViewModel(store: store, appState: appState, now: LifeCalendar.date(on: build19Day, hour: 8, minute: 0))
    }
}

private func eventServer() -> FakeSharedServer {
    let server = FakeSharedServer()
    server.enabledKinds = ["event", "todo", "shopping"]
    return server
}

private func event(_ title: String, hour: Int = 10, on day: Date = build19Day) -> LifeItem {
    LifeItem(title: title, kind: .event, ownership: .personal, date: LifeCalendar.date(on: day, hour: hour, minute: 0), hasTime: true, assignee: .me)
}

private func item(_ title: String, _ kind: LifeItemKind, on day: Date = build19Day) -> LifeItem {
    LifeItem(title: title, kind: kind, ownership: .personal, date: LifeCalendar.startOfDay(day), assignee: .me)
}

final class Build19EventRegistrantTests: XCTestCase {
    /// 17：自分だけの予定は自分の色
    func testPersonalEventIsMine() {
        let alice = Build19Device(server: eventServer(), uid: "alice")
        let dentist = event("歯医者")
        alice.store.add([dentist])
        XCTAssertEqual(alice.store.registrant(of: dentist), .me)
        XCTAssertEqual(alice.calendar().registrant(for: dentist), .me)
        XCTAssertEqual(ItemRegistrant.me.label, "自分")
    }

    /// 18・19：自分が作った共有の予定は自分、パートナーが作った共有の予定はパートナー（送信待ちでも自分）
    func testSharedEventsByMeAndPartner() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.backend.isOnline = false
        alice.store.add([event("家族の予定")], destination: .household)
        let pending = try XCTUnwrap(alice.store.householdEvents.first)
        XCTAssertEqual(alice.store.registrant(of: pending), .me, "送信待ちの自分の作成")
        alice.backend.goOnline()
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        XCTAssertEqual(alice.store.registrant(of: shared), .me)
        XCTAssertEqual(bob.store.registrant(of: shared), .partner)
        XCTAssertEqual(ItemRegistrant.partner.label, "パートナー")
    }

    /// 20・33：登録した人が分からない古い共有の予定はグレー（落ちない）
    func testUnknownCreatorIsGray() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("古い予定")], destination: .household)
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        server.removeCreator(of: shared.id)
        XCTAssertEqual(bob.store.registrant(of: shared), .unknown)
        XCTAssertEqual(alice.store.registrant(of: shared), .unknown)
        XCTAssertEqual(ItemRegistrant.unknown.label, "共有")
        XCTAssertEqual(bob.calendar().dayMarkers(on: build19Day), [.registrant(.unknown)])
        // サインインの情報が無い・形が違うときも不明（落ちない）
        XCTAssertEqual(ItemRegistrant.from(createdBy: nil, currentUID: "alice"), .unknown)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "alice", currentUID: nil), .unknown)
        XCTAssertEqual(ItemRegistrant.from(createdBy: 123, currentUID: "alice"), .unknown)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "", currentUID: "alice"), .unknown)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "alice", currentUID: "alice"), .me)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "bob", currentUID: "alice"), .partner)
        // 以前の形の一覧（登録した人の無いスナップショット）も読める
        let store = build19Store()
        store.applyHouseholdSnapshot([SharedItemSnapshot(item: shared, isConfirmed: true)])
        XCTAssertEqual(store.registrant(of: shared), .unknown)
    }

    /// 21：パートナーが編集しても、登録した人の色は変わらない
    func testPartnerEditDoesNotChangeRegistrant() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("歯医者")], destination: .household)
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        var changed = shared
        changed.title = "歯医者（再診）"
        changed.date = LifeCalendar.date(on: build19Day, hour: 15, minute: 0)
        XCTAssertTrue(bob.store.updateEvent(changed))
        XCTAssertEqual(server.updatedBy(of: shared.id), "bob")
        XCTAssertEqual(alice.store.householdEvents.first?.title, "歯医者（再診）")
        XCTAssertEqual(alice.store.registrant(of: shared), .me, "登録した人（alice）のまま")
        XCTAssertEqual(bob.store.registrant(of: shared), .partner)
    }

    /// 22：自分だけ → わが家で共有は、その操作をした本人の色
    func testPersonalToSharedIsOperatorsColor() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        let dentist = event("歯医者")
        alice.store.add([dentist])
        XCTAssertEqual(alice.store.saveEvent(dentist, destination: .household), .sharingStarted)
        XCTAssertEqual(alice.store.registrant(of: dentist), .me)
        XCTAssertEqual(bob.store.registrant(of: dentist), .partner)
    }

    /// 23：わが家で共有 → 自分だけは自分の色
    func testSharedToPersonalIsMine() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("歯医者")], destination: .household)
        let shared = try XCTUnwrap(bob.store.householdEvents.first)
        XCTAssertEqual(bob.store.registrant(of: shared), .partner)
        XCTAssertEqual(bob.store.saveEvent(shared, destination: .personal), .madePersonal)
        let personal = try XCTUnwrap(bob.store.items.first)
        XCTAssertEqual(bob.store.registrant(of: personal), .me, "自分だけの予定は自分の色")
    }
}

// MARK: - 4. カレンダー・今日の表示

final class Build19CalendarColorDisplayTests: XCTestCase {
    /// 24・25：同じ日に自分とパートナーの予定があれば2色の点。同じ色は1つだけ
    func testTwoColorsWithoutDuplicates() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("自分の予定1", hour: 9), event("自分の予定2", hour: 11)])
        bob.store.add([event("パートナーの予定1")], destination: .household)
        bob.store.add([event("パートナーの予定2", hour: 15)], destination: .household)
        alice.store.add([event("自分の共有の予定", hour: 18)], destination: .household)
        XCTAssertEqual(alice.calendar().dayMarkers(on: build19Day), [.registrant(.me), .registrant(.partner)])
        XCTAssertEqual(bob.calendar().dayMarkers(on: build19Day), [.registrant(.me), .registrant(.partner)])
        XCTAssertEqual(alice.calendar().dayMarkers(on: TestDates.make(2026, 11, 21)), [], "予定の無い日は点なし")
    }

    /// 26：日付の点は最大3つ（予定の色のあとに、ほかの種類のカテゴリー色）
    func testAtMostThreeMarkers() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("自分の予定"), item("書類", .todo), item("牛乳", .shopping), item("ゴミ出し", .chore)])
        bob.store.add([event("パートナーの予定")], destination: .household)
        let markers = alice.calendar().dayMarkers(on: build19Day)
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers, [.registrant(.me), .registrant(.partner), .kind(.todo)])
        XCTAssertEqual(CalendarViewModel.maxMarkerCount, 3)
        // 予定以外の点はこれまでどおり（markerKinds も変えていない）
        XCTAssertEqual(alice.calendar().markerKinds(on: build19Day), [.event, .todo, .chore])
    }

    /// 27：「すべて／自分／共有」の絞り込み後も正しい
    func testMarkersFollowScopeFilter() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("自分だけの予定")])
        bob.store.add([event("パートナーの予定")], destination: .household)
        let calendar = alice.calendar()
        alice.appState.scope = .mine
        XCTAssertEqual(calendar.dayMarkers(on: build19Day), [.registrant(.me)])
        alice.appState.scope = .shared
        XCTAssertEqual(calendar.dayMarkers(on: build19Day), [.registrant(.partner)])
        alice.appState.scope = .all
        XCTAssertEqual(calendar.dayMarkers(on: build19Day), [.registrant(.me), .registrant(.partner)])
    }

    /// 28・32：今日とカレンダーで意味が同じ。色だけに頼らず「自分／パートナー／共有」の文字を出す
    func testTodayAndCalendarMatchAndUseText() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        let bob = Build19Device(server: server, uid: "bob")
        alice.store.add([event("自分の予定", hour: 9), item("書類", .todo)])
        bob.store.add([event("パートナーの予定", hour: 15)], destination: .household)
        let calendar = alice.calendar()
        let today = alice.today()
        for item in alice.store.items(on: build19Day, scope: .all) {
            XCTAssertEqual(today.registrant(for: item), calendar.registrant(for: item), item.title)
        }
        let mine = try XCTUnwrap(alice.store.items.first { $0.title == "自分の予定" })
        let partners = try XCTUnwrap(alice.store.householdEvents.first)
        let todo = try XCTUnwrap(alice.store.items.first { $0.kind == .todo })
        XCTAssertEqual(today.registrantDetail("09:00", for: mine), "自分・09:00")
        XCTAssertEqual(today.registrantDetail(nil, for: partners), "パートナー")
        XCTAssertEqual(today.registrantDetail("書類", for: todo), "書類", "予定以外は変えない")
        XCTAssertNil(calendar.registrant(for: todo))
        let view = codeOnly(try build19Source("LifeOS/Features/Calendar/CalendarView.swift"))
        XCTAssertTrue(view.contains("Text(registrant.label)"), "文字で出す")
        XCTAssertTrue(view.contains("registrant: viewModel.registrant(for: item),"))
        XCTAssertTrue(view.contains("let markers = viewModel.dayMarkers(on: date)"))
        XCTAssertTrue(view.contains(".fill(marker.tint)"))
        let todayView = codeOnly(try build19Source("LifeOS/Features/Today/TodayView.swift"))
        XCTAssertTrue(todayView.contains("detail: viewModel.registrantDetail(viewModel.timelineDetail(for: item), for: item),"))
        XCTAssertTrue(todayView.contains("tint: viewModel.registrant(for: item)?.tint ?? item.kind.tint,"))
    }

    /// 31：VoiceOver で「自分／パートナー／共有」が分かる
    func testVoiceOverLabels() throws {
        XCTAssertEqual(ItemRegistrant.me.spokenLabel, "自分が登録した予定")
        XCTAssertEqual(ItemRegistrant.partner.spokenLabel, "パートナーが登録した予定")
        XCTAssertEqual(ItemRegistrant.unknown.spokenLabel, "共有の予定。登録した人は分かりません")
        let view = codeOnly(try build19Source("LifeOS/Features/Calendar/CalendarView.swift"))
        XCTAssertTrue(view.contains(".accessibilityLabel(registrant.spokenLabel)"))
        XCTAssertTrue(view.contains("HouseholdSharedMark()"), "共有マークも出す")
        // 3人とも違う色（ライト・ダークのどちらも色の値を持つ）
        XCTAssertEqual(Set(ItemRegistrant.allCases.map(\.label)).count, 3)
    }
}

// MARK: - 5. プライバシー・保存の形・Build

final class Build19PrivacyAndBuildTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build19P-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 29：UID・メールを画面に出さない・端末に保存しない・ログに出さない
    func testNoUIDOrEmailShownSavedOrLogged() throws {
        let server = eventServer()
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let alice = Build19Device(server: server, uid: "alice-uid-123", store: store)
        let bob = Build19Device(server: server, uid: "bob-uid-456")
        alice.store.add([event("自分の予定")])
        bob.store.add([event("パートナーの予定")], destination: .household)
        alice.store.add([event("共有の自分の予定", hour: 12)], destination: .household)
        let calendar = alice.calendar()
        calendar.select(build19Day)
        var shown: [String] = []
        for item in calendar.selectedItems {
            shown.append(calendar.detailText(for: item))
            if let registrant = calendar.registrant(for: item) {
                shown += [registrant.label, registrant.spokenLabel]
            }
        }
        for text in shown {
            XCTAssertFalse(text.contains("uid"), text)
            XCTAssertFalse(text.contains("@"), text)
        }
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        for word in ["alice-uid-123", "bob-uid-456", "createdBy", "registrant", "householdRegistrants"] {
            XCTAssertFalse(file.contains(word), word)
        }
        // 登録した人は UID を持たない（自分／パートナー／不明だけ）
        XCTAssertEqual(ItemRegistrant.allCases.map(\.rawValue), ["me", "partner", "unknown"])
        let backend = codeOnly(try build19Source("LifeOS/Core/Sharing/FirestoreSharedItemsBackend.swift"))
        XCTAssertTrue(backend.contains("registrant: ItemRegistrant.from(createdBy: data[\"createdBy\"], currentUID: currentUID)"))
        for path in ["LifeOS/Core/Sharing/FirestoreSharedItemsBackend.swift", "LifeOS/Core/Sharing/HouseholdItems.swift", "LifeOS/Core/Store/LifeStore.swift", "LifeOS/Features/Calendar/CalendarView.swift", "LifeOS/Features/Calendar/CalendarViewModel.swift", "LifeOS/Features/Today/TodayViewModel.swift"] {
            let code = codeOnly(try build19Source(path))
            for word in ["print(", "NSLog(", "os_log(", "Logger(", "dump(", ".email"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
    }

    /// 30：Firestore に保存する項目は増えていない（作成・更新）
    func testFirestoreFieldsUnchanged() throws {
        let server = eventServer()
        let alice = Build19Device(server: server, uid: "alice")
        alice.store.add([event("歯医者")], destination: .household)
        let created = try XCTUnwrap(alice.backend.sentCreates.first?.fields)
        XCTAssertEqual(Set(created.keys), ["schemaVersion", "kind", "title", "date", "hasTime", "isCompleted", "assigneeUID", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        var changed = try XCTUnwrap(alice.store.householdEvents.first)
        changed.title = "歯医者（再診）"
        XCTAssertTrue(alice.store.updateEvent(changed))
        let updated = try XCTUnwrap(alice.backend.sentUpdates.last?.fields)
        XCTAssertEqual(Set(updated.keys), ["title", "date", "hasTime", "isCompleted", "deferredTo", "droppedAt", "updatedBy", "updatedAt"])
        XCTAssertEqual(alice.backend.totalCalls, 2, "色分けのために書き込みを増やさない")
    }

    /// Build 19・Version 1.0・暗号化の設定。Build 16 は欠番のまま
    func testBuildNumberIs19() throws {
        let project = try build19Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        // Build 20（2026-11-05）で 20 に上げたため、「4か所がそろっていて 19 以上」を確かめる（Build 15・17・18 と同じ扱い）
        let versions = lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(Set(versions).count, 1, "アプリ／テスト、Debug／Release の4か所が同じ")
        let number = Int(versions.first?.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = ", with: "").replacingOccurrences(of: ";", with: "") ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(number, 19)
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build19Source("docs/BUILD_19_RECEIPT_STORE_SELECTION_AND_CALENDAR_COLORS.md").contains("Build 16 は欠番"))
    }
}
