import SwiftUI

@main
struct LifeOSApp: App {
    // 端末内に保存したデータを読み込んで始める（初回は Mock データ）
    @State private var appState = AppState.persistent()
    @State private var store = LifeStore.persistent()

    init() {
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

    var body: some View {
        let theme = apply(appState.effectiveTheme)
        MainTabView()
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
