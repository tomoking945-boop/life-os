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

    /// 利用スタイル（一人 / 家族・パートナー）。開発用設定で切り替える。
    /// TODO: 初回オンボーディングで選べるようにするかは未定（v2 仕様は「初回オンボーディングまたは開発用設定」）。
    var usageStyle: UsageStyle = .shared

    /// 実際に使うフィルター。一人モードでは「すべて / 自分 / 共有」を出さないため、常に「すべて」。
    var effectiveScope: ScopeFilter {
        usageStyle.showsScopeFilter ? scope : .all
    }
    /// パートナーが参加済みか（Mock。招待の流れを確認するため開発用設定で切り替える）
    var partnerJoined = true

    var isPremium: Bool { plan == .premium }

    // MARK: - 端末内への保存

    /// true のとき、save() で端末内へ保存する（プレビューでは保存しない）
    @ObservationIgnored private var persists = false

    /// 端末内に保存する設定（タブやフィルターの選択状態は保存しない）
    private struct Settings: Codable {
        var plan: PlanType
        var profile: UserProfile
        var notificationSettings: NotificationSettings
        /// v2 で追加。以前の保存データには無いため Optional
        var usageStyle: UsageStyle?
        var partnerJoined: Bool?
    }

    private static let fileName = "app-settings.json"

    /// 端末内に保存された設定を読み込む。保存がなければ Mock の初期値で始める。
    static func persistent() -> AppState {
        let state = AppState()
        if let settings = LocalStorage.load(Settings.self, from: fileName) {
            state.plan = settings.plan
            state.profile = settings.profile
            state.notificationSettings = settings.notificationSettings
            state.usageStyle = settings.usageStyle ?? .shared
            state.partnerJoined = settings.partnerJoined ?? true
        }
        state.persists = true
        state.save()
        return state
    }

    /// 現在の設定を端末内に保存する（Free/Premium と通知は MainTabView の変更検知から呼ぶ）
    func save() {
        guard persists else { return }
        LocalStorage.save(
            Settings(
                plan: plan,
                profile: profile,
                notificationSettings: notificationSettings,
                usageStyle: usageStyle,
                partnerJoined: partnerJoined
            ),
            to: Self.fileName
        )
    }

    /// 開発用：名前・生活グループ・通知を Mock の初期値に戻す（プランと写真はそのまま）
    func resetSettingsToMock() {
        profile = MockData.profile
        notificationSettings = NotificationSettings()
        save()
    }

    /// 名前を変更する（共有メンバー一覧の自分の名前も合わせて変える）
    /// 空白だけの名前は受け付けない。
    func updateName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.name = trimmed
        if let index = profile.members.firstIndex(where: { $0.isCurrentUser }) {
            profile.members[index].name = trimmed
        }
        save()
    }

    /// 生活グループ名を変更する。空白だけの名前は受け付けない。
    func updateGroupName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.groupName = trimmed
        save()
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
