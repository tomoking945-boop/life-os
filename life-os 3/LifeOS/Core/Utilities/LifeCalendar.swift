import Foundation

/// アプリ全体で使う暦と「現在時刻」
enum LifeCalendar {
    /// 日本語・グレゴリオ暦・日曜始まり
    /// TODO: 週の始まり（日曜 / 月曜）は仕様未定。現状は日曜始まり。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Mock の現在時刻。
    /// 仕様のレイアウト例（NEXT 10:30 / あと1時間20分）を再現するため、「今日の 9:10」を現在時刻として扱う。
    /// TODO: 本実装では `Date()` に置き換える（時間帯による挨拶の切り替えも合わせて検討）。
    static var now: Date {
        calendar.date(bySettingHour: 9, minute: 10, second: 0, of: Date()) ?? Date()
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
