import SwiftUI

/// 生活グループ（Mock）：グループ名の変更とメンバーの確認。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// メンバーの招待は v2 の「1タップ家族招待」の Mock 画面を開く。
/// TODO: 本物の招待・メンバーの削除・グループの切り替えは Firebase 接続時に実装する。
struct GroupSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store
    @State private var draftName = ""
    @State private var isShowingInviteNotice = false

    var body: some View {
        SettingsScreen(title: "生活グループ") {
            SettingsTextField(label: "グループ名", text: $draftName, onCommit: commit)

            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("メンバー", trailing: "\(appState.profile.members.count)人")
                LifeCard(padding: LifeSpacing.md) {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.profile.members.enumerated()), id: \.element.id) { index, member in
                            if index > 0 {
                                LifeDivider()
                            }
                            HStack(spacing: LifeSpacing.sm) {
                                LifeAvatar(
                                    name: member.name,
                                    image: member.isCurrentUser ? appState.profileImage : nil,
                                    size: .medium
                                )
                                Text(member.name)
                                    .font(LifeTypography.body)
                                    .foregroundStyle(LifeColors.text)
                                if member.isCurrentUser {
                                    Text("自分")
                                        .font(LifeTypography.caption)
                                        .foregroundStyle(LifeColors.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, LifeSpacing.xs)
                            .frame(minHeight: LifeSpacing.buttonHeight)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            LifeButton("メンバーを招待", systemImage: "person.badge.plus", kind: .secondary) {
                isShowingInviteNotice = true
            }

            SettingsNote(text: "試作版のため、グループ名はこの端末の中にだけ保存されます。")
        }
        .onAppear { draftName = appState.profile.groupName }
        .onDisappear(perform: commit)
        .sheet(isPresented: $isShowingInviteNotice) {
            // v2：1タップ家族招待の Mock 画面（実際の招待は送らない）
            SharingFlowView(item: nil, store: store)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
        }
    }

    private func commit() {
        appState.updateGroupName(draftName)
        draftName = appState.profile.groupName
    }
}

#Preview {
    NavigationStack {
        GroupSettingsView()
    }
    .environment(AppState())
    .environment(LifeStore())
}
