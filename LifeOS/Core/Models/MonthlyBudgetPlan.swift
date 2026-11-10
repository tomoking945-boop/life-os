import Foundation

// 家計簿の月の予算・カテゴリー別の予算（2026-11-10 Build 24）。docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md
//
// - 予算は月ごと（月のキーは YYYY-MM）。翌月へ自動でコピーしない（利用者が「前月の予算をコピー」を押したときだけ）
// - 自分だけの予算は端末の中（life-store.json）だけ。わが家の共有予算は Firestore の groups/{groupID}/monthlyBudgets/{YYYY-MM}
// - 「すべて」でも、自分だけの予算とわが家の予算を足して1つの予算にしない（別々のカードで出す）
// - 支出は「支出の日付」の月で数える（作った日・直した日では数えない）
// - 金額は整数の円だけ。月の予算は 1〜999,999,999 円、カテゴリーの予算は 0〜999,999,999 円（未設定と 0 円は別）。
//   カテゴリーの予算の合計は、月の予算以下
// - 予算・金額はログに出さない。お金の助言・おすすめはしない（「1日あたりの目安」は残りを残りの日数で割った参考の値）

/// 予算の月（YYYY-MM）。端末の暦（LifeCalendar：日本語・グレゴリオ暦・端末のタイムゾーン）で決める
struct BudgetMonth: Hashable, Comparable, Identifiable {
    /// 予算を保存できる年の範囲（Security Rules の月のキーの形 ^20[0-9]{2}-(0[1-9]|1[0-2])$ と同じ）
    static let minYear = 2000
    static let maxYear = 2099

    let year: Int
    let month: Int

    init?(year: Int, month: Int) {
        guard (1...12).contains(month), (1...9999).contains(year) else { return nil }
        self.year = year
        self.month = month
    }

    /// その日を含む月（端末の暦で）
    init(date: Date, calendar: Calendar = LifeCalendar.calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        self.year = max(1, components.year ?? Self.minYear)
        self.month = (1...12).contains(month) ? month : 1
    }

    /// 「2026-11」から。形が違えば nil
    init?(key: String) {
        guard key.range(of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil,
              let year = Int(key.prefix(4)), let month = Int(key.suffix(2)) else { return nil }
        self.init(year: year, month: month)
    }

    /// 「2026-11」
    var key: String {
        let yearText = String(year)
        let monthText = String(month)
        return String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText + "-" + (month < 10 ? "0" : "") + monthText
    }

    var id: String { key }

    /// 予算を保存できる月か（2000年〜2099年）
    var isStorable: Bool { (Self.minYear...Self.maxYear).contains(year) }

    /// 「2026年11月」
    var title: String { "\(year)年\(month)月" }

    /// 何か月か前・後（年をまたぐ）
    func adding(months: Int) -> BudgetMonth {
        let index = max(12, year * 12 + (month - 1) + months)
        return BudgetMonth(uncheckedYear: index / 12, month: index % 12 + 1)
    }

    var previous: BudgetMonth { adding(months: -1) }
    var next: BudgetMonth { adding(months: 1) }

    /// その月の1日の0時（端末の暦で）
    func firstDay(calendar: Calendar = LifeCalendar.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date(timeIntervalSince1970: 0)
    }

    /// その月の日数（うるう年の2月は29日）
    func dayCount(calendar: Calendar = LifeCalendar.calendar) -> Int {
        calendar.range(of: .day, in: .month, for: firstDay(calendar: calendar))?.count ?? 30
    }

    /// その日がこの月か（支出の日付で数える）
    func contains(_ date: Date, calendar: Calendar = LifeCalendar.calendar) -> Bool {
        BudgetMonth(date: date, calendar: calendar) == self
    }

    static func < (lhs: BudgetMonth, rhs: BudgetMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    private init(uncheckedYear year: Int, month: Int) {
        self.year = year
        self.month = month
    }
}

/// 予算の持ち主（自分だけ／わが家で共有）
enum BudgetScope: String, CaseIterable, Identifiable, Hashable {
    case personal
    case household

    var id: String { rawValue }

    /// 「自分だけ」「わが家で共有」
    var label: String {
        switch self {
        case .personal: return "自分だけ"
        case .household: return "わが家で共有"
        }
    }

    /// カードの見出し
    var budgetTitle: String {
        switch self {
        case .personal: return "自分だけの予算"
        case .household: return "わが家の共有予算"
        }
    }

    /// 数える支出の範囲（自分だけの予算は自分だけの支出だけ、共有の予算は共有の支出だけ）
    var expenseScope: ScopeFilter {
        switch self {
        case .personal: return .mine
        case .household: return .shared
        }
    }

    /// 画面の「すべて／自分／共有」で出す予算のカード（「すべて」は2枚。一人で使う設定は自分だけ）
    static func cards(showsScopeFilter: Bool, effectiveScope: ScopeFilter) -> [BudgetScope] {
        guard showsScopeFilter else { return [.personal] }
        switch effectiveScope {
        case .all: return [.personal, .household]
        case .mine: return [.personal]
        case .shared: return [.household]
        }
    }
}

/// 1か月の予算（月の予算と、任意のカテゴリーの予算）
struct MonthlyBudgetPlan: Equatable, Codable {
    /// 金額の上限（支出・明細と同じ）
    static let maxAmount = 999_999_999

    /// 月の予算（1〜999,999,999 円）
    var totalAmount: Int
    /// カテゴリー（rawValue）ごとの予算（0〜999,999,999 円）。設定していないカテゴリーは入れない（未設定と 0 円を区別する）
    var categoryAmounts: [String: Int]

    init(totalAmount: Int, categoryAmounts: [ExpenseCategory: Int] = [:]) {
        self.totalAmount = totalAmount
        var raw: [String: Int] = [:]
        for (category, amount) in categoryAmounts { raw[category.rawValue] = amount }
        self.categoryAmounts = raw
    }

    init(totalAmount: Int, rawCategoryAmounts: [String: Int]) {
        self.totalAmount = totalAmount
        self.categoryAmounts = rawCategoryAmounts
    }

    /// そのカテゴリーの予算（設定していなければ nil）
    func amount(for category: ExpenseCategory) -> Int? {
        categoryAmounts[category.rawValue]
    }

    /// カテゴリーの予算の合計（あふれない）
    var categoryTotal: Int {
        categoryAmounts.values.reduce(0) { MonthlyBudgetCalculator.saturatingAdd($0, $1) }
    }

    /// 保存できない理由（保存できるなら nil）
    var validationError: BudgetInputError? {
        guard (1...Self.maxAmount).contains(totalAmount) else {
            return totalAmount < 1 ? .total(totalAmount < 0 ? .negative : .zeroNotAllowed) : .total(.tooLarge)
        }
        for category in ExpenseCategory.allCases {
            guard let amount = amount(for: category) else { continue }
            if amount < 0 { return .category(category, .negative) }
            if amount > Self.maxAmount { return .category(category, .tooLarge) }
        }
        guard categoryAmounts.keys.allSatisfy({ ExpenseCategory(rawValue: $0) != nil }) else { return .unknownCategory }
        guard categoryTotal <= totalAmount else { return .categoriesExceedTotal(sum: categoryTotal, total: totalAmount) }
        return nil
    }
}

/// 金額の入力の問題（1つの欄）
enum BudgetAmountProblem: Equatable {
    case negative
    case decimal
    case notNumber
    case tooLarge
    case zeroNotAllowed

    var message: String {
        switch self {
        case .negative: return "マイナスの金額は使えません。"
        case .decimal: return "小数は使えません。円単位の整数で入れてください。"
        case .notNumber: return "数字で入れてください。"
        case .tooLarge: return "999,999,999円までで入れてください。"
        case .zeroNotAllowed: return "1円以上で入れてください。"
        }
    }
}

/// 予算を保存できない理由（画面に日本語で出す）
enum BudgetInputError: Error, Equatable {
    /// 月の予算が空
    case totalMissing
    case total(BudgetAmountProblem)
    case category(ExpenseCategory, BudgetAmountProblem)
    /// 決まっていないカテゴリー
    case unknownCategory
    /// カテゴリーの予算の合計が月の予算を超える
    case categoriesExceedTotal(sum: Int, total: Int)
    /// 予算を保存できない月（2000年〜2099年の外）
    case invalidMonth
    /// 変えられない（わが家に参加していない・家計簿がオフ など。理由の文）
    case notEditable(String)
    /// 端末に保存できなかった
    case saveFailed

    var message: String {
        switch self {
        case .totalMissing: return "月の予算を入れてください（1〜999,999,999円）。"
        case .total(let problem): return "月の予算：\(problem.message)"
        case .category(let category, let problem): return "\(category.label)の予算：\(problem.message)"
        case .unknownCategory: return "決まっていないカテゴリーの予算は保存できません。"
        case .categoriesExceedTotal(let sum, let total):
            return "カテゴリーの予算の合計（\(LifeFormatters.yen(sum))）が、月の予算（\(LifeFormatters.yen(total))）を超えています。合計が月の予算以下になるように直してください。"
        case .invalidMonth: return "この月の予算は設定できません。"
        case .notEditable(let reason): return reason
        case .saveFailed: return "予算を保存できませんでした。もう一度お試しください。"
        }
    }
}

/// 金額の欄の読み方（全角・カンマ・「円」「¥」は許す。マイナス・小数・文字・上限超えは拒否）
enum BudgetAmountInput {
    /// 空なら nil（未設定）。0 円は allowsZero のときだけ
    static func parse(_ text: String, allowsZero: Bool) -> Result<Int?, BudgetAmountProblem> {
        let cleaned = ReceiptFieldExtractor.normalize(text)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "、", with: "")
            .filter { !$0.isWhitespace }
        if cleaned.isEmpty { return .success(nil) }
        if let first = cleaned.first, ["-", "\u{2212}", "▲", "△", "ー"].contains(first) { return .failure(.negative) }
        if cleaned.contains(".") {
            let digitsAndPoint = cleaned.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
            return .failure(digitsAndPoint ? .decimal : .notNumber)
        }
        guard cleaned.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .failure(.notNumber) }
        let significant = cleaned.drop { $0 == "0" }
        // 10桁以上は上限を超える（Int に直す前に確かめる。あふれない）
        guard significant.count <= 9, let value = Int(significant.isEmpty ? "0" : String(significant)) else { return .failure(.tooLarge) }
        guard value <= MonthlyBudgetPlan.maxAmount else { return .failure(.tooLarge) }
        if value == 0, !allowsZero { return .failure(.zeroNotAllowed) }
        return .success(value)
    }

    /// 入力欄に入れる文字（「120000」。カンマは付けない）
    static func text(_ amount: Int?) -> String {
        amount.map(String.init) ?? ""
    }
}

/// 予算の入力欄（編集の画面のあいだだけ。保存するまで予算は変わらない）
struct MonthlyBudgetDraft: Equatable, Identifiable {
    let month: BudgetMonth
    let scope: BudgetScope
    /// 月の予算の欄
    var totalText: String
    /// カテゴリーの予算の欄（空なら未設定）
    var categoryTexts: [ExpenseCategory: String]
    /// すでに予算があるか（「予算を解除」を出す）
    let isExisting: Bool

    var id: String { "\(scope.rawValue)-\(month.key)" }

    init(month: BudgetMonth, scope: BudgetScope, plan: MonthlyBudgetPlan?) {
        self.month = month
        self.scope = scope
        self.isExisting = plan != nil
        self.totalText = BudgetAmountInput.text(plan?.totalAmount)
        var texts: [ExpenseCategory: String] = [:]
        for category in ExpenseCategory.allCases { texts[category] = BudgetAmountInput.text(plan?.amount(for: category)) }
        self.categoryTexts = texts
    }

    /// 前月などの予算を欄に入れる（保存はしない。利用者が「保存」を押したときだけ）
    mutating func fill(from plan: MonthlyBudgetPlan) {
        totalText = BudgetAmountInput.text(plan.totalAmount)
        for category in ExpenseCategory.allCases { categoryTexts[category] = BudgetAmountInput.text(plan.amount(for: category)) }
    }

    func text(for category: ExpenseCategory) -> String {
        categoryTexts[category] ?? ""
    }

    /// 保存する予算。正しくなければ理由
    func validated() -> Result<MonthlyBudgetPlan, BudgetInputError> {
        guard month.isStorable else { return .failure(.invalidMonth) }
        let total: Int
        switch BudgetAmountInput.parse(totalText, allowsZero: false) {
        case .failure(let problem): return .failure(.total(problem))
        case .success(nil): return .failure(.totalMissing)
        case .success(let value?): total = value
        }
        var amounts: [ExpenseCategory: Int] = [:]
        for category in ExpenseCategory.allCases {
            switch BudgetAmountInput.parse(text(for: category), allowsZero: true) {
            case .failure(let problem): return .failure(.category(category, problem))
            case .success(nil): continue
            case .success(let value?): amounts[category] = value
            }
        }
        let plan = MonthlyBudgetPlan(totalAmount: total, categoryAmounts: amounts)
        if let error = plan.validationError { return .failure(error) }
        return .success(plan)
    }

    /// 欄の下に出す理由（正しければ nil）
    var problem: BudgetInputError? {
        if case .failure(let error) = validated() { return error }
        return nil
    }

    /// 読めたカテゴリーの予算の合計（欄の下に出す）
    var enteredCategoryTotal: Int {
        ExpenseCategory.allCases.reduce(0) { sum, category in
            if case .success(let value?) = BudgetAmountInput.parse(text(for: category), allowsZero: true) {
                return MonthlyBudgetCalculator.saturatingAdd(sum, value)
            }
            return sum
        }
    }
}

// MARK: - 集計

/// カテゴリー1つの予算と使った金額
struct BudgetCategoryLine: Identifiable, Equatable {
    let category: ExpenseCategory
    /// 予算（設定していなければ nil）
    let budget: Int?
    let spent: Int

    var id: ExpenseCategory { category }

    /// 残り（予算が無ければ nil。上回っていれば負）
    var remaining: Int? { budget.map { $0 - spent } }

    /// 使った割合（予算が 1 円以上のときだけ。0 で割らない）
    var usageRatio: Double? {
        guard let budget, budget > 0 else { return nil }
        return Double(spent) / Double(budget)
    }
}

/// 1か月の予算と実績（自分だけ、またはわが家で共有のどちらか1つ）
struct MonthlyBudgetSummary: Identifiable, Equatable {
    let month: BudgetMonth
    let scope: BudgetScope
    /// 予算（未設定なら nil）
    let plan: MonthlyBudgetPlan?
    /// その月に使った金額（支出の日付で数える）
    let spent: Int
    /// カテゴリーごと（予算があるか、使った金額があるカテゴリーだけ。決まった順）
    let categoryLines: [BudgetCategoryLine]
    /// 残りの日数（今月は今日を含む。過ぎた月は 0、先の月はその月の日数）
    let daysRemaining: Int

    var id: String { scope.rawValue }

    var hasBudget: Bool { plan != nil }

    /// 残り（未設定なら nil。上回っていれば負）
    var remaining: Int? { plan.map { $0.totalAmount - spent } }

    /// 上回った金額（上回っていなければ nil）
    var overAmount: Int? {
        guard let remaining, remaining < 0 else { return nil }
        return -remaining
    }

    /// 使った割合（予算は 1 円以上なので 0 で割らない）
    var usageRatio: Double? {
        guard let plan, plan.totalAmount > 0 else { return nil }
        return Double(spent) / Double(plan.totalAmount)
    }

    /// 「75%」
    var usagePercentText: String? {
        usageRatio.map { "\(Int(min($0 * 100, 1_000_000).rounded()))%" }
    }

    /// 細い線の長さ（0〜1）
    var barRatio: Double { min(max(usageRatio ?? 0, 0), 1) }

    /// 1日あたりの目安（残りを残りの日数で割った参考の値。残りが無い・日数が無いときは nil。0 で割らない）
    var dailyAllowance: Int? {
        guard let remaining, remaining > 0, daysRemaining > 0 else { return nil }
        return remaining / daysRemaining
    }

    /// 残りの一言（責めない・強い警告にしない）
    var statusText: String {
        guard let remaining else { return "予算は未設定です" }
        if let overAmount { return "予算を\(LifeFormatters.yen(overAmount))上回っています" }
        return "残り \(LifeFormatters.yen(remaining))"
    }
}

enum MonthlyBudgetCalculator {
    /// あふれない足し算（上限で止める）
    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow { return rhs > 0 ? Int.max : Int.min }
        return value
    }

    /// その月の支出（支出の日付で選ぶ）
    static func expenses(_ expenses: [Expense], in month: BudgetMonth, calendar: Calendar = LifeCalendar.calendar) -> [Expense] {
        expenses.filter { month.contains($0.date, calendar: calendar) }
    }

    /// 残りの日数（今月は今日を含む。過ぎた月は 0、先の月はその月の日数）
    static func daysRemaining(in month: BudgetMonth, today: Date, calendar: Calendar = LifeCalendar.calendar) -> Int {
        let current = BudgetMonth(date: today, calendar: calendar)
        if month < current { return 0 }
        let count = month.dayCount(calendar: calendar)
        guard month == current else { return count }
        let day = calendar.component(.day, from: today)
        return max(0, count - day + 1)
    }

    /// 1か月の予算と実績。expenses は、その予算の範囲（自分だけ／共有）の支出（同じ支出は1回だけ）
    static func summary(
        month: BudgetMonth,
        scope: BudgetScope,
        plan: MonthlyBudgetPlan?,
        expenses: [Expense],
        today: Date,
        calendar: Calendar = LifeCalendar.calendar
    ) -> MonthlyBudgetSummary {
        var seen: Set<Expense.ID> = []
        var total = 0
        var byCategory: [ExpenseCategory: Int] = [:]
        for expense in expenses where scope.expenseScope.includes(expense.ownership)
            && month.contains(expense.date, calendar: calendar) && seen.insert(expense.id).inserted {
            total = saturatingAdd(total, expense.amount)
            byCategory[expense.category] = saturatingAdd(byCategory[expense.category] ?? 0, expense.amount)
        }
        let lines = ExpenseCategory.allCases.compactMap { category -> BudgetCategoryLine? in
            let budget = plan?.amount(for: category)
            let spent = byCategory[category] ?? 0
            guard budget != nil || spent > 0 else { return nil }
            return BudgetCategoryLine(category: category, budget: budget, spent: spent)
        }
        return MonthlyBudgetSummary(
            month: month, scope: scope, plan: plan, spent: total, categoryLines: lines,
            daysRemaining: daysRemaining(in: month, today: today, calendar: calendar)
        )
    }
}

/// 端末に保存する自分だけの予算（月のキーごと）。読めない記録・正しくない予算は飛ばす（ファイル全体を読めなくしない）
struct MonthlyBudgetRecords: Codable, Equatable {
    var budgets: [String: MonthlyBudgetPlan]

    init(budgets: [String: MonthlyBudgetPlan]) {
        self.budgets = budgets
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        var result: [String: MonthlyBudgetPlan] = [:]
        if let container = try? decoder.container(keyedBy: Key.self) {
            for key in container.allKeys {
                guard let month = BudgetMonth(key: key.stringValue), month.isStorable,
                      let plan = try? container.decode(MonthlyBudgetPlan.self, forKey: key),
                      plan.validationError == nil else { continue }
                result[month.key] = plan
            }
        }
        budgets = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, plan) in budgets.sorted(by: { $0.key < $1.key }) {
            guard let codingKey = Key(stringValue: key) else { continue }
            try container.encode(plan, forKey: codingKey)
        }
    }
}
