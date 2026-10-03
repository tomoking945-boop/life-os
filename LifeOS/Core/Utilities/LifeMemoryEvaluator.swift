import Foundation

/// 暮らしメモリーの表示条件と文言を決める固定ロジック。
/// TODO: 将来は購入履歴・完了履歴から周期を学習する（AI・暮らしの記録と連携）。
enum LifeMemoryEvaluator {
    /// 今日画面に出すか
    static func isDue(_ memory: LifeMemory, now: Date) -> Bool {
        if let hiddenUntil = memory.hiddenUntil, hiddenUntil > now { return false }
        let calendar = LifeCalendar.calendar
        switch memory.rule {
        case let .sinceLast(lastDate, dueAfterDays):
            return daysBetween(lastDate, now) >= dueAfterDays
        case let .monthlyDay(day, noticeDaysBefore):
            guard let days = daysUntilMonthlyDay(day, from: now) else { return false }
            return days <= noticeDaysBefore
        case let .weekdays(weekdays):
            return weekdays.contains(calendar.component(.weekday, from: now))
        }
    }

    /// 周期の説明（例：前回購入から7週間 / 毎月27日 / 火曜・金曜）
    static func cycleText(_ memory: LifeMemory, now: Date) -> String {
        switch memory.rule {
        case let .sinceLast(lastDate, _):
            let elapsed = elapsedText(days: daysBetween(lastDate, now))
            if case .addToShopping(_) = memory.action { return "前回購入から\(elapsed)" }
            return "前回から\(elapsed)"
        case let .monthlyDay(day, _):
            return "毎月\(day)日"
        case let .weekdays(weekdays):
            let symbols = LifeCalendar.calendar.shortWeekdaySymbols
            return weekdays.sorted()
                .compactMap { symbols.indices.contains($0 - 1) ? "\(symbols[$0 - 1])曜" : nil }
                .joined(separator: "・")
        }
    }

    /// 今日画面のひとこと（責めない言い方にする）
    static func message(_ memory: LifeMemory, now: Date) -> String {
        switch memory.rule {
        case let .sinceLast(lastDate, _):
            if case .addToShopping(_) = memory.action { return "そろそろ買う頃です" }
            return "前回から\(elapsedText(days: daysBetween(lastDate, now)))です"
        case let .monthlyDay(day, _):
            let days = daysUntilMonthlyDay(day, from: now) ?? 0
            return days == 0 ? "今日は\(memory.title)の日です" : "\(day)日は\(memory.title)の日です（あと\(days)日）"
        case .weekdays:
            return "今日は\(memory.title)の日です"
        }
    }

    /// 14日未満は「◯日」、60日未満は「◯週間」、それ以上は「◯か月」
    static func elapsedText(days: Int) -> String {
        if days >= 60 { return "\(days / 30)か月" }
        if days >= 14 { return "\(days / 7)週間" }
        return "\(days)日"
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        LifeCalendar.calendar.dateComponents(
            [.day],
            from: LifeCalendar.startOfDay(from),
            to: LifeCalendar.startOfDay(to)
        ).day ?? 0
    }

    /// 今日から、今月（過ぎていれば来月）の指定日まで何日か
    static func daysUntilMonthlyDay(_ day: Int, from now: Date) -> Int? {
        let calendar = LifeCalendar.calendar
        let today = LifeCalendar.startOfDay(now)
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = day
        guard var target = calendar.date(from: components) else { return nil }
        if target < today, let next = calendar.date(byAdding: .month, value: 1, to: target) {
            target = next
        }
        return daysBetween(today, target)
    }
}
