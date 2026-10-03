import Foundation

/// 「今日これだけ」の選び方（Mock の固定ロジック）。
/// TODO: 将来は期限・時刻・担当・優先度・暮らしメモリー・ユーザーの余力を使って選ぶ。
enum TodayFocusSelector {
    static let maxCount = 3

    /// 今日の項目（習慣を除く）から、目立たせる最大3件と残りに分ける。
    /// 完了しても入れ替えない（3つ全部終わったことが分かるようにするため）。
    static func split(_ items: [LifeItem]) -> (focus: [LifeItem], rest: [LifeItem]) {
        let candidates = items.filter { !$0.isHabit }
        let sorted = candidates.sorted { lhs, rhs in
            let left = sortKey(lhs)
            let right = sortKey(rhs)
            if left.partner != right.partner { return !left.partner }
            if left.kind != right.kind { return left.kind < right.kind }
            return lhs.displayDate < rhs.displayDate
        }
        return (Array(sorted.prefix(maxCount)), Array(sorted.dropFirst(maxCount)))
    }

    /// 並び順の決め方：
    /// 1. パートナー担当のものは後ろ
    /// 2. 家事 → 昼までの予定 → 買い物 → 夕方以降の予定 → 支払予定 → ToDo
    private static func sortKey(_ item: LifeItem) -> (partner: Bool, kind: Double) {
        let kindRank: Double
        switch item.kind {
        case .chore: kindRank = 0
        case .event:
            let hour = LifeCalendar.calendar.component(.hour, from: item.displayDate)
            kindRank = hour < 18 ? 1 : 2.5
        case .shopping: kindRank = 2
        case .payment: kindRank = 3
        case .todo: kindRank = 4
        case .habit: kindRank = 5
        }
        return (item.assignee == .partner, kindRank)
    }
}
