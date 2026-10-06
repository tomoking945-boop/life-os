import Foundation

/// 習慣（Calm Future 第3段階）。
/// Mock の日付に置いた項目ではなく、くり返しのルールで毎日（または決まった曜日に）今日画面へ出す。
/// 記録するのは「できた日」だけ。できなかった日は数えて警告しない（責めないため）。
struct Habit: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    /// くり返し方（今は毎日だけを使う）
    var repeatRule: HabitRepeat
    /// 軽い習慣か（余力が「少ない」日にも出す）
    var isLight: Bool
    /// 始めた日。これより前の日はリズムの点を薄い線の色にする（できなかった日として数えない）
    var startedAt: Date
    /// できた日（その日の0時）
    var doneDays: [Date]

    init(
        id: UUID = UUID(),
        title: String,
        repeatRule: HabitRepeat = .daily,
        isLight: Bool = false,
        startedAt: Date,
        doneDays: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.repeatRule = repeatRule
        self.isLight = isLight
        self.startedAt = LifeCalendar.startOfDay(startedAt)
        self.doneDays = doneDays.map { LifeCalendar.startOfDay($0) }
    }

    /// くり返しのルール上、その日にある習慣か（始めた日より前でも、ルールだけで判定する）
    func occurs(on day: Date) -> Bool {
        switch repeatRule {
        case .daily:
            return true
        case let .weekdays(weekdays):
            return weekdays.contains(LifeCalendar.calendar.component(.weekday, from: day))
        }
    }

    /// その日に今日画面へ出すか（始めた日以降で、ルール上ある日）
    func isActive(on day: Date) -> Bool {
        LifeCalendar.startOfDay(startedAt) <= LifeCalendar.startOfDay(day) && occurs(on: day)
    }

    /// その日にできたか
    func isDone(on day: Date) -> Bool {
        doneDays.contains { LifeCalendar.isSameDay($0, day) }
    }
}

/// 習慣のくり返し方
enum HabitRepeat: Hashable, Codable {
    /// 毎日
    case daily
    /// 決まった曜日（日=1 … 土=7）
    /// TODO: 曜日を選ぶ画面は未実装（構造だけ用意）。習慣の追加・編集の画面と一緒に検討する。
    case weekdays([Int])
}
