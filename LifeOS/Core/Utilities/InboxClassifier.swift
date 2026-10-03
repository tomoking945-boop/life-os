import Foundation

/// Inbox の文から整理の候補を作る Mock 分類。
/// AI API は使わず、決まった言葉を手がかりにするだけの固定ロジック。
/// TODO: AI 接続時（OpenAI API 等）は、ここを本物の分類に置き換える。
enum InboxClassifier {
    /// パートナーと一緒にやることを表す言葉
    private static let sharedKeywords = ["妻と", "夫と", "二人で", "ふたりで", "家族で", "相談"]
    private static let shoppingKeywords = ["買う", "買い", "購入"]
    private static let paymentKeywords = ["払う", "支払", "振込", "振り込"]
    private static let choreKeywords = ["掃除", "洗濯", "ゴミ", "片付け"]

    static func suggest(for text: String) -> InboxSuggestion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let day: InboxDay = trimmed.contains("明日") ? .tomorrow : .today
        let isShared = sharedKeywords.contains { trimmed.contains($0) }

        let kind: LifeItemKind
        if shoppingKeywords.contains(where: { trimmed.contains($0) }) {
            kind = .shopping
        } else if paymentKeywords.contains(where: { trimmed.contains($0) }) {
            kind = .payment
        } else if choreKeywords.contains(where: { trimmed.contains($0) }) {
            kind = .chore
        } else {
            kind = .todo
        }

        return InboxSuggestion(
            title: cleanTitle(trimmed, kind: kind),
            kind: kind,
            ownership: isShared ? .shared : .personal,
            day: day
        )
    }

    /// 「明日牛乳買う」→「牛乳を買う」のように、日付の言葉を外して整える
    static func cleanTitle(_ text: String, kind: LifeItemKind) -> String {
        var title = text
        for word in ["明日", "今日", "妻と", "夫と"] {
            title = title.replacingOccurrences(of: word, with: "")
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if kind == .shopping, title.hasSuffix("買う"), !title.hasSuffix("を買う") {
            title = String(title.dropLast(2)).trimmingCharacters(in: .whitespaces) + "を買う"
        }
        return title.isEmpty ? text : title
    }
}
