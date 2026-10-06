import Foundation

/// 暮らしメモリー：生活の周期や忘れやすいことを覚えておく。
/// 一人で使うときに特に役立つ機能（v2 仕様 6）。
///
/// Calm Future 第3段階で、記録（前回・誰が対応したか）・季節による変化・提案を採用／スキップした履歴を
/// 持てるようにした。どれも以前の保存データには無いため Optional（無ければ従来どおりの動き）。
struct LifeMemory: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var rule: MemoryRule
    var action: MemoryAction
    /// 「この日時までは今日画面に出さない」（対応済み・スキップ後）
    var hiddenUntil: Date?
    /// 実施・購入した記録（新しい順とは限らない。前回の日・平均周期・誰が対応したかに使う）
    var history: [MemoryRecord]?
    /// 提案を採用／スキップした履歴
    var decisions: [MemoryDecision]?
    /// 季節による変化（例：冷暖房を使う季節はエアコン掃除の周期を短くする）
    var seasonal: SeasonalCycle?

    init(
        id: UUID = UUID(),
        title: String,
        rule: MemoryRule,
        action: MemoryAction,
        hiddenUntil: Date? = nil,
        history: [MemoryRecord]? = nil,
        decisions: [MemoryDecision]? = nil,
        seasonal: SeasonalCycle? = nil
    ) {
        self.id = id
        self.title = title
        self.rule = rule
        self.action = action
        self.hiddenUntil = hiddenUntil
        self.history = history
        self.decisions = decisions
        self.seasonal = seasonal
    }
}

/// いつ知らせるか
enum MemoryRule: Hashable, Codable {
    /// 前回から一定日数たったら（例：シャンプー 前回購入から7週間）
    case sinceLast(lastDate: Date, dueAfterDays: Int)
    /// 毎月決まった日の数日前から（例：家賃 毎月27日）
    case monthlyDay(day: Int, noticeDaysBefore: Int)
    /// 決まった曜日（例：ゴミ 火曜・金曜。日=1 … 土=7）
    case weekdays([Int])
}

/// 今日画面のボタンでできること
enum MemoryAction: Hashable, Codable {
    /// 買い物に追加（タイトル）
    case addToShopping(String)
    /// 土曜日の家事に追加（タイトル）
    case addOnSaturday(String)
    /// やることに追加（タイトル）
    case addToTodo(String)
    /// お知らせだけ
    case notifyOnly
}

/// 実施・購入した記録（暮らしメモリーから追加した項目を完了したときに残す）
struct MemoryRecord: Identifiable, Hashable, Codable {
    let id: UUID
    /// 実施・購入した日時
    var date: Date
    /// 誰が対応したか（分からなければ nil）
    var by: Assignee?
    /// この記録のもとになった項目（完了を取り消したときに記録も消すため）
    var itemID: LifeItem.ID?

    init(id: UUID = UUID(), date: Date, by: Assignee? = nil, itemID: LifeItem.ID? = nil) {
        self.id = id
        self.date = date
        self.by = by
        self.itemID = itemID
    }
}

/// 提案を採用／スキップした記録
struct MemoryDecision: Identifiable, Hashable, Codable {
    let id: UUID
    var decidedAt: Date
    var choice: SuggestionChoice

    init(id: UUID = UUID(), decidedAt: Date, choice: SuggestionChoice) {
        self.id = id
        self.decidedAt = decidedAt
        self.choice = choice
    }
}

/// 季節による周期の変化（指定した月のあいだは周期を変える）
struct SeasonalCycle: Hashable, Codable {
    /// 対象の月（1〜12）
    var months: [Int]
    /// その月のあいだの周期（日）
    var dueAfterDays: Int
    /// 画面に出す説明（例：冷暖房を使う季節）
    var note: String
}
