import Foundation

/// 習慣のリズムの1日分（7日の点の1つ）
struct HabitRhythmDay: Identifiable, Hashable {
    enum State: Hashable {
        /// できた日（明るい点）
        case done
        /// まだ・できなかった日（薄い点。警告はしない）
        case open
        /// 始める前の日・くり返しの無い日（数えない）
        case inactive
    }

    let date: Date
    let state: State
    let isToday: Bool

    var id: Date { date }
}

/// 習慣を「生活リズム」として見せるためのルール（Calm Future 第3段階・AI は使わない）。
///
/// - 直近7日（今日を含む）を点で表す
/// - ストリーク（◯日連続）は出さず、「最近、自然に続いています」のような言い方にする
/// - 今日まだできていないことは数えない（一日が終わっていないため）
enum HabitRhythm {
    /// 点を並べる日数
    static let dayCount = 7
    /// 「自然に続いています」とする割合
    static let steadyRatio = 0.7
    /// 「リズムができています」とする割合
    static let formingRatio = 0.4
    /// 割合で言い方を変えるのに必要な日数（これより少なければ「始めたばかり」）
    static let minimumCountedDays = 3

    /// 直近7日（古い日 → 今日）
    static func days(for habit: Habit, now: Date) -> [HabitRhythmDay] {
        let calendar = LifeCalendar.calendar
        let today = LifeCalendar.startOfDay(now)
        return (0..<dayCount).reversed().compactMap { offset -> HabitRhythmDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let state: HabitRhythmDay.State
            if !habit.isActive(on: date) {
                state = .inactive
            } else if habit.isDone(on: date) {
                state = .done
            } else {
                state = .open
            }
            return HabitRhythmDay(date: date, state: state, isToday: offset == 0)
        }
    }

    /// 責めない一言（例：最近、自然に続いています）
    static func message(for habit: Habit, now: Date) -> String {
        let counted = days(for: habit, now: now).filter { day in
            // 始める前の日と、まだ終わっていない今日（未チェック）は数えない
            day.state != .inactive && !(day.isToday && day.state == .open)
        }
        let done = counted.filter { $0.state == .done }.count

        guard counted.count >= minimumCountedDays else {
            return done > 0 ? "いいスタートです" : "始めたばかりです"
        }
        let ratio = Double(done) / Double(counted.count)
        if ratio >= steadyRatio { return "最近、自然に続いています" }
        if ratio >= formingRatio { return "少しずつ、リズムができています" }
        if done > 0 { return "できた日が、ちゃんとあります" }
        return "できる日に、また始めれば大丈夫です"
    }
}
