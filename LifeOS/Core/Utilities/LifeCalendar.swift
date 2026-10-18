import Foundation

/// アプリ全体で使う暦と「現在時刻」
enum LifeCalendar {
    /// 日本語・グレゴリオ暦・日曜始まり
    /// 決定済み：週の始まりは日曜（2026-10-01）。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }()

    /// 端末の現在時刻。
    /// テストやプレビューで時刻を固定したい場合は、各 ViewModel の `now` 引数へ明示的に渡す。
    static var now: Date {
        Date()
    }

    /// 指定日の指定時刻
    static func date(on day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// 指定日の0時
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 指定日を含む月の1日
    static func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? startOfDay(date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
