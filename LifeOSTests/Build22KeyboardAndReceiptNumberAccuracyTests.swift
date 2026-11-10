import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import LifeOS

// Build 22（2026-11-10）：キーボードを閉じやすくする・レシートの数字の読み取りの正確さを上げる。
// docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md
// 本物の Firestore・ネットワークは使わない。文字認識は偽物（読み取った文字の代わりに、架空の合成レシートを渡す）。
// 合成レシートは LifeOSTests/Fixtures/JapaneseSyntheticReceipts.json（店名・商品名はすべて架空）。
// 同じ合成レシートを tools/receipt-eval/receipt_eval.py でも確かめ、Build 21 との比べた結果を文書に残している。

private let build22Now = TestDates.make(2026, 11, 10, 9, 0)

private func build22Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func build22CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

// MARK: - 合成レシート（架空）

/// 商品明細1件の比べる形（商品名・数量・単価・金額）
private struct Build22Item: Equatable, CustomStringConvertible {
    let name: String
    let quantity: Int?
    let unitPrice: Int?
    let amount: Int?

    init(_ name: String, _ quantity: Int?, _ unitPrice: Int?, _ amount: Int?) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
    }

    var description: String { "\(name) / \(quantity.map(String.init) ?? "-") / \(unitPrice.map(String.init) ?? "-") / \(amount.map(String.init) ?? "-")" }
}

/// 合成レシート1枚（期待値つき）
private struct Build22Fixture {
    let id: String
    let kind: String
    let lines: [ReceiptRecognizedLine]
    let amount: Int?
    let issue: ReceiptAmountIssue?
    let expectsWarning: Bool
    /// 商品明細（確かめない合成レシートは nil）
    let items: [Build22Item]?
}

private final class Build22BundleMarker {}

private enum Build22Fixtures {
    static let fileName = "JapaneseSyntheticReceipts"

    /// テストの中の合成レシートを読む（テストの束の中 → 無ければリポジトリの中）
    static func load() throws -> [Build22Fixture] {
        let bundle = Bundle(for: Build22BundleMarker.self)
        var url = bundle.url(forResource: fileName, withExtension: "json")
            ?? bundle.url(forResource: fileName, withExtension: "json", subdirectory: "Fixtures")
        if url == nil {
            let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures").appendingPathComponent("\(fileName).json")
            if FileManager.default.fileExists(atPath: local.path) { url = local }
        }
        let data = try Data(contentsOf: try XCTUnwrap(url, "合成レシートのファイルが見つかりません"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let receipts = try XCTUnwrap(root["receipts"] as? [[String: Any]])
        return try receipts.map(fixture(from:))
    }

    private static func fixture(from raw: [String: Any]) throws -> Build22Fixture {
        let id = try XCTUnwrap(raw["id"] as? String)
        let expected = try XCTUnwrap(raw["expected"] as? [String: Any], id)
        let rawLines = try XCTUnwrap(raw["lines"] as? [Any], id)
        let lines: [ReceiptRecognizedLine] = try rawLines.map { value in
            if let text = value as? String { return ReceiptRecognizedLine(text: text) }
            let object = try XCTUnwrap(value as? [String: Any], id)
            var line = ReceiptRecognizedLine(text: try XCTUnwrap(object["text"] as? String, id))
            if let confidence = object["c"] as? Double { line.confidence = Float(confidence) }
            if let x = object["x"] as? Double, let y = object["y"] as? Double,
               let width = object["w"] as? Double, let height = object["h"] as? Double {
                line.box = RecognizedTextBox(x: x, y: y, width: width, height: height)
            }
            line.alternatives = object["alt"] as? [String] ?? []
            return line
        }
        let issue: ReceiptAmountIssue?
        switch expected["issue"] as? String {
        case "notFound": issue = .notFound
        case "ambiguous": issue = .ambiguous
        case "inconsistent": issue = .inconsistent
        default: issue = nil
        }
        let items: [Build22Item]? = try (expected["items"] as? [[Any]])?.map { row in
            XCTAssertEqual(row.count, 4, id)
            let name = try XCTUnwrap(row.first as? String, id)
            let numbers = row.dropFirst().map { ($0 as? NSNumber)?.intValue }
            return Build22Item(name, numbers.first ?? nil, numbers.dropFirst().first ?? nil, numbers.last ?? nil)
        }
        return Build22Fixture(
            id: id, kind: raw["kind"] as? String ?? "", lines: lines,
            amount: expected["amount"] as? Int, issue: issue,
            expectsWarning: expected["warning"] as? Bool ?? false, items: items
        )
    }
}

private func extract(_ lines: [ReceiptRecognizedLine]) -> ReceiptExtractionProposal {
    ReceiptFieldExtractor.extract(from: lines, today: build22Now)
}

private func extract(_ texts: [String]) -> ReceiptExtractionProposal {
    ReceiptFieldExtractor.extract(from: texts, today: build22Now)
}

private func simplified(_ items: [ReceiptLineItem]) -> [Build22Item] {
    items.map { Build22Item($0.name, $0.quantity, $0.unitPrice, $0.amount) }
}

// MARK: - 偽物の文字認識・画面の部品

private final class Build22FakeRecognizer: ReceiptTextRecognizing {
    var lines: [ReceiptRecognizedLine]
    var delayNanoseconds: UInt64
    private(set) var calls = 0

    init(lines: [ReceiptRecognizedLine], delayNanoseconds: UInt64 = 0) {
        self.lines = lines
        self.delayNanoseconds = delayNanoseconds
    }

    func recognizeLines(in imageData: Data) async throws -> [String] {
        try await recognizeReceipt(in: imageData, detectsDocument: true).map(\.text)
    }

    func recognizeReceipt(in imageData: Data, detectsDocument: Bool) async throws -> [ReceiptRecognizedLine] {
        calls += 1
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        return lines
    }
}

private struct Build22Setup {
    let store: LifeStore
    let recognizer: Build22FakeRecognizer
    let viewModel: MoneyViewModel
}

@MainActor
private func makeBuild22(lines: [ReceiptRecognizedLine], delay: UInt64 = 0, store: LifeStore? = nil) -> Build22Setup {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    let appState = AppState()
    appState.usageStyle = .solo
    let recognizer = Build22FakeRecognizer(lines: lines, delayNanoseconds: delay)
    let viewModel = MoneyViewModel(store: store, appState: appState, now: build22Now, receiptRecognizer: recognizer)
    return Build22Setup(store: store, recognizer: recognizer, viewModel: viewModel)
}

private let build22Image = WarrantyTestImages.text(["合計 ¥3,520"])

/// 見本のレシート（架空）：小計＋外税＝合計、お預り－お釣り＝合計。合計の2番目の読み方に読み違い（¥3,820）がある
private let build22Receipt: [ReceiptRecognizedLine] = [
    ReceiptRecognizedLine(text: "架空ベーカリー こむぎ堂"),
    ReceiptRecognizedLine(text: "2026/11/10 08:15"),
    ReceiptRecognizedLine(text: "クロワッサン 2点 × ¥240 ¥480"),
    ReceiptRecognizedLine(text: "食パン ¥2,720"),
    ReceiptRecognizedLine(text: "小計 ¥3,200"),
    ReceiptRecognizedLine(text: "外税 10% ¥320"),
    ReceiptRecognizedLine(text: "合計 ¥3,520", alternatives: ["合計 ¥3,820"]),
    ReceiptRecognizedLine(text: "お預り ¥4,000"),
    ReceiptRecognizedLine(text: "お釣り ¥480")
]

/// 画面の上で試すための、画面の外のウインドウ
@MainActor
private func makeTestWindow() -> UIWindow {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    return window
}

// MARK: - 1. キーボード（1〜7）

final class Build22KeyboardTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build22K-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 1：背景・ボタン・候補のタップでは閉じる。入力欄（とその中）のタップでは閉じない（別の入力欄へ移れる）
    @MainActor
    func testBackgroundTapDismissesButTextFieldTapDoesNot() {
        XCTAssertTrue(LifeKeyboard.shouldDismiss(forTouchIn: UIView()))
        XCTAssertTrue(LifeKeyboard.shouldDismiss(forTouchIn: UIButton()), "ボタン（候補・保存・キャンセル）のタップでも閉じる。タップそのものは奪わない")
        XCTAssertTrue(LifeKeyboard.shouldDismiss(forTouchIn: nil))
        let field = UITextField()
        let inner = UIView()
        field.addSubview(inner)
        XCTAssertFalse(LifeKeyboard.shouldDismiss(forTouchIn: field))
        XCTAssertFalse(LifeKeyboard.shouldDismiss(forTouchIn: inner), "入力欄の中の部品のタップでも閉じない")
        XCTAssertFalse(LifeKeyboard.shouldDismiss(forTouchIn: UITextView()))
        XCTAssertFalse(LifeKeyboard.shouldDismiss(forTouchIn: UISearchBar()))
    }

    /// 2：背景のタップの仕組みは、タップを奪わない・遅らせない・ほかの操作と同時に動く（候補・保存・キャンセル・スクロールを妨げない）
    @MainActor
    func testTapHandlerDoesNotStealTaps() {
        let handler = KeyboardDismissTapHandler()
        XCTAssertFalse(handler.recognizer.cancelsTouchesInView)
        XCTAssertFalse(handler.recognizer.delaysTouchesBegan)
        XCTAssertFalse(handler.recognizer.delaysTouchesEnded)
        XCTAssertFalse(handler.recognizer.requiresExclusiveTouchType)
        XCTAssertTrue(handler.recognizer.delegate === handler)
        XCTAssertTrue(handler.gestureRecognizer(handler.recognizer, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
        XCTAssertTrue(handler.gestureRecognizer(handler.recognizer, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()))
    }

    /// 3：閉じても入力した文字はそのまま（背景のタップ・「完了」・タブの移動で使う閉じ方の両方）
    @MainActor
    func testDismissKeepsTypedText() throws {
        let window = makeTestWindow()
        defer { window.isHidden = true }
        let root = try XCTUnwrap(window.rootViewController?.view)
        let title = UITextField(frame: CGRect(x: 16, y: 100, width: 300, height: 44))
        let amount = UITextField(frame: CGRect(x: 16, y: 160, width: 300, height: 44))
        root.addSubview(title)
        root.addSubview(amount)
        let handler = KeyboardDismissTapHandler()
        window.addGestureRecognizer(handler.recognizer)
        defer { window.removeGestureRecognizer(handler.recognizer) }

        title.text = "架空ベーカリー"
        XCTAssertTrue(title.becomeFirstResponder())
        handler.dismissKeyboard()
        XCTAssertFalse(title.isFirstResponder, "背景のタップで閉じる")
        XCTAssertEqual(title.text, "架空ベーカリー", "入力した文字は残る")

        amount.text = "3520"
        XCTAssertTrue(amount.becomeFirstResponder())
        LifeKeyboard.dismiss()
        XCTAssertFalse(amount.isFirstResponder, "「完了」・タブの移動・画面を離れたときに閉じる")
        XCTAssertEqual(amount.text, "3520")
    }

    /// 4：支出の追加・編集（レシートの確認画面と、その中の商品明細）・支出の詳細（明細を直す欄）で、
    /// スクロール・背景のタップ・「完了」・画面を離れたときに閉じる
    func testScreensUseKeyboardDismissal() throws {
        let money = build22CodeOnly(try build22Source("LifeOS/Features/Money/MoneyView.swift"))
        let detail = build22CodeOnly(try build22Source("LifeOS/Features/Money/ExpenseDetailView.swift"))
        let keyboard = build22CodeOnly(try build22Source("LifeOS/DesignSystem/Components/LifeKeyboardDismissal.swift"))
        for (name, source) in [("支出の追加・編集", money), ("支出の詳細", detail)] {
            XCTAssertTrue(source.contains(".lifeKeyboardDismissal()"), name)
            XCTAssertTrue(source.contains(".lifeKeyboardDoneButton { focusedField = nil }"), name)
            XCTAssertTrue(source.contains("@FocusState private var focusedField"), name)
        }
        for field in [".title", ".amount"] {
            XCTAssertTrue(money.contains(".focused($focusedField, equals: \(field))"), field)
        }
        for field in [".name", ".quantity", ".unitPrice", ".amount"] {
            XCTAssertTrue(money.contains(".focused($focusedField, equals: \(field))"), "確認画面の商品明細 \(field)")
            XCTAssertTrue(detail.contains(".focused($focusedField, equals: \(field))"), "詳細の明細 \(field)")
        }
        XCTAssertTrue(keyboard.contains("scrollDismissesKeyboard(.interactively)"), "スクロールで閉じる")
        XCTAssertTrue(keyboard.contains("ToolbarItemGroup(placement: .keyboard)"))
        XCTAssertTrue(keyboard.contains("Button(\"完了\")"), "キーボードの上の「完了」")
        XCTAssertTrue(keyboard.contains("cancelsTouchesInView = false"), "タップを奪わない")
        XCTAssertTrue(keyboard.contains(".onDisappear { LifeKeyboard.dismiss() }"), "画面を離れたら閉じる")
        XCTAssertFalse(keyboard.contains("onTapGesture"), "画面全体を覆う強いタップの仕組みは使わない")
        XCTAssertFalse(money.contains("onTapGesture { LifeKeyboard") || detail.contains("onTapGesture { LifeKeyboard"))
    }

    /// 5：別のタブへ移ったら閉じる
    func testTabChangeDismissesKeyboard() throws {
        let tabs = build22CodeOnly(try build22Source("LifeOS/App/MainTabView.swift"))
        XCTAssertTrue(tabs.contains("onChange(of: appState.selectedTab)"))
        XCTAssertTrue(tabs.contains("LifeKeyboard.dismiss()"))
    }

    /// 6：候補の選択・保存・キャンセルは今までどおり動く（キーボードの変更で妨げない）
    @MainActor
    func testCandidateSaveAndCancelStillWork() async throws {
        let setup = makeBuild22(lines: build22Receipt)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(setup.viewModel.draft)
        let candidate = try XCTUnwrap(draft.amountCandidates.first { $0.label == "小計" })
        draft.selectAmountCandidate(candidate)
        XCTAssertEqual(draft.amount, 3200, "小計も利用者が選べば入る")
        let total = try XCTUnwrap(draft.amountCandidates.first { $0.isRecommended })
        draft.selectAmountCandidate(total)
        XCTAssertEqual(draft.amount, 3520)
        if let store = draft.storeCandidates.first { draft.selectStoreCandidate(store) }
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.amount), [3520])

        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertNotNil(setup.viewModel.draft)
        setup.viewModel.cancelEditing()
        XCTAssertNil(setup.viewModel.draft, "キャンセルで閉じる")
        XCTAssertEqual(setup.store.expenses.count, 1, "キャンセルでは保存しない")
    }

    /// 7：VoiceOver の説明と、押しやすい大きさ（44pt 以上）を保つ。見えない部品は読み上げない
    func testAccessibilityAndTapTargets() throws {
        let keyboard = build22CodeOnly(try build22Source("LifeOS/DesignSystem/Components/LifeKeyboardDismissal.swift"))
        XCTAssertTrue(keyboard.contains(".accessibilityHint(\"キーボードを閉じます。入力した内容はそのまま残ります\")"))
        XCTAssertTrue(keyboard.contains(".accessibilityHidden(true)"), "背景のタップの見えない部品は VoiceOver に出さない")
        XCTAssertTrue(keyboard.contains("isAccessibilityElement = false"))
        let money = build22CodeOnly(try build22Source("LifeOS/Features/Money/MoneyView.swift"))
        let detail = build22CodeOnly(try build22Source("LifeOS/Features/Money/ExpenseDetailView.swift"))
        XCTAssertTrue(money.contains(".frame(minHeight: LifeSpacing.minTapTarget)"))
        XCTAssertTrue(detail.contains(".frame(minHeight: LifeSpacing.minTapTarget)"))
        XCTAssertTrue(detail.contains(".frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)"), "保存・やめるのボタン")
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
    }
}

// MARK: - 2. レシートの数字（8〜30）

final class Build22ReceiptNumberTests: XCTestCase {
    /// 8：架空の合成レシート（13の形式＋数字の形）すべてで、合計金額・決められない理由・確かめてほしいこと・商品明細が期待どおり
    func testAllSyntheticReceiptsMatchExpectations() throws {
        let fixtures = try Build22Fixtures.load()
        XCTAssertGreaterThanOrEqual(fixtures.count, 40)
        for fixture in fixtures {
            let proposal = extract(fixture.lines)
            XCTAssertEqual(proposal.amount, fixture.amount, "\(fixture.id)（\(fixture.kind)）の合計")
            if let issue = fixture.issue {
                XCTAssertEqual(proposal.amountIssue, issue, "\(fixture.id) の理由")
            }
            if fixture.amount != nil {
                XCTAssertNil(proposal.amountIssue, fixture.id)
            }
            XCTAssertEqual(proposal.amountWarning != nil, fixture.expectsWarning, "\(fixture.id) の確かめてほしいこと")
            if let items = fixture.items {
                XCTAssertEqual(simplified(proposal.lineItems), items, "\(fixture.id) の商品明細")
            }
        }
    }

    /// 9：日本向けの13の形式（コンビニ・スーパー・ドラッグストア・飲食店・ガソリンスタンド・複数税率・値引き・ポイント・
    /// 現金とカード・長いレシート・薄い印字・合計が別行・数量が別行）をすべて含む
    func testFixturesCoverThirteenFormats() throws {
        let ids = Set(try Build22Fixtures.load().map(\.id))
        let formats = ["convenience", "supermarket", "drugstore", "restaurant", "gas_station", "multiple_tax_rates",
                       "discount_coupon", "points_used", "cash_and_card", "long_receipt", "faint_print",
                       "total_on_separate_row", "quantity_on_separate_row"]
        XCTAssertEqual(formats.count, 13)
        for format in formats {
            XCTAssertTrue(ids.contains(format), format)
        }
    }

    /// 10：金額の場所（¥のあと・円の前・行の右端）の O/0・I/l/1・Z/2・S/5・G/6・B/8 の読み違いを直す
    func testConfusableCharactersAreRepairedInAmountPositions() {
        XCTAssertEqual(ReceiptNumberText.repaired("合計 ¥1,2OO"), "合計 ¥1,200")
        XCTAssertEqual(ReceiptNumberText.repaired("合計 ¥l,98O"), "合計 ¥1,980")
        XCTAssertEqual(ReceiptNumberText.repaired("S00円"), "500円")
        XCTAssertEqual(ReceiptNumberText.repaired("合計 ¥3,B2O"), "合計 ¥3,820")
        XCTAssertEqual(ReceiptNumberText.repaired("¥Z,4G0"), "¥2,460")
        XCTAssertEqual(extract(["合計 ¥1,2OO"]).amount, 1200)
    }

    /// 11：商品名・店名・電話番号などの英字や数字は直さない（金額の場所でない・英字が多すぎる）
    func testWordsAndOtherNumbersAreNotRepaired() {
        XCTAssertEqual(ReceiptNumberText.repaired("BOSS コーヒー ¥150"), "BOSS コーヒー ¥150")
        XCTAssertEqual(ReceiptNumberText.repaired("SOLD OUT"), "SOLD OUT")
        XCTAssertEqual(ReceiptNumberText.repaired("TEL 03-0000-1234"), "TEL 03-0000-1234")
        XCTAssertEqual(ReceiptNumberText.repaired("レジ#01 責任者 ヤマダ"), "レジ#01 責任者 ヤマダ")
        XCTAssertEqual(ReceiptNumberText.repaired("合計 1,2OO"), "合計 1,2OO", "行の右端は英字1つまで（推測で直しすぎない）")
        XCTAssertNil(ReceiptNumberText.repairedToken("SOS", requireMostlyDigits: false), "数字の無いまとまりは直さない")
        let proposal = extract(["BOSS 缶コーヒー ¥150", "合計 ¥150"])
        XCTAssertEqual(proposal.lineItems.first?.name, "BOSS 缶コーヒー")
        XCTAssertEqual(proposal.amount, 150)
    }

    /// 12：全角の数字・記号
    func testFullwidthDigits() {
        XCTAssertEqual(extract(["合計 ￥１，２３４"]).amount, 1234)
    }

    /// 13：区切り（1,234 / 1234 / 1.234 / 1, 234 / ¥1 234）
    func testSeparators() {
        XCTAssertEqual(extract(["合計 ¥1,234"]).amount, 1234)
        XCTAssertEqual(extract(["合計 1234円"]).amount, 1234)
        XCTAssertEqual(extract(["合計 1.234"]).amount, 1234)
        XCTAssertEqual(extract(["お支払額 ¥1, 234"]).amount, 1234)
        XCTAssertEqual(extract(["合計 ¥1 234"]).amount, 1234)
        XCTAssertEqual(ReceiptNumberText.repairedToken("1.5", requireMostlyDigits: false), "1.5", "小数は区切りにしない")
    }

    /// 14：¥・￥・円
    func testYenFormats() {
        XCTAssertEqual(extract(["合計 ¥1,234"]).amount, 1234)
        XCTAssertEqual(extract(["合計 ￥1,234"]).amount, 1234)
        XCTAssertEqual(extract(["合計 1,234円"]).amount, 1234)
    }

    /// 15：2行に分かれた数字（「¥3,」と「520」）をつなぐ
    func testNumberSplitAcrossTwoRows() {
        XCTAssertEqual(extract(["合計", "¥3,", "520"]).amount, 3520)
    }

    /// 16：見出しと金額が別の行
    func testLabelAndAmountOnSeparateRows() {
        XCTAssertEqual(extract(["合計", "¥3,520"]).amount, 3520)
    }

    /// 17：右端に並ぶ金額（位置つき）。見出しと同じ高さの金額を合計にする
    func testRightAlignedAmountsWithPositions() throws {
        let fixture = try XCTUnwrap(try Build22Fixtures.load().first { $0.id == "right_aligned" })
        XCTAssertTrue(fixture.lines.contains { $0.box != nil }, "位置つきの合成レシート")
        XCTAssertEqual(extract(fixture.lines).amount, fixture.amount)
    }

    /// 18：数量×単価。合わないときは知らせる（値は変えない）
    func testQuantityTimesUnitPrice() throws {
        let matched = try XCTUnwrap(extract(["ノート 3点 × ¥120 ¥360", "合計 ¥360"]).lineItems.first)
        XCTAssertEqual(simplified([matched]), [Build22Item("ノート", 3, 120, 360)])
        XCTAssertFalse(matched.hasArithmeticMismatch)
        let mismatched = try XCTUnwrap(extract(["ノート 3点 × ¥120 ¥380", "合計 ¥380"]).lineItems.first)
        XCTAssertEqual(simplified([mismatched]), [Build22Item("ノート", 3, 120, 380)], "推測で直さない")
        XCTAssertTrue(mismatched.hasArithmeticMismatch, "確認画面で「数量×単価と金額が合いません」と知らせる")
        let money = build22CodeOnly(try build22Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains("item.hasArithmeticMismatch"))
    }

    /// 19：値引き（-30・▲50・−100・△20・▲1,000）。割引率（10%）・点数は金額にしない
    func testNegativeDiscounts() {
        XCTAssertEqual(ReceiptNumberText.discountAmount(in: "値引 -30"), 30)
        XCTAssertEqual(ReceiptNumberText.discountAmount(in: "▲50"), 50)
        XCTAssertEqual(ReceiptNumberText.discountAmount(in: "割引 \u{2212}100"), 100)
        XCTAssertEqual(ReceiptNumberText.discountAmount(in: "△20"), 20)
        XCTAssertEqual(ReceiptNumberText.discountAmount(in: "クーポン ▲1,000"), 1000)
        XCTAssertNil(ReceiptNumberText.discountAmount(in: "10%引"))
        XCTAssertNil(ReceiptNumberText.discountAmount(in: "値引 -10%"))
        XCTAssertNil(ReceiptNumberText.discountAmount(in: "2点 -1個"))
    }

    /// 20：8% と 10% の外税を足して、小計＋税＝合計を確かめる
    func testMultipleTaxRates() throws {
        let proposal = extract(["小計 ¥1,000", "外税 8% ¥40", "外税 10% ¥50", "合計 ¥1,090"])
        XCTAssertEqual(proposal.amount, 1090)
        XCTAssertNil(proposal.amountWarning)
        XCTAssertTrue(try XCTUnwrap(proposal.amountCandidates.first).isConsistent)
    }

    /// 21：内税・消費税（内訳）は足さない
    func testInnerTaxIsNotAdded() {
        let proposal = extract(["小計 ¥1,100", "(内消費税 ¥100)", "合計 ¥1,100"])
        XCTAssertEqual(proposal.amount, 1100)
        XCTAssertNil(proposal.amountWarning)
    }

    /// 22：お預り・お釣り・ポイント・カード番号・電話番号・時刻・伝票番号は合計にしない
    func testNonTotalNumbersAreExcluded() {
        XCTAssertNil(extract(["お預り ¥1,000", "お釣り ¥200"]).amount)
        XCTAssertNil(extract(["ポイント 1,000"]).amount)
        XCTAssertNil(extract(["TEL 03-1234-5678", "12:34", "伝票番号 1234"]).amount)
        XCTAssertEqual(extract(["合計 ¥800", "ポイント 1,000", "今回ポイント 8"]).amount, 800)
        XCTAssertEqual(extract(["合計 ¥980", "カード番号 ****1234"]).amount, 980)
    }

    /// 23：小計＋税－値引き＝合計
    func testSubtotalPlusTaxMinusDiscount() throws {
        let proposal = extract(["小計 ¥1,000", "値引 -100", "外税 10% ¥90", "合計 ¥990"])
        XCTAssertEqual(proposal.amount, 990)
        XCTAssertTrue(try XCTUnwrap(proposal.amountCandidates.first { $0.amount == 990 }).isConsistent)
        XCTAssertNil(proposal.amountWarning)
    }

    /// 24：商品明細の合計＝合計
    func testItemsSumMatchesTotal() throws {
        let proposal = extract(["パン ¥120", "牛乳 ¥200", "合計 ¥320"])
        XCTAssertEqual(proposal.amount, 320)
        XCTAssertEqual(proposal.lineItems.count, 2)
        XCTAssertTrue(try XCTUnwrap(proposal.amountCandidates.first).isConsistent)
    }

    /// 25：数量×単価が合わない明細は、Vision のほかの読み方で合うものを使う
    func testQuantityTimesUnitUsesAlternativeReading() throws {
        let fixture = try XCTUnwrap(try Build22Fixtures.load().first { $0.id == "quantity_times_unit_alternative" })
        let proposal = extract(fixture.lines)
        XCTAssertEqual(simplified(proposal.lineItems), fixture.items)
        XCTAssertFalse(proposal.lineItems.contains { $0.hasArithmeticMismatch })
    }

    /// 26：強い候補が矛盾するときは、自動で選ばない（空にして理由を出す）
    func testConflictingCandidatesAreNotAutoSelected() throws {
        let proposal = extract(["合計 ¥1,000", "合計 ¥2,000"])
        XCTAssertNil(proposal.amount)
        XCTAssertEqual(proposal.amountIssue, .ambiguous)
        XCTAssertEqual(Set(proposal.amountCandidates.map(\.amount)), [1000, 2000], "候補には出す（利用者が選べる）")
    }

    /// 27：合計が小計＋税とお預り－お釣りの両方と合わないときは、自動で入れない（読み違いの疑いが強い）
    @MainActor
    func testInconsistentTotalIsNotAutoFilled() async throws {
        let lines = ["小計 ¥1,000", "外税 10% ¥100", "合計 ¥1,200", "お預り ¥2,000", "お釣り ¥900"].map { ReceiptRecognizedLine(text: $0) }
        let proposal = extract(lines)
        XCTAssertNil(proposal.amount)
        XCTAssertEqual(proposal.amountIssue, .inconsistent)
        XCTAssertTrue(proposal.notes.contains(ReceiptAmountIssue.inconsistent.message))
        let setup = makeBuild22(lines: lines)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        let draft = try XCTUnwrap(setup.viewModel.draft)
        XCTAssertEqual(draft.amountText, "", "金額欄は空のまま")
        XCTAssertNil(draft.selectedAmountCandidateID)
        XCTAssertTrue(draft.amountCandidates.contains { $0.amount == 1200 }, "読んだ合計も候補に出す")
        XCTAssertTrue(setup.store.expenses.isEmpty)
    }

    /// 28：計算した金額の候補は「確認してください」と出し、自動では選ばない（選択の推奨もしない）
    func testCalculatedCandidateIsNeverRecommended() throws {
        let proposal = extract(["小計 ¥1,000", "外税 10% ¥100", "合計 ¥1,200", "お預り ¥2,000", "お釣り ¥900"])
        let calculated = try XCTUnwrap(proposal.amountCandidates.first { $0.kind == .calculated })
        XCTAssertEqual(calculated.amount, 1100)
        XCTAssertFalse(calculated.isRecommended)
        XCTAssertTrue(calculated.displayText.contains("確認してください"))
        XCTAssertTrue(calculated.spokenLabel.contains("確かめてください"))
        var draft = ExpenseDraft(receipt: proposal, today: build22Now)
        XCTAssertNil(draft.amount)
        draft.selectAmountCandidate(calculated)
        XCTAssertEqual(draft.amount, 1100, "利用者が選んだときだけ入る")
        XCTAssertLessThan(ReceiptAmountCandidate.Kind.calculated, .subtotal)
    }

    /// 29：Vision のほかの読み方は、計算と合うときだけ使う（合わなければ1番目の読み方のまま）
    func testVisionAlternativesOnlyWhenSupported() {
        let fixed = extract([
            ReceiptRecognizedLine(text: "小計 ¥3,200"),
            ReceiptRecognizedLine(text: "外税 10% ¥320"),
            ReceiptRecognizedLine(text: "合計 ¥3,820", alternatives: ["合計 ¥3,520"])
        ])
        XCTAssertEqual(fixed.amount, 3520, "計算と合うほかの読み方を使う")
        let kept = extract([
            ReceiptRecognizedLine(text: "小計 ¥3,200"),
            ReceiptRecognizedLine(text: "外税 10% ¥320"),
            ReceiptRecognizedLine(text: "合計 ¥3,520", alternatives: ["合計 ¥3,820"])
        ])
        XCTAssertEqual(kept.amount, 3520, "1番目が計算と合えば変えない")
        XCTAssertEqual(extract([ReceiptRecognizedLine(text: "合計 ¥980", alternatives: ["合計 ¥960"])]).amount, 980,
                       "確かめる手掛かりが無ければ1番目の読み方のまま")
    }

    /// 30：以前のレシート（Build 18〜21 の見本）は今までどおり
    func testEarlierReceiptsStillWork() throws {
        let proposal = extract([
            "いらっしゃいませ", "まちの八百屋", "TEL 03-1234-5678", "2026/11/08 18:42",
            "牛乳 ¥198", "ティッシュ 2点 × ¥250 ¥500", "小計 ¥698", "合計 ¥698", "お預り ¥1,000", "お釣り ¥302"
        ])
        XCTAssertEqual(proposal.amount, 698)
        XCTAssertEqual(proposal.title, "まちの八百屋")
        XCTAssertEqual(simplified(proposal.lineItems), [Build22Item("牛乳", nil, nil, 198), Build22Item("ティッシュ", 2, 250, 500)])
        XCTAssertNil(proposal.amountWarning)
        let subtotal = try XCTUnwrap(proposal.amountCandidates.first { $0.kind == .subtotal })
        XCTAssertFalse(subtotal.isRecommended)
        XCTAssertTrue(subtotal.displayText.contains("選択非推奨"))
    }
}

// MARK: - 3. 安定性・プライバシー（31〜40）

final class Build22StabilityAndPrivacyTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build22-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 31：読み取り中にもう一度読み取っても、二重に動かない
    @MainActor
    func testNoDuplicateProcessing() async throws {
        let setup = makeBuild22(lines: build22Receipt, delay: 100_000_000)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertEqual(setup.recognizer.calls, 1)
        XCTAssertNotNil(setup.viewModel.draft)
    }

    /// 32：キャンセルしたら、結果が後から届いても開かない・保存しない
    @MainActor
    func testCancelStopsReading() async throws {
        let setup = makeBuild22(lines: build22Receipt, delay: 300_000_000)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        XCTAssertTrue(setup.viewModel.isReadingReceipt)
        setup.viewModel.cancelReceiptReading()
        XCTAssertFalse(setup.viewModel.isHoldingReceiptWork)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertTrue(setup.store.expenses.isEmpty)
        // 本物の読み取りも、キャンセルされていれば写真を整える前・2回目の読み取りの前に止まる
        let task = Task { () async throws -> [ReceiptRecognizedLine] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReceiptTextRecognizer().recognizeReceipt(in: build22Image, detectsDocument: true)
        }
        do {
            _ = try await task.value
            XCTFail("キャンセルしたら読み取らない")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    /// 33：重さの上限（文字認識は1枚につき2回まで・写真の長い辺は3000px まで・候補は3つまで・ほかの読み方の行は3つまで）
    func testPerformanceLimits() {
        XCTAssertEqual(ReceiptTextRecognizer.maxRecognitionPasses, 2)
        XCTAssertEqual(ReceiptImagePreparer.maxPixelSize, 3000)
        XCTAssertEqual(WarrantyTextRecognizer.maxCandidates, 3)
        XCTAssertEqual(ReceiptLayout.maxAlternativeRows, 3)
        let many = ReceiptRecognizedLine(text: "合計 ¥1,000", alternatives: ["合計 ¥1,001", "合計 ¥1,002", "合計 ¥1,003", "合計 ¥1,004", "合計 ¥1,005"])
        let rows = ReceiptLayout.rows(from: [many])
        XCTAssertEqual(rows.count, 1)
        XCTAssertLessThanOrEqual(rows[0].alternatives.count, ReceiptLayout.maxAlternativeRows)
        XCTAssertFalse(rows[0].alternatives.contains(rows[0].text), "同じ文字の読み方は数えない")
    }

    /// 34：薄い印字向けの補正：写真の大きさは変えず、読めない写真では作らない（無理に読まない）
    func testFaintPrintEnhancementIsBounded() throws {
        let image = WarrantyTestImages.text(["合計 ¥3,520"])
        let enhanced = try XCTUnwrap(ReceiptImagePreparer.enhancedForFaintPrint(image))
        let original = try XCTUnwrap(CGImageSourceCreateWithData(image as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let result = try XCTUnwrap(CGImageSourceCreateWithData(enhanced as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        XCTAssertEqual(result.width, original.width)
        XCTAssertEqual(result.height, original.height)
        XCTAssertNil(ReceiptImagePreparer.enhancedForFaintPrint(Data("not an image".utf8)))
        XCTAssertLessThanOrEqual(ReceiptImagePreparer.enhancedContrast, 2)
        XCTAssertLessThanOrEqual(ReceiptImagePreparer.enhancedGamma, 2)
    }

    /// 35：2回目の読み取りは、1回目の精度が低いときだけ。良い方の結果を使う
    func testSecondPassOnlyWhenLowQuality() {
        let good = [ReceiptRecognizedLine(text: "架空ベーカリー こむぎ堂", confidence: 0.9), ReceiptRecognizedLine(text: "合計 ¥3,520", confidence: 0.9)]
        let faint = [ReceiptRecognizedLine(text: "合計", confidence: 0.3)]
        XCTAssertFalse(ReceiptReadQuality.isLow(good))
        XCTAssertTrue(ReceiptReadQuality.isLow(faint))
        XCTAssertEqual(ReceiptReadQuality.better(faint, good), good)
        XCTAssertEqual(ReceiptReadQuality.better(good, faint), good)
        XCTAssertGreaterThan(ReceiptReadQuality.score(good), ReceiptReadQuality.score(faint))
    }

    /// 36：写真・読み取った文字・ほかの読み方・候補・位置・信頼度は保存しない（支出と確かめた明細だけ）
    @MainActor
    func testRecognitionDataIsNotSaved() async throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeBuild22(lines: build22Receipt, store: store)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        let draft = try XCTUnwrap(setup.viewModel.draft)
        XCTAssertEqual(draft.amount, 3520)
        XCTAssertTrue(setup.viewModel.save(draft))
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(file.contains("クロワッサン"), "確かめた明細は保存する")
        for notSaved in ["3,820", "お預り", "お釣り", "外税", "小計", "選択非推奨", "確認してください", "alternatives",
                         "amountCandidates", "amountWarning", "confidence", "boundingBox", "receiptNotes"] {
            XCTAssertFalse(file.contains(notSaved), notSaved)
        }
        let expense = try XCTUnwrap(store.expenses.first)
        XCTAssertEqual(Set(Mirror(reflecting: expense).children.compactMap(\.label)), ["id", "title", "amount", "category", "date", "ownership"], "支出の項目は増やさない")
        let saved = try XCTUnwrap(store.lineItems(for: expense.id).first)
        XCTAssertEqual(Set(Mirror(reflecting: saved).children.compactMap(\.label)), ["id", "name", "quantity", "unitPrice", "amount", "sortOrder"], "明細の項目も増やさない")
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertEqual(files.filter { name in [".jpg", ".jpeg", ".png", ".heic"].contains { name.lowercased().hasSuffix($0) } }, [], "写真のファイルを作らない")
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined(separator: "\n")
        XCTAssertFalse(defaults.contains("クロワッサン"))
        XCTAssertFalse(defaults.contains("3,820"))
    }

    /// 37：ネットワークを使わない・ログに出さない・データセットをアプリに入れない・新しい文字認識の窓口は使わない
    func testNoNetworkNoLoggingNoDatasetInApp() throws {
        let files = [
            "LifeOS/Core/Utilities/ReceiptNumberText.swift",
            "LifeOS/Core/Utilities/ReceiptLayout.swift",
            "LifeOS/Core/Utilities/ReceiptFieldExtractor.swift",
            "LifeOS/Core/Utilities/ReceiptTextRecognizer.swift",
            "LifeOS/Core/Utilities/ReceiptImagePreparer.swift",
            "LifeOS/Core/Utilities/WarrantyTextRecognizer.swift",
            "LifeOS/DesignSystem/Components/LifeKeyboardDismissal.swift"
        ]
        for path in files {
            let code = build22CodeOnly(try build22Source(path))
            for word in ["URLSession", "URLRequest", "print(", "NSLog", "os_log", "Logger(", "debugPrint", "dump(", "Firestore", "Analytics",
                         "RecognizeDocumentsRequest"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        // データセット（CORD など）はアプリにもリポジトリにも入れない（Mac の中だけの、Git に入らない場所で評価する）
        let gitignore = try build22Source(".gitignore")
        XCTAssertTrue(gitignore.contains("evaluation/datasets/"))
        let bundle = Bundle.main
        for suffix in ["cord", "sroie"] {
            XCTAssertNil(bundle.path(forResource: suffix, ofType: nil))
        }
        // 対応 OS は上げない（iOS 17.0 のまま）
        let project = try build22Source("LifeOS.xcodeproj/project.pbxproj")
        let targets = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("IPHONEOS_DEPLOYMENT_TARGET =") }
        XCTAssertFalse(targets.isEmpty)
        XCTAssertEqual(Set(targets), ["IPHONEOS_DEPLOYMENT_TARGET = 17.0;"])
    }

    /// 38：Build 21 の商品明細の保存は今までどおり（確かめた明細を支出と一緒に保存する）
    @MainActor
    func testBuild21LineItemsStillSaved() async throws {
        let setup = makeBuild22(lines: build22Receipt)
        setup.viewModel.readReceipt(build22Image, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        var draft = try XCTUnwrap(setup.viewModel.draft)
        XCTAssertEqual(draft.lineItems.map(\.name), ["クロワッサン", "食パン"])
        let removed = try XCTUnwrap(draft.lineItems.last)
        draft.removeLineItem(removed.id)
        XCTAssertTrue(setup.viewModel.save(draft))
        let expense = try XCTUnwrap(setup.store.expenses.first)
        let saved = setup.store.lineItems(for: expense.id)
        XCTAssertEqual(saved.map(\.name), ["クロワッサン"], "確認画面に残した明細だけ")
        XCTAssertEqual(saved.first?.quantity, 2)
        XCTAssertEqual(saved.first?.unitPrice, 240)
        XCTAssertEqual(saved.first?.amount, 480)
    }

    /// 39：保証書の文字の読み取りは今までどおり（ほかの読み方は使わない）
    func testWarrantyOCRStillWorks() {
        let proposal = WarrantyFieldExtractor.extract(from: [
            WarrantyRecognizedLine(text: "型番 AB-123", alternatives: ["型番 A8-123"]),
            WarrantyRecognizedLine(text: "お買上げ日 2026/10/13", confidence: 0.9)
        ])
        XCTAssertEqual(proposal.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
        XCTAssertEqual(proposal.fields.first { $0.kind == .purchaseDate }?.date, TestDates.make(2026, 10, 13))
    }

    /// 40：Build 番号は4か所とも 22。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    func testBuildNumberIs22() throws {
        let project = try build22Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 22;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build22Source("docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md").contains("Build 16 は欠番"))
    }
}
