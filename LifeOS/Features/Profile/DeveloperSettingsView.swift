import SwiftUI

/// 開発用設定：Free / Premium の切り替えと、保存データの初期化
/// TODO: リリース前に削除、または DEBUG ビルドのみ表示にする。
struct DeveloperSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    @State private var isConfirmingReset = false
    @State private var didReset = false

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

                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("保存データ")
                    LifeButton("データを初期化", systemImage: "arrow.counterclockwise", kind: .destructive) {
                        isConfirmingReset = true
                    }
                    Text(didReset
                         ? "初期化しました。今日の日付のMockデータに戻っています。"
                         : "やること・予定・お金・リスト・名前・生活グループ・通知を、今日の日付のMockデータに戻します。プランとプロフィール写真はそのままです。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("開発用設定")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
        .confirmationDialog("データを初期化しますか？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("初期化する", role: .destructive) {
                store.resetToMock()
                appState.resetSettingsToMock()
                didReset = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("追加したやることやリストの項目は消えます。元には戻せません。")
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperSettingsView()
    }
    .environment(AppState())
    .environment(LifeStore())
}
