import Foundation

// 月次レポート・支出推移（2026-11-13 Build 26）。docs/BUILD_26_MONTHLY_SPENDING_REPORT.md
//
// - すでに端末に読み込んである支出（自分だけは端末、共有は Firestore から受け取ったもの）だけを、その場で数える
// - 新しい保存先・データの形は作らない。集計の結果・見た月は保存しない・送らない・ログに出さない
// - 支出は「支出の日付」の暦月（端末の暦：LifeCalendar）で数える。同じ支出（同じ UUID）は1回だけ
// - 月の金額は支出本体の金額（商品明細の合計は足さない）。定期支出の候補は支出ではないので入らない
// - 金額は丸めない・推測しない。良い・悪い・使いすぎ・節約などの評価や助言はしない（事実だけ）

/// 最近の月の1か月分（推移のグラフ・一覧の1本）
struct MonthlySpendingPoint: Identifiable, Equatable {
    let month: BudgetMonth
    /// その月の支出の合計（支出が無ければ 0）
    let amount: Int
    /// その月の支出の件数
    let expenseCount: Int
    /// 選んでいる月か（強調する）
    let isSelected: Bool
    /// 今月より先の月か
    let isFuture: Bool

    var id: String { month.key }
    var hasExpenses: Bool { expenseCount > 0 }

    /// 金額の文字（先の月で支出が無いときは金額を出さない）
    var amountText: String {
        if isFuture && !hasExpenses { return "記録なし" }
        return LifeFormatters.yen(amount)
    }

    /// 「11月」（グラフの軸）
    var shortTitle: String { "\(month.month)月" }
}

/// カテゴリーの金額と割合
struct MonthlyCategoryShare: Identifiable, Equatable {
    let category: ExpenseCategory
    let amount: Int
    /// 支出全体に占める割合（0〜1。丸めない値）
    let share: Double
    /// 画面に出す割合（整数の％。全部のカテゴリーで足すと100になるように、端数の大きい順に1ずつ足す）
    let percent: Int

    var id: String { category.rawValue }
    var percentText: String { "\(percent)%" }
}

/// 前月との差
struct MonthlySpendingComparison: Equatable {
    enum Kind: Equatable {
        /// 今月：前月の同じ日までと比べる（day は今日の日）
        case sameDayRange(day: Int)
        /// 過ぎた月・先の月：前月の月全体と比べる
        case fullMonth
    }

    let kind: Kind
    /// 比べた期間（対象の月）
    let currentRange: ClosedRange<Date>
    /// 比べた期間（前月）
    let previousRange: ClosedRange<Date>
    let currentAmount: Int
    let previousAmount: Int
    let currentCount: Int
    let previousCount: Int
    let month: BudgetMonth
    /// 対象の月が今月より先か
    let isFutureMonth: Bool

    /// 比べられるか（前月の期間に支出があること。先の月は、その月に支出があること）
    var isAvailable: Bool {
        previousCount > 0 && !(isFutureMonth && currentCount == 0)
    }

    /// 差（対象 − 前月。比べられないときは nil）
    var difference: Int? {
        guard isAvailable else { return nil }
        return MonthlyBudgetCalculator.saturatingAdd(currentAmount, -previousAmount)
    }

    /// 「前月の同じ期間より 3,200円多い」「前月より 1,800円少ない」「比較できる支出がありません」（評価・助言はしない）
    var text: String {
        guard let difference else { return "比較できる支出がありません" }
        let base = kind == .fullMonth ? "前月" : "前月の同じ期間"
        if difference == 0 { return "\(base)と同じ金額" }
        // 金額は正の整数なので、差が Int.min になることは無い
        let amount = LifeFormatters.yenSpoken(abs(difference))
        return difference > 0 ? "\(base)より \(amount)多い" : "\(base)より \(amount)少ない"
    }

    /// 比べた期間の説明（「11月1日〜13日と10月1日〜13日」）
    var periodText: String {
        "\(Self.rangeText(currentRange))と\(Self.rangeText(previousRange))を比べています"
    }

    static func rangeText(_ range: ClosedRange<Date>, calendar: Calendar = LifeCalendar.calendar) -> String {
        let start = calendar.dateComponents([.year, .month, .day], from: range.lowerBound)
        let end = calendar.dateComponents([.day], from: range.upperBound)
        return "\(start.year ?? 0)年\(start.month ?? 0)月\(start.day ?? 0)日〜\(end.day ?? 0)日"
    }
}

/// 1か月のレポート（表示している範囲：すべて／自分／共有）
struct MonthlySpendingReport: Equatable {
    let month: BudgetMonth
    let scope: ScopeFilter
    /// その月の支出の合計（支出本体の金額）
    let total: Int
    let expenseCount: Int
    let isCurrentMonth: Bool
    let isFutureMonth: Bool
    let comparison: MonthlySpendingComparison
    /// 最近6か月（古い月から新しい月の順。最後が対象の月）
    let trend: [MonthlySpendingPoint]
    /// カテゴリー（金額の多い順。0円のカテゴリーは出さない）
    let categories: [MonthlyCategoryShare]
    /// 数えた支出の数（同じ支出を2回数えていないかの確認用）
    let checkedExpenses: Int

    var hasExpenses: Bool { expenseCount > 0 }
    var topCategory: MonthlyCategoryShare? { categories.first }

    /// 合計の文字（先の月で支出が無いときは金額を出さない）
    var totalText: String {
        if isFutureMonth && !hasExpenses { return "まだ支出はありません" }
        return LifeFormatters.yen(total)
    }
}

enum MonthlySpendingCalculator {
    /// 推移に出す月の数
    static let trendMonthCount = 6

    /// 1か月のレポートを作る。expenses は表示している範囲の支出（ほかの範囲の支出が混ざっていても scope で除く。同じ支出は1回だけ）。
    /// 支出を1回だけ見て、推移の6か月・前月との比較・カテゴリーをまとめて数える
    static func report(
        expenses: [Expense],
        scope: ScopeFilter,
        month: BudgetMonth,
        today: Date,
        calendar: Calendar = LifeCalendar.calendar
    ) -> MonthlySpendingReport {
        let currentMonth = BudgetMonth(date: today, calendar: calendar)
        let trendMonths = self.trendMonths(selected: month, current: currentMonth)
        let previous = month.previous
        let isCurrent = month == currentMonth
        let isFuture = month > currentMonth
        let ranges = comparisonRanges(month: month, today: today, isCurrent: isCurrent, calendar: calendar)

        var totals: [BudgetMonth: Int] = [:]
        var counts: [BudgetMonth: Int] = [:]
        var byCategory: [ExpenseCategory: Int] = [:]
        var current = (amount: 0, count: 0)
        var before = (amount: 0, count: 0)
        var seen: Set<Expense.ID> = []
        var checked = 0
        // 数える期間：推移の6か月と、前月（前月との差に使う）
        let earliest = min(trendMonths[0], previous).firstDay(calendar: calendar)
        let latest = max(trendMonths[trendMonths.count - 1], month).dayRange(calendar: calendar).upperBound

        for expense in expenses where scope.includes(expense.ownership) && seen.insert(expense.id).inserted {
            checked += 1
            let day = calendar.startOfDay(for: expense.date)
            // 推移の6か月・前月より前・後の支出は数えない
            guard day >= earliest, day <= latest else { continue }
            let expenseMonth = BudgetMonth(date: expense.date, calendar: calendar)
            totals[expenseMonth] = MonthlyBudgetCalculator.saturatingAdd(totals[expenseMonth] ?? 0, expense.amount)
            counts[expenseMonth, default: 0] += 1
            if expenseMonth == month {
                byCategory[expense.category] = MonthlyBudgetCalculator.saturatingAdd(byCategory[expense.category] ?? 0, expense.amount)
            }
            if ranges.current.contains(day) {
                current = (MonthlyBudgetCalculator.saturatingAdd(current.amount, expense.amount), current.count + 1)
            }
            if expenseMonth == previous, ranges.previous.contains(day) {
                before = (MonthlyBudgetCalculator.saturatingAdd(before.amount, expense.amount), before.count + 1)
            }
        }

        let trend = trendMonths.map { trendMonth in
            MonthlySpendingPoint(
                month: trendMonth,
                amount: totals[trendMonth] ?? 0,
                expenseCount: counts[trendMonth] ?? 0,
                isSelected: trendMonth == month,
                isFuture: trendMonth > currentMonth
            )
        }
        let total = totals[month] ?? 0
        let comparison = MonthlySpendingComparison(
            kind: isCurrent ? .sameDayRange(day: calendar.component(.day, from: today)) : .fullMonth,
            currentRange: ranges.current,
            previousRange: ranges.previous,
            currentAmount: current.amount,
            previousAmount: before.amount,
            currentCount: current.count,
            previousCount: before.count,
            month: month,
            isFutureMonth: isFuture
        )
        return MonthlySpendingReport(
            month: month,
            scope: scope,
            total: total,
            expenseCount: counts[month] ?? 0,
            isCurrentMonth: isCurrent,
            isFutureMonth: isFuture,
            comparison: comparison,
            trend: trend,
            categories: shares(byCategory, total: total),
            checkedExpenses: checked
        )
    }

    /// 推移に出す6か月（古い月から新しい月の順）。
    /// 選んだ月が今月までの最近6か月の中なら、今月までの6か月（グラフで月を選んでも並びが動かない）。
    /// それより前の月・先の月を選んだときは、その月までの6か月
    static func trendMonths(selected month: BudgetMonth, current: BudgetMonth) -> [BudgetMonth] {
        let oldestRecent = current.adding(months: -(trendMonthCount - 1))
        let end = (month <= current && month >= oldestRecent) ? current : month
        return (0..<trendMonthCount).reversed().map { end.adding(months: -$0) }
    }

    /// 比べる期間（日の初めの日付で、両端を含む）。
    /// 今月は「今月1日〜今日」と「前月1日〜前月の同じ日（前月に無い日なら前月の最終日）」。ほかの月は両方とも月全体
    static func comparisonRanges(
        month: BudgetMonth,
        today: Date,
        isCurrent: Bool,
        calendar: Calendar = LifeCalendar.calendar
    ) -> (current: ClosedRange<Date>, previous: ClosedRange<Date>) {
        let previous = month.previous
        guard isCurrent else {
            return (month.dayRange(calendar: calendar), previous.dayRange(calendar: calendar))
        }
        let day = calendar.component(.day, from: today)
        let first = month.firstDay(calendar: calendar)
        let currentEnd = calendar.date(byAdding: .day, value: max(0, day - 1), to: first) ?? first
        let previousFirst = previous.firstDay(calendar: calendar)
        let previousDay = min(day, previous.dayCount(calendar: calendar))
        let previousEnd = calendar.date(byAdding: .day, value: max(0, previousDay - 1), to: previousFirst) ?? previousFirst
        return (first...currentEnd, previousFirst...previousEnd)
    }

    /// カテゴリーの金額と割合（金額の多い順。同じ金額ならカテゴリーの決まった順）。合計が0円なら空（0 で割らない）
    static func shares(_ amounts: [ExpenseCategory: Int], total: Int) -> [MonthlyCategoryShare] {
        let order = Dictionary(uniqueKeysWithValues: ExpenseCategory.allCases.enumerated().map { ($1, $0) })
        let positive = amounts.filter { $0.value > 0 }
            .sorted { $0.value == $1.value ? (order[$0.key] ?? 0) < (order[$1.key] ?? 0) : $0.value > $1.value }
        guard total > 0, !positive.isEmpty else { return [] }
        // 整数の％：切り捨てたあと、端数の大きい順に1ずつ足して合計を100にする（最大剰余法）
        let exact = positive.map { Double($0.value) / Double(total) * 100 }
        var percents = exact.map { Int($0.rounded(.down)) }
        let missing = max(0, 100 - percents.reduce(0, +))
        let byRemainder = exact.indices.sorted { lhs, rhs in
            let left = exact[lhs] - Double(percents[lhs])
            let right = exact[rhs] - Double(percents[rhs])
            return left == right ? lhs < rhs : left > right
        }
        for index in byRemainder.prefix(missing) { percents[index] += 1 }
        return positive.enumerated().map { index, entry in
            MonthlyCategoryShare(category: entry.key, amount: entry.value, share: Double(entry.value) / Double(total), percent: percents[index])
        }
    }
}
