import Foundation

/// 提案への答え（LifeOSからの提案・暮らしメモリーで共通）
enum SuggestionChoice: String, Hashable, Codable {
    /// 提案どおりにした（移動する・買い物に追加 など）
    case accepted
    /// 今日はそのまま
    case kept
    /// 今回はスキップ（暮らしメモリー）
    case skipped
}

/// LifeOSからの提案の種類（Calm Future 第3段階）
/// 将来の Life Forecast・Invisible Automation などはここに種類を足す。
enum LifeSuggestionKind: String, Hashable, Codable {
    /// 予定が多い日（または余力が少ない日）に、時刻の決まっていない家事・やることを週末へ移す
    case lightenDay
}

/// LifeOSからの提案（画面に出す内容。保存はしない）
struct LifeSuggestion: Identifiable, Hashable {
    let kind: LifeSuggestionKind
    /// 移す項目
    let itemID: LifeItem.ID
    let itemTitle: String
    /// 移す先の日
    let targetDate: Date
    /// 移す先の言い方（例：10/10（土））
    let targetText: String
    /// 提案の文（例：今日は予定が多いため、「筋トレ」を10/10（土）へ移すと余裕ができます。）
    let message: String
    /// 提案の理由（例：今日の予定・やることが7つあります。時刻の決まっていないものから選びました。）
    let reason: String
    /// 提案どおりにするボタン
    let acceptTitle: String

    var id: String { "\(kind.rawValue)-\(itemID.uuidString)" }
}

/// LifeOSからの提案に答えた記録（同じ日に同じ提案を何度も出さないため・将来の学習のため）
struct SuggestionDecision: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: LifeSuggestionKind
    /// 対象（項目のタイトル）
    var subject: String
    var decidedAt: Date
    var choice: SuggestionChoice

    init(id: UUID = UUID(), kind: LifeSuggestionKind, subject: String, decidedAt: Date, choice: SuggestionChoice) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.decidedAt = decidedAt
        self.choice = choice
    }
}
