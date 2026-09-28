import SwiftUI

/// 共有メンバー一覧
/// TODO: メンバーの招待・削除は仕様未定のため未実装。
struct MembersView: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeSectionTitle(appState.profile.groupName, trailing: "\(appState.profile.members.count)人")
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
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("共有メンバー")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}
