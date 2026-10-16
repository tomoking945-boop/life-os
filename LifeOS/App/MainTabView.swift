import SwiftUI

/// 下部5タブ＋全画面共通の「なんでも追加」
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    /// 通知を予約し直すきっかけ（予定・タスク・保証書・プラン・通知設定が変わったとき）
    private struct NotificationSyncKey: Equatable {
        let items: [LifeItem]
        let warranties: [WarrantyDocument]
        let isPremium: Bool
        let settings: NotificationSettings
    }

    private var notificationSyncKey: NotificationSyncKey {
        NotificationSyncKey(
            items: store.items,
            warranties: store.warranties,
            isPremium: appState.isPremium,
            settings: appState.notificationSettings
        )
    }

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
        // 起動時・予定やタスクや保証書の変更時・プランや通知設定の変更時に、通知を予約し直す（2026-10-13・10-17）
        .task(id: notificationSyncKey) {
            await LifeNotificationService.shared.resync(store: store, appState: appState)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await LifeNotificationService.shared.resync(store: store, appState: appState) }
        }
        .sheet(isPresented: $appState.isQuickAddPresented) {
            QuickAddSheet(store: store)
                .presentationDetents([.medium, .large])
                .lifeSheetPresentation()
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(LifeStore())
}
