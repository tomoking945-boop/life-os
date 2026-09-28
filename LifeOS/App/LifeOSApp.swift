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
                // TODO: ダークモードの配色は仕様未定のため、ライトモードに固定している。
                .preferredColorScheme(.light)
        }
    }
}
