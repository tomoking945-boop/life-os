import Foundation

/// 文の中の日付を読み取る（Build 12。docs/BUILD_12_CALENDAR_EVENT_AND_ICON.md）。
/// なんでも追加で、1週間より先の予定も入れられるようにする。AI は使わず、決まった書き方だけを読む。
///
/// 読める書き方：
/// - 「2027年3月10日」（年あり）
/// - 「12月25日」（年なし：今年のその日がもう過ぎていれば、次の年）
/// - 「来月15日」
///
/// 存在しない日付（「2月30日」「4月31日」「来月31日」で来月が30日まで など）は、日付を決めずに「確かめてください」として返す。
/// 黙って別の日（3月2日など）にずらして保存しない。
enum DateReader {
    struct Match: Hashable {
        /// 読み取った日（その日の0時）。存在しない日付なら nil
        let date: Date?
        /// 存在しない日付のときの説明（「2月30日はありません」）
        let problem: String?
        /// 理由に出す手がかり（「12月25日」「来月15日」）
        let clue: String
        /// 日付の部分を取り除いた文
        let remainingText: String

        var needsConfirmation: Bool { date == nil }
    }

    private static let absolutePattern = "(?:([0-9]{4})年)?([0-9]{1,2})月([0-9]{1,2})日(?:に|の)?"
    private static let nextMonthPattern = "来月([0-9]{1,2})日(?:に|の)?"

    static func read(_ text: String, now: Date) -> Match? {
        let normalized = TimeReader.normalizeDigits(text)
        let calendar = LifeCalendar.calendar
        let today = LifeCalendar.startOfDay(now)

        if let match = firstMatch(nextMonthPattern, in: normalized),
           let day = Int(substring(normalized, match.range(at: 1)) ?? ""),
           let nextMonth = calendar.date(byAdding: .month, value: 1, to: LifeCalendar.startOfMonth(today)) {
            let components = calendar.dateComponents([.year, .month], from: nextMonth)
            let year = components.year ?? 0
            let month = components.month ?? 0
            let clue = "来月\(day)日"
            return makeMatch(
                date: validDate(year: year, month: month, day: day),
                problem: "\(year)年\(month)月\(day)日はありません",
                clue: clue,
                range: match.range,
                in: text
            )
        }

        if let match = firstMatch(absolutePattern, in: normalized),
           let month = Int(substring(normalized, match.range(at: 2)) ?? ""),
           let day = Int(substring(normalized, match.range(at: 3)) ?? "") {
            if let yearText = substring(normalized, match.range(at: 1)), let year = Int(yearText) {
                return makeMatch(
                    date: validDate(year: year, month: month, day: day),
                    problem: "\(year)年\(month)月\(day)日はありません",
                    clue: "\(year)年\(month)月\(day)日",
                    range: match.range,
                    in: text
                )
            }
            // 年が無い：今年のその日。もう過ぎていれば次の年
            let thisYear = calendar.component(.year, from: today)
            var year = thisYear
            if let candidate = validDate(year: thisYear, month: month, day: day), candidate < today {
                year = thisYear + 1
            } else if validDate(year: thisYear, month: month, day: day) == nil,
                      (1...12).contains(month),
                      let monthStart = calendar.date(from: DateComponents(year: thisYear, month: month, day: 1)),
                      monthStart < LifeCalendar.startOfMonth(today) {
                // 今年は存在しない日（2月29日など）で、その月がもう過ぎている：次の年で確かめる
                year = thisYear + 1
            }
            return makeMatch(
                date: validDate(year: year, month: month, day: day),
                problem: "\(year)年\(month)月\(day)日はありません",
                clue: "\(month)月\(day)日",
                range: match.range,
                in: text
            )
        }
        return nil
    }

    /// その年月日が本当にあるときだけ、その日の0時を返す（2月30日を3月2日にずらさない）
    static func validDate(year: Int, month: Int, day: Int) -> Date? {
        let calendar = LifeCalendar.calendar
        guard (1...12).contains(month), day >= 1,
              let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: monthStart),
              days.contains(day) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func makeMatch(date: Date?, problem: String, clue: String, range: NSRange, in text: String) -> Match? {
        guard let wholeRange = Range(range, in: text) else { return nil }
        var remaining = text
        remaining.replaceSubrange(wholeRange, with: " ")
        while remaining.contains("  ") {
            remaining = remaining.replacingOccurrences(of: "  ", with: " ")
        }
        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return Match(date: date, problem: date == nil ? problem : nil, clue: clue, remainingText: remaining)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ text: String, _ range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
