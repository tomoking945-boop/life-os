import Foundation

/// おまかせInbox の1件。
/// 分類・日時・担当を決めずに「とりあえず保存」した生活メモ。
struct InboxItem: Identifiable, Hashable, Codable {
    let id: UUID
    /// 入力したそのままの文
    var text: String
    var createdAt: Date
    /// 「後で」を選んだとき、この日時までおまかせ整理に出さない。
    /// 日時で持つことで、将来の「今夜・明日・週末・来週」の延期と同じ仕組みに統合できる。
    var postponedUntil: Date?

    init(id: UUID = UUID(), text: String, createdAt: Date, postponedUntil: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.postponedUntil = postponedUntil
    }

    /// 指定時点でおまかせ整理の対象か（「後で」の期限が過ぎているか）
    func isReady(at now: Date) -> Bool {
        guard let postponedUntil else { return true }
        return postponedUntil <= now
    }
}

/// いつにするか（おまかせ整理の候補）
enum InboxDay: String, CaseIterable, Identifiable, Hashable, Codable {
    case today
    case tomorrow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "今日"
        case .tomorrow: return "明日"
        }
    }

    var dayOffset: Int {
        switch self {
        case .today: return 0
        case .tomorrow: return 1
        }
    }
}

/// Inbox の1件に対する整理の候補（AI分類候補風の Mock）
struct InboxSuggestion: Hashable {
    var title: String
    var kind: LifeItemKind
    var ownership: Ownership
    var day: InboxDay

    /// 「買い物・明日」「共有ToDo・今日」のような短い説明
    var summary: String {
        let kindText = ownership == .shared ? "共有\(kind.label)" : kind.label
        return "\(kindText)・\(day.label)"
    }

    /// 今日の日付をもとに LifeItem にする
    func makeItem(today: Date) -> LifeItem {
        let start = LifeCalendar.startOfDay(today)
        let date = LifeCalendar.calendar.date(byAdding: .day, value: day.dayOffset, to: start) ?? start
        return LifeItem(
            title: title,
            kind: kind,
            ownership: ownership,
            date: date,
            assignee: ownership == .shared ? .either : .me
        )
    }
}
