import Foundation

/// なんでも追加の「LifeOSの理解」（Calm Future 第2段階）。
/// 入力した一文を、ルールだけで「何として・いつ・誰の」ものか読み取る。AI は使わない。
struct LifeUnderstanding: Hashable {
    enum Outcome: Hashable {
        /// やること・買い物・予定など（品名が並んでいれば複数）
        case items([InboxSuggestion])
        /// 支出（「ランチ 1200」）
        case expense(title: String, amount: Int, category: ExpenseCategory)
    }

    let text: String
    let outcome: Outcome

    /// 1行目（買い物・食品／冷蔵、支出・外食）
    var headline: String {
        switch outcome {
        case let .items(suggestions):
            return suggestions.first?.categoryText ?? ""
        case let .expense(_, _, category):
            return "支出・\(category.label)"
        }
    }

    /// 追加される内容（牛乳を買う、ティッシュを買う／ランチ ¥1,200）
    var titles: [String] {
        switch outcome {
        case let .items(suggestions):
            return suggestions.map(\.title)
        case let .expense(title, amount, _):
            return ["\(title) \(LifeFormatters.yen(amount))"]
        }
    }

    /// いつ（帰宅時に表示・10/10（土）・今日の支出）
    func timing(now: Date) -> String {
        switch outcome {
        case let .items(suggestions):
            return suggestions.first?.timingText(now: now) ?? ""
        case .expense(_, _, _):
            return "今日の支出"
        }
    }

    /// 自分／共有（支出は分けないため nil）
    var ownershipText: String? {
        switch outcome {
        case let .items(suggestions):
            return suggestions.first?.ownershipText
        case .expense(_, _, _):
            return nil
        }
    }

    /// 理由
    var reason: String {
        switch outcome {
        case let .items(suggestions):
            return suggestions.first?.reasonText ?? ""
        case let .expense(_, _, category):
            return category == .other
                ? "金額があるので支出にしました"
                : "金額があるので支出、品目から\(category.label)にしました"
        }
    }

    /// 追加する件数
    var count: Int {
        switch outcome {
        case let .items(suggestions): return suggestions.count
        case .expense(_, _, _): return 1
        }
    }
}

enum LifeInterpreter {
    /// 支出とみなす最低の金額。「歯医者 10:30」の 30 などを金額と取り違えないため。
    /// 新しい解釈：100円以上の数字があり、時刻の書き方（10:30・10時）でなければ支出とする。
    static let minimumExpenseAmount = 100

    private static let expenseCategoryRules: [(keywords: [String], category: ExpenseCategory)] = [
        (["ランチ", "ディナー", "外食", "カフェ", "居酒屋", "飲み会"], .diningOut),
        (["スーパー", "食材", "コンビニ"], .food),
        (["電車", "バス", "タクシー", "ガソリン", "駐車"], .transport),
        (["ドラッグ", "日用品", "薬局"], .dailyGoods),
        (["Netflix", "サブスク", "Spotify"], .subscription)
    ]

    /// 空のときは nil
    static func understand(_ text: String) -> LifeUnderstanding? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let expense = expense(in: trimmed) {
            return LifeUnderstanding(
                text: trimmed,
                outcome: .expense(title: expense.title, amount: expense.amount, category: expense.category)
            )
        }
        return LifeUnderstanding(text: trimmed, outcome: .items(InboxClassifier.suggestions(for: trimmed)))
    }

    static func expense(in text: String) -> (title: String, amount: Int, category: ExpenseCategory)? {
        let looksLikeTime = text.contains(":") || text.contains("：") || text.contains("時")
        guard !looksLikeTime,
              !hasCountingUnit(text),
              let parsed = QuickAddViewModel.parseExpense(text),
              parsed.amount >= minimumExpenseAmount else {
            return nil
        }
        return (parsed.title, parsed.amount, expenseCategory(for: parsed.title))
    }

    /// 品目から支出のカテゴリーを決める（分からなければ「その他」）
    static func expenseCategory(for title: String) -> ExpenseCategory {
        expenseCategoryRules.first { rule in
            rule.keywords.contains { title.contains($0) }
        }?.category ?? .other
    }

    /// 「2026年」「1000歩」「3回」のように、数字のすぐ後に単位があれば金額ではない
    private static func hasCountingUnit(_ text: String) -> Bool {
        let pattern = "[0-9０-９][0-9０-９,，]*\\s*(年|月|日|歩|回|分|人|個|枚|件|kg|km)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
