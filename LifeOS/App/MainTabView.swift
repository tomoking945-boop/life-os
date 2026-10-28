import SwiftUI

/// 下部5タブ＋全画面共通の「なんでも追加」
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Firebase の「わが家」（招待・参加・設定はすべてここ。2026-10-28）
    private let household = HouseholdService.live
    /// わが家で共有する ToDo・買い物（2026-10-28 Build 7）
    private let sharedItems = SharedItemsService.live
    /// サインインの状態（サインイン・サインアウト・アカウント削除で、わが家を読み直す）
    private let auth = AuthService.live

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
        // Firebase の「わが家」（2026-10-28）：人数は「今日」の招待のカードに、groupID と種類は共有 ToDo・買い物の見張りに使う。
        // 退出・削除・サインアウトでわが家が無くなったら、共有項目の表示だけを消す（端末の個人データは消さない）
        .onAppear { sharedItems.attach(store) }
        .onChange(of: household.state) { applyHousehold() }
        .task(id: auth.account != nil) {
            await household.refresh()
            applyHousehold()
        }
        // 起動時・予定やタスクや保証書の変更時・プランや通知設定の変更時に、通知を予約し直す（2026-10-13・10-17）
        .task(id: notificationSyncKey) {
            await LifeNotificationService.shared.resync(store: store, appState: appState)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await LifeNotificationService.shared.resync(store: store, appState: appState) }
        }
        .onChange(of: scenePhase) { _, phase in
            // アプリに戻ったとき、わが家の設定（パートナーが変えた共有する種類など）を読み直す
            guard phase == .active, auth.account != nil else { return }
            Task { await household.refresh() }
        }
        .sheet(isPresented: $appState.isQuickAddPresented) {
            QuickAddSheet(store: store)
                .presentationDetents([.medium, .large])
                .lifeSheetPresentation()
        }
    }
}

extension MainTabView {
    /// わが家の情報を、招待のカードと共有項目の見張りへ伝える
    private func applyHousehold() {
        switch household.state {
        case .loaded(let summary):
            appState.householdMemberCount = summary.members.count
            sharedItems.apply(household: summary)
        case .none, .signedOut, .unavailable:
            appState.householdMemberCount = nil
            sharedItems.apply(household: nil)
        case .idle, .loading, .failed:
            // 読み込み中・通信できないときは、いまの表示のまま（勝手に消さない）
            break
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(LifeStore())
}
