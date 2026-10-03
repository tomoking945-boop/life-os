import Foundation

/// 利用スタイル（v2 仕様 8：一人モード / 家族・パートナーモード）
enum UsageStyle: String, CaseIterable, Identifiable, Hashable, Codable {
    /// ひとりで使う：共有を前面に出さない「自分専用の生活秘書」
    case solo
    /// 家族・パートナーと使う：「家族の暮らしをまとめる共有OS」
    case shared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solo: return "ひとりで使う"
        case .shared: return "家族・パートナーと使う"
        }
    }

    /// 今日画面のヒーローに添えるコピー
    var copy: String {
        switch self {
        case .solo: return "自分専用の生活秘書"
        case .shared: return "家族の暮らしをまとめる共有OS"
        }
    }

    /// 「すべて / 自分 / 共有」を表示するか（一人モードでは出さず、常に「すべて」）
    var showsScopeFilter: Bool { self == .shared }
}
