import SwiftUI

/// 開発用設定：Free / Premium の切り替えと、保存データの初期化
/// TODO: リリース前に削除、または DEBUG ビルドのみ表示にする。
struct DeveloperSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    @State private var isConfirmingReset = false
    @State private var didReset = false

    /// 自動＋朝・昼・夕方・夜
    private let ambientOptions: [LifeTimeOfDay?] = [nil] + LifeTimeOfDay.allCases.map { Optional($0) }

    var body: some View {
        @Bindable var appState = appState

        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("プラン（Mock）")
                    LifeSegmentControl(PlanType.allCases, selection: $appState.plan) { $0.label }
                }

                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("利用スタイル（Mock）")
                    LifeSegmentControl(UsageStyle.allCases, selection: $appState.usageStyle) { style in
                        style == .solo ? "ひとり" : "家族・パートナー"
                    }
                    Toggle("パートナー参加済み", isOn: $appState.partnerJoined)
                        .font(LifeTypography.body)
                        .tint(LifeColors.primary)
                        .disabled(appState.usageStyle == .solo)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                    Text("ひとり：共有を前面に出さず「すべて / 自分 / 共有」を隠します。家族・パートナー：共有ボタンを出し、未参加なら招待画面を出します。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("時間帯の背景（確認用）")
                    LifeSegmentControl(ambientOptions, selection: $appState.ambientPreview) { option in
                        option?.label ?? "自動"
                    }
                    Text("今日画面の背景と挨拶を、時間帯ごとに確かめられます。保存はされず、アプリを終了すると「自動」に戻ります。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LifeGroupedSection {
                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        Text("Free：今日画面に広告カードを1枠表示します。")
                        Text("Premium：広告カードを表示しません。")
                        Text("StoreKit には接続していません。")
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.text)
                    .padding(.vertical, LifeSpacing.sm)
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
        .lifeScreenBackground()
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
