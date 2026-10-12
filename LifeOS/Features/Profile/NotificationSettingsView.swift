import SwiftUI

/// 通知（Mock）：ON/OFF の切り替えのみ。実際の通知は送らない。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// TODO: Push通知の接続時に、通知の許可のお願いと送信処理を実装する。
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

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
                        detail: "予定の前にお知らせします",
                        isOn: $appState.notificationSettings.todaySchedule
                    )
                    LifeDivider()
                    SettingsToggleRow(
                        title: "やることのリマインド",
                        detail: "未完了のやることをお知らせします",
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

            SettingsNote(text: "「保証書の期限」は、この iPhone の中で実際にお知らせします。そのほかの通知は試作版のため送られません。設定はこの端末の中に保存されます。")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(AppState())
}
