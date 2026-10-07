import Foundation

/// 時刻だけ（10:30 など）。なんでも追加・Inbox で読み取った時刻を持つ。
/// 「入力をもっと賢く」（2026-10-07）で追加。
struct ClockTime: Hashable, Codable {
    var hour: Int
    var minute: Int

    /// 0:00〜23:59 のときだけ作れる
    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// 日時から時刻だけを取り出す
    init(date: Date) {
        let components = LifeCalendar.calendar.dateComponents([.hour, .minute], from: date)
        self.hour = components.hour ?? 0
        self.minute = components.minute ?? 0
    }

    /// 指定した日のこの時刻
    func date(on day: Date) -> Date {
        LifeCalendar.date(on: LifeCalendar.startOfDay(day), hour: hour, minute: minute)
    }

    /// 10:30
    var text: String { String(format: "%d:%02d", hour, minute) }
}
