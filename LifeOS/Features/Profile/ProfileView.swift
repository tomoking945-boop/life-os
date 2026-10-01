import SwiftUI

/// プロフィール（「今日」画面右上のプロフィール画像から開く）
struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @Environment(AppState.self) private var appState

    init(appState: AppState) {
        _viewModel = State(initialValue: ProfileViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                photoSection

                LifeCard(padding: LifeSpacing.md) {
                    VStack(spacing: 0) {
                        ProfileLinkRow(title: "アカウント") {
                            AccountSettingsView()
                        }
                        LifeDivider()
                        ProfileLinkRow(title: "生活グループ", value: viewModel.groupName) {
                            GroupSettingsView()
                        }
                        LifeDivider()
                        ProfileLinkRow(title: "共有メンバー", value: viewModel.memberCountText) {
                            MembersView(appState: appState)
                        }
                    }
                }

                LifeCard(padding: LifeSpacing.md) {
                    VStack(spacing: 0) {
                        ProfileLinkRow(title: "通知") {
                            NotificationSettingsView()
                        }
                        LifeDivider()
                        ProfileLinkRow(title: "表示設定") {
                            DisplaySettingsView()
                        }
                    }
                }

                LifeCard(padding: LifeSpacing.md) {
                    VStack(spacing: 0) {
                        ProfileLinkRow(title: "Premium", value: viewModel.planLabel) {
                            PremiumView(appState: appState)
                        }
                        LifeDivider()
                        ProfileLinkRow(title: "開発用設定", value: "Free / Premium 切替") {
                            DeveloperSettingsView()
                        }
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }

    private var photoSection: some View {
        VStack(spacing: LifeSpacing.md) {
            LifeAvatar(name: viewModel.name, image: appState.profileImage, size: .extraLarge)
            Text(viewModel.name)
                .font(LifeTypography.title)
                .foregroundStyle(LifeColors.text)
            NavigationLink {
                PhotoChangeView()
            } label: {
                Text("写真を変更")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.primary)
                    .padding(.horizontal, LifeSpacing.md)
                    .frame(minHeight: LifeSpacing.minTapTarget)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// プロフィールの1行（タップで遷移）
struct ProfileLinkRow<Destination: View>: View {
    let title: String
    var value: String?
    let destination: () -> Destination

    init(title: String, value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) {
        self.title = title
        self.value = value
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: LifeSpacing.sm) {
                Text(title)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                Spacer(minLength: LifeSpacing.xs)
                if let value {
                    Text(value)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LifeSpacing.xs)
            .frame(minHeight: LifeSpacing.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let appState = AppState()
    return NavigationStack {
        ProfileView(appState: appState)
    }
    .environment(appState)
}
