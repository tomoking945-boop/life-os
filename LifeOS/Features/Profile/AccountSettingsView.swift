import SwiftUI

/// アカウント（Mock）：名前の変更のみ。ログインは今回やらない。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// TODO: Apple Sign In / Firebase 接続時に、ログイン方法・メールアドレス・アカウント削除を追加する。
struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var draftName = ""

    var body: some View {
        SettingsScreen(title: "アカウント") {
            VStack(spacing: LifeSpacing.md) {
                LifeAvatar(name: appState.profile.name, image: appState.profileImage, size: .large)
                Text(appState.profile.name)
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
            }
            .frame(maxWidth: .infinity)

            SettingsTextField(label: "名前", text: $draftName, onCommit: commit)

            LifeGroupedSection {
                SettingsValueRow(title: "ログイン方法", value: "未設定")
            }

            SettingsNote(text: "試作版のため、ログインやアカウントの登録は行われません。名前はこの端末の中にだけ保存されます。")
        }
        .onAppear { draftName = appState.profile.name }
        .onDisappear(perform: commit)
    }

    private func commit() {
        appState.updateName(draftName)
        draftName = appState.profile.name
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
    .environment(AppState())
}
