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

    /// 開発用：時間帯の背景を確かめるための切り替え（nil なら現在時刻から決める）。保存しない。
    /// Mock の現在時刻は 9:10 固定のため、昼・夕方・夜の見え方はここで確認する。
    var ambientPreview: LifeTimeOfDay? = nil

    var isPremium: Bool { plan == .premium }

    // MARK: - はじめての設定（2026-10-09）

    /// はじめての設定が終わっているか。
    /// 新しく使い始める人（保存データが無い）は false。以前から使っている人・設定を終えた人は true。
    /// AppState() の初期値（プレビュー・テスト）は true（これまでどおり今日画面から）。
    var hasCompletedOnboarding = true
    /// はじめての設定の途中経過（終わったら nil）
    var onboardingProgress: OnboardingProgress?

    /// 途中経過を保存する（端末内だけ）
    func saveOnboardingProgress(_ progress: OnboardingProgress) {
        onboardingProgress = progress
        save()
    }

    /// はじめての設定の内容を反映する：使い方・名前（自分のメンバー名も）・家族モードなら生活グループ名
    /// - Returns: 名前が空白だけなら false（何も変えない）
    @discardableResult
    func applyOnboarding(usageStyle: UsageStyle, name: String, groupName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        self.usageStyle = usageStyle
        if profile.members.contains(where: { $0.isCurrentUser }) {
            updateName(trimmedName)
        } else {
            profile.name = trimmedName
            profile.members.insert(Member(name: trimmedName, isCurrentUser: true), at: 0)
        }
        let trimmedGroup = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        if usageStyle == .shared, !trimmedGroup.isEmpty {
            profile.groupName = trimmedGroup
        }
        save()
        return true
    }

    /// はじめての設定を終える：完了を保存し、途中経過を消して、今日タブにする
    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        onboardingProgress = nil
        selectedTab = .today
        save()
    }

    /// 開発用：はじめての設定をもう一度出す（予定・習慣・メモなどのデータは消さない）。
    /// 今の使い方・名前・生活グループ名を入れた状態で、最初のステップから始める。
    func restartOnboarding() {
        hasCompletedOnboarding = false
        onboardingProgress = OnboardingProgress(
            step: 0,
            usageStyle: usageStyle,
            name: profile.name,
            groupName: profile.groupName,
            selectedStarterIDs: []
        )
        save()
    }

    /// 新しく使い始める人のプロフィール（見本の名前や「妻」は入れない）。名前ははじめての設定で入れる
    static let newUserProfile = UserProfile(
        name: "",
        groupName: "わが家",
        members: [Member(name: "", isCurrentUser: true)]
    )

    // MARK: - テーマとダークモード（2026-10-08）

    /// ライト／ダーク（表示設定）。新しい解釈：初期値は「端末に合わせる」
    var appearanceMode: LifeAppearanceMode = .system
    /// Premium で選んだテーマ（Free に戻しても選んだものは覚えておく）
    var selectedTheme: LifeTheme = .forest

    /// 実際に使うテーマ。テーマは Premium の機能なので、Free のときは Forest
    var effectiveTheme: LifeTheme {
        isPremium ? selectedTheme : .forest
    }

    /// テーマを選んで保存する（Premium のときだけ選べる）
    func selectTheme(_ theme: LifeTheme) {
        guard isPremium else { return }
        selectedTheme = theme
        save()
    }

    /// ライト／ダークを選んで保存する
    func setAppearanceMode(_ mode: LifeAppearanceMode) {
        appearanceMode = mode
        save()
    }

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
        /// テーマとダークモード（2026-10-08）で追加。以前の保存データには無いため Optional
        var appearanceMode: LifeAppearanceMode?
        var selectedTheme: LifeTheme?
        /// はじめての設定（2026-10-09）で追加。以前の保存データには無いため Optional（無ければ完了済みとして扱う）
        var hasCompletedOnboarding: Bool?
        var onboardingProgress: OnboardingProgress?
    }

    private static let fileName = "app-settings.json"

    /// 端末内に保存された設定を読み込む。
    /// はじめての設定（2026-10-09）：
    /// - 設定の保存があれば読み込む。完了状態が無い（以前のバージョン）なら完了済み（初回設定を出さない）
    /// - 設定もデータも保存が無ければ新しく使い始める人：初回設定は未完了、見本の名前は入れない
    /// - 設定が読めないが保存ファイルはある（壊れているなど）なら、以前から使っている人として扱う（これまでどおり）
    static func persistent() -> AppState {
        let state = AppState()
        let hasSavedFiles = LocalStorage.exists(fileName) || LocalStorage.exists(LifeStore.fileName)
        if let settings = LocalStorage.load(Settings.self, from: fileName) {
            state.plan = settings.plan
            state.profile = settings.profile
            state.notificationSettings = settings.notificationSettings
            state.usageStyle = settings.usageStyle ?? .shared
            state.partnerJoined = settings.partnerJoined ?? true
            state.appearanceMode = settings.appearanceMode ?? .system
            state.selectedTheme = settings.selectedTheme ?? .forest
            state.hasCompletedOnboarding = settings.hasCompletedOnboarding ?? true
            state.onboardingProgress = settings.onboardingProgress
        } else if !hasSavedFiles {
            // 新しく使い始める人
            state.hasCompletedOnboarding = false
            state.onboardingProgress = nil
            state.profile = newUserProfile
            // まだ誰も参加していない（実際の同期は無い）
            state.partnerJoined = false
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
                partnerJoined: partnerJoined,
                appearanceMode: appearanceMode,
                selectedTheme: selectedTheme,
                hasCompletedOnboarding: hasCompletedOnboarding,
                onboardingProgress: onboardingProgress
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
