import Foundation

/// 「LifeOSからの提案」を決めるルール（Calm Future 第3段階・AI は使わない）。
///
/// 今あるルール（`lightenDay`）：
/// 1. 今日の未完了の予定・やること（習慣は除く）が 6件以上、または余力「少ない」で 3件以上なら「多い日」
/// 2. 「余力があれば」に入っている、時刻の決まっていない家事・やることを1つ選ぶ
///    （パートナー担当・共有で自分が担当でないもの・支払予定は選ばない。家事 → やることの順）
/// 3. 週末（次の土曜。土曜なら日曜）へ移すことを提案する
/// 4. 同じ日にこの提案へ答えていれば（移動した・今日はそのまま）、もう出さない
///
/// 提案は自動では反映しない。「移動する」を押したときだけ変え、理由と「元に戻す」を出す。
enum LifeSuggestionEngine {
    /// 「多い日」とする件数
    static let busyCount = 6
    /// 余力が少ない日に「多い日」とする件数
    static let lowEnergyBusyCount = 3

    static func suggestion(
        todayItems: [LifeItem],
        extraItems: [LifeItem],
        energy: EnergyLevel?,
        decisions: [SuggestionDecision],
        now: Date
    ) -> LifeSuggestion? {
        let answeredToday = decisions.contains { $0.kind == .lightenDay && LifeCalendar.isSameDay($0.decidedAt, now) }
        guard !answeredToday else { return nil }

        let openCount = todayItems.filter { !$0.isHabit && !$0.isCompleted && !$0.isDropped }.count
        let isLowEnergy = energy == .low
        let isBusy = openCount >= busyCount || (isLowEnergy && openCount >= lowEnergyBusyCount)
        guard isBusy, let item = candidate(from: extraItems) else { return nil }

        let target = PostponeOption.weekend.date(from: now)
        let targetText = LifeFormatters.shortDate(target)
        let cause = isLowEnergy ? "今日は余力が少ないため" : "今日は予定が多いため"
        return LifeSuggestion(
            kind: .lightenDay,
            itemID: item.id,
            itemTitle: item.title,
            targetDate: target,
            targetText: targetText,
            message: "\(cause)、「\(item.title)」を\(targetText)へ移すと余裕ができます。",
            reason: "今日の予定・やることが\(openCount)つあります。時刻の決まっていないものから選びました。",
            acceptTitle: "移動する"
        )
    }

    /// 移す候補（時刻の決まっていない家事 → やること。自分が動かしてよいものだけ）
    static func candidate(from extraItems: [LifeItem]) -> LifeItem? {
        let movable = extraItems.filter { item in
            guard !item.isCompleted, !item.isDropped, !item.showsTime else { return false }
            guard item.kind == .chore || item.kind == .todo else { return false }
            guard item.assignee != .partner else { return false }
            return item.ownership == .personal || item.assignee == .me
        }
        return movable.first { $0.kind == .chore } ?? movable.first
    }
}
