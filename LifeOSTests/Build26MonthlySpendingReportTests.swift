import XCTest
@testable import LifeOS

// Build 26（2026-11-13）：月次レポート・支出推移。docs/BUILD_26_MONTHLY_SPENDING_REPORT.md
// 本物の Firestore・ネットワークは使わない（共有の支出は偽物の窓口から受け取る）。
// 集計は端末に読み込んである支出だけで行い、保存・送信しないことも確かめる。

private let build26Now = TestDates.make(2026, 11, 13, 12, 0)
private let nov2026 = BudgetMonth(year: 2026, month: 11)!
private let oct2026 = BudgetMonth(year: 2026, month: 10)!
private let sep2026 = BudgetMonth(year: 2026, month: 9)!

private func build26Source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        throw XCTSkip("ソースを読めない環境のため、確認を省きます")
    }
    return text
}

/// コメント（// と ///）の行を除いたソース
private func build26CodeOnly(_ source: String) -> String {
    source.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

private func spend(_ amount: Int, _ category: ExpenseCategory = .food, on date: Date, shared: Bool = false,
                   title: String = "テストの支出", id: UUID = UUID()) -> Expense {
    Expense(id: id, title: title, amount: amount, category: category, date: date, ownership: shared ? .shared : .personal)
}

private func report(_ expenses: [Expense], scope: ScopeFilter = .all, month: BudgetMonth = nov2026, today: Date = build26Now) -> MonthlySpendingReport {
    MonthlySpendingCalculator.report(expenses: expenses, scope: scope, month: month, today: today)
}

private func household(_ kinds: [SharedSpaceKind] = [.todo, .shopping, .money]) -> HouseholdSummary {
    HouseholdSummary(
        name: "わが家", sharedKinds: kinds, isOwner: true,
        members: [HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false)],
        groupID: "group-build26"
    )
}

/// 自分だけの支出（端末）と、わが家の共有の支出（偽物の窓口から受け取る）を持つ1台
private struct Build26Device {
    let store: LifeStore
    let backend: FakeSharedExpensesBackend
    let service: SharedExpensesService
    let appState: AppState
    let money: MoneyViewModel
}

private func makeDevice(personal: [Expense] = [], shared: [Expense] = [], usageStyle: UsageStyle = .shared,
                        store: LifeStore? = nil, now: Date = build26Now) -> Build26Device {
    let store = store ?? LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    for expense in personal {
        store.addExpense(expense, destination: .personal)
    }
    let backend = FakeSharedExpensesBackend()
    let service = SharedExpensesService(backend: backend)
    service.attach(store)
    service.apply(household: household(), isSignedIn: true)
    backend.emit(shared)
    let appState = AppState()
    appState.usageStyle = usageStyle
    let money = MoneyViewModel(store: store, appState: appState, now: now)
    return Build26Device(store: store, backend: backend, service: service, appState: appState, money: money)
}

// MARK: - 1. 暦月・年またぎ・うるう年・比べる期間（1〜6）

final class Build26MonthBoundaryTests: XCTestCase {
    /// 1：支出の日付の暦月で数える（10月31日 23:59 は10月、11月1日 0:00 は11月）
    func testCalendarMonthBoundary() {
        let expenses = [
            spend(1000, on: TestDates.make(2026, 10, 31, 23, 59)),
            spend(2000, on: TestDates.make(2026, 11, 1, 0, 0)),
            spend(4000, on: TestDates.make(2026, 11, 30, 23, 59)),
            spend(8000, on: TestDates.make(2026, 12, 1, 0, 0))
        ]
        let november = report(expenses)
        XCTAssertEqual(november.total, 6000)
        XCTAssertEqual(november.expenseCount, 2)
        XCTAssertEqual(report(expenses, month: oct2026).total, 1000)
        let december = report(expenses, month: BudgetMonth(year: 2026, month: 12)!)
        XCTAssertEqual(december.total, 8000, "先の月は、保存済みの支出があれば金額を出す")
        XCTAssertEqual(december.totalText, LifeFormatters.yen(8000))
    }

    /// 2：12月から1月への年またぎ（推移・前月との差）
    func testYearBoundary() {
        let today = TestDates.make(2027, 1, 15, 9, 0)
        let january = BudgetMonth(year: 2027, month: 1)!
        let expenses = [
            spend(3000, on: TestDates.make(2026, 12, 10)),
            spend(500, on: TestDates.make(2026, 12, 20)),
            spend(1200, on: TestDates.make(2027, 1, 5))
        ]
        let result = report(expenses, month: january, today: today)
        XCTAssertEqual(result.trend.map(\.month.key), ["2026-08", "2026-09", "2026-10", "2026-11", "2026-12", "2027-01"])
        XCTAssertEqual(result.trend.map(\.amount), [0, 0, 0, 0, 3500, 1200])
        XCTAssertEqual(result.comparison.previousAmount, 3000, "前月（12月）の1日〜15日だけ")
        XCTAssertEqual(result.comparison.text, "前月の同じ期間より 1,800円少ない")
        XCTAssertEqual(result.comparison.periodText, "2027年1月1日〜15日と2026年12月1日〜15日を比べています")
        // 過ぎた12月は、11月の月全体と比べる
        XCTAssertEqual(report(expenses, month: BudgetMonth(year: 2026, month: 12)!, today: today).comparison.text, "比較できる支出がありません", "11月に支出が無い")
    }

    /// 3：うるう年（2028年2月は29日。3月30日の「前月の同じ日まで」は2月29日まで）
    func testLeapYear() {
        let today = TestDates.make(2028, 3, 30, 9, 0)
        let march = BudgetMonth(year: 2028, month: 3)!
        let expenses = [
            spend(100, on: TestDates.make(2028, 2, 29, 22, 0)),
            spend(200, on: TestDates.make(2028, 2, 28)),
            spend(1000, on: TestDates.make(2028, 3, 1))
        ]
        let result = report(expenses, month: march, today: today)
        XCTAssertEqual(result.comparison.previousAmount, 300, "2月29日も入る")
        XCTAssertEqual(MonthlySpendingComparison.rangeText(result.comparison.previousRange), "2028年2月1日〜29日")
        XCTAssertEqual(report(expenses, month: BudgetMonth(year: 2028, month: 2)!, today: today).total, 300)
        // うるう年でない年：3月30日は2月28日まで
        let notLeap = MonthlySpendingCalculator.comparisonRanges(month: BudgetMonth(year: 2027, month: 3)!, today: TestDates.make(2027, 3, 30), isCurrent: true)
        XCTAssertEqual(MonthlySpendingComparison.rangeText(notLeap.previous), "2027年2月1日〜28日")
    }

    /// 4：今月は前月の同じ日まで、過ぎた月は前月の月全体と比べる。評価・助言の言葉は出さない
    func testComparisonRanges() {
        let expenses = [
            spend(5000, on: TestDates.make(2026, 11, 2)),
            spend(1800, on: TestDates.make(2026, 11, 13, 20, 0)),
            spend(9999, on: TestDates.make(2026, 11, 14), title: "先の日付"),
            spend(3600, on: TestDates.make(2026, 10, 13, 23, 0)),
            spend(7000, on: TestDates.make(2026, 10, 14), title: "前月の14日"),
            spend(2000, on: TestDates.make(2026, 9, 30))
        ]
        let current = report(expenses)
        XCTAssertEqual(current.comparison.kind, .sameDayRange(day: 13))
        XCTAssertEqual(current.comparison.currentAmount, 6800, "11月1日〜13日")
        XCTAssertEqual(current.comparison.previousAmount, 3600, "10月1日〜13日（14日は入れない）")
        XCTAssertEqual(current.comparison.text, "前月の同じ期間より 3,200円多い")
        XCTAssertEqual(current.comparison.periodText, "2026年11月1日〜13日と2026年10月1日〜13日を比べています")
        XCTAssertEqual(current.total, 16_799, "合計は月全体（先の日付の支出も保存されていれば入る）")
        let past = report(expenses, month: oct2026)
        XCTAssertEqual(past.comparison.kind, .fullMonth)
        XCTAssertEqual(past.comparison.currentAmount, 10_600)
        XCTAssertEqual(past.comparison.previousAmount, 2000)
        XCTAssertEqual(past.comparison.text, "前月より 8,600円多い")
        let less = report([spend(1000, on: TestDates.make(2026, 10, 5)), spend(2800, on: TestDates.make(2026, 9, 5))], month: oct2026)
        XCTAssertEqual(less.comparison.text, "前月より 1,800円少ない")
        let same = report([spend(1000, on: TestDates.make(2026, 10, 5)), spend(1000, on: TestDates.make(2026, 9, 5))], month: oct2026)
        XCTAssertEqual(same.comparison.text, "前月と同じ金額")
        XCTAssertEqual(report([spend(1000, on: TestDates.make(2026, 10, 5))], month: oct2026).comparison.text, "比較できる支出がありません")
        for text in [current.comparison.text, past.comparison.text, less.comparison.text] {
            for word in ["使いすぎ", "節約", "良い", "悪い", "おすすめ", "注意", "予測"] {
                XCTAssertFalse(text.contains(word), word)
            }
        }
    }

    /// 5：最近6か月は古い月から新しい月の順。最近の6か月の中の月を選んでも並びは動かない。それより前を選ぶと、その月まで
    func testTrendOrder() {
        let result = report([])
        XCTAssertEqual(result.trend.map(\.month.key), ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(result.trend.filter(\.isSelected).map(\.month), [nov2026])
        let september = report([], month: sep2026)
        XCTAssertEqual(september.trend.map(\.month.key), result.trend.map(\.month.key), "最近6か月の中なら並びはそのまま")
        XCTAssertEqual(september.trend.filter(\.isSelected).map(\.month), [sep2026], "選んだ月を強調")
        let older = report([], month: BudgetMonth(year: 2026, month: 3)!)
        XCTAssertEqual(older.trend.map(\.month.key), ["2025-10", "2025-11", "2025-12", "2026-01", "2026-02", "2026-03"])
        let future = report([], month: BudgetMonth(year: 2027, month: 2)!)
        XCTAssertEqual(future.trend.last?.month.key, "2027-02")
        XCTAssertEqual(future.trend.count, 6)
        // 推移の一番古い月を選んでも、前月との差はその前の月で数える
        let oldest = report([spend(1000, on: TestDates.make(2026, 5, 10)), spend(500, on: TestDates.make(2026, 6, 10))], month: BudgetMonth(year: 2026, month: 6)!)
        XCTAssertEqual(oldest.comparison.previousAmount, 1000)
        XCTAssertEqual(oldest.comparison.text, "前月より 500円少ない")
    }

    /// 6：支出の無い月も 0円として順番に出す。先の月で支出が無いときは金額を出さない（「記録なし」）
    func testMonthsWithoutDataAreZero() {
        let result = report([spend(1500, on: TestDates.make(2026, 8, 3))])
        XCTAssertEqual(result.trend.map(\.amount), [0, 0, 1500, 0, 0, 0])
        XCTAssertEqual(result.trend.map(\.amountText), ["¥0", "¥0", "¥1,500", "¥0", "¥0", "¥0"])
        let future = report([], month: BudgetMonth(year: 2027, month: 1)!)
        XCTAssertEqual(future.totalText, "まだ支出はありません")
        XCTAssertEqual(future.trend.last?.amountText, "記録なし")
        XCTAssertEqual(future.trend.first?.amountText, "¥0", "過ぎた月・今月は 0円")
        XCTAssertEqual(future.comparison.text, "比較できる支出がありません")
    }
}

// MARK: - 2. 範囲・重複・カテゴリー・割合（7〜10・16）

final class Build26ScopeAndCategoryTests: XCTestCase {
    /// 7：自分は端末の支出だけ、共有は Firestore から受け取った支出だけ、すべては両方
    func testScopesDoNotMix() {
        let device = makeDevice(
            personal: [spend(1000, on: TestDates.make(2026, 11, 3)), spend(200, .transport, on: TestDates.make(2026, 11, 4))],
            shared: [spend(5000, .dailyGoods, on: TestDates.make(2026, 11, 5), shared: true)]
        )
        device.money.scope = .mine
        XCTAssertEqual(device.money.monthlyReport.total, 1200)
        XCTAssertEqual(Set(device.money.monthlyReport.categories.map(\.category)), [.food, .transport])
        device.money.scope = .shared
        XCTAssertEqual(device.money.monthlyReport.total, 5000)
        XCTAssertEqual(device.money.monthlyReport.categories.map(\.category), [.dailyGoods])
        device.money.scope = .all
        XCTAssertEqual(device.money.monthlyReport.total, 6200)
        XCTAssertEqual(device.money.monthlyReport.expenseCount, 3)
        // 一人で使う設定は自分だけ
        let solo = makeDevice(personal: [spend(1000, on: TestDates.make(2026, 11, 3))],
                              shared: [spend(5000, on: TestDates.make(2026, 11, 5), shared: true)], usageStyle: .solo)
        XCTAssertEqual(solo.money.monthlyReport.total, 1000)
        XCTAssertEqual(solo.money.reportScopeTitle, "")
        // 計算部品でも、範囲の外の支出は除く
        let mixed = [spend(1000, on: TestDates.make(2026, 11, 3)), spend(5000, on: TestDates.make(2026, 11, 5), shared: true)]
        XCTAssertEqual(report(mixed, scope: .mine).total, 1000)
        XCTAssertEqual(report(mixed, scope: .shared).total, 5000)
    }

    /// 8：「すべて」でも同じ支出（同じ UUID）は1回だけ
    func testNoDuplicatesInAll() {
        let id = UUID()
        let expense = spend(3000, on: TestDates.make(2026, 11, 3), shared: true, id: id)
        let result = report([expense, expense, expense])
        XCTAssertEqual(result.total, 3000)
        XCTAssertEqual(result.expenseCount, 1)
        XCTAssertEqual(result.checkedExpenses, 1)
        XCTAssertEqual(result.trend.last?.amount, 3000)
        XCTAssertEqual(result.categories.first?.amount, 3000)
        // 画面でも：同じ支出が端末とわが家の両方にあっても（共有に変えている途中など）「すべて」で1回だけ
        let personalCopy = spend(3000, on: TestDates.make(2026, 11, 3), id: id)
        let device = makeDevice(personal: [personalCopy], shared: [expense])
        device.money.scope = .all
        XCTAssertEqual(device.money.monthlyReport.total, 3000)
        XCTAssertEqual(device.money.monthlyReport.checkedExpenses, 1)
        XCTAssertEqual(device.money.expenses.count, 1)
    }

    /// 9：カテゴリーは金額の多い順（同じ金額ならカテゴリーの決まった順）。0円のカテゴリーは出さない
    func testCategoryOrder() {
        let day = TestDates.make(2026, 11, 3)
        let result = report([
            spend(1000, .food, on: day), spend(5000, .other, on: day), spend(3000, .transport, on: day),
            spend(3000, .dailyGoods, on: day), spend(500, .food, on: day)
        ])
        XCTAssertEqual(result.categories.map(\.category), [.other, .dailyGoods, .transport, .food])
        XCTAssertEqual(result.categories.map(\.amount), [5000, 3000, 3000, 1500])
        XCTAssertEqual(result.topCategory?.category, .other)
        XCTAssertFalse(result.categories.contains { $0.category == .subscription }, "0円のカテゴリーは出さない")
    }

    /// 10：割合（％）は全部で100。0円の月は空（0 で割らない）
    func testSharesSumToHundredAndZeroTotal() {
        let day = TestDates.make(2026, 11, 3)
        let thirds = report([spend(100, .food, on: day), spend(100, .transport, on: day), spend(100, .other, on: day)])
        XCTAssertEqual(thirds.categories.map(\.percent), [34, 33, 33])
        XCTAssertEqual(thirds.categories.map(\.percent).reduce(0, +), 100)
        XCTAssertEqual(thirds.categories.map(\.share).reduce(0, +), 1, accuracy: 0.000_001)
        let uneven = report([spend(1, .food, on: day), spend(998, .other, on: day), spend(1, .transport, on: day)])
        XCTAssertEqual(uneven.categories.map(\.percent).reduce(0, +), 100)
        XCTAssertEqual(uneven.categories.first?.percentText, "100%")
        for share in uneven.categories { XCTAssertGreaterThanOrEqual(share.percent, 0) }
        let single = report([spend(12_345, .food, on: day)])
        XCTAssertEqual(single.categories.map(\.percent), [100])
        XCTAssertTrue(MonthlySpendingCalculator.shares([:], total: 0).isEmpty)
        XCTAssertTrue(MonthlySpendingCalculator.shares([.food: 0], total: 0).isEmpty)
        XCTAssertTrue(report([]).categories.isEmpty)
    }

    /// 16：月の金額は支出本体の金額（商品明細の合計は足さない）
    func testLineItemsAreNotAdded() {
        let device = makeDevice()
        let expense = spend(698, on: TestDates.make(2026, 11, 3), title: "まちの八百屋")
        XCTAssertTrue(device.store.addExpense(expense, destination: .personal, lineItems: [
            ExpenseLineItem(name: "牛乳", amount: 198), ExpenseLineItem(name: "ティッシュ", amount: 500), ExpenseLineItem(name: "割引", amount: 300)
        ]))
        device.money.scope = .all
        XCTAssertEqual(device.money.monthlyReport.total, 698)
        XCTAssertEqual(device.money.monthlyReport.categories.first?.amount, 698)
        XCTAssertEqual(device.money.monthlyReport.trend.last?.amount, 698)
    }
}

// MARK: - 3. 予算・定期支出（11〜15）

final class Build26BudgetAndRecurringTests: XCTestCase {
    /// 11：予算が未設定（残りを出さない）
    func testNoBudget() {
        let device = makeDevice(personal: [spend(1000, on: TestDates.make(2026, 11, 3))])
        device.money.scope = .mine
        let summary = device.money.budgetSummaries[0]
        XCTAssertNil(summary.plan)
        XCTAssertNil(device.money.reportBudgetLine(summary))
    }

    /// 12：予算を上回った月（上回った金額を事実として出す。評価はしない）
    func testOverBudget() {
        let device = makeDevice(personal: [spend(32_000, on: TestDates.make(2026, 11, 3))])
        device.store.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 30_000, categoryAmounts: [:]), for: nov2026, scope: .personal)
        device.money.scope = .mine
        let line = device.money.reportBudgetLine(device.money.budgetSummaries[0])
        XCTAssertEqual(line, "自分だけの予算 30,000円・予算を 2,000円上回っています")
        device.store.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 50_000, categoryAmounts: [:]), for: nov2026, scope: .personal)
        XCTAssertEqual(device.money.reportBudgetLine(device.money.budgetSummaries[0]), "自分だけの予算 50,000円・残り 18,000円")
    }

    /// 13：「すべて」でも自分だけの予算とわが家の共有予算は足さない（別々に出す。それぞれの支出だけを数える）
    func testBudgetsAreNotCombined() {
        let device = makeDevice(personal: [spend(1000, on: TestDates.make(2026, 11, 3))],
                                shared: [spend(4000, on: TestDates.make(2026, 11, 4), shared: true)])
        device.store.setMonthlyBudget(MonthlyBudgetPlan(totalAmount: 10_000, categoryAmounts: [:]), for: nov2026, scope: .personal)
        device.store.applySharedBudgetSnapshot([SharedMonthlyBudgetSnapshot(month: nov2026, plan: MonthlyBudgetPlan(totalAmount: 20_000, categoryAmounts: [:]))])
        device.money.scope = .all
        let summaries = device.money.budgetSummaries
        XCTAssertEqual(summaries.map(\.scope), [.personal, .household])
        XCTAssertEqual(summaries.map(\.spent), [1000, 4000])
        XCTAssertEqual(device.money.reportBudgetLine(summaries[0]), "自分だけの予算 10,000円・残り 9,000円")
        XCTAssertEqual(device.money.reportBudgetLine(summaries[1]), "わが家の共有予算 20,000円・残り 16,000円")
        XCTAssertEqual(device.money.monthlyReport.total, 5000, "支出の合計は両方")
        let lines = summaries.compactMap(device.money.reportBudgetLine)
        XCTAssertFalse(lines.contains { $0.contains("30,000") }, "予算を足した金額は出さない")
    }

    /// 14・15：定期支出の候補は数えない。実際に追加した支出は数える
    func testRecurringCandidatesAreNotCountedButAddedOnesAre() throws {
        let device = makeDevice()
        let template = RecurringExpenseTemplate(id: UUID(), title: "家賃", expectedAmount: 85_000, category: .other, dueDay: 27,
                                                startMonthKey: "2026-11", isActive: true, ownership: .personal)
        XCTAssertNil(device.store.saveRecurringTemplate(template))
        device.money.scope = .all
        XCTAssertEqual(device.money.recurringCandidates(for: .personal).first?.state, .unconfirmed)
        XCTAssertEqual(device.money.monthlyReport.total, 0, "候補は支出ではない")
        XCTAssertTrue(device.money.monthlyReport.categories.isEmpty)
        let added = Expense(title: "家賃", amount: 86_000, category: .other, date: TestDates.make(2026, 11, 27))
        XCTAssertNil(device.store.addRecurringExpense(added, templateID: template.id, month: nov2026))
        let after = device.money.monthlyReport
        XCTAssertEqual(after.total, 86_000, "実際に追加した金額")
        XCTAssertEqual(after.categories.first?.category, .other)
        XCTAssertEqual(after.trend.last?.amount, 86_000)
        // 次の月の候補（未確認）も数えない
        device.money.selectReportMonth(BudgetMonth(year: 2026, month: 12)!)
        XCTAssertEqual(device.money.recurringCandidates(for: .personal).first?.state, .unconfirmed)
        XCTAssertEqual(device.money.monthlyReport.totalText, "まだ支出はありません")
    }
}

// MARK: - 4. 画面のつながり・読み上げ・空・たくさんの支出・保存しない（17〜22）

final class Build26NavigationAndSafetyTests: XCTestCase {
    /// 17：カテゴリー・「支出一覧を見る」から、その月（・カテゴリー）で絞り込んだ既存の支出一覧へ進む。お金の画面へ戻れる
    func testOpenExpenseListFromReport() {
        let device = makeDevice(personal: [
            spend(1000, .food, on: TestDates.make(2026, 10, 3), title: "10月の食費"),
            spend(2000, .transport, on: TestDates.make(2026, 10, 4), title: "10月の交通"),
            spend(3000, .food, on: TestDates.make(2026, 11, 5), title: "11月の食費")
        ])
        let money = device.money
        money.searchText = "残っていた検索語"
        money.openMonthlyReport()
        XCTAssertTrue(money.isShowingMonthlyReport)
        money.showPreviousMonth()
        XCTAssertEqual(money.monthlyReport.month, oct2026)
        money.openExpenseList(category: .food)
        XCTAssertFalse(money.isShowingMonthlyReport, "レポートを閉じてお金の画面へ戻る")
        XCTAssertFalse(money.isSearching, "検索欄は空に戻す（支出一覧を出す）")
        XCTAssertEqual(money.listMonth, oct2026)
        XCTAssertEqual(money.selectedCategory, .food)
        XCTAssertEqual(money.listMonthTitle, "2026年10月の支出")
        XCTAssertEqual(money.expenses.map(\.title), ["10月の食費"])
        let request = money.listScrollRequest
        money.monthlyReportDidClose()
        XCTAssertEqual(money.listScrollRequest, request + 1, "閉じたあと支出一覧まで動かす")
        money.monthlyReportDidClose()
        XCTAssertEqual(money.listScrollRequest, request + 1, "1回だけ")
        // 月の一覧（カテゴリーなし）
        money.openMonthlyReport()
        money.openExpenseList()
        money.monthlyReportDidClose()
        XCTAssertEqual(money.listScrollRequest, request + 2)
        XCTAssertNil(money.selectedCategory)
        XCTAssertEqual(Set(money.expenses.map(\.title)), ["10月の食費", "10月の交通"])
        // 絞り込みを外す
        money.clearListMonth()
        XCTAssertNil(money.listMonthTitle)
        XCTAssertEqual(money.expenses.count, 3)
        // レポートを閉じただけなら一覧は動かさない
        money.openMonthlyReport()
        money.closeMonthlyReport()
        money.monthlyReportDidClose()
        XCTAssertEqual(money.listScrollRequest, request + 2)
        // グラフ・月の一覧から月を選ぶ（保存できない年は選ばない）
        money.selectReportMonth(sep2026)
        XCTAssertEqual(money.displayedMonth, sep2026)
        money.selectReportMonth(BudgetMonth(year: 2100, month: 1)!)
        XCTAssertEqual(money.displayedMonth, sep2026)
        money.showCurrentMonth()
        XCTAssertEqual(money.monthlyReport.month, nov2026)
    }

    /// 18：VoiceOver で月・金額・カテゴリー・割合が読める（色だけに頼らない）
    func testSpokenLabels() throws {
        let device = makeDevice(personal: [
            spend(3000, .food, on: TestDates.make(2026, 11, 3)), spend(1000, .transport, on: TestDates.make(2026, 11, 4)),
            spend(2000, .food, on: TestDates.make(2026, 10, 3))
        ])
        let money = device.money
        money.scope = .mine
        let report = money.monthlyReport
        XCTAssertEqual(money.reportTotalSpokenLabel(report), "2026年11月、支出の合計、自分、4,000円、2件")
        let food = try XCTUnwrap(report.categories.first)
        XCTAssertEqual(money.categoryShareSpokenLabel(food), "食費、3,000円、支出全体の75パーセント")
        XCTAssertEqual(money.trendSpokenLabel(try XCTUnwrap(report.trend.last)), "2026年11月、4,000円、表示中の月")
        XCTAssertEqual(money.trendSpokenLabel(report.trend[4]), "2026年10月、2,000円")
        XCTAssertTrue(money.comparisonSpokenLabel(report.comparison).hasPrefix("前月との差、前月の同じ期間より 2,000円多い"))
        let view = build26CodeOnly(try build26Source("LifeOS/Features/Money/MonthlyReportViews.swift"))
        for snippet in [
            ".accessibilityLabel(viewModel.reportTotalSpokenLabel(report))",
            ".accessibilityLabel(viewModel.categoryShareSpokenLabel(share))",
            ".accessibilityLabel(viewModel.trendSpokenLabel(point))",
            ".accessibilityLabel(viewModel.comparisonSpokenLabel(comparison))",
            ".accessibilityLabel(point.month.title)",
            "Text(\"\\(LifeFormatters.yen(share.amount))（\\(share.percentText)）\")",
            "Text(point.amountText)",
            "LifeSpacing.minTapTarget"
        ] {
            XCTAssertTrue(view.contains(snippet), snippet)
        }
        XCTAssertFalse(view.contains("SectorMark"), "円グラフだけで表さない")
        XCTAssertTrue(view.contains("BarMark"))
    }

    /// 19：支出が1件も無くても落ちない（6か月とも 0円・カテゴリーは空・比較できない）
    func testEmptyState() {
        let device = makeDevice()
        let report = device.money.monthlyReport
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.totalText, "¥0")
        XCTAssertFalse(report.hasExpenses)
        XCTAssertNil(report.topCategory)
        XCTAssertTrue(report.categories.isEmpty)
        XCTAssertEqual(report.trend.count, 6)
        XCTAssertEqual(report.trend.map(\.amount), Array(repeating: 0, count: 6))
        XCTAssertEqual(report.comparison.text, "比較できる支出がありません")
        XCTAssertNil(report.comparison.difference)
        device.money.openExpenseList()
        XCTAssertTrue(device.money.expenses.isEmpty)
        XCTAssertEqual(device.money.comparisonSpokenLabel(report.comparison), "前月との差、比較できる支出がありません")
    }

    /// 20：支出が1,000件以上でも、同じ支出を2回数えない（支出を1回だけ見て、6か月・前月・カテゴリーをまとめて数える）
    func testManyExpenses() {
        var expenses: [Expense] = []
        let categories = ExpenseCategory.allCases
        for index in 0..<1_200 {
            let month = 6 + index % 6
            let day = 1 + index % 28
            expenses.append(spend(100 + index, categories[index % categories.count], on: TestDates.make(2026, month, day, 10, 0)))
        }
        let duplicates = Array(expenses.prefix(300))
        let all = expenses + duplicates
        let result = report(all)
        XCTAssertEqual(result.checkedExpenses, 1_200, "同じ支出は1回だけ見る")
        let november = expenses.filter { BudgetMonth(date: $0.date) == nov2026 }
        XCTAssertEqual(result.total, november.reduce(0) { $0 + $1.amount })
        XCTAssertEqual(result.expenseCount, november.count)
        XCTAssertEqual(result.trend.map(\.expenseCount).reduce(0, +), 1_200)
        XCTAssertEqual(result.trend.map(\.amount).reduce(0, +), expenses.reduce(0) { $0 + $1.amount })
        XCTAssertEqual(result.categories.map(\.amount).reduce(0, +), result.total)
        // 画面：同じ値を何度作っても同じ（描画のたびに結果が変わらない）
        let device = makeDevice(personal: expenses)
        device.money.scope = .all
        let first = device.money.monthlyReport
        XCTAssertEqual(first, device.money.monthlyReport)
        XCTAssertEqual(first.checkedExpenses, 1_200)
        // 画面では1回の描画で1回だけ作る
        guard let source = try? build26Source("LifeOS/Features/Money/MonthlyReportViews.swift") else { return }
        let view = build26CodeOnly(source)
        XCTAssertEqual(view.components(separatedBy: "viewModel.monthlyReport").count - 1, 2, "カードと画面で1回ずつ")
        XCTAssertTrue(view.contains(".transaction { $0.animation = nil }"), "グラフにアニメーションを付けない")
    }

    /// 21：Firebase への新しい書き込みが無い。集計・見た月は保存しない・送らない。Rules・Functions・索引は変えない
    func testNoNewWritesOrStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Build26-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalStorage.directoryOverride = directory
        defer {
            LocalStorage.directoryOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let store = LifeStore.persistent(startEmptyIfNoSavedData: true)
        let device = makeDevice(personal: [spend(1000, on: TestDates.make(2026, 11, 3))],
                                shared: [spend(2000, on: TestDates.make(2026, 11, 4), shared: true)], store: store)
        let file = directory.appendingPathComponent(LifeStore.fileName)
        let before = try Data(contentsOf: file)
        let money = device.money
        money.openMonthlyReport()
        for scope in ScopeFilter.allCases {
            money.scope = scope
            _ = money.monthlyReport
            money.showPreviousMonth()
            _ = money.monthlyReport
            money.showCurrentMonth()
        }
        money.selectReportMonth(sep2026)
        money.openExpenseList(category: .food)
        money.monthlyReportDidClose()
        XCTAssertEqual(try Data(contentsOf: file), before, "端末のファイルを書き換えない")
        XCTAssertEqual(device.backend.writeCount, 0, "Firestore へ書かない")
        let saved = try String(contentsOf: file, encoding: .utf8)
        for word in ["monthlyReport", "listMonth", "trend", "comparison"] {
            XCTAssertFalse(saved.contains(word), word)
        }
        for path in ["LifeOS/Core/Models/MonthlySpendingReport.swift", "LifeOS/Features/Money/MonthlyReportViews.swift"] {
            let code = build26CodeOnly(try build26Source(path))
            for word in ["Firestore", "import Firebase", "UserDefaults", ".write(to", "FileManager", "URLSession", "URLRequest",
                         "print(", "NSLog(", "os_log(", "Logger(", "dump(", "Analytics", "Crashlytics", "OpenAI", "anthropic"] {
                XCTAssertFalse(code.contains(word), "\(path)：\(word)")
            }
        }
        let rules = try build26Source("firestore.rules")
        XCTAssertFalse(rules.contains("monthlyReport") || rules.contains("spendingReport"), "新しい保存先を作らない")
        let indexes = try build26Source("firestore.indexes.json")
        XCTAssertFalse(indexes.contains("Report"))
        let project = try build26Source("LifeOS.xcodeproj/project.pbxproj")
        let products = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("productName = ") }
        XCTAssertEqual(products.filter { $0.hasPrefix("productName = Firebase") }.count, 6, "外部のライブラリを足していない")
        for name in ["swift-charts", "DGCharts", "danielgindi"] {
            XCTAssertFalse(project.contains(name), "グラフは Apple の Swift Charts（外部のパッケージではない）：\(name)")
        }
    }

    /// 22：Build 番号は4か所とも 26。Version は 1.0、暗号化の申告は NO のまま。Build 16 は欠番
    func testBuildNumberIs26() throws {
        let project = try build26Source("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CURRENT_PROJECT_VERSION =") }, Array(repeating: "CURRENT_PROJECT_VERSION = 26;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("MARKETING_VERSION =") }, Array(repeating: "MARKETING_VERSION = 1.0;", count: 4))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =") }, Array(repeating: "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;", count: 2))
        XCTAssertTrue(try build26Source("docs/BUILD_26_MONTHLY_SPENDING_REPORT.md").contains("Build 16 は欠番"))
    }

    /// 既存の画面とのつながり：お金の画面に月次レポートのカード（予算の下・定期支出の上）、今日画面の MONEY は Build 24 のまま
    func testMoneyScreenPlacement() throws {
        let money = build26CodeOnly(try build26Source("LifeOS/Features/Money/MoneyView.swift"))
        let budget = try XCTUnwrap(money.range(of: "budgetSection\n"))
        let card = try XCTUnwrap(money.range(of: "MonthlyReportCard(viewModel: viewModel)"))
        let recurring = try XCTUnwrap(money.range(of: "RecurringExpensesSection(viewModel: viewModel)"))
        XCTAssertLessThan(budget.lowerBound, card.lowerBound)
        XCTAssertLessThan(card.lowerBound, recurring.lowerBound)
        XCTAssertTrue(money.contains("MonthlyReportSheet(viewModel: viewModel)"))
        XCTAssertTrue(money.contains("viewModel.monthlyReportDidClose()"))
        XCTAssertTrue(money.contains("proxy.scrollTo(Self.expenseListAnchor, anchor: .top)"))
        let today = build26CodeOnly(try build26Source("LifeOS/Features/Today/TodayViewModel.swift"))
        XCTAssertFalse(today.contains("monthlyReport"), "今日画面の MONEY は変えない")
        let views = build26CodeOnly(try build26Source("LifeOS/Features/Money/MonthlyReportViews.swift"))
        XCTAssertTrue(views.contains("import Charts"))
        XCTAssertTrue(views.contains("\"閉じる\""), "お金の画面へ戻れる")
        XCTAssertTrue(views.contains("viewModel.openExpenseList(category: share.category)"))
        XCTAssertTrue(views.contains("onSelect(point.month)"), "グラフをタップすると、その月へ")
    }
}
