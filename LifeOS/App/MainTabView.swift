import SwiftUI

/// 下部5タブ＋全画面共通の「なんでも追加」
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                TodayView(store: store, appState: appState)
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
            .tag(AppTab.today)

            NavigationStack {
                CalendarView(store: store, appState: appState)
            }
            .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage) }
            .tag(AppTab.calendar)

            NavigationStack {
                TasksView(store: store, appState: appState)
            }
            .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.systemImage) }
            .tag(AppTab.tasks)

            NavigationStack {
                ListsView(store: store)
            }
            .tabItem { Label(AppTab.lists.title, systemImage: AppTab.lists.systemImage) }
            .tag(AppTab.lists)

            NavigationStack {
                MoneyView(store: store)
            }
            .tabItem { Label(AppTab.money.title, systemImage: AppTab.money.systemImage) }
            .tag(AppTab.money)
        }
        .tint(LifeColors.primary)
        // Free/Premium と通知設定は画面のスイッチで直接変わるため、変わったときに保存する
        .onChange(of: appState.plan) { appState.save() }
        .onChange(of: appState.notificationSettings) { appState.save() }
        .onChange(of: appState.usageStyle) { appState.save() }
        .onChange(of: appState.partnerJoined) { appState.save() }
        .sheet(isPresented: $appState.isQuickAddPresented) {
            QuickAddSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(LifeStore())
}
