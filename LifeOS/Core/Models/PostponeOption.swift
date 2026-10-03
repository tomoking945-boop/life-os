import Foundation

/// 「あとで」の延期先。Inbox の「後で」とタスクの「あとで」、未完了救済で同じ計算を使う。
/// 決定済み：Inbox の「後で」と同じ仕組みに統合する（2026-10-02）。
enum PostponeOption: String, CaseIterable, Identifiable, Hashable {
    /// 今日の夜（20:00）
    case tonight
    /// 明日
    case tomorrow
    /// 週末（次の土曜。土曜なら日曜）
    case weekend
    /// 来週（次の月曜）
    case nextWeek
    /// 今週に回す（未完了救済で使う。今週の土曜。土・日なら翌日）
    /// TODO: 「今週に回す」の正確な意味（曜日を決めずに今週中とするか等）は仕様に明記がない。現状は今週の土曜。
    case thisWeek

    var id: String { rawValue }

    /// 「あとで」シートに出す選択肢（仕様：今日の夜・明日・週末・来週）
    static let sheetOptions: [PostponeOption] = [.tonight, .tomorrow, .weekend, .nextWeek]

    var label: String {
        switch self {
        case .tonight: return "今日の夜"
        case .tomorrow: return "明日"
        case .weekend: return "週末"
        case .nextWeek: return "来週"
        case .thisWeek: return "今週"
        }
    }

    var systemImage: String {
        switch self {
        case .tonight: return "moon"
        case .tomorrow: return "sunrise"
        case .weekend: return "cup.and.saucer"
        case .nextWeek: return "calendar"
        case .thisWeek: return "calendar"
        }
    }

    /// 延期先の日時
    /// TODO: 「週末」「来週」の曜日の決め方は仕様に明記がない。現状は 週末＝次の土曜（土曜なら日曜）、来週＝次の月曜。
    func date(from now: Date) -> Date {
        let calendar = LifeCalendar.calendar
        let today = LifeCalendar.startOfDay(now)
        let weekday = calendar.component(.weekday, from: today) // 日=1 … 土=7

        func day(after days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: today) ?? today
        }

        switch self {
        case .tonight:
            return LifeCalendar.date(on: today, hour: 20, minute: 0)
        case .tomorrow:
            return day(after: 1)
        case .weekend:
            if weekday == 7 { return day(after: 1) }      // 土曜 → 日曜
            if weekday == 1 { return day(after: 6) }      // 日曜 → 次の土曜
            return day(after: 7 - weekday)                // 平日 → 今週の土曜
        case .nextWeek:
            let untilMonday = (2 - weekday + 7) % 7
            return day(after: untilMonday == 0 ? 7 : untilMonday)
        case .thisWeek:
            if weekday == 7 || weekday == 1 { return day(after: 1) }
            return day(after: 7 - weekday)
        }
    }

    /// 「明日に回しました」などの短い表示
    var doneMessage: String { "\(label)に回しました" }
}
