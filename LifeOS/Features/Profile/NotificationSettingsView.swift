import SwiftUI

/// 通知（Mock）：ON/OFF の切り替えのみ。実際の通知は送らない。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// TODO: Push通知の接続時に、通知の許可のお願いと送信処理を実装する。
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        SettingsScreen(title: "通知") {
            LifeCard(padding: LifeSpacing.md) {
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
                    SettingsToggleRow(
                        title: "共有の更新",
                        detail: "共有メンバーが追加・更新したときにお知らせします",
                        isOn: $appState.notificationSettings.sharedUpdates
                    )
                }
            }

            SettingsNote(text: "試作版のため、実際の通知は送られません。設定はアプリを閉じると元に戻ります。")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(AppState())
}
