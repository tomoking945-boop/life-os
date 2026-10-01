import SwiftUI

@main
struct LifeOSApp: App {
    @State private var appState = AppState()
    @State private var store = LifeStore()

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
