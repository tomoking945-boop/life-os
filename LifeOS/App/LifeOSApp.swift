import SwiftUI

@main
struct LifeOSApp: App {
    // 端末内に保存したデータを読み込んで始める。
    // はじめての設定（2026-10-09）：先に AppState を読み込み、初回設定が終わっていない（新しく使い始める）人は、
    // 保存データが無ければ空のデータから始める（見本の Mock データは入れない）。以前から使っている人は保存データをそのまま読む。
    @State private var appState: AppState
    @State private var store: LifeStore

    init() {
        let state = AppState.persistent()
        _appState = State(initialValue: state)
        _store = State(initialValue: LifeStore.persistent(startEmptyIfNoSavedData: !state.hasCompletedOnboarding))
        LifeAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            LifeThemedRoot()
                .environment(appState)
                .environment(store)
        }
    }
}

/// テーマとダークモード（2026-10-08）：アプリの一番外側でテーマとライト／ダークを反映する。
/// - ライト／ダーク：表示設定の選択（端末に合わせる／ライト／ダーク）
/// - テーマ：Premium で選んだテーマ（Free は Forest）。変わったときは画面を描き直して新しい色にする
///   （色はその場で決まるしくみのため、描き直しで全画面が新しいテーマになる。開いていた画面は最初の画面に戻る）
struct LifeThemedRoot: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    var body: some View {
        let theme = apply(appState.effectiveTheme)
        Group {
            // はじめての設定（2026-10-09）：終わるまでは MainTabView を作らない（一瞬でも表示しない）
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(appState: appState, store: store)
            }
        }
        .id(theme)
        .preferredColorScheme(appState.appearanceMode.colorScheme)
    }

    /// 色が参照するテーマを切り替える（描き直す前に反映する）
    private func apply(_ theme: LifeTheme) -> LifeTheme {
        if LifeThemeRuntime.theme != theme {
            LifeThemeRuntime.theme = theme
        }
        return theme
    }
}
