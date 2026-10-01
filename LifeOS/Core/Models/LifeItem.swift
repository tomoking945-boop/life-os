import Foundation

/// データの持ち主。「自分用」か「共有用」かを識別する。
enum Ownership: String, CaseIterable, Hashable, Codable {
    /// 本人の個人データ
    case personal
    /// 夫婦・家族の共有データ
    case shared

    var label: String {
        switch self {
        case .personal: return "自分"
        case .shared: return "共有"
        }
    }
}

/// 「すべて / 自分 / 共有」の表示フィルター
enum ScopeFilter: String, CaseIterable, Identifiable, Hashable {
    /// 自分の個人データ＋共有データ
    case all
    /// 自分だけのデータ
    case mine
    /// 夫婦・家族共有データ
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "すべて"
        case .mine: return "自分"
        case .shared: return "共有"
        }
    }

    func includes(_ ownership: Ownership) -> Bool {
        switch self {
        case .all: return true
        case .mine: return ownership == .personal
        case .shared: return ownership == .shared
        }
    }
}

/// 担当者
enum Assignee: String, Hashable, Codable {
    /// 本人
    case me
    /// パートナー（Mock では「妻」）
    case partner
    /// どちらでも
    case either
}

/// 項目の種類（カレンダーの表示対象と同じ5種類）
enum LifeItemKind: String, CaseIterable, Hashable, Codable {
    case event
    case todo
    case chore
    case shopping
    case payment

    var label: String {
        switch self {
        case .event: return "予定"
        case .todo: return "ToDo"
        case .chore: return "家事"
        case .shopping: return "買い物"
        case .payment: return "支払予定"
        }
    }

    var systemImage: String {
        switch self {
        case .event: return "calendar"
        case .todo: return "checkmark.circle"
        case .chore: return "house"
        case .shopping: return "bag"
        case .payment: return "yensign.circle"
        }
    }
}

/// 予定・ToDo・家事・買い物・支払予定をまとめて表す項目
struct LifeItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var kind: LifeItemKind
    var ownership: Ownership
    /// 日付（hasTime が true の場合は時刻も意味を持つ）
    var date: Date
    var hasTime: Bool
    var assignee: Assignee?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kind: LifeItemKind,
        ownership: Ownership,
        date: Date,
        hasTime: Bool = false,
        assignee: Assignee? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.ownership = ownership
        self.date = date
        self.hasTime = hasTime
        self.assignee = assignee
        self.isCompleted = isCompleted
    }

    /// チェックできる項目か（予定以外）
    var isTask: Bool { kind != .event }
}
