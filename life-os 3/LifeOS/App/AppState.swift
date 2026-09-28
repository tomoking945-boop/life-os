import Observation
import UIKit

/// 下部タブ
enum AppTab: Hashable, CaseIterable {
    case today
    case calendar
    case tasks
    case lists
    case money

    var title: String {
        switch self {
        case .today: return "今日"
        case .calendar: return "カレンダー"
        case .tasks: return "やること"
        case .lists: return "リスト"
        case .money: return "お金"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .calendar: return "calendar"
        case .tasks: return "checklist"
        case .lists: return "list.bullet"
        case .money: return "yensign.circle"
        }
    }
}

/// 画面をまたいで共有する状態
@Observable
final class AppState {
    var selectedTab: AppTab = .today
    /// 今日・カレンダーで共通の「すべて / 自分 / 共有」フィルター
    /// TODO: 今日とカレンダーでフィルターを共有するか、画面ごとに持つかは仕様未定。現状は共有。
    var scope: ScopeFilter = .all
    /// Free / Premium（開発用スイッチで切り替え。StoreKit には接続しない）
    var plan: PlanType = .free
    var profile: UserProfile = MockData.profile
    /// プロフィール写真（端末内のメモリのみ。アップロードはしない）
    /// TODO: アプリ再起動後も写真を保持するかは仕様未定。現状は再起動で消える。
    var profileImage: UIImage?
    var isQuickAddPresented = false

    var isPremium: Bool { plan == .premium }
}
