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
    /// 曜日・日付の言葉（長いものから順に調べる）
    private static let dayKeywords: [(word: String, day: InboxDay)] = [
        ("明日", .tomorrow),
        ("土曜日", .saturday), ("土曜", .saturday), ("週末", .saturday),
        ("日曜日", .sunday), ("日曜", .sunday)
    ]
    /// 品名を区切る言葉（「牛乳とティッシュ」「卵、パン」）
    private static let listSeparators: [Character] = ["と", "、", ",", "，", "・", " ", "　"]

    static func suggest(for text: String) -> InboxSuggestion {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var clues: [String] = []

        // 「入力をもっと賢く」（2026-10-07）：時刻を先に読み取り、残りの文で分類する（「10:30 歯医者」→ 歯医者・10:30）
        let timeMatch = TimeReader.read(trimmed)
        if let timeMatch, !timeMatch.remainingText.isEmpty {
            trimmed = timeMatch.remainingText
        }
        let time = (timeMatch?.remainingText.isEmpty == false) ? timeMatch?.time : nil

        var day = InboxDay.today
        if let match = dayKeywords.first(where: { trimmed.contains($0.word) }) {
            day = match.day
            clues.append(match.word)
        }

        let sharedWord = sharedKeywords.first { trimmed.contains($0) }
        if let sharedWord { clues.append(sharedWord) }

        let kind: LifeItemKind
        if let word = shoppingKeywords.first(where: { trimmed.contains($0) }) {
            kind = .shopping
            clues.append(word)
        } else if let word = paymentKeywords.first(where: { trimmed.contains($0) }) {
            kind = .payment
            clues.append(word)
        } else if let word = choreKeywords.first(where: { trimmed.contains($0) }) {
            kind = .chore
            clues.append(word)
        } else if let names = productNames(in: cleanTitle(trimmed, kind: .todo)) {
            // 品名だけが並んでいる（「牛乳とティッシュ」）→ 買い物
            kind = .shopping
            clues.append(names[0])
        } else {
            // 新しい解釈：時刻があって、ほかに手がかりが無ければ「予定」（「10:30 歯医者」）
            kind = time == nil ? .todo : .event
        }

        if let timeMatch, time != nil {
            clues.insert(timeMatch.clue, at: 0)
        }

        // 新しい解釈：今日の買い物は「帰宅時」に出す（仕様の例「帰宅時に表示」）。時刻があれば時刻を優先する
        let softTime: SoftTime? = (time == nil && kind == .shopping && day == .today) ? .onTheWayHome : nil

        return InboxSuggestion(
            title: cleanTitle(trimmed, kind: kind),
            kind: kind,
            ownership: sharedWord == nil ? .personal : .shared,
            day: day,
            softTime: softTime,
            clues: clues,
            time: time
        )
    }

    /// なんでも追加の「提案どおり追加」用：品名だけが並んでいるときは1品ずつに分ける
    /// （「牛乳とティッシュ」→「牛乳を買う」「ティッシュを買う」）。それ以外は1件。
    static func suggestions(for text: String) -> [InboxSuggestion] {
        let base = suggest(for: text)
        guard base.kind == .shopping,
              let names = productNames(in: ShoppingCategorizer.itemName(from: base.title)),
              names.count > 1 else {
            return [base]
        }
        return names.map { name in
            var suggestion = base
            suggestion.title = "\(name)を買う"
            return suggestion
        }
    }

    /// 知っている品名だけが並んでいれば、その品名を返す（「水を飲む」のような文は nil）
    static func productNames(in text: String) -> [String]? {
        let parts = text
            .split(whereSeparator: { listSeparators.contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let isProductList = parts.allSatisfy { ShoppingCategorizer.isKnownProduct($0) }
        return isProductList ? parts : nil
    }

    /// 「明日牛乳買う」→「牛乳を買う」のように、日付の言葉を外して整える
    static func cleanTitle(_ text: String, kind: LifeItemKind) -> String {
        var title = text
        let words = ["明日の", "今日の", "土曜の", "日曜の", "明日", "今日", "土曜日に", "土曜に", "土曜日", "土曜", "日曜日に", "日曜に", "日曜日", "日曜",
                     "週末に", "週末", "妻と", "夫と"]
        for word in words {
            title = title.replacingOccurrences(of: word, with: "")
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if kind == .shopping, title.hasSuffix("買う"), !title.hasSuffix("を買う") {
            title = String(title.dropLast(2)).trimmingCharacters(in: .whitespaces) + "を買う"
        } else if kind == .shopping, !title.hasSuffix("買う"), productNames(in: title) != nil {
            title += "を買う"
        }
        return title.isEmpty ? text : title
    }
}
