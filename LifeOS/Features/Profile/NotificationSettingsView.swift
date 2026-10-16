import SwiftUI
import UIKit

/// 通知の設定。予定・やること・保証書の通知は、この iPhone の中で予約するローカル通知（外部へは送らない）。
/// 2026-10-17：予定10分前・未完了タスク20時を追加。通知の許可が未確認なら、この画面を開いたときにお願いする。
/// 「共有の更新」は、本物のパートナー同期ができるまで使えない（Push 通知は未接続）。
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store
    @Environment(\.openURL) private var openURL

    /// 通知が許可されているか（未確認なら nil）
    @State private var isAuthorized: Bool?

    /// 本物のメンバー参加が確認できるまでは、オフとして表示する（保存されている値は変えない）
    private var sharedUpdatesBinding: Binding<Bool> {
        Binding(
            get: { appState.canUseSharedUpdates && appState.notificationSettings.sharedUpdates },
            set: { appState.notificationSettings.sharedUpdates = $0 }
        )
    }

    var body: some View {
        @Bindable var appState = appState

        SettingsScreen(title: "通知") {
            LifeGroupedSection {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "今日の予定",
                        detail: "時刻のある予定の10分前にお知らせします（時刻のない予定は通知しません）",
                        isOn: $appState.notificationSettings.todaySchedule
                    )
                    LifeDivider()
                    SettingsToggleRow(
                        title: "やることのリマインド",
                        detail: "その日のやることが残っていたら、20時に1回お知らせします（習慣は除きます）",
                        isOn: $appState.notificationSettings.taskReminder
                    )
                    LifeDivider()
                    // パートナー共有（2026-10-11）：本物のメンバー参加が確認できた場合だけ使える（仕様 7-7）。
                    // まだ同期していないのに届くと誤解されないよう、それまでは切り替えられない
                    SettingsToggleRow(
                        title: "共有の更新",
                        detail: appState.canUseSharedUpdates
                            ? "共有メンバーが追加・変更したときにお知らせします"
                            : "パートナーが参加して同期が始まると使えます（いまは同期していません）",
                        isOn: sharedUpdatesBinding
                    )
                    .disabled(!appState.canUseSharedUpdates)
                    LifeDivider()
                    // 保証書管理（2026-10-13）：Premium の保証書の期限（30日前・7日前・当日 9:00）。端末内の通知
                    SettingsToggleRow(
                        title: "保証書の期限",
                        detail: "保証が終わる前にお知らせします（Premium）",
                        isOn: $appState.notificationSettings.warrantyRemindersEnabled
                    )
                }
            }

            if isAuthorized == false {
                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    SettingsNote(text: "iPhone の設定で、くらしOSの通知がオフになっています。お知らせを受け取るには、設定アプリで通知を許可してください。")
                    LifeButton("設定を開く", systemImage: "gear", kind: .secondary) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }

            SettingsNote(text: "予定・やること・保証書のお知らせは、この iPhone の中で予約します（外部のサービスには送りません）。「共有の更新」は、パートナーとの同期ができるようになるまで使えません。設定はこの端末の中に保存されます。")
        }
        .task {
            await refreshAuthorization(askIfNeeded: true)
        }
        .onChange(of: appState.notificationSettings) {
            Task { await refreshAuthorization(askIfNeeded: true) }
        }
    }

    /// 通知を使う設定があり、許可が未確認なら許可をお願いする。そのあと予約し直す
    private func refreshAuthorization(askIfNeeded: Bool) async {
        let service = LifeNotificationService.shared
        let settings = appState.notificationSettings
        let usesNotifications = settings.todaySchedule || settings.taskReminder
            || (settings.warrantyRemindersEnabled && appState.isPremium)
        if askIfNeeded && usesNotifications {
            await service.requestAuthorizationIfNeeded()
        }
        isAuthorized = await service.authorizationState()
        await service.resync(store: store, appState: appState)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(AppState())
    .environment(LifeStore())
}
