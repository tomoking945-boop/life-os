import Foundation

/// 柔らかい時間表現（Calm Future）。
/// すべてを時刻に固定せず、「帰宅時」「余力があれば」「今週中」のような置き場所を持てるようにする。
/// `LifeItem.softTime` に保存できる（Optional なので以前の保存データもそのまま読める）。
enum SoftTime: String, CaseIterable, Hashable, Codable {
    /// 帰宅時（買い物など）
    case onTheWayHome
    /// 夜（家に帰ってから）
    case evening
    /// 余力があれば
    case ifYouHaveTime
    /// 今週中
    case thisWeek

    /// 日本語の表示
    var label: String {
        switch self {
        case .onTheWayHome: return "帰宅時"
        case .evening: return "夜"
        case .ifYouHaveTime: return "余力があれば"
        case .thisWeek: return "今週中"
        }
    }

    /// タイムライン上の小さな英語の見出し
    var eyebrow: String {
        switch self {
        case .onTheWayHome: return "ON THE WAY HOME"
        case .evening: return "EVENING"
        case .ifYouHaveTime: return "IF YOU HAVE TIME"
        case .thisWeek: return "THIS WEEK"
        }
    }

    /// タイムライン上の並び位置（その日の何分ごろとして扱うか）
    /// 新しい解釈：帰宅時=18:00ごろ、夜=19:00ごろ、余力があれば・今週中=一日の最後。
    var anchorMinutes: Int {
        switch self {
        case .onTheWayHome: return 18 * 60
        case .evening: return 19 * 60
        case .ifYouHaveTime: return 24 * 60
        case .thisWeek: return 24 * 60 + 1
        }
    }
}
