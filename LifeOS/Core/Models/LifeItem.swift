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

/// 項目の種類（予定・ToDo・家事・買い物・支払予定・習慣）
enum LifeItemKind: String, CaseIterable, Hashable, Codable {
    case event
    case todo
    case chore
    case shopping
    case payment
    /// 習慣（水を飲む・ストレッチ など）。できなくても責めない表示にする。
    case habit

    var label: String {
        switch self {
        case .event: return "予定"
        case .todo: return "ToDo"
        case .chore: return "家事"
        case .shopping: return "買い物"
        case .payment: return "支払予定"
        case .habit: return "習慣"
        }
    }

    var systemImage: String {
        switch self {
        case .event: return "calendar"
        case .todo: return "checkmark.circle"
        case .chore: return "house"
        case .shopping: return "bag"
        case .payment: return "yensign.circle"
        case .habit: return "leaf"
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
    /// 表示先の日時（「あとで」「未完了救済」で変える）。元の日付 `date` は書き換えない。
    /// v2 で追加。以前の保存データには無いため Optional。
    var deferredTo: Date?
    /// 「もうやらない」を選んだ日時。削除はせず、一覧に出さないだけにする。
    var droppedAt: Date?
    /// 柔らかい時間表現（帰宅時・余力があれば・今週中 など）。
    /// Calm Future で追加。以前の保存データには無いため Optional。無ければ種類から自動で決める（LivingTimelineBuilder）。
    var softTime: SoftTime?
    /// 暮らしメモリーから追加した項目なら、そのメモリー（完了したときに「前回」の記録を残すため）。
    /// Calm Future 第3段階で追加。以前の保存データには無いため Optional。
    var memoryID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        kind: LifeItemKind,
        ownership: Ownership,
        date: Date,
        hasTime: Bool = false,
        assignee: Assignee? = nil,
        isCompleted: Bool = false,
        deferredTo: Date? = nil,
        droppedAt: Date? = nil,
        softTime: SoftTime? = nil,
        memoryID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.ownership = ownership
        self.date = date
        self.hasTime = hasTime
        self.assignee = assignee
        self.isCompleted = isCompleted
        self.deferredTo = deferredTo
        self.droppedAt = droppedAt
        self.softTime = softTime
        self.memoryID = memoryID
    }

    /// 画面に表示する日時（あとで・救済で回した先。無ければ元の日付）
    var displayDate: Date { deferredTo ?? date }

    /// 「もうやらない」にしたか
    var isDropped: Bool { droppedAt != nil }

    /// 表示する時刻があるか（元の予定の時刻、または「今夜」に回した場合）
    var showsTime: Bool { hasTime || deferredTo.map { LifeCalendar.calendar.component(.hour, from: $0) > 0 } == true }

    /// チェックできる項目か（予定以外。習慣もチェックできる）
    var isTask: Bool { kind != .event }

    /// 習慣か（今日画面では「やること」と分けて表示する）
    var isHabit: Bool { kind == .habit }
}
