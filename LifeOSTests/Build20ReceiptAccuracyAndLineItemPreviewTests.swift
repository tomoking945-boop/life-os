import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LifeOS

// Build 20（2026-11-05）：レシートの店名・合計金額の読み取り精度の改善と、商品明細（確認用）の表示。
// docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md
// 本物の Firestore・ネットワークは使わない（共有の支出は Build13 の FakeSharedExpensesBackend）。
// 文字認識は偽物（位置・信頼度つきの行を返す）に差し替える。写真の向き・縮小・キャンセルは本物の部品で確かめる。

private let build20Now = TestDates.make(2026, 11, 12, 9, 0)

private func build20Store() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func build20Source(_ path: String) throws -> String {
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

/// 位置つきの1つの文字のまとまり（左上が原点、0〜1）
private func line(_ text: String, y: Double, x: Double = 0.05, width: Double = 0.4, height: Double = 0.015, confidence: Float = 0.95) -> ReceiptRecognizedLine {
    ReceiptRecognizedLine(text: text, confidence: confidence, box: RecognizedTextBox(x: x, y: y, width: width, height: height))
}

private func extract(_ lines: [String]) -> ReceiptExtractionProposal {
    ReceiptFieldExtractor.extract(from: lines, today: build20Now)
}

private func extract(_ lines: [ReceiptRecognizedLine]) -> ReceiptExtractionProposal {
    ReceiptFieldExtractor.extract(from: lines, today: build20Now)
}

/// 位置つきのレシート（左に見出し・商品名、右に金額）。上に小さな運営会社名、その下に大きな店名
private let layoutReceipt: [ReceiptRecognizedLine] = [
    line("テスト運営株式会社", y: 0.02),
    line("まちの八百屋", y: 0.05, x: 0.25, height: 0.04),
    line("東京都台東区浅草1-2-3", y: 0.10),
    line("TEL 03-1234-5678", y: 0.12),
    line("2026年11月2日(月) 18:42", y: 0.16),
    line("レジ#2 担当 山田", y: 0.18),
    line("牛乳", y: 0.24), line("¥198", y: 0.242, x: 0.75, width: 0.15),
    line("ティッシュ", y: 0.27), line("¥500", y: 0.272, x: 0.75, width: 0.15),
    line("2点 × ¥250", y: 0.29, x: 0.1),
    line("小計", y: 0.40), line("¥698", y: 0.40, x: 0.75, width: 0.15),
    line("(内消費税 ¥63)", y: 0.42),
    line("合計", y: 0.46, height: 0.02), line("¥698", y: 0.462, x: 0.70, width: 0.2, height: 0.02),
    line("お預り", y: 0.50), line("¥1,000", y: 0.50, x: 0.75, width: 0.15),
    line("お釣り", y: 0.52), line("¥302", y: 0.52, x: 0.75, width: 0.15)
]

/// 合計と明細が一致しないレシート（外税のため。文字だけ）
private let mismatchReceipt = [
    "スーパーテスト 新宿店",
    "2026/11/02 18:42",
    "牛乳 ¥198",
    "食パン ¥250",
    "小計 ¥448",
    "外税 ¥35",
    "合計 ¥483",
    "お預り ¥1,000",
    "お釣り ¥517"
]

/// 偽物の文字認識（位置・信頼度つきの行を返す。呼ばれた回数と「範囲を直すか」を記録する）
private final class Build20FakeRecognizer: ReceiptTextRecognizing {
    var lines: [ReceiptRecognizedLine]
    var delayNanoseconds: UInt64
    private(set) var calls = 0
    private(set) var detectsDocumentFlags: [Bool] = []

    init(lines: [ReceiptRecognizedLine], delayNanoseconds: UInt64 = 0) {
        self.lines = lines
        self.delayNanoseconds = delayNanoseconds
    }

    func recognizeLines(in imageData: Data) async throws -> [String] {
        try await recognizeReceipt(in: imageData, detectsDocument: true).map(\.text)
    }

    func recognizeReceipt(in imageData: Data, detectsDocument: Bool) async throws -> [ReceiptRecognizedLine] {
        calls += 1
        detectsDocumentFlags.append(detectsDocument)
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        return lines
    }
}

private struct Build20ReceiptSetup {
    let store: LifeStore
    let backend: FakeSharedExpensesBackend
    let service: SharedExpensesService
    let recognizer: Build20FakeRecognizer
    let viewModel: MoneyViewModel
}

private func makeSetup(lines: [ReceiptRecognizedLine] = layoutReceipt, delay: UInt64 = 0, store: LifeStore = build20Store()) -> Build20ReceiptSetup {
    let backend = FakeSharedExpensesBackend()
    let service = SharedExpensesService(backend: backend)
    service.attach(store)
    service.apply(household: HouseholdSummary(
        name: "わが家", sharedKinds: [.todo, .shopping, .money], isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build20"
    ), isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = .shared
    let recognizer = Build20FakeRecognizer(lines: lines, delayNanoseconds: delay)
    let viewModel = MoneyViewModel(store: store, appState: appState, now: build20Now, receiptRecognizer: recognizer)
    return Build20ReceiptSetup(store: store, backend: backend, service: service, recognizer: recognizer, viewModel: viewModel)
}

private let receiptImage = WarrantyTestImages.text(["合計 ¥698"])

/// テスト用の画像（単色。CGContext で作るので、画面の倍率に左右されない）
private func testImage(width: Int, height: Int, orientation: Int? = nil) -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("テスト用の画像を作れませんでした")
    }
    context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        fatalError("テスト用の画像を作れませんでした")
    }
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("テスト用の画像を作れませんでした") }
    return data as Data
}

// MARK: - 1. 店名（1〜8）

final class Build20StoreNameTests: XCTestCase {
    /// 1：レシートの上の方・大きな文字の店名を優先する（位置で行をまとめる）
    func testTopAndLargeStoreNameIsPreferred() {
        let proposal = extract(layoutReceipt)
        XCTAssertEqual(proposal.title, "まちの八百屋", "上の方の大きな文字で、店名らしい言葉がある")
        XCTAssertEqual(proposal.storeCandidates.first, proposal.title)
        // 同じ大きさなら、上にある方が上の順位
        let sameSize = extract([
            line("三越 日本橋店", y: 0.20),
            line("まちの八百屋", y: 0.05),
            line("2026/11/02", y: 0.30),
            line("合計 ¥500", y: 0.60)
        ])
        XCTAssertEqual(sameSize.storeCandidates, ["まちの八百屋", "三越 日本橋店"])
        // 「店名：」の近く（見出しだけの行の次の行）を優先する
        let labeled = extract([
            line("テスト運営株式会社", y: 0.02),
            line("店名：", y: 0.06),
            line("カフェ・ド・テスト", y: 0.08),
            line("2026/11/02", y: 0.30)
        ])
        XCTAssertEqual(labeled.title, "カフェ・ド・テスト")
    }

    /// 2：商品名を店名にしない（日付・明細より下は探さない）
    func testItemNamesAreNotStoreNames() {
        let candidates = extract(layoutReceipt).storeCandidates
        for item in ["牛乳", "ティッシュ", "牛乳 ¥198", "ティッシュ ¥500"] {
            XCTAssertFalse(candidates.contains(item), item)
        }
        XCTAssertEqual(extract(["まちの八百屋", "八百屋の漬物 ¥300", "大根 2点"]).storeCandidates, ["まちの八百屋"])
    }

    /// 3：住所・電話・番号・担当・会員・カード・ポイント・お預り・お釣りを除く
    func testExcludesAddressPhoneNumbersAndPaymentWords() {
        let notNames = [
            "東京都台東区浅草1-2-3", "TEL 03-1234-5678", "〒160-0023", "登録番号 T1234567890123", "レシート番号 0012", "レジ#2 担当 山田",
            "担当 山田", "会員番号 1234", "ポイントカード", "お預り", "お釣り", "カード ****1234", "お支払い クレジット", "現金",
            "https://example.jp", "いらっしゃいませ", "18:42", "小計", "合計"
        ]
        for name in notNames {
            XCTAssertEqual(extract([name]).storeCandidates, [], name)
        }
        let candidates = extract(layoutReceipt).storeCandidates
        XCTAssertFalse(candidates.contains { $0.contains("浅草") || $0.contains("TEL") || $0.contains("担当") })
    }

    /// 4：漢数字の店名を残す
    func testKeepsKanjiNumeralStoreNames() {
        let proposal = extract([
            line("八百八町そば", y: 0.03, height: 0.03),
            line("三越 日本橋店", y: 0.08),
            line("一休堂", y: 0.11),
            line("2026/11/02", y: 0.30)
        ])
        XCTAssertEqual(proposal.storeCandidates, ["八百八町そば", "三越 日本橋店", "一休堂"])
    }

    /// 5：複数の候補の順位（上の小さな会社名より、下の大きな店名を上にする。最大5件）
    func testRankingOfMultipleCandidates() {
        XCTAssertEqual(extract(layoutReceipt).storeCandidates, ["まちの八百屋", "テスト運営株式会社"])
        // 信頼度の低い候補は下に
        let lowConfidence = extract([
            line("まちの八百屋", y: 0.05, confidence: 0.3),
            line("まちの青果店", y: 0.06, confidence: 0.98),
            line("2026/11/02", y: 0.30)
        ])
        XCTAssertEqual(lowConfidence.storeCandidates, ["まちの青果店", "まちの八百屋"])
        let many = (0..<8).map { line("候補の店\($0 + 1)", y: 0.01 + Double($0) * 0.02) }
        XCTAssertEqual(extract(many).storeCandidates.count, ReceiptFieldExtractor.maxStoreCandidates)
        XCTAssertEqual(ReceiptFieldExtractor.maxStoreCandidates, 5)
    }

    /// 6：同じ候補を重ねない
    func testNoDuplicateCandidates() {
        let proposal = extract([
            line("まちの八百屋", y: 0.02),
            line("**** まちの八百屋 ****", y: 0.05),
            line("まちの八百屋", y: 0.08),
            line("2026/11/02", y: 0.30)
        ])
        XCTAssertEqual(proposal.storeCandidates, ["まちの八百屋"])
    }
}

// MARK: - 2. 合計金額（9〜15）

final class Build20TotalAmountTests: XCTestCase {
    /// 9：見出しと同じ行の合計を読む。表示は「¥3,520（合計）」
    func testReadsTotalOnSameRow() {
        let proposal = extract(["合計 ¥3,520"])
        XCTAssertEqual(proposal.amount, 3520)
        XCTAssertEqual(proposal.amountCandidates.map(\.displayText), ["¥3,520（合計）"])
        XCTAssertEqual(extract(["お支払額 3,520円"]).amountCandidates.first?.displayText, "¥3,520（お支払額）")
    }

    /// 10：右側に離れた合計を読む（位置で同じ行にまとめる）
    func testReadsTotalFarToTheRight() {
        let proposal = extract([
            line("合計", y: 0.70, width: 0.1, height: 0.02),
            line("¥3,520", y: 0.705, x: 0.75, width: 0.2, height: 0.02)
        ])
        XCTAssertEqual(proposal.amount, 3520)
        XCTAssertEqual(proposal.amountCandidates.first?.label, "合計")
    }

    /// 11：見出しの直下の合計を読む
    func testReadsTotalDirectlyBelow() {
        let proposal = extract([
            line("お支払額", y: 0.60),
            line("¥3,520", y: 0.63, x: 0.7, width: 0.2)
        ])
        XCTAssertEqual(proposal.amount, 3520)
        XCTAssertEqual(proposal.amountCandidates.first?.label, "お支払額")
        XCTAssertNil(extract(["合計", "03-1234-5678"]).amount, "直下が電話番号なら使わない")
    }

    /// 12：レシート下部の合計を上の順位にする（同じ強さで金額が違えば、選んでもらう）
    func testBottomTotalIsRankedFirst() {
        let proposal = extract(["合計 1,000", "合計 2,000"])
        XCTAssertEqual(proposal.amountCandidates.map(\.amount), [2000, 1000], "下の方を上の順位に")
        XCTAssertNil(proposal.amount)
        let layout = extract([
            line("合計 ¥1,000", y: 0.20),
            line("合計 ¥2,000", y: 0.80)
        ])
        XCTAssertEqual(layout.amountCandidates.map(\.amount), [2000, 1000])
        // 強い見出しは、位置より優先
        XCTAssertEqual(extract(["総合計 ¥1,080", "合計 ¥1,000"]).amount, 1080)
    }

    /// 13：お預り・お釣り・税・値引き・ポイントを候補にしない
    func testDepositChangeAndTaxAreExcluded() {
        let proposal = extract(["小計 ¥3,200", "合計 ¥3,520", "お支払額 ¥3,520", "お預り ¥5,000", "お釣り ¥1,480", "消費税 ¥320", "値引 ¥100", "ポイント 35"])
        XCTAssertEqual(proposal.amount, 3520)
        let amounts = proposal.amountCandidates.map(\.amount)
        for excluded in [5000, 1480, 320, 100, 35] {
            XCTAssertFalse(amounts.contains(excluded), "\(excluded)")
        }
        XCTAssertEqual(proposal.amountCandidates.map(\.displayText), ["¥3,520（お支払額）", "¥3,520（合計）", "¥3,200（小計・選択非推奨）"])
        XCTAssertEqual(extract(layoutReceipt).amountCandidates.map(\.amount), [698, 698], "合計と小計（お預り・お釣りは入らない）")
    }

    /// 14：小計は自動で入れない（参考の候補「小計・選択非推奨」だけ）
    func testSubtotalIsNeverAutoSelected() {
        let proposal = extract(["小計 ¥3,200"])
        XCTAssertNil(proposal.amount)
        XCTAssertEqual(proposal.amountIssue, .notFound)
        let candidate = try? XCTUnwrap(proposal.amountCandidates.first)
        XCTAssertEqual(candidate?.displayText, "¥3,200（小計・選択非推奨）")
        XCTAssertEqual(candidate?.isRecommended, false)
        XCTAssertNil(extract(["SUB TOTAL 1000"]).amount)
        XCTAssertEqual(extract(["SUBTOTAL 1000", "TAX 100", "TOTAL 1100"]).amountCandidates.map(\.displayText), ["¥1,100（TOTAL）", "¥1,000（小計・選択非推奨）"])
        let draft = ExpenseDraft(receipt: proposal, today: build20Now)
        XCTAssertEqual(draft.amountText, "", "小計しか無いときも金額欄は空")
        XCTAssertFalse(draft.amountCandidates.contains { draft.isSelectedAmountCandidate($0) })
    }

    /// 15：異なる強い候補が複数あるときは空欄にして、選んでもらう
    func testDifferentStrongCandidatesLeaveAmountEmpty() {
        let proposal = extract(["総合計 ¥3,520", "お支払額 ¥3,600"])
        XCTAssertNil(proposal.amount)
        XCTAssertEqual(proposal.amountIssue, .ambiguous)
        XCTAssertEqual(Set(proposal.amountCandidates.map(\.amount)), [3520, 3600])
        XCTAssertLessThanOrEqual(proposal.amountCandidates.count, ReceiptFieldExtractor.maxAmountCandidates)
        XCTAssertEqual(ReceiptFieldExtractor.maxAmountCandidates, 5)
        XCTAssertNil(extract(["牛乳 198", "パン 250"]).amount, "どれも安全でなければ空")
    }
}

// MARK: - 3. 商品明細（19〜27）

final class Build20LineItemExtractionTests: XCTestCase {
    /// 19：左の商品名と右の金額を組み合わせる
    func testCombinesNameAndRightAmount() {
        let items = extract(layoutReceipt).lineItems
        XCTAssertEqual(items.first?.name, "牛乳")
        XCTAssertEqual(items.first?.amount, 198)
        XCTAssertEqual(extract(["2026/11/02", "4901234567890 牛乳 ¥198"]).lineItems.map(\.name), ["牛乳"], "先頭の商品コードは名前にしない")
    }

    /// 20：複数の商品を行ごとに分ける
    func testSplitsMultipleItemsByRow() {
        let items = extract(mismatchReceipt).lineItems
        XCTAssertEqual(items.map(\.name), ["牛乳", "食パン"])
        XCTAssertEqual(items.map(\.amount), [198, 250])
        XCTAssertEqual(extract(layoutReceipt).lineItems.map(\.name), ["牛乳", "ティッシュ"])
    }

    /// 21：数量を読む（「2点」「2 x 198」「2×198」「198円×2」。読めなければ空）
    func testReadsQuantity() {
        let items = extract([
            "2026/11/02",
            "パン 2点 ¥300",
            "みかん 2 x 198 396",
            "バナナ 2×150 300",
            "ぶどう 198円×2 396",
            "食パン 6枚切 ¥250",
            "合計 ¥1,642"
        ]).lineItems
        XCTAssertEqual(items.map(\.name), ["パン", "みかん", "バナナ", "ぶどう", "食パン 6枚切"])
        XCTAssertEqual(items.map(\.quantity), [2, 2, 2, 2, nil], "「6枚切」は数量にしない")
        XCTAssertEqual(items.map(\.amount), [300, 396, 300, 396, 250])
        // 次の行の「2点 × ¥250」は直前の商品の数量・単価
        let tissue = extract(layoutReceipt).lineItems.last
        XCTAssertEqual(tissue?.name, "ティッシュ")
        XCTAssertEqual(tissue?.quantity, 2)
        XCTAssertEqual(tissue?.unitPrice, 250)
        XCTAssertEqual(tissue?.amount, 500)
        XCTAssertEqual(tissue?.displayText, "ティッシュ　2点 × ¥250　¥500")
    }

    /// 22：単価を読む（「@198」「単198」「2 x 198」）
    func testReadsUnitPrice() {
        let items = extract([
            "2026/11/02",
            "りんご @98 196",
            "みかん 2 x 198 396",
            "ヨーグルト ¥396",
            "2コ × 単198",
            "牛乳 ¥198",
            "合計 ¥1,186"
        ]).lineItems
        XCTAssertEqual(items.map(\.name), ["りんご", "みかん", "ヨーグルト", "牛乳"])
        XCTAssertEqual(items.map(\.unitPrice), [98, 198, 198, nil], "読めない単価は空（推測しない）")
        XCTAssertEqual(items.map(\.quantity), [nil, 2, 2, nil])
        XCTAssertEqual(items.first?.displayText, "りんご　@¥98　¥196")
    }

    /// 23：小計・合計・税・値引き・ポイント・支払い・電話・日時・レジ・担当・記号だけの行は商品にしない
    func testExcludesTotalsTaxPaymentAndInfoRows() {
        let items = extract([
            "まちの八百屋",
            "TEL 03-1234-5678",
            "2026/11/02 10:00",
            "レジ#2 担当 山田",
            "牛乳 ¥198",
            "値引 -50",
            "クーポン ¥100",
            "ポイント 10",
            "消費税 ¥33",
            "****",
            "小計 ¥198",
            "合計 ¥198",
            "お預り ¥1,000",
            "お釣り ¥802",
            "クレジット ¥198",
            "カード番号 **** **** **** 1234",
            "牛乳 999"
        ]).lineItems
        XCTAssertEqual(items.map(\.name), ["牛乳"], "合計より下（支払いの欄）は見ない")
        XCTAssertEqual(items.map(\.amount), [198])
        XCTAssertEqual(extract(["2026/11/02", "合計 ¥500"]).lineItems, [])
    }

    /// 26：明細の合計とレシートの合計が一致する
    func testMatchingTotals() {
        let proposal = extract(layoutReceipt)
        let draft = ExpenseDraft(receipt: proposal, today: build20Now)
        XCTAssertEqual(draft.lineItemsTotal, 698)
        XCTAssertEqual(draft.lineItemComparison, .matched(total: 698))
        XCTAssertEqual(draft.lineItemComparison.message, "商品明細の合計と一致しています")
    }

    /// 27：一致しなければ警告する。比べられないとき・明細が無いときの案内
    func testMismatchWarningAndInsufficientData() {
        let draft = ExpenseDraft(receipt: extract(mismatchReceipt), today: build20Now)
        XCTAssertEqual(draft.amount, 483)
        XCTAssertEqual(draft.lineItemComparison, .mismatched(itemsTotal: 448, receiptTotal: 483))
        XCTAssertEqual(draft.lineItemComparison.message, "値引き・税・読み取り違いなどにより、商品明細の合計とレシート合計が一致しません")
        XCTAssertTrue(draft.lineItemComparison.isMismatch)
        // 合計金額が空・金額の無い明細がある → 比較不能
        XCTAssertEqual(ReceiptLineItemComparison.compare(items: draft.lineItems, receiptTotal: nil), .insufficient)
        XCTAssertEqual(ReceiptLineItemComparison.compare(items: [ReceiptLineItem(name: "牛乳", unitPrice: 198)], receiptTotal: 198), .insufficient)
        XCTAssertTrue(ReceiptLineItemComparison.insufficient.message.contains("比較不能"))
        XCTAssertEqual(ReceiptLineItemComparison.compare(items: [], receiptTotal: 500), .noItems)
        XCTAssertEqual(ReceiptLineItemComparison.noItems.message, "商品明細を読み取れませんでした")
    }
}

// MARK: - 4. 確認画面・保存しない（7・8・16〜18・24・25・28〜32）

final class Build20ReceiptDraftFlowTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build20-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    @MainActor
    private func readDraft(_ setup: Build20ReceiptSetup) async throws -> ExpenseDraft {
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        return try XCTUnwrap(setup.viewModel.draft)
    }

    /// 7：店名の候補を選べる・手入力できる（Build 19 と同じ）
    @MainActor
    func testStoreCandidateSelectionAndManualEntry() async throws {
        let setup = makeSetup()
        var draft = try await readDraft(setup)
        XCTAssertEqual(draft.title, "まちの八百屋")
        draft.selectStoreCandidate("テスト運営株式会社")
        XCTAssertEqual(draft.title, "テスト運営株式会社")
        XCTAssertTrue(draft.isSelectedStoreCandidate("テスト運営株式会社"))
        draft.title = "八百屋（浅草）"
        XCTAssertFalse(draft.storeCandidates.contains { draft.isSelectedStoreCandidate($0) })
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.title), ["八百屋（浅草）"])
    }

    /// 16：合計金額の候補を選ぶと金額欄へ入る（選んだ候補にチェック）
    @MainActor
    func testSelectingAmountCandidateFillsAmount() async throws {
        let setup = makeSetup(lines: ["総合計 ¥3,520", "お支払額 ¥3,600", "小計 ¥3,200"].map { ReceiptRecognizedLine(text: $0) })
        var draft = try await readDraft(setup)
        XCTAssertEqual(draft.amountText, "", "強い候補が2つあるので空")
        XCTAssertEqual(draft.amountCandidates.count, 3)
        let candidate = try XCTUnwrap(draft.amountCandidates.first { $0.amount == 3520 })
        draft.selectAmountCandidate(candidate)
        XCTAssertEqual(draft.amountText, "3520")
        XCTAssertEqual(draft.amount, 3520)
        XCTAssertTrue(draft.isSelectedAmountCandidate(candidate))
        XCTAssertEqual(draft.amountCandidates.filter { draft.isSelectedAmountCandidate($0) }.count, 1)
        // 小計も、利用者が選べば入る（自動では入れない）
        let subtotal = try XCTUnwrap(draft.amountCandidates.first { !$0.isRecommended })
        draft.selectAmountCandidate(subtotal)
        XCTAssertEqual(draft.amount, 3200)
        // 候補に無いものは入れない
        draft.selectAmountCandidate(ReceiptAmountCandidate(amount: 9999, label: "合計", kind: .total, score: 0))
        XCTAssertEqual(draft.amount, 3200)
        // 自動で入れた金額は、その候補にチェック
        let auto = try await readDraft(makeSetup())
        XCTAssertEqual(auto.amount, 698)
        XCTAssertTrue(auto.amountCandidates.first.map { auto.isSelectedAmountCandidate($0) } == true)
    }

    /// 17：金額欄は手入力できる（候補が無くても）
    @MainActor
    func testAmountCanBeEnteredManually() async throws {
        var draft = try await readDraft(makeSetup())
        draft.amountText = "３，５００円"
        XCTAssertEqual(draft.amount, 3500)
        XCTAssertFalse(draft.amountCandidates.contains { draft.isSelectedAmountCandidate($0) }, "手で変えたら、どの候補も選ばれていない")
        XCTAssertTrue(draft.canSave)
        var empty = try await readDraft(makeSetup(lines: ["まちの八百屋", "牛乳 198"].map { ReceiptRecognizedLine(text: $0) }))
        XCTAssertEqual(empty.amountCandidates, [])
        XCTAssertFalse(empty.canSave)
        empty.amountText = "198"
        XCTAssertTrue(empty.canSave)
    }

    /// 24：商品明細を修正できる（確認用）
    @MainActor
    func testEditingLineItem() async throws {
        var draft = try await readDraft(makeSetup())
        draft.lineItems[0].name = "低脂肪牛乳"
        draft.lineItems[0].quantityText = "１"
        draft.lineItems[0].amountText = "200"
        XCTAssertEqual(draft.lineItems[0].name, "低脂肪牛乳")
        XCTAssertEqual(draft.lineItems[0].quantity, 1)
        XCTAssertEqual(draft.lineItems[0].amount, 200)
        XCTAssertEqual(draft.lineItemsTotal, 700)
        XCTAssertTrue(draft.lineItemComparison.isMismatch)
        draft.lineItems[0].amountText = "abc"
        XCTAssertNil(draft.lineItems[0].amount, "数字でなければ空として扱う")
        XCTAssertEqual(draft.lineItemComparison, .insufficient)
    }

    /// 25：誤った商品明細を消せる
    @MainActor
    func testDeletingLineItem() async throws {
        var draft = try await readDraft(makeSetup())
        let tissue = try XCTUnwrap(draft.lineItems.first { $0.name == "ティッシュ" })
        draft.removeLineItem(tissue.id)
        XCTAssertEqual(draft.lineItems.map(\.name), ["牛乳"])
        XCTAssertTrue(draft.lineItemComparison.isMismatch)
        draft.removeLineItem(draft.lineItems[0].id)
        XCTAssertEqual(draft.lineItemComparison, .noItems)
    }

    /// 28：一致しなくても支出を保存できる
    @MainActor
    func testCanSaveEvenWhenTotalsMismatch() async throws {
        let setup = makeSetup(lines: mismatchReceipt.map { ReceiptRecognizedLine(text: $0) })
        let draft = try await readDraft(setup)
        XCTAssertTrue(draft.lineItemComparison.isMismatch)
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.map(\.amount), [483])
    }

    /// 8・18・29：店名の候補・合計の候補・商品明細を life-store.json に保存しない（支出の項目も増やさない）
    @MainActor
    func testCandidatesAndLineItemsAreNotPersisted() async throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeSetup(store: store)
        var draft = try await readDraft(setup)
        XCTAssertFalse(draft.lineItems.isEmpty)
        draft.lineItems[0].name = "修正した牛乳"
        XCTAssertTrue(setup.viewModel.save(draft))
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        XCTAssertTrue(file.contains("まちの八百屋"), "選んだタイトルだけ保存する")
        // Build 21（2026-11-08）：確認画面に残っている商品明細は、支出と一緒に保存する仕様になった
        // （docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md）。そのため「牛乳」「修正した牛乳」「ティッシュ」「lineItems」を
        // 保存しないものの確認から外し、直した明細が保存されることを確かめる。候補・読み取った全文は今までどおり保存しない
        XCTAssertTrue(file.contains("修正した牛乳"), "Build 21：確かめた（直した）商品明細は保存する")
        for notSaved in ["テスト運営株式会社", "選択非推奨", "小計", "amountCandidates", "storeCandidates", "浅草", "03-1234-5678", "confidence", "boundingBox"] {
            XCTAssertFalse(file.contains(notSaved), notSaved)
        }
        let saved = try XCTUnwrap(store.expenses.first)
        XCTAssertEqual(Set(Mirror(reflecting: saved).children.compactMap(\.label)), ["id", "title", "amount", "category", "date", "ownership"])
        XCTAssertEqual(saved.amount, 698)
        // 端末のほかの場所（UserDefaults・ファイル）にも残さない
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        let imageSuffixes = [".jpg", ".jpeg", ".png", ".heic"]
        XCTAssertEqual(files.filter { name in imageSuffixes.contains { name.lowercased().hasSuffix($0) } }, [], "写真のファイルを作らない")
        XCTAssertEqual(files.filter { $0.lowercased().contains("receipt") || $0.lowercased().contains("lineitem") }, [], "明細・候補のファイルを作らない")
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined(separator: "\n")
        XCTAssertFalse(defaults.contains("修正した牛乳"))
        XCTAssertFalse(defaults.contains("テスト運営株式会社"))
    }

    /// 30：共有しても、Firestore へは今までの9項目だけ（商品明細・候補を送らない）
    @MainActor
    func testFirestoreReceivesOnlyNineFields() async throws {
        let setup = makeSetup()
        var draft = try await readDraft(setup)
        draft.destination = .household
        XCTAssertTrue(setup.viewModel.save(draft))
        let fields = try XCTUnwrap(setup.backend.creates.first?.fields)
        XCTAssertEqual(Set(fields.keys), ["schemaVersion", "title", "amount", "category", "date", "createdBy", "updatedBy", "createdAt", "updatedAt"])
        let values = fields.values.map { "\($0)" }.joined(separator: "\n")
        for notSent in ["牛乳", "ティッシュ", "テスト運営株式会社", "小計", "選択非推奨"] {
            XCTAssertFalse(values.contains(notSent), notSent)
        }
        for key in ["lineItems", "items", "amountCandidates", "storeCandidates", "receipt", "ocr", "text"] {
            XCTAssertNil(fields[key], key)
        }
    }

    /// 31：キャンセル・保存のあと、候補と商品明細を手放す
    @MainActor
    func testCandidatesAreReleasedAfterCancelOrSave() async throws {
        func held(_ viewModel: MoneyViewModel) -> [String] {
            Mirror(reflecting: viewModel).children.compactMap { child in
                switch child.value {
                case is Data, is [String], is [ReceiptRecognizedLine], is [ReceiptRow], is [ReceiptLineItem],
                     is [ReceiptAmountCandidate], is ReceiptExtractionProposal, is ExpenseDraft:
                    return child.label ?? "?"
                default:
                    return nil
                }
            }
        }
        let setup = makeSetup()
        _ = try await readDraft(setup)
        setup.viewModel.cancelEditing()
        XCTAssertNil(setup.viewModel.draft)
        XCTAssertEqual(held(setup.viewModel), [])
        XCTAssertTrue(setup.store.expenses.isEmpty, "キャンセルでは何も残らない")
        XCTAssertEqual(setup.backend.writeCount, 0)

        let saved = makeSetup()
        // XCTAssert の中（autoclosure）では await を使えないため、読み取りと保存を先に行ってから確かめる
        let savedDraft = try await readDraft(saved)
        let didSave = saved.viewModel.save(savedDraft)
        XCTAssertTrue(didSave)
        XCTAssertNil(saved.viewModel.draft)
        XCTAssertEqual(held(saved.viewModel), [])
    }

    /// 32：読み取りを二重に始めない・二重に保存しない
    @MainActor
    func testNoDoubleReadingOrDoubleSave() async throws {
        let setup = makeSetup(delay: 100_000_000)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertFalse(setup.viewModel.canStartReceiptScan)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertEqual(setup.recognizer.calls, 1)
        let draft = try XCTUnwrap(setup.viewModel.draft)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertEqual(setup.recognizer.calls, 1, "確認画面を開いている間は読み取らない")
        XCTAssertTrue(setup.viewModel.save(draft))
        XCTAssertFalse(setup.viewModel.save(draft))
        XCTAssertEqual(setup.store.expenses.count, 1)
    }
}

// MARK: - 5. 写真・品質・既存の機能（33〜42）

final class Build20ImageAndRegressionTests: XCTestCase {
    /// 33：向きの違う写真（EXIF の向き）を直してから読む
    func testOrientationIsCorrected() throws {
        let rotated = testImage(width: 40, height: 20, orientation: 6)
        let prepared = try ReceiptImagePreparer.prepare(rotated, detectsDocument: false)
        XCTAssertEqual(prepared.pixelWidth, 20, "90度回して縦長にする")
        XCTAssertEqual(prepared.pixelHeight, 40)
        let upright = try ReceiptImagePreparer.prepare(testImage(width: 40, height: 20), detectsDocument: false)
        XCTAssertEqual(upright.pixelWidth, 40)
        XCTAssertEqual(upright.pixelHeight, 20)
        // 整えた写真には向きの情報を残さない（すでに直している）
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual((properties?[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
    }

    /// 34：大きな写真は、文字が読める大きさを保って縮小する（小さな写真は大きくしない）
    func testLargeImageIsDownscaledSafely() throws {
        let large = try ReceiptImagePreparer.prepare(testImage(width: 4000, height: 1000), detectsDocument: false)
        XCTAssertEqual(max(large.pixelWidth, large.pixelHeight), ReceiptImagePreparer.maxPixelSize)
        XCTAssertEqual(large.pixelWidth, 3000)
        XCTAssertEqual(large.pixelHeight, 750)
        XCTAssertEqual(ReceiptImagePreparer.maxPixelSize, 3000)
        let small = try ReceiptImagePreparer.prepare(testImage(width: 120, height: 300), detectsDocument: false)
        XCTAssertEqual(small.pixelWidth, 120)
        XCTAssertEqual(small.pixelHeight, 300)
        // レシートの範囲が見つからない写真は、切り抜かずにそのまま使う（落ちない）
        let plain = try ReceiptImagePreparer.prepare(testImage(width: 200, height: 400), detectsDocument: true)
        XCTAssertGreaterThan(plain.data.count, 0)
        XCTAssertThrowsError(try ReceiptImagePreparer.prepare(Data("not an image".utf8)))
    }

    /// 35：読み取りをキャンセルしたら、続きを進めない
    @MainActor
    func testCancellationStopsReading() async throws {
        let setup = makeSetup(delay: 300_000_000)
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        XCTAssertTrue(setup.viewModel.isReadingReceipt)
        setup.viewModel.cancelReceiptReading()
        XCTAssertFalse(setup.viewModel.isReadingReceipt)
        XCTAssertFalse(setup.viewModel.isHoldingReceiptWork)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(setup.viewModel.draft, "キャンセルのあとに結果が届いても開かない")
        XCTAssertTrue(setup.store.expenses.isEmpty)
        // 本物の読み取りも、キャンセルされていれば写真を整える前に止まる
        let task = Task { () async throws -> [ReceiptRecognizedLine] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReceiptTextRecognizer().recognizeReceipt(in: receiptImage, detectsDocument: true)
        }
        do {
            _ = try await task.value
            XCTFail("キャンセルしたら読み取らない")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    /// 36：文字が少ない・信頼度が低いときは「読み取り精度が低い可能性があります」と出す
    @MainActor
    func testLowQualityGuidance() async throws {
        let message = "読み取り精度が低い可能性があります。撮り直すか、内容を確認してください"
        XCTAssertEqual(ReceiptReadQuality.lowQualityMessage, message)
        XCTAssertTrue(ReceiptReadQuality.isLow([ReceiptRecognizedLine(text: "合計 500")]), "文字が少ない")
        XCTAssertTrue(ReceiptReadQuality.isLow(layoutReceipt.map { ReceiptRecognizedLine(text: $0.text, confidence: 0.3, box: $0.box) }), "信頼度が低い")
        XCTAssertFalse(ReceiptReadQuality.isLow(layoutReceipt))
        XCTAssertTrue(ReceiptReadQuality.isLow([]))
        let low = makeSetup(lines: layoutReceipt.map { ReceiptRecognizedLine(text: $0.text, confidence: 0.2, box: $0.box) })
        low.viewModel.readReceipt(receiptImage, contentType: .png)
        await low.viewModel.waitForReceiptReading()
        XCTAssertTrue(low.viewModel.draft?.receiptNotes.contains(message) == true)
        let good = makeSetup()
        good.viewModel.readReceipt(receiptImage, contentType: .png)
        await good.viewModel.waitForReceiptReading()
        XCTAssertFalse(good.viewModel.draft?.receiptNotes.contains(message) == true)
    }

    /// 37：書類スキャン（VisionKit）を使えないときは今までのカメラ。失敗したら今までのカメラへ。
    /// 書類スキャンで撮ったものは範囲を直さず、写真から選んだものは範囲を直す
    @MainActor
    func testDocumentScannerFallback() async throws {
        XCTAssertEqual(ReceiptCaptureMode.preferred(isDocumentScannerSupported: false), .camera)
        XCTAssertEqual(ReceiptCaptureMode.preferred(isDocumentScannerSupported: true), .documentScanner)
        XCTAssertTrue(ReceiptScanOutcome.failed.fallsBackToCamera)
        XCTAssertFalse(ReceiptScanOutcome.cancelled.fallsBackToCamera)
        XCTAssertFalse(ReceiptScanOutcome.scanned(Data()).fallsBackToCamera)
        let view = codeOnly(try build20Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(view.contains("ReceiptDocumentScannerView { outcome in"))
        XCTAssertTrue(view.contains("switch ReceiptCaptureMode.preferred() {"))
        XCTAssertTrue(view.contains("viewModel.readReceipt(scanned.data, contentType: scanned.type, detectsDocument: false)"))
        XCTAssertTrue(view.contains("WarrantyCameraView(guide: WarrantyCameraView.receiptGuide)"), "今までのカメラも残す")
        let scanner = codeOnly(try build20Source("LifeOS/Features/Money/ReceiptDocumentScannerView.swift"))
        XCTAssertTrue(scanner.contains("scan.imageOfPage(at: 0)"), "使うのは1枚目だけ")
        XCTAssertTrue(scanner.contains("guard !didFinish else { return }"), "結果は1回だけ")
        // 範囲を直すかどうかが読み取りへ渡る
        let setup = makeSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .jpeg, detectsDocument: false)
        await setup.viewModel.waitForReceiptReading()
        setup.viewModel.cancelEditing()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertEqual(setup.recognizer.detectsDocumentFlags, [false, true])
    }

    /// 38：保証書の文字の読み取りは今までどおり（位置は省略できる項目として足しただけ）
    @MainActor
    func testWarrantyOCRStillWorks() async throws {
        let proposal = WarrantyFieldExtractor.extract(from: [
            WarrantyRecognizedLine(text: "型番 AB-123"),
            WarrantyRecognizedLine(text: "お買上げ日 2026/10/13", confidence: 0.9)
        ])
        XCTAssertEqual(proposal.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
        XCTAssertEqual(proposal.fields.first { $0.kind == .purchaseDate }?.date, TestDates.make(2026, 10, 13))
        XCTAssertNil(WarrantyRecognizedLine(text: "型番 AB-123").box)
        // SwiftUI の View の値（MainActor）は、XCTAssert の外でローカル変数に取り出してから比べる
        let warrantyGuide = WarrantyCameraView.warrantyGuide
        XCTAssertEqual(warrantyGuide, "保証書・レシート・製品ラベルを枠いっぱいに")
        let editor = try build20Source("LifeOS/Features/Documents/Warranty/WarrantyEditorView.swift")
        XCTAssertTrue(editor.contains("WarrantyCameraView { data, type in"))
        _ = try? await WarrantyTextRecognizer.proposal(for: [WarrantyTestImages.text(["型番 AB-123"])])
    }

    /// 39：Build 19 の店名候補（文字だけの行は上から順）と予定の色分けは今までどおり
    func testBuild19StoreCandidatesAndColorsStillWork() throws {
        let lines = [
            "いらっしゃいませ", "まちの八百屋", "八百八町そば 本店", "TEL 03-1234-5678", "東京都台東区浅草1-2-3",
            "三越 日本橋店", "登録番号 T1234567890123", "2026年11月2日(月) 18:42", "大根 198", "合計 ¥198"
        ]
        XCTAssertEqual(extract(lines).storeCandidates, ["まちの八百屋", "八百八町そば 本店", "三越 日本橋店"])
        XCTAssertEqual(extract(lines).amount, 198)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "alice", currentUID: "alice"), .me)
        XCTAssertEqual(ItemRegistrant.from(createdBy: "bob", currentUID: "alice"), .partner)
        XCTAssertEqual(ItemRegistrant.from(createdBy: nil, currentUID: "alice"), .unknown)
        XCTAssertEqual(ItemRegistrant.me.label, "自分")
        let calendar = try build20Source("LifeOS/Features/Calendar/CalendarView.swift")
        XCTAssertTrue(calendar.contains("CalendarRegistrantBadge"))
    }

    /// 40：外部と通信しない・ログを出さない・Firebase の部品を増やさない・端末に書かない
    @MainActor
    func testNoNetworkLoggingOrFirebaseAdditions() async throws {
        NetworkSpyProtocol.requestedURLs = []
        URLProtocol.registerClass(NetworkSpyProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkSpyProtocol.self) }
        let setup = makeSetup()
        setup.viewModel.readReceipt(receiptImage, contentType: .png)
        await setup.viewModel.waitForReceiptReading()
        XCTAssertTrue(setup.viewModel.save(try XCTUnwrap(setup.viewModel.draft)))
        _ = try? ReceiptImagePreparer.prepare(testImage(width: 200, height: 400))
        XCTAssertEqual(NetworkSpyProtocol.requestedURLs, [])
        for path in [
            "LifeOS/Core/Utilities/ReceiptFieldExtractor.swift",
            "LifeOS/Core/Utilities/ReceiptLayout.swift",
            "LifeOS/Core/Utilities/ReceiptImagePreparer.swift",
            "LifeOS/Core/Utilities/ReceiptTextRecognizer.swift",
            "LifeOS/Features/Money/ReceiptDocumentScannerView.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift"
        ] {
            let code = codeOnly(try build20Source(path))
            for word in ["URLSession", "URLRequest", "Firestore", "import Firebase", "Analytics", "Crashlytics", "UserDefaults", "FileManager",
                         ".write(to", "print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump("] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        let project = try build20Source("LifeOS.xcodeproj/project.pbxproj")
        let products = project.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("productName = Firebase") }
        XCTAssertEqual(products, [
            "productName = FirebaseCore;", "productName = FirebaseAuth;", "productName = FirebaseFirestore;",
            "productName = FirebaseAppCheck;", "productName = FirebaseFunctions;", "productName = FirebaseMessaging;"
        ], "Analytics・Crashlytics を足していない")
    }

    /// 41：VoiceOver で商品名・数量・単価・金額を読める。操作は 44pt 以上
    func testVoiceOverAndTapTargets() throws {
        let item = ReceiptLineItem(name: "ティッシュ", quantity: 2, unitPrice: 250, amount: 500)
        XCTAssertEqual(item.spokenLabel, "商品名 ティッシュ、数量 2、単価 250円、金額 500円")
        XCTAssertEqual(ReceiptLineItem(name: "牛乳").spokenLabel, "商品名 牛乳、金額 読み取れず")
        let candidate = ReceiptAmountCandidate(amount: 3200, label: "小計", kind: .subtotal, score: 0)
        XCTAssertEqual(candidate.spokenLabel, "小計 3,200円、合計としての選択は非推奨")
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
        let view = codeOnly(try build20Source("LifeOS/Features/Money/MoneyView.swift"))
        for snippet in [
            ".accessibilityLabel(item.spokenLabel)",
            ".accessibilityLabel(candidate.spokenLabel)",
            ".frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)",
            ".frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)",
            "Text(\"商品明細（確認用）\")",
            // Build 21（2026-11-08）：商品明細を保存する仕様になったため、案内の文を差し替えた
            "Text(\"ここに残っている商品明細は、支出と一緒に保存されます（あとから支出の詳細で見返し・修正できます）。わが家で共有にした支出の明細は、わが家のメンバーにも表示されます。\")",
            "Text(ReceiptLineItemComparison.noItemsMessage)",
            "Text(\"合計金額の候補\")",
            "DisclosureGroup(isExpanded: $isShowingLineItems)"
        ] {
            XCTAssertTrue(view.contains(snippet), snippet)
        }
    }

    /// 42：Build 番号は4か所とも 20。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    func testBuildNumberIs20() throws {
        let project = try build20Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        // Build 21（2026-11-08）で 21 に上げたため、「4か所がそろっていて 20 以上」を確かめる（Build 15・17・18・19 と同じ扱い）
        let versions = lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(Set(versions).count, 1, "アプリ／テスト、Debug／Release の4か所が同じ")
        let number = Int(versions.first?.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = ", with: "").replacingOccurrences(of: ";", with: "") ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(number, 20)
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build20Source("docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md").contains("Build 16 は欠番"))
    }
}
