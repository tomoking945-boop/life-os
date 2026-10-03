import Foundation

/// 暮らしメモリー：生活の周期や忘れやすいことを覚えておく。
/// 一人で使うときに特に役立つ機能（v2 仕様 6）。
struct LifeMemory: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var rule: MemoryRule
    var action: MemoryAction
    /// 「この日時までは今日画面に出さない」（対応済み・スキップ後）
    var hiddenUntil: Date?

    init(id: UUID = UUID(), title: String, rule: MemoryRule, action: MemoryAction, hiddenUntil: Date? = nil) {
        self.id = id
        self.title = title
        self.rule = rule
        self.action = action
        self.hiddenUntil = hiddenUntil
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
