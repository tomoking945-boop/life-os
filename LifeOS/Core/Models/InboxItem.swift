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
/// Calm Future 第2段階で「土曜」「日曜」を追加（「土曜に母へ電話」など）。
enum InboxDay: String, CaseIterable, Identifiable, Hashable, Codable {
    case today
    case tomorrow
    case saturday
    case sunday

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "今日"
        case .tomorrow: return "明日"
        case .saturday: return "土曜"
        case .sunday: return "日曜"
        }
    }

    /// その日の0時。土曜・日曜は、今日からいちばん近いその曜日（今日がその曜日なら今日）。
    func date(from now: Date) -> Date {
        let calendar = LifeCalendar.calendar
        let start = LifeCalendar.startOfDay(now)
        switch self {
        case .today:
            return start
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .saturday:
            return Self.next(weekday: 7, from: start)
        case .sunday:
            return Self.next(weekday: 1, from: start)
        }
    }

    /// 日=1 … 土=7
    private static func next(weekday: Int, from start: Date) -> Date {
        let current = LifeCalendar.calendar.component(.weekday, from: start)
        let diff = (weekday - current + 7) % 7
        return LifeCalendar.calendar.date(byAdding: .day, value: diff, to: start) ?? start
    }
}

/// Inbox の1件に対する整理の候補（AI分類候補風の Mock）
struct InboxSuggestion: Hashable {
    var title: String
    var kind: LifeItemKind
    var ownership: Ownership
    var day: InboxDay
    /// 柔らかい時間（買い物は「帰宅時」など）。Calm Future 第2段階で追加
    var softTime: SoftTime? = nil
    /// 判断の手がかりにした言葉（「明日」「買う」など）。理由の表示に使う
    var clues: [String] = []
    /// 「修正」で自分で変えたか
    var isEditedByUser = false

    /// 「買い物・明日」「共有ToDo・今日」のような短い説明
    var summary: String {
        let kindText = ownership == .shared ? "共有\(kind.label)" : kind.label
        return "\(kindText)・\(day.label)"
    }

    // MARK: - LifeOSの理解（Calm Future 第2段階）

    /// 分類候補（買い物は売り場のカテゴリーも：買い物・食品／冷蔵）
    var categoryText: String {
        guard kind == .shopping else { return kind.label }
        let categories = ShoppingCategorizer.categories(for: title).filter { $0 != .other }
        guard !categories.isEmpty else { return kind.label }
        return "\(kind.label)・\(categories.map(\.label).joined(separator: "／"))"
    }

    /// 日時候補（今日・帰宅時に表示・明日 10/7（水）など）
    func timingText(now: Date) -> String {
        let base: String
        switch day {
        case .today:
            if let softTime { return "\(softTime.label)に表示" }
            base = "今日"
        case .tomorrow:
            base = "明日 \(LifeFormatters.shortDate(day.date(from: now)))"
        case .saturday, .sunday:
            base = LifeFormatters.shortDate(day.date(from: now))
        }
        if let softTime { return "\(base)・\(softTime.label)" }
        return base
    }

    /// 自分／共有
    var ownershipText: String {
        ownership == .shared ? "家族と共有" : "自分"
    }

    /// 「修正」で変えたあとに呼ぶ：今日の買い物だけ帰宅時に出し、理由を「修正した内容」にする
    mutating func applyUserEdit() {
        softTime = (kind == .shopping && day == .today) ? .onTheWayHome : nil
        clues = []
        isEditedByUser = true
    }

    /// 提案の理由（責めない・短く）
    var reasonText: String {
        if isEditedByUser {
            return "修正した内容で追加します"
        }
        var text: String
        if clues.isEmpty {
            text = "決まった手がかりが無いので、今日のやることにしました"
        } else {
            text = clues.map { "「\($0)」" }.joined() + "を手がかりにしました"
        }
        if softTime == .onTheWayHome {
            text += "。買い物は帰宅時に出します"
        }
        return text
    }

    /// 今日の日付をもとに LifeItem にする
    func makeItem(today: Date) -> LifeItem {
        LifeItem(
            title: title,
            kind: kind,
            ownership: ownership,
            date: day.date(from: today),
            assignee: ownership == .shared ? .either : .me,
            softTime: softTime
        )
    }
}
