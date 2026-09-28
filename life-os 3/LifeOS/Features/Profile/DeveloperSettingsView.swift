import SwiftUI

/// 開発用設定：Free / Premium を Mock で切り替える
/// TODO: リリース前に削除、または DEBUG ビルドのみ表示にする。
struct DeveloperSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("プラン（Mock）")
                    LifeSegmentControl(PlanType.allCases, selection: $appState.plan) { $0.label }
                }

                LifeCard {
                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        Text("Free：今日画面に広告カードを1枠表示します。")
                        Text("Premium：広告カードを表示しません。")
                        Text("StoreKit には接続していません。")
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.text)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("開発用設定")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
    .environment(AppState())
}
