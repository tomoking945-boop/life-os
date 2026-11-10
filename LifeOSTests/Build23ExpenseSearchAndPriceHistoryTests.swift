import XCTest
import UIKit
@testable import LifeOS

// Build 23（2026-11-10）：家計簿の検索・商品の購入履歴・過去の参考価格。
// docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md
// 本物の Firestore・ネットワークは使わない（共有の支出・明細は、この下の偽物の保存先）。店名・商品名はすべて架空。

private let build23Now = TestDates.make(2026, 11, 10, 12, 0)
private let november1 = TestDates.make(2026, 11, 1, 10, 0)
private let november5 = TestDates.make(2026, 11, 5, 10, 0)
private let october20 = TestDates.make(2026, 10, 20, 10, 0)
private let september15 = TestDates.make(2026, 9, 15, 10, 0)

private func build23Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース（コメントの単語だけで誤検出しないため）
private func build23CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

/// 偽物の共有の明細の保存先（見張りの数・書き込みの数を数える）
private final class Build23LineItemsBackend: SharedExpenseLineItemsBackend {
    private(set) var listenCount = 0
    private(set) var removedListenerCount = 0
    private(set) var writeCount = 0
    private var onChange: (([SharedExpenseLineItemsSnapshot]) -> Void)?

    var activeListenerCount: Int { listenCount - removedListenerCount }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseLineItemsSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listenCount += 1
        self.onChange = onChange
        return RepositoryObservation { [weak self] in
            self?.removedListenerCount += 1
            self?.onChange = nil
        }
    }

    func set(groupID: String, expenseID: UUID, rows: [String], completion: @escaping (SharedItemsFailure?) -> Void) {
        writeCount += 1
        completion(nil)
    }

    func delete(groupID: String, expenseID: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        writeCount += 1
        completion(nil)
    }
}

private struct Build23Setup {
    let store: LifeStore
    let expenses: FakeSharedExpensesBackend
    let lineItems: Build23LineItemsBackend
    let service: SharedExpensesService
    let appState: AppState
    let viewModel: MoneyViewModel

    @discardableResult
    func addPersonal(_ title: String, amount: Int, category: ExpenseCategory = .food, date: Date = november5, items: [ExpenseLineItem] = []) -> Expense {
        let expense = Expense(title: title, amount: amount, category: category, date: date)
        store.addExpense(expense, destination: .personal, lineItems: items)
        return expense
    }

    @discardableResult
    func addShared(_ title: String, amount: Int, category: ExpenseCategory = .food, date: Date = november5, items: [ExpenseLineItem] = []) -> Expense {
        let expense = Expense(title: title, amount: amount, category: category, date: date, ownership: .shared)
        store.addExpense(expense, destination: .household, lineItems: items)
        return expense
    }

    func search(_ text: String) -> [ExpenseSearchResult] {
        viewModel.searchText = text
        return viewModel.searchResults
    }
}

private func makeBuild23(usageStyle: UsageStyle = .shared, store: LifeStore? = nil) -> Build23Setup {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    let expenses = FakeSharedExpensesBackend()
    let lineItems = Build23LineItemsBackend()
    let service = SharedExpensesService(backend: expenses, lineItemsBackend: lineItems)
    service.attach(store)
    service.apply(household: HouseholdSummary(
        name: "わが家", sharedKinds: [.todo, .shopping, .money], isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build23"
    ), isSignedIn: true)
    let appState = AppState()
    appState.usageStyle = usageStyle
    let viewModel = MoneyViewModel(store: store, appState: appState, now: build23Now)
    return Build23Setup(store: store, expenses: expenses, lineItems: lineItems, service: service, appState: appState, viewModel: viewModel)
}

private func item(_ name: String, quantity: Decimal? = nil, unitPrice: Int? = nil, amount: Int, sortOrder: Int = 0, id: UUID = UUID()) -> ExpenseLineItem {
    ExpenseLineItem(id: id, name: name, quantity: quantity, unitPrice: unitPrice, amount: amount, sortOrder: sortOrder)
}

/// 純粋な検索・購入履歴の部品だけで確かめるための支出
private func expense(_ title: String, amount: Int = 1000, category: ExpenseCategory = .food, date: Date = november5, ownership: Ownership = .personal) -> Expense {
    Expense(title: title, amount: amount, category: category, date: date, ownership: ownership)
}

/// 購入記録の材料（支出の一覧と、支出ごとの明細）
private struct Build23Purchases {
    var expenses: [Expense]
    var lineItems: [Expense.ID: [ExpenseLineItem]]
}

/// 同じ商品の購入記録を作る（支出1件に明細1件。日付・店名・明細）
private func purchases(_ entries: [(Date, String, ExpenseLineItem)]) -> Build23Purchases {
    var result = Build23Purchases(expenses: [], lineItems: [:])
    for (date, store, lineItem) in entries {
        let spending = expense(store, amount: max(lineItem.amount, 1), date: date)
        result.expenses.append(spending)
        result.lineItems[spending.id] = [lineItem]
    }
    return result
}

private func history(_ name: String, _ data: Build23Purchases) -> ProductPurchaseHistory {
    PurchaseHistory.history(forKey: PurchaseHistory.key(for: name), expenses: data.expenses, lineItems: data.lineItems)
}

// MARK: - 1. 検索（1〜7・12〜14）

final class Build23SearchTests: XCTestCase {
    /// 1：店名・支出のタイトルで探す
    func testSearchByStoreName() {
        let setup = makeBuild23()
        let shop = setup.addPersonal("まちの八百屋", amount: 698)
        setup.addPersonal("架空スーパー みどり台店", amount: 1200)
        let results = setup.search("八百屋")
        XCTAssertEqual(results.map(\.id), [shop.id])
        XCTAssertEqual(results.first?.matchesTitle, true)
        XCTAssertEqual(results.first?.matchedItems, [])
    }

    /// 2：商品明細の商品名で探す。一致した商品名と金額も持つ
    func testSearchByItemName() throws {
        let setup = makeBuild23()
        let milk = item("牛乳", amount: 198)
        let shop = setup.addPersonal("架空スーパー", amount: 698, items: [milk, item("食パン", amount: 500, sortOrder: 1)])
        setup.addPersonal("架空ドラッグ", amount: 300, items: [item("ばんそうこう", amount: 300)])
        let result = try XCTUnwrap(setup.search("牛乳").first)
        XCTAssertEqual(setup.viewModel.searchResults.count, 1)
        XCTAssertEqual(result.expense.id, shop.id)
        XCTAssertFalse(result.matchesTitle)
        XCTAssertEqual(result.matchedItems.map(\.name), ["牛乳"])
        XCTAssertEqual(result.matchedItems.map(\.amount), [198])
        XCTAssertTrue(setup.viewModel.searchSpokenLabel(for: result).contains("一致した商品 牛乳 198円"))
    }

    /// 3：部分一致（店名の一部・商品名の一部）
    func testPartialMatch() {
        let setup = makeBuild23()
        setup.addPersonal("まちの八百屋", amount: 698, items: [item("低脂肪牛乳", amount: 198)])
        XCTAssertEqual(setup.search("百屋").count, 1)
        XCTAssertEqual(setup.search("脂肪").count, 1)
        XCTAssertEqual(setup.search("乳").first?.matchedItems.map(\.name), ["低脂肪牛乳"])
        XCTAssertEqual(setup.search("魚").count, 0)
    }

    /// 4：英字の大文字・小文字を区別しない
    func testCaseInsensitive() {
        let setup = makeBuild23()
        setup.addPersonal("FICTION MART", amount: 500, items: [item("Green Tea", amount: 150)])
        XCTAssertEqual(setup.search("fiction mart").count, 1)
        XCTAssertEqual(setup.search("Fiction").count, 1)
        XCTAssertEqual(setup.search("GREEN tea").first?.matchedItems.map(\.name), ["Green Tea"])
    }

    /// 5：全角・半角を同じものとして扱う（英数字・半角カタカナ・全角の空白）
    func testFullwidthAndHalfwidth() {
        XCTAssertEqual(ExpenseSearchText.normalized("ＦＩＣＴＩＯＮ　マート"), "fiction マート")
        XCTAssertEqual(ExpenseSearchText.normalized("ｷﾞｭｳﾆｭｳ"), "ギュウニュウ")
        XCTAssertEqual(ExpenseSearchText.normalized("５００ｍｌ"), "500ml")
        let setup = makeBuild23()
        setup.addPersonal("ＦＩＣＴＩＯＮ マート", amount: 500, items: [item("ｷﾞｭｳﾆｭｳ ５００ｍｌ", amount: 150)])
        XCTAssertEqual(setup.search("fiction").count, 1)
        XCTAssertEqual(setup.search("ギュウニュウ").count, 1)
        XCTAssertEqual(setup.search("500ML").count, 1)
    }

    /// 6：前後の空白を無視し、続く空白を1つとして扱う。日本語は壊さない
    func testSpacesAndJapaneseAreKept() {
        XCTAssertEqual(ExpenseSearchText.normalized("  まちの   八百屋  "), "まちの 八百屋")
        XCTAssertEqual(ExpenseSearchText.normalized("牛乳\t \n パン"), "牛乳 パン")
        XCTAssertEqual(ExpenseSearchText.normalized("みどり台店の牛乳"), "みどり台店の牛乳", "ひらがな・漢字はそのまま")
        XCTAssertNotEqual(ExpenseSearchText.normalized("ぎゅうにゅう"), ExpenseSearchText.normalized("ギュウニュウ"), "ひらがなとカタカナは別（推測でまとめない）")
        let setup = makeBuild23()
        setup.addPersonal("まちの　八百屋", amount: 698)
        XCTAssertEqual(setup.search("  まちの   八百屋 ").count, 1)
        XCTAssertEqual(setup.search("まちの 八百屋").count, 1)
    }

    /// 7：同じ支出の複数の商品が一致しても、支出は1件だけ
    func testSameExpenseShownOnce() throws {
        let setup = makeBuild23()
        setup.addPersonal("牛乳屋さん", amount: 900, items: [item("牛乳", amount: 198), item("低脂肪牛乳", amount: 218, sortOrder: 1), item("パン", amount: 484, sortOrder: 2)])
        let results = setup.search("牛乳")
        XCTAssertEqual(results.count, 1)
        let result = try XCTUnwrap(results.first)
        XCTAssertTrue(result.matchesTitle)
        XCTAssertEqual(result.matchedItems.map(\.name), ["牛乳", "低脂肪牛乳"])
        // 同じ支出が2回渡されても1件だけ（念のため）
        let duplicated = expense("牛乳屋さん")
        let outcome = ExpenseSearch.search("牛乳", expenses: [duplicated, duplicated], lineItems: [:])
        XCTAssertEqual(outcome.results.count, 1)
        XCTAssertEqual(outcome.checkedExpenses, 1)
    }

    /// 12：結果0件（「該当する支出はありません」）
    func testNoResults() throws {
        let setup = makeBuild23()
        setup.addPersonal("まちの八百屋", amount: 698)
        XCTAssertEqual(setup.search("架空の言葉"), [])
        XCTAssertTrue(setup.viewModel.isSearching)
        let money = build23CodeOnly(try build23Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains("title: \"該当する支出はありません\""))
        XCTAssertTrue(money.contains("LifeSectionTitle(\"検索結果\", trailing: \"\\(results.count)件\")"), "検索中は件数を出す")
    }

    /// 13：検索をやめる（空・空白だけなら通常の一覧。消すボタンで絞り込みも戻す）
    func testClearingSearch() throws {
        let setup = makeBuild23()
        setup.addPersonal("まちの八百屋", amount: 698)
        setup.viewModel.searchMonth = LifeCalendar.startOfMonth(november5)
        setup.viewModel.searchCategory = .food
        XCTAssertEqual(setup.search("八百屋").count, 1)
        setup.viewModel.clearSearch()
        XCTAssertFalse(setup.viewModel.isSearching)
        XCTAssertEqual(setup.viewModel.searchText, "")
        XCTAssertNil(setup.viewModel.searchMonth)
        XCTAssertNil(setup.viewModel.searchCategory)
        XCTAssertEqual(setup.viewModel.searchResults, [])
        XCTAssertEqual(setup.viewModel.expenses.count, 1, "通常の一覧に戻る")
        XCTAssertEqual(setup.search("   "), [], "空白だけは検索しない")
        XCTAssertFalse(setup.viewModel.isSearching)
        let money = build23CodeOnly(try build23Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains(".accessibilityLabel(\"検索語を消す\")"))
        XCTAssertTrue(money.contains("viewModel.clearSearch()"))
        XCTAssertTrue(money.contains("if viewModel.isSearching {"))
    }

    /// 14：検索結果から、今までの支出の詳細を開く
    func testOpeningDetailFromSearchResult() throws {
        let setup = makeBuild23()
        let shop = setup.addPersonal("まちの八百屋", amount: 698, items: [item("牛乳", amount: 198)])
        let result = try XCTUnwrap(setup.search("牛乳").first)
        setup.viewModel.showDetail(result.expense)
        XCTAssertEqual(setup.viewModel.detailTarget?.id, shop.id)
        XCTAssertEqual(setup.viewModel.lineItems(for: result.expense).map(\.name), ["牛乳"])
        let money = build23CodeOnly(try build23Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains("viewModel.showDetail(result.expense)"))
        XCTAssertTrue(money.contains("ExpenseDetailSheet(viewModel: viewModel, expenseID: target.id)"))
    }
}

// MARK: - 2. 絞り込み（8〜11）

final class Build23FilterTests: XCTestCase {
    /// 8：すべて／自分／共有（画面上部の切り替えと同じ）。一人モードは「すべて」
    func testScopeFilter() {
        let setup = makeBuild23()
        let mine = setup.addPersonal("架空スーパー 自分", amount: 500)
        let ours = setup.addShared("架空スーパー わが家", amount: 800)
        setup.appState.scope = .all
        XCTAssertEqual(Set(setup.search("架空スーパー").map(\.id)), [mine.id, ours.id])
        setup.appState.scope = .mine
        XCTAssertEqual(setup.search("架空スーパー").map(\.id), [mine.id])
        setup.appState.scope = .shared
        XCTAssertEqual(setup.search("架空スーパー").map(\.id), [ours.id])
        XCTAssertEqual(setup.viewModel.searchDetailText(for: ours), "食費・11/5（木）・わが家で共有", "色だけでなく文字で")
        XCTAssertEqual(setup.viewModel.searchDetailText(for: mine), "食費・11/5（木）・自分だけ")
        // 一人モードでは切り替えを出さず、すべて
        setup.appState.usageStyle = .solo
        XCTAssertEqual(setup.viewModel.searchFilter.scope, .all)
    }

    /// 9：月で絞り込む（支出のある月だけを、新しい順に出す）
    func testMonthFilter() {
        let setup = makeBuild23()
        let november = setup.addPersonal("架空スーパー", amount: 500, date: november5)
        let october = setup.addPersonal("架空スーパー", amount: 600, date: october20)
        XCTAssertEqual(setup.viewModel.searchMonths, [LifeCalendar.startOfMonth(november5), LifeCalendar.startOfMonth(october20)])
        setup.viewModel.searchMonth = LifeCalendar.startOfMonth(october20)
        XCTAssertEqual(setup.search("架空").map(\.id), [october.id])
        XCTAssertEqual(setup.viewModel.searchMonthTitle, "2026年10月")
        setup.viewModel.searchMonth = nil
        XCTAssertEqual(setup.search("架空").map(\.id), [november.id, october.id], "新しい順")
    }

    /// 10：カテゴリーで絞り込む
    func testCategoryFilter() {
        let setup = makeBuild23()
        let food = setup.addPersonal("架空マート", amount: 500, category: .food)
        let goods = setup.addPersonal("架空マート", amount: 300, category: .dailyGoods)
        setup.viewModel.searchCategory = .dailyGoods
        XCTAssertEqual(setup.search("架空マート").map(\.id), [goods.id])
        XCTAssertEqual(setup.viewModel.searchCategoryTitle, "日用品")
        setup.viewModel.searchCategory = .food
        XCTAssertEqual(setup.search("架空マート").map(\.id), [food.id])
    }

    /// 11：条件の組み合わせ（共有・10月・日用品）
    func testCombinedFilters() {
        let setup = makeBuild23()
        setup.addPersonal("架空マート", amount: 100, category: .dailyGoods, date: october20)
        setup.addShared("架空マート", amount: 200, category: .food, date: october20)
        setup.addShared("架空マート", amount: 300, category: .dailyGoods, date: november5)
        let target = setup.addShared("架空マート", amount: 400, category: .dailyGoods, date: october20)
        setup.appState.scope = .shared
        setup.viewModel.searchMonth = LifeCalendar.startOfMonth(october20)
        setup.viewModel.searchCategory = .dailyGoods
        XCTAssertEqual(setup.search("マート").map(\.id), [target.id])
        XCTAssertEqual(setup.viewModel.searchFilter, ExpenseSearchFilter(scope: .shared, month: LifeCalendar.startOfMonth(october20), category: .dailyGoods))
    }
}

// MARK: - 3. 購入履歴・過去の参考価格（15〜26）

final class Build23PurchaseHistoryTests: XCTestCase {
    /// 15：商品明細から購入履歴を開く
    func testOpeningHistoryFromLineItem() throws {
        let setup = makeBuild23()
        let milk = item("牛乳", unitPrice: 198, amount: 198)
        setup.addPersonal("まちの八百屋", amount: 198, date: november5, items: [milk])
        setup.addPersonal("架空スーパー", amount: 208, date: october20, items: [item(" 牛乳 ", unitPrice: 208, amount: 208)])
        let target = setup.viewModel.historyTarget(for: milk)
        XCTAssertEqual(target.key, "牛乳")
        let history = setup.viewModel.purchaseHistory(for: target)
        XCTAssertEqual(history.name, "牛乳")
        XCTAssertEqual(history.purchaseCount, 2)
        let detail = build23CodeOnly(try build23Source("LifeOS/Features/Money/ExpenseDetailView.swift"))
        XCTAssertTrue(detail.contains("historyTarget = viewModel.historyTarget(for: item)"), "明細をタップすると購入履歴")
        XCTAssertTrue(detail.contains(".navigationDestination(item: $historyTarget)"))
        XCTAssertTrue(detail.contains("ProductPurchaseHistoryView(viewModel: viewModel, target: target)"))
        XCTAssertTrue(detail.contains("startEditing(item)"), "直すのは鉛筆のボタンから")
        XCTAssertTrue(detail.contains(".accessibilityLabel(\"\\(item.name)の明細を直す\")"))
    }

    /// 16：新しい順に並ぶ（同じ日なら決まった順）
    func testRecordsAreNewestFirst() {
        let data = purchases([
            (october20, "架空スーパー", item("牛乳", unitPrice: 200, amount: 200)),
            (november5, "まちの八百屋", item("牛乳", unitPrice: 190, amount: 190)),
            (september15, "架空マート", item("牛乳", unitPrice: 210, amount: 210))
        ])
        let records = history("牛乳", data).records
        XCTAssertEqual(records.map(\.date), [november5, october20, september15])
        XCTAssertEqual(records.map(\.storeName), ["まちの八百屋", "架空スーパー", "架空マート"])
        let again = history("牛乳", Build23Purchases(expenses: Array(data.expenses.reversed()), lineItems: data.lineItems)).records
        XCTAssertEqual(again.map(\.id), records.map(\.id), "渡す順に関係なく同じ順")
    }

    /// 17：購入回数・最新の購入日
    func testPurchaseCount() {
        let data = purchases([
            (october20, "架空スーパー", item("牛乳", amount: 200)),
            (november5, "まちの八百屋", item("牛乳", amount: 190)),
            (november1, "架空マート", item("パン", amount: 150))
        ])
        let milk = history("牛乳", data)
        XCTAssertEqual(milk.purchaseCount, 2)
        XCTAssertEqual(milk.latestDate, november5)
        XCTAssertEqual(history("パン", data).purchaseCount, 1)
    }

    /// 18・19・20：最新の参考価格・これまでの最安と最高・前回との差（店名と購入日つき）
    func testLatestLowestHighestAndDifference() throws {
        let data = purchases([
            (september15, "架空マート", item("牛乳", unitPrice: 230, amount: 230)),
            (october20, "架空スーパー", item("牛乳", unitPrice: 180, amount: 180)),
            (november1, "まちの八百屋", item("牛乳", unitPrice: 230, amount: 230)),
            (november5, "架空ドラッグ", item("牛乳", unitPrice: 200, amount: 200))
        ])
        let summary = try XCTUnwrap(history("牛乳", data).summary)
        XCTAssertEqual(summary.latest.price, PurchasePrice(yen: 200, basis: .unitPrice))
        XCTAssertEqual(summary.latest.storeName, "架空ドラッグ")
        XCTAssertEqual(summary.lowest?.price?.yen, 180)
        XCTAssertEqual(summary.lowest?.storeName, "架空スーパー")
        XCTAssertEqual(summary.lowest?.date, october20)
        XCTAssertEqual(summary.highest?.price?.yen, 230)
        XCTAssertEqual(summary.highest?.date, november1, "同じ価格なら新しい方")
        XCTAssertEqual(summary.previous?.storeName, "まちの八百屋")
        XCTAssertEqual(summary.differenceFromPrevious, -30)
        XCTAssertEqual(summary.comparedCount, 4)
        XCTAssertEqual(summary.excludedCount, 0)
        XCTAssertEqual(ProductPurchaseHistoryView.differenceText(-30), "前回より ¥30 安い")
        XCTAssertEqual(ProductPurchaseHistoryView.differenceText(20), "前回より ¥20 高い")
        XCTAssertEqual(ProductPurchaseHistoryView.differenceText(0), "前回と同じ")
        // 1件だけなら、最新だけ（最安・最高・前回との差は出さない）
        let single = try XCTUnwrap(history("牛乳", purchases([(november5, "架空ドラッグ", item("牛乳", unitPrice: 200, amount: 200))])).summary)
        XCTAssertNil(single.lowest)
        XCTAssertNil(single.highest)
        XCTAssertNil(single.differenceFromPrevious)
    }

    /// 21：単価が保存されていれば、単価を使う（金額÷数量より優先）
    func testStoredUnitPriceIsPreferred() {
        let price = PurchaseHistory.price(for: item("牛乳", quantity: 2, unitPrice: 100, amount: 150))
        XCTAssertEqual(price, PurchasePrice(yen: 100, basis: .unitPrice))
        XCTAssertEqual(ProductPurchaseHistoryView.basisLabel(.unitPrice), "単価")
    }

    /// 22：単価が無く、数量が正しいときだけ、金額÷数量の参考単価（1円未満は四捨五入）
    func testReferenceUnitPriceFromQuantity() throws {
        XCTAssertEqual(PurchaseHistory.price(for: item("りんご", quantity: 3, amount: 400)), PurchasePrice(yen: 133, basis: .referenceUnitPrice))
        XCTAssertEqual(PurchaseHistory.price(for: item("お米", quantity: Decimal(string: "1.5"), amount: 300)), PurchasePrice(yen: 200, basis: .referenceUnitPrice))
        XCTAssertEqual(PurchaseHistory.price(for: item("りんご", quantity: 3, amount: 401)), PurchasePrice(yen: 134, basis: .referenceUnitPrice))
        let summary = try XCTUnwrap(history("りんご", purchases([(november5, "架空マート", item("りんご", quantity: 3, amount: 400))])).summary)
        XCTAssertTrue(summary.usesReferencePrice)
        XCTAssertEqual(ProductPurchaseHistoryView.basisLabel(.referenceUnitPrice), "参考単価")
    }

    /// 23：数量が分からなければ、商品の金額だけ。「単価は比較できません」（比べない）
    func testUnknownQuantityIsNotCompared() throws {
        let unknown = purchases([
            (november5, "まちの八百屋", item("牛乳", amount: 198)),
            (october20, "架空スーパー", item("牛乳", amount: 398))
        ])
        let milk = history("牛乳", unknown)
        XCTAssertNil(milk.summary, "数量が分からない購入記録だけなら、比べない")
        XCTAssertEqual(milk.records.map(\.amount), [198, 398], "商品の金額は出す")
        XCTAssertTrue(milk.records.allSatisfy { $0.price == nil })
        XCTAssertEqual(ProductPurchaseHistoryView.quantityAndPriceText(milk.records[0]), "数量・単価は分かりません")
        XCTAssertTrue(PurchaseHistory.unitPriceUnavailableMessage.hasPrefix("単価は比較できません"))
        // 比べられる記録と混ざっていれば、比べられる記録だけで要約し、比べなかった数を出す
        let mixed = purchases([
            (november5, "まちの八百屋", item("牛乳", unitPrice: 190, amount: 190)),
            (november1, "架空マート", item("牛乳", amount: 380)),
            (october20, "架空スーパー", item("牛乳", unitPrice: 200, amount: 200))
        ])
        let summary = try XCTUnwrap(history("牛乳", mixed).summary)
        XCTAssertEqual(summary.comparedCount, 2)
        XCTAssertEqual(summary.excludedCount, 1)
        XCTAssertEqual(summary.differenceFromPrevious, -10)
        XCTAssertEqual(summary.previous?.storeName, "架空スーパー", "比べられない記録は飛ばす")
    }

    /// 24：0 で割らない（数量 0・負の数量でも落ちない）
    func testNoDivisionByZero() {
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: 0, amount: 198)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: -2, amount: 198)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: Decimal(string: "0.0001"), amount: 198)), "小数3桁より細かい数量は正しくない")
        XCTAssertNil(history("牛乳", purchases([(november5, "架空マート", item("牛乳", quantity: 0, amount: 198))])).summary)
    }

    /// 25：異常値・正しくない金額は比べない（0円・負の金額・上限を超える金額・範囲外の数量）
    func testInvalidValuesAreExcluded() throws {
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: 2, amount: 0)), "0円は比べない")
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", unitPrice: 0, amount: 0)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: 1, amount: -100)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", unitPrice: -5, amount: 100)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", unitPrice: 1_000_000_000, amount: 100)))
        XCTAssertNil(PurchaseHistory.price(for: item("牛乳", quantity: 10_000, amount: 100)), "数量は 10000 未満")
        XCTAssertEqual(PurchaseHistory.price(for: item("牛乳", quantity: 2, unitPrice: 0, amount: 400)), PurchasePrice(yen: 200, basis: .referenceUnitPrice),
                       "正しくない単価は使わず、正しい数量と金額があれば参考単価")
        let data = purchases([
            (november5, "架空マート", item("牛乳", unitPrice: 0, amount: 0)),
            (november1, "まちの八百屋", item("牛乳", unitPrice: 190, amount: 190)),
            (october20, "架空スーパー", item("牛乳", unitPrice: 1_000_000_000, amount: 200))
        ])
        let summary = try XCTUnwrap(history("牛乳", data).summary)
        XCTAssertEqual(summary.comparedCount, 1)
        XCTAssertEqual(summary.excludedCount, 2)
        XCTAssertEqual(summary.latest.price?.yen, 190)
        XCTAssertNil(summary.lowest)
    }

    /// 26：似ている別の商品をまとめない（整えた名前が同じものだけ）
    func testSimilarProductsAreNotMerged() {
        let data = purchases([
            (november5, "架空マート", item("牛乳", amount: 198)),
            (november5, "架空マート", item("低脂肪牛乳", amount: 218)),
            (november1, "架空マート", item("牛乳 1000ml", amount: 238)),
            (october20, "架空マート", item("  牛乳  ", amount: 208)),
            (october20, "架空マート", item("ＭＩＬＫ", amount: 150)),
            (september15, "架空マート", item("milk", amount: 160))
        ])
        XCTAssertEqual(history("牛乳", data).records.map(\.amount), [198, 208], "前後の空白だけの違いはまとめる")
        XCTAssertEqual(history("低脂肪牛乳", data).purchaseCount, 1)
        XCTAssertEqual(history("牛乳 1000ml", data).purchaseCount, 1)
        XCTAssertEqual(history("milk", data).records.map(\.amount), [150, 160], "全角・英字の大小だけの違いはまとめる")
        XCTAssertNotEqual(PurchaseHistory.key(for: "牛乳"), PurchaseHistory.key(for: "低脂肪牛乳"))
        XCTAssertEqual(history("", data).records, [], "空の名前ではまとめない")
    }

    /// 自分だけ／共有は、購入記録ごとに文字で出す
    func testOwnershipIsShownAsText() {
        let setup = makeBuild23()
        setup.addPersonal("架空マート", amount: 198, date: november5, items: [item("牛乳", unitPrice: 198, amount: 198)])
        setup.addShared("架空スーパー", amount: 208, date: october20, items: [item("牛乳", unitPrice: 208, amount: 208)])
        let records = setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).records
        XCTAssertEqual(records.map { ProductPurchaseHistoryView.ownershipLabel($0.ownership) }, ["自分だけ", "わが家で共有"])
        XCTAssertEqual(setup.viewModel.historyScopeText, "自分だけ・わが家で共有の両方")
        setup.appState.scope = .mine
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).records.map(\.storeName), ["架空マート"], "範囲を混ぜない")
        XCTAssertEqual(setup.viewModel.historyScopeText, "自分だけ")
        XCTAssertTrue(ProductPurchaseHistoryView.spokenLabel(records[0]).contains("自分だけ"))
    }

    /// 文言：「過去の購入記録」「参考価格」。購入をすすめない・お得と決めない
    func testWordingIsNotARecommendation() throws {
        let view = build23CodeOnly(try build23Source("LifeOS/Features/Money/ProductPurchaseHistoryView.swift"))
        XCTAssertTrue(view.contains("Text(\"過去の購入記録（参考価格）\")"))
        XCTAssertTrue(PurchaseHistory.referenceNote.contains("どちらがお得かは判断できません"))
        let engine = build23CodeOnly(try build23Source("LifeOS/Core/Utilities/ExpenseSearch.swift"))
        for word in ["おすすめ", "お買い得", "買うべき", "予測"] {
            XCTAssertFalse(view.contains(word), word)
            XCTAssertFalse(engine.contains(word), word)
        }
        XCTAssertFalse(view.contains("Chart"), "グラフは作らない")
    }
}

// MARK: - 4. 更新・個人と共有・古いデータ（27〜31）

final class Build23UpdateTests: XCTestCase {
    /// 27：商品名を直すと、そのあとの履歴のまとまりも変わる
    func testRenamingUpdatesHistory() throws {
        let setup = makeBuild23()
        let milk = item("牛乳", unitPrice: 198, amount: 198)
        let spending = setup.addPersonal("架空マート", amount: 198, items: [milk])
        setup.addPersonal("架空スーパー", amount: 208, date: october20, items: [item("牛乳", unitPrice: 208, amount: 208)])
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 2)
        let saved = try XCTUnwrap(setup.viewModel.lineItems(for: spending).first)
        XCTAssertNil(setup.viewModel.updateLineItem(saved, in: spending, name: "低脂肪牛乳", quantityText: "", unitPriceText: "198", amountText: "198"))
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 1)
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "低脂肪牛乳")).purchaseCount, 1)
        XCTAssertEqual(setup.search("低脂肪").map(\.id), [spending.id], "検索結果も新しい名前")
    }

    /// 28：明細を消すと、履歴・検索から消える
    func testDeletingLineItemUpdatesHistory() throws {
        let setup = makeBuild23()
        let spending = setup.addPersonal("架空マート", amount: 698, items: [item("牛乳", amount: 198), item("パン", amount: 500, sortOrder: 1)])
        let milk = try XCTUnwrap(setup.viewModel.lineItems(for: spending).first)
        XCTAssertEqual(setup.search("牛乳").count, 1)
        XCTAssertNil(setup.viewModel.deleteLineItem(milk, in: spending))
        XCTAssertEqual(setup.search("牛乳"), [])
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 0)
        XCTAssertEqual(setup.search("パン").count, 1, "ほかの明細は残る")
    }

    /// 29：支出を消すと、検索結果から消える
    func testDeletingExpenseRemovesSearchResult() {
        let setup = makeBuild23()
        let spending = setup.addPersonal("まちの八百屋", amount: 698, items: [item("牛乳", amount: 198)])
        XCTAssertEqual(setup.search("八百屋").count, 1)
        setup.viewModel.requestDelete(spending)
        XCTAssertTrue(setup.viewModel.confirmDelete())
        XCTAssertEqual(setup.viewModel.searchResults, [])
        XCTAssertEqual(setup.search("牛乳"), [])
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).records, [])
    }

    /// 30：自分だけ⇔共有を変えても、検索結果・購入履歴に重ねて出さない
    func testDestinationChangeDoesNotDuplicate() {
        let setup = makeBuild23()
        let spending = setup.addPersonal("まちの八百屋", amount: 198, items: [item("牛乳", unitPrice: 198, amount: 198)])
        // 共有への保存が確かめられる前（端末と共有の両方にある途中）も1件だけ
        setup.expenses.holdsCompletion = true
        XCTAssertTrue(setup.store.changeExpenseDestination(spending.id, to: .household))
        XCTAssertEqual(setup.search("牛乳").map(\.id), [spending.id])
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 1)
        setup.expenses.heldCompletions.forEach { $0(nil) }
        setup.expenses.holdsCompletion = false
        XCTAssertTrue(setup.store.expenses.isEmpty, "共有になった")
        XCTAssertEqual(setup.search("牛乳").map(\.id), [spending.id])
        XCTAssertEqual(setup.search("牛乳").first?.expense.isShared, true)
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 1)
        XCTAssertTrue(setup.store.changeExpenseDestination(spending.id, to: .personal))
        XCTAssertEqual(setup.search("牛乳").map(\.id), [spending.id])
        XCTAssertEqual(setup.search("八百屋").count, 1)
        XCTAssertEqual(setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳")).purchaseCount, 1)
        let all = setup.store.visibleExpenses(scope: .all)
        XCTAssertEqual(setup.store.lineItemsByExpense(all.map(\.id) + all.map(\.id))[spending.id]?.count, 1, "同じ ID を2回渡しても1回だけ")
    }

    /// 31：明細の無い古い支出も、店名で探せる（商品名では出ない）
    func testOldExpensesWithoutLineItems() {
        let setup = makeBuild23()
        let old = setup.addPersonal("以前のスーパー", amount: 1500, date: september15)
        XCTAssertEqual(setup.search("以前の").map(\.id), [old.id])
        XCTAssertEqual(setup.search("以前の").first?.matchedItems, [])
        XCTAssertEqual(setup.store.lineItemsByExpense([old.id]), [:])
        let empty = setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳"))
        XCTAssertEqual(empty.records, [])
        XCTAssertNil(empty.summary)
        XCTAssertNil(empty.latestDate)
    }
}

// MARK: - 5. 性能・送らない・ログ（32〜35）

final class Build23PerformanceAndPrivacyTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Build23-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDownWithError() throws {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 32：支出1,000件・明細5,000件。同じ支出・明細を2回調べない・結果は重ならない（時間だけに頼らない）
    func testThousandExpensesAndFiveThousandItems() {
        var expenses: [Expense] = []
        var lineItems: [Expense.ID: [ExpenseLineItem]] = [:]
        for index in 0..<1000 {
            let spending = expense("架空ストア \(index % 10)", amount: 1000, date: TestDates.make(2026, 1 + index % 11, 1 + index % 28, 10, 0))
            expenses.append(spending)
            lineItems[spending.id] = (0..<5).map { number in
                item("商品\(index % 50)-\(number)", unitPrice: 100 + number, amount: 100 + number, sortOrder: number)
            }
        }
        let outcome = ExpenseSearch.search("商品7-", expenses: expenses, lineItems: lineItems)
        XCTAssertEqual(outcome.checkedExpenses, 1000)
        XCTAssertEqual(outcome.checkedItems, 5000, "明細は1回ずつだけ調べる")
        XCTAssertEqual(outcome.results.count, 20)
        XCTAssertEqual(Set(outcome.results.map(\.id)).count, outcome.results.count, "同じ支出を重ねない")
        XCTAssertTrue(outcome.results.allSatisfy { $0.matchedItems.count == 5 })
        XCTAssertEqual(ExpenseSearch.search("架空ストア 3", expenses: expenses, lineItems: lineItems).results.count, 100)
        // 同じ検索をくり返しても、結果は同じで増えない
        XCTAssertEqual(ExpenseSearch.search("商品7-", expenses: expenses, lineItems: lineItems), outcome)
        let milk = PurchaseHistory.history(forKey: PurchaseHistory.key(for: "商品7-0"), expenses: expenses, lineItems: lineItems)
        XCTAssertEqual(milk.purchaseCount, 20)
        XCTAssertEqual(milk.summary?.comparedCount, 20)

        // 端末の保存先（LifeStore）を通しても同じ：明細はまとめて1回で読む
        let setup = makeBuild23()
        for spending in expenses {
            setup.store.addExpense(spending, destination: .personal, lineItems: lineItems[spending.id] ?? [])
        }
        XCTAssertEqual(setup.store.lineItemsByExpense(expenses.map(\.id)).values.reduce(0) { $0 + $1.count }, 5000)
        setup.viewModel.searchText = "商品7-"
        let viaStore = setup.viewModel.searchOutcome
        XCTAssertEqual(viaStore.checkedExpenses, 1000)
        XCTAssertEqual(viaStore.checkedItems, 5000)
        XCTAssertEqual(viaStore.results.count, 20)
        XCTAssertEqual(setup.store.expenses.count, 1000, "検索で支出を複製しない")
    }

    /// 33・34：検索・購入履歴は Firestore へ送らない。見張り（リスナー）を増やさない。画面を開閉しても増えない
    func testNoSendingAndNoNewListeners() {
        let setup = makeBuild23()
        let spending = setup.addShared("架空スーパー", amount: 198, items: [item("牛乳", unitPrice: 198, amount: 198)])
        let writesBefore = setup.expenses.writeCount
        let lineItemWritesBefore = setup.lineItems.writeCount
        XCTAssertEqual(setup.expenses.activeListenerCount, 1)
        XCTAssertEqual(setup.lineItems.activeListenerCount, 1)
        for text in ["牛", "牛乳", "架空", "架空ス", "存在しない", ""] {
            setup.viewModel.searchText = text
            _ = setup.viewModel.searchResults
            _ = setup.viewModel.searchMonths
        }
        for _ in 0..<20 {
            setup.viewModel.showDetail(spending)
            _ = setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳"))
            setup.viewModel.closeDetail()
            setup.viewModel.detailDidClose()
        }
        setup.viewModel.searchMonth = LifeCalendar.startOfMonth(november5)
        setup.viewModel.searchCategory = .food
        _ = setup.search("牛乳")
        setup.viewModel.clearSearch()
        XCTAssertEqual(setup.expenses.writeCount, writesBefore, "検索・購入履歴では書き込まない")
        XCTAssertEqual(setup.lineItems.writeCount, lineItemWritesBefore)
        XCTAssertEqual(setup.expenses.listenCount, 1, "文字を入れるたびに見張りを増やさない")
        XCTAssertEqual(setup.lineItems.listenCount, 1)
        XCTAssertEqual(setup.expenses.activeListenerCount, 1)
        XCTAssertEqual(setup.lineItems.activeListenerCount, 1)
    }

    /// 33・35：検索語・絞り込み・見た商品・比べた結果を保存しない。送る・ログに出す仕組みを使わない
    func testSearchIsNotSavedSentOrLogged() throws {
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let setup = makeBuild23(store: store)
        setup.addPersonal("まちの八百屋", amount: 198, items: [item("牛乳", unitPrice: 198, amount: 198)])
        _ = setup.search("検索だけの言葉")
        _ = setup.search("牛乳")
        setup.viewModel.searchMonth = LifeCalendar.startOfMonth(november5)
        _ = setup.viewModel.purchaseHistory(for: ProductHistoryTarget(key: "牛乳"))
        // 支出を足して保存させてから、ファイルを確かめる
        setup.addPersonal("架空マート", amount: 300)
        let file = try String(contentsOf: temporaryDirectory.appendingPathComponent(LifeStore.fileName), encoding: .utf8)
        for notSaved in ["検索だけの言葉", "searchText", "searchMonth", "searchCategory", "historyTarget", "参考単価", "comparedCount"] {
            XCTAssertFalse(file.contains(notSaved), notSaved)
        }
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined(separator: "\n")
        XCTAssertFalse(defaults.contains("検索だけの言葉"))
        XCTAssertEqual(Set(Mirror(reflecting: try XCTUnwrap(store.expenses.first)).children.compactMap(\.label)), ["id", "title", "amount", "category", "date", "ownership"], "支出の項目は増やさない")

        for path in [
            "LifeOS/Core/Utilities/ExpenseSearch.swift",
            "LifeOS/Features/Money/ProductPurchaseHistoryView.swift",
            "LifeOS/Features/Money/MoneyView.swift",
            "LifeOS/Features/Money/MoneyViewModel.swift",
            "LifeOS/Features/Money/ExpenseDetailView.swift"
        ] {
            let code = build23CodeOnly(try build23Source(path))
            for word in ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "Analytics", "Crashlytics",
                         "URLSession", "URLRequest", "Firestore", "import Firebase", "UserDefaults", ".write(to"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
    }
}

// MARK: - 6. 今までの機能・Build 番号（36〜40）

final class Build23CompatibilityTests: XCTestCase {
    /// 36：検索欄のキーボードも、Build 22 と同じ方法で閉じる（スクロール・背景のタップ・「完了」・画面を離れたとき）
    @MainActor
    func testKeyboardDismissalLikeBuild22() throws {
        let money = build23CodeOnly(try build23Source("LifeOS/Features/Money/MoneyView.swift"))
        XCTAssertTrue(money.contains(".focused($isSearchFocused)"))
        XCTAssertTrue(money.contains(".lifeKeyboardDoneButton { isSearchFocused = false }"))
        XCTAssertGreaterThanOrEqual(money.components(separatedBy: ".lifeKeyboardDismissal()").count - 1, 2, "お金の画面と、支出の追加・編集の両方")
        XCTAssertTrue(money.contains(".lifeKeyboardDoneButton { focusedField = nil }"), "Build 22 の追加・編集はそのまま")
        let handler = KeyboardDismissTapHandler()
        XCTAssertFalse(handler.recognizer.cancelsTouchesInView, "タップを奪わない（候補・保存・キャンセル・検索結果へ届く）")
        XCTAssertTrue(LifeKeyboard.shouldDismiss(forTouchIn: UIView()))
        XCTAssertFalse(LifeKeyboard.shouldDismiss(forTouchIn: UITextField()))
        // 検索欄・消すボタン・結果の行は 44pt 以上・VoiceOver の説明
        XCTAssertTrue(money.contains(".accessibilityLabel(\"支出を探す\")"))
        XCTAssertTrue(money.contains(".frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)"))
        XCTAssertTrue(money.contains(".accessibilityLabel(viewModel.searchSpokenLabel(for: result))"))
        XCTAssertGreaterThanOrEqual(LifeSpacing.minTapTarget, 44)
    }

    /// 37：Build 21 の商品明細の保存・直す・消すは今までどおり
    func testBuild21LineItemsStillWork() throws {
        let setup = makeBuild23()
        let spending = setup.addPersonal("まちの八百屋", amount: 698, items: [item("牛乳", amount: 198), item("ティッシュ", quantity: 2, unitPrice: 250, amount: 500, sortOrder: 1)])
        XCTAssertEqual(setup.viewModel.lineItems(for: spending).map(\.name), ["牛乳", "ティッシュ"])
        XCTAssertEqual(setup.viewModel.lineItemComparison(for: spending), .matched(total: 698))
        let milk = try XCTUnwrap(setup.viewModel.lineItems(for: spending).first)
        XCTAssertEqual(setup.viewModel.updateLineItem(milk, in: spending, name: "", quantityText: "", unitPriceText: "", amountText: "198"), ExpenseLineItemIssue.emptyName.message)
        XCTAssertNil(setup.viewModel.updateLineItem(milk, in: spending, name: "低脂肪牛乳", quantityText: "1", unitPriceText: "200", amountText: "200"))
        XCTAssertEqual(setup.viewModel.lineItems(for: spending).first?.name, "低脂肪牛乳")
        let shared = setup.addShared("架空スーパー", amount: 300, items: [item("パン", amount: 300)])
        XCTAssertEqual(setup.viewModel.lineItems(for: shared).map(\.name), ["パン"])
        XCTAssertEqual(setup.store.lineItemsByExpense([spending.id, shared.id]).mapValues { $0.map(\.name) }, [spending.id: ["低脂肪牛乳", "ティッシュ"], shared.id: ["パン"]],
                       "まとめて読んでも、1件ずつと同じ")
        let detail = build23CodeOnly(try build23Source("LifeOS/Features/Money/ExpenseDetailView.swift"))
        for snippet in [".accessibilityLabel(item.spokenLabel)", ".accessibilityLabel(\"\\(item.name)の明細を削除\")", "viewModel.editFromDetail()", "Text(\"商品明細はありません\")"] {
            XCTAssertTrue(detail.contains(snippet), snippet)
        }
    }

    /// 38：保証書の文字の読み取りは今までどおり
    func testWarrantyOCRStillWorks() {
        let proposal = WarrantyFieldExtractor.extract(from: [
            WarrantyRecognizedLine(text: "型番 AB-123"),
            WarrantyRecognizedLine(text: "お買上げ日 2026/10/13", confidence: 0.9)
        ])
        XCTAssertEqual(proposal.fields.first { $0.kind == .modelNumber }?.value, "AB-123")
        XCTAssertEqual(proposal.fields.first { $0.kind == .purchaseDate }?.date, TestDates.make(2026, 10, 13))
    }

    /// 39・40：Build 番号は4か所とも 23。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番。Rules・Functions は変えていない
    func testBuildNumberIs23() throws {
        let project = try build23Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        // Build 24（2026-11-10）で 24 に上げたため、「4か所がそろっていて 23 以上」を確かめる（Build 15・17〜22 と同じ扱い）
        let versions = lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(Set(versions).count, 1, "アプリ／テスト、Debug／Release の4か所が同じ")
        let number = Int(versions.first?.replacingOccurrences(of: "CURRENT_PROJECT_VERSION = ", with: "").replacingOccurrences(of: ";", with: "") ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(number, 23)
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build23Source("docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md").contains("Build 16 は欠番"))
    }
}
