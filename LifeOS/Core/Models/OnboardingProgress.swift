import Foundation

/// はじめての設定の途中経過（2026-10-09）。
/// 途中でアプリを終了しても、再起動後に続きから再開できるよう、端末内（AppState の設定）にだけ保存する。外部には送らない。
/// 完了したら削除する。
struct OnboardingProgress: Codable, Hashable {
    /// いまのステップ（0：ようこそ／1：使い方／2：名前／3：最初の習慣）
    var step: Int
    /// 選んだ使い方（まだ選んでいなければ nil）
    var usageStyle: UsageStyle?
    var name: String
    var groupName: String
    /// 選んだ最初の習慣（`OnboardingStarter.id`）
    var selectedStarterIDs: Set<String>

    /// 最初から始めるときの状態
    static let initial = OnboardingProgress(step: 0, usageStyle: nil, name: "", groupName: "", selectedStarterIDs: [])
}

/// はじめての設定で選べる最初の習慣（仕様の5つ）
struct OnboardingStarter: Identifiable, Hashable {
    /// 保存用の変わらない識別子
    let id: String
    let title: String
    /// 軽い習慣か（余力が「少ない」日にも出す）
    let isLight: Bool
    /// 選択タイルに出す記号
    let symbol: String

    /// 仕様の候補と扱い（すべて毎日）
    static let all: [OnboardingStarter] = [
        OnboardingStarter(id: "water", title: "水を飲む", isLight: true, symbol: "💧"),
        OnboardingStarter(id: "medicine", title: "薬を飲む", isLight: false, symbol: "💊"),
        OnboardingStarter(id: "stretch", title: "ストレッチ", isLight: true, symbol: "🧘"),
        OnboardingStarter(id: "walk", title: "散歩する", isLight: true, symbol: "🚶"),
        OnboardingStarter(id: "diary", title: "日記を書く", isLight: false, symbol: "📓")
    ]
}
