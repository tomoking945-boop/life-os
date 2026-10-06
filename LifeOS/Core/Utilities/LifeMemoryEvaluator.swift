import Foundation

/// 暮らしメモリーの表示条件と文言を決める固定ロジック。
/// Calm Future 第3段階：記録（前回・平均周期・誰が対応したか）、次に必要になりそうな時期、季節による変化、
/// 提案を採用／スキップした履歴を読めるようにした（ルールのみ・AI は使わない）。
/// TODO: 将来は記録が十分にたまったら、平均周期で知らせる時期を自動で調整する（今は表示だけ）。
enum LifeMemoryEvaluator {
    /// 今日画面に出すか
    static func isDue(_ memory: LifeMemory, now: Date) -> Bool {
        if let hiddenUntil = memory.hiddenUntil, hiddenUntil > now { return false }
        let calendar = LifeCalendar.calendar
        switch memory.rule {
        case .sinceLast(_, _):
            guard let last = lastDate(memory), let dueAfterDays = effectiveDueAfterDays(memory, now: now) else { return false }
            return daysBetween(last, now) >= dueAfterDays
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
        case .sinceLast(_, _):
            let elapsed = elapsedText(days: daysBetween(lastDate(memory) ?? now, now))
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
        case .sinceLast(_, _):
            if case .addToShopping(_) = memory.action { return "そろそろ買う頃です" }
            return "前回から\(elapsedText(days: daysBetween(lastDate(memory) ?? now, now)))です"
        case let .monthlyDay(day, _):
            let days = daysUntilMonthlyDay(day, from: now) ?? 0
            return days == 0 ? "今日は\(memory.title)の日です" : "\(day)日は\(memory.title)の日です（あと\(days)日）"
        case .weekdays:
            return "今日は\(memory.title)の日です"
        }
    }

    // MARK: - 記録（Calm Future 第3段階）

    /// 前回実施・購入した日。
    /// 「前回から」の周期はルールの日付と記録の新しいほう。記録を消せば（完了の取り消し）元の日付に戻る。
    static func lastDate(_ memory: LifeMemory) -> Date? {
        let recorded = (memory.history ?? []).map(\.date).max()
        if case let .sinceLast(ruleDate, _) = memory.rule {
            guard let recorded else { return ruleDate }
            return max(ruleDate, recorded)
        }
        return recorded
    }

    /// 前回対応した人（記録が無ければ nil）
    static func lastHandler(_ memory: LifeMemory) -> Assignee? {
        (memory.history ?? []).max(by: { $0.date < $1.date })?.by
    }

    /// 今の季節で使う周期（日）。季節の指定があり、今がその月ならそちら。
    static func effectiveDueAfterDays(_ memory: LifeMemory, now: Date) -> Int? {
        guard case let .sinceLast(_, dueAfterDays) = memory.rule else { return nil }
        if let seasonal = memory.seasonal, isInSeason(seasonal, now: now) {
            return seasonal.dueAfterDays
        }
        return dueAfterDays
    }

    static func isInSeason(_ seasonal: SeasonalCycle, now: Date) -> Bool {
        seasonal.months.contains(LifeCalendar.calendar.component(.month, from: now))
    }

    /// 記録から求めた平均周期（日）。記録が2件以上あるときだけ。
    static func averageCycleDays(_ memory: LifeMemory) -> Int? {
        let days = Set((memory.history ?? []).map { LifeCalendar.startOfDay($0.date) }).sorted()
        guard days.count >= 2 else { return nil }
        let intervals = zip(days, days.dropFirst()).map { daysBetween($0, $1) }.filter { $0 > 0 }
        guard !intervals.isEmpty else { return nil }
        let average = Double(intervals.reduce(0, +)) / Double(intervals.count)
        return Int(average.rounded())
    }

    /// 次に必要になりそうな時期（前回＋今の季節の周期／次の毎月の日／次の曜日）
    static func nextExpectedDate(_ memory: LifeMemory, now: Date) -> Date? {
        let calendar = LifeCalendar.calendar
        let today = LifeCalendar.startOfDay(now)
        switch memory.rule {
        case .sinceLast(_, _):
            guard let last = lastDate(memory), let dueAfterDays = effectiveDueAfterDays(memory, now: now) else { return nil }
            return calendar.date(byAdding: .day, value: dueAfterDays, to: LifeCalendar.startOfDay(last))
        case let .monthlyDay(day, _):
            guard let days = daysUntilMonthlyDay(day, from: now) else { return nil }
            return calendar.date(byAdding: .day, value: days, to: today)
        case let .weekdays(weekdays):
            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if weekdays.contains(calendar.component(.weekday, from: date)) { return date }
            }
            return nil
        }
    }

    /// 提案を採用／スキップした回数の説明（例：提案を2回使いました・1回スキップ）。履歴が無ければ nil。
    static func decisionSummary(_ memory: LifeMemory) -> String? {
        let decisions = memory.decisions ?? []
        let accepted = decisions.filter { $0.choice == .accepted }.count
        let skipped = decisions.filter { $0.choice == .skipped || $0.choice == .kept }.count
        var parts: [String] = []
        if accepted > 0 { parts.append("提案を\(accepted)回使いました") }
        if skipped > 0 { parts.append("\(skipped)回スキップ") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    // MARK: - 日数

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
