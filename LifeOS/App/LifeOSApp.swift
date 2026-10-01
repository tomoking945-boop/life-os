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
            MainTabView()
                .environment(appState)
                .environment(store)
                // 決定済み：当面はライトモード固定（2026-10-01）。ダーク配色はデザインを詰める段階で追加する。
                .preferredColorScheme(.light)
        }
    }
}
