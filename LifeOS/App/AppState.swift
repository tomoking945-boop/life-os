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
    /// プロフィール写真（端末内に保存。アップロードはしない）
    /// 決定済み：再起動後も残るよう端末内に保存する（2026-10-01）。変更は updateProfileImage(_:) から行う。
    private(set) var profileImage: UIImage? = ProfileImageStorage.load()
    var isQuickAddPresented = false

    /// 通知設定（Mock。実際の通知は送らない。Push通知は今回やらない）
    var notificationSettings = NotificationSettings()

    var isPremium: Bool { plan == .premium }

    /// 名前を変更する（共有メンバー一覧の自分の名前も合わせて変える）
    /// 空白だけの名前は受け付けない。
    func updateName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.name = trimmed
        if let index = profile.members.firstIndex(where: { $0.isCurrentUser }) {
            profile.members[index].name = trimmed
        }
    }

    /// 生活グループ名を変更する。空白だけの名前は受け付けない。
    func updateGroupName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.groupName = trimmed
    }

    /// プロフィール写真を変更・削除し、端末内の保存内容も合わせて更新する
    func updateProfileImage(_ image: UIImage?) {
        profileImage = image
        if let image {
            ProfileImageStorage.save(image)
        } else {
            ProfileImageStorage.delete()
        }
    }
}
