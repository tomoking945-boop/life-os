import Foundation
import Observation

/// はじめての設定（2026-10-09）。
/// 4ステップ（ようこそ → 使い方 → 名前 → 最初の習慣）。入力のたびに途中経過を端末内に保存し、途中で終了しても続きから再開する。
@Observable
final class OnboardingViewModel {
    /// ステップの数
    static let stepCount = 4

    enum Step: Int, CaseIterable {
        case welcome = 0
        case usage = 1
        case name = 2
        case habits = 3
    }

    private let appState: AppState
    private let store: LifeStore
    private let now: Date
    private(set) var progress: OnboardingProgress
    /// 完了処理を一度だけにする（連打しても習慣が重複しないように）
    @ObservationIgnored private var isCompleting = false

    init(appState: AppState, store: LifeStore, now: Date = LifeCalendar.now) {
        self.appState = appState
        self.store = store
        self.now = now
        var restored = appState.onboardingProgress ?? .initial
        restored.step = min(max(restored.step, 0), Self.stepCount - 1)
        self.progress = restored
    }

    // MARK: - ステップ

    var step: Step { Step(rawValue: progress.step) ?? .welcome }

    /// 読み上げ用（ステップ 2 / 4）
    var stepText: String { "ステップ \(progress.step + 1) / \(Self.stepCount)" }

    var canGoBack: Bool { progress.step > 0 }

    /// 次へ進めるか（使い方は選択が必要、名前は空白だけでは進めない）
    var canGoNext: Bool {
        switch step {
        case .welcome: return true
        case .usage: return progress.usageStyle != nil
        case .name: return hasValidName
        case .habits: return canComplete
        }
    }

    /// 下のボタンの文言
    var primaryTitle: String {
        switch step {
        case .welcome: return "はじめる"
        case .usage, .name: return "次へ"
        case .habits: return "生活OSをはじめる"
        }
    }

    func next() {
        guard canGoNext, progress.step < Self.stepCount - 1 else { return }
        progress.step += 1
        persist()
    }

    func back() {
        guard canGoBack else { return }
        progress.step -= 1
        persist()
    }

    // MARK: - 使い方

    var usageStyle: UsageStyle? { progress.usageStyle }

    func selectUsage(_ style: UsageStyle) {
        progress.usageStyle = style
        persist()
    }

    /// 選択肢の説明（仕様の文言。すぐ同期されると誤解させる言い方はしない）
    static func usageDescription(_ style: UsageStyle) -> String {
        switch style {
        case .solo: return "自分の予定や習慣をまとめます"
        case .shared: return "自分と共有の情報を分けて管理します"
        }
    }

    // MARK: - 名前

    var name: String {
        get { progress.name }
        set {
            progress.name = newValue
            persist()
        }
    }

    var groupName: String {
        get { progress.groupName }
        set {
            progress.groupName = newValue
            persist()
        }
    }

    /// 生活グループ名を聞くか（家族・パートナーと使うときだけ）
    var asksGroupName: Bool { progress.usageStyle == .shared }

    var hasValidName: Bool {
        !progress.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 最初の習慣

    let starters = OnboardingStarter.all

    func isSelected(_ starter: OnboardingStarter) -> Bool {
        progress.selectedStarterIDs.contains(starter.id)
    }

    func toggle(_ starter: OnboardingStarter) {
        if progress.selectedStarterIDs.contains(starter.id) {
            progress.selectedStarterIDs.remove(starter.id)
        } else {
            progress.selectedStarterIDs.insert(starter.id)
        }
        persist()
    }

    // MARK: - 完了

    var canComplete: Bool { progress.usageStyle != nil && hasValidName }

    /// 完了：検証 → 使い方 → 名前・生活グループ名 → 選んだ習慣（重複なし）→ 完了を保存 → 途中経過を削除 → 今日タブ。
    /// 二度目以降の呼び出しは何もしない。
    /// - Returns: 完了したら true
    @discardableResult
    func complete() -> Bool {
        guard !isCompleting, !appState.hasCompletedOnboarding,
              let usageStyle = progress.usageStyle, hasValidName else { return false }
        isCompleting = true

        guard appState.applyOnboarding(usageStyle: usageStyle, name: progress.name, groupName: progress.groupName) else {
            isCompleting = false
            return false
        }
        // 選んだ順ではなく候補の順で追加する。同じ名前の習慣がすでにあれば addHabit が追加しない
        for starter in starters where progress.selectedStarterIDs.contains(starter.id) {
            store.addHabit(title: starter.title, isLight: starter.isLight, repeatRule: .daily, startedAt: now)
        }
        appState.markOnboardingCompleted()
        return true
    }

    /// 下のボタン：最後のステップなら完了、それ以外は次へ
    func primaryAction() {
        if step == .habits {
            complete()
        } else {
            next()
        }
    }

    private func persist() {
        appState.saveOnboardingProgress(progress)
    }
}
