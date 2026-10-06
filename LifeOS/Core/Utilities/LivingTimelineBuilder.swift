import Foundation

/// Living Timeline の置き場所（Calm Future）
enum TimelineSlot: Hashable {
    /// いま（時刻の決まっていない「今日これだけ」）
    case now
    /// 時刻の決まった予定
    case time(Date)
    /// 柔らかい時間表現（帰宅時・夜・余力があれば・今週中）
    case soft(SoftTime)

    /// 小さな見出し（NOW / 10:30 / ON THE WAY HOME）
    var eyebrow: String {
        switch self {
        case .now: return "NOW"
        case let .time(date): return LifeFormatters.time(date)
        case let .soft(softTime): return softTime.eyebrow
        }
    }

    /// 見出しに添える日本語（時刻のときは無し）
    var japaneseLabel: String? {
        switch self {
        case .now: return "いま"
        case .time(_): return nil
        case let .soft(softTime): return softTime.label
        }
    }

    /// VoiceOver で読む見出し
    var spokenLabel: String {
        switch self {
        case .now: return "いま"
        case let .time(date): return LifeFormatters.time(date)
        case let .soft(softTime): return softTime.label
        }
    }
}

/// タイムラインのひとまとまり（同じ置き場所の項目）
struct TimelineSection: Identifiable, Hashable {
    let slot: TimelineSlot
    var items: [LifeItem]

    var id: String {
        switch slot {
        case .now: return "now"
        case let .time(date): return "time-\(Int(date.timeIntervalSince1970))"
        case let .soft(softTime): return "soft-\(softTime.rawValue)"
        }
    }
}

/// 「今日これだけ」「NEXT」「このあと」を、ひとつの Living Timeline に組み直す（ルールのみ・AI は使わない）。
///
/// 置き場所の決め方：
/// 1. 時刻のある項目（予定・「今夜」に回した項目）→ その時刻
/// 2. 「今日これだけ」の項目 → `softTime` があればそこ。無ければ 買い物＝帰宅時、それ以外＝いま
/// 3. それ以外（今日これだけ に入らなかった時刻のない項目）→ 「余力があれば」に折りたたむ
///
/// 並び順は「その日の何分ごろか」。柔らかい時間は「いま」より前には来ない。
enum LivingTimelineBuilder {
    struct Timeline: Hashable {
        /// タイムラインに並べるまとまり
        var sections: [TimelineSection]
        /// 「余力があれば」に折りたたむ項目
        var extra: [LifeItem]
    }

    static func build(focus: [LifeItem], rest: [LifeItem], now: Date) -> Timeline {
        let nowMinutes = minutes(of: now)
        var sections: [TimelineSection] = []
        var extra: [LifeItem] = []

        func append(_ item: LifeItem, to slot: TimelineSlot) {
            if let index = sections.firstIndex(where: { $0.slot == slot }) {
                sections[index].items.append(item)
            } else {
                sections.append(TimelineSection(slot: slot, items: [item]))
            }
        }

        for item in focus {
            append(item, to: slot(forFocus: item))
        }
        for item in rest {
            if item.showsTime {
                append(item, to: .time(item.displayDate))
            } else {
                extra.append(item)
            }
        }

        let sorted = sections.enumerated().sorted { lhs, rhs in
            let left = sortKey(lhs.element.slot, nowMinutes: nowMinutes)
            let right = sortKey(rhs.element.slot, nowMinutes: nowMinutes)
            if left.anchor != right.anchor { return left.anchor < right.anchor }
            if left.rank != right.rank { return left.rank < right.rank }
            return lhs.offset < rhs.offset
        }
        return Timeline(sections: sorted.map { $0.element }, extra: extra)
    }

    /// 「今日これだけ」の項目の置き場所
    static func slot(forFocus item: LifeItem) -> TimelineSlot {
        if item.showsTime { return .time(item.displayDate) }
        if let softTime = item.softTime { return .soft(softTime) }
        return item.kind == .shopping ? .soft(.onTheWayHome) : .now
    }

    private static func sortKey(_ slot: TimelineSlot, nowMinutes: Int) -> (anchor: Int, rank: Int) {
        switch slot {
        case .now: return (nowMinutes, 0)
        case let .time(date): return (minutes(of: date), 1)
        case let .soft(softTime): return (max(softTime.anchorMinutes, nowMinutes + 1), 2)
        }
    }

    private static func minutes(of date: Date) -> Int {
        let components = LifeCalendar.calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
