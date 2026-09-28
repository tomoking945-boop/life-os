import Foundation

/// 表示用の文字列フォーマット
enum LifeFormatters {
    private static let locale = Locale(identifier: "ja_JP")

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter
    }()

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = LifeCalendar.calendar
        formatter.timeZone = LifeCalendar.calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static let headerDateFormatter = dateFormatter("M月d日（E）")
    private static let shortDateFormatter = dateFormatter("M/d（E）")
    private static let timeFormatter = dateFormatter("H:mm")
    private static let monthFormatter = dateFormatter("yyyy年M月")
    private static let spokenDateFormatter = dateFormatter("M月d日EEEE")

    /// ¥82,450
    static func yen(_ amount: Int) -> String {
        let number = decimalFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "¥\(number)"
    }

    /// VoiceOver 用「82,450円」
    static func yenSpoken(_ amount: Int) -> String {
        let number = decimalFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(number)円"
    }

    /// 9月25日（金）
    static func headerDate(_ date: Date) -> String {
        headerDateFormatter.string(from: date)
    }

    /// 9/25（金）
    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    /// 10:30
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// 2026年9月
    static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    /// VoiceOver 用「9月25日金曜日」
    static func spokenDate(_ date: Date) -> String {
        spokenDateFormatter.string(from: date)
    }

    /// あと1時間20分
    static func remaining(from now: Date, to target: Date) -> String {
        let minutes = Int(target.timeIntervalSince(now) / 60)
        guard minutes > 0 else { return "まもなく" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "あと\(hours)時間\(rest)分" }
        if hours > 0 { return "あと\(hours)時間" }
        return "あと\(rest)分"
    }
}
