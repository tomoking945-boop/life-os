import SwiftUI

/// 表示設定。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// テーマとダークモード（2026-10-08）：ライト／ダーク（端末に合わせる／ライト／ダーク）を選べるようにした。
/// カラーテーマは Premium の機能のため、ここでは今のテーマを表示し、Premium 画面へ案内する。
/// TODO: 週の始まりを利用者が選べるようにするかは未定。
struct DisplaySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SettingsScreen(title: "表示設定") {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("ライト / ダーク")
                LifeSegmentControl(LifeAppearanceMode.allCases, selection: appearanceBinding) { $0.label }
                SettingsNote(text: "「端末に合わせる」は、iPhoneの「設定」→「画面表示と明るさ」に合わせて切り替わります。")
            }

            LifeGroupedSection {
                VStack(spacing: 0) {
                    ProfileLinkRow(title: "カラーテーマ", value: appState.effectiveTheme.name) {
                        PremiumView(appState: appState)
                    }
                    LifeDivider()
                    SettingsValueRow(title: "週の始まり", value: "日曜日")
                    LifeDivider()
                    SettingsValueRow(title: "文字の大きさ", value: "iPhoneの設定に合わせる")
                }
            }

            SettingsNote(text: appState.isPremium
                         ? "カラーテーマは Premium 画面で選べます。"
                         : "カラーテーマは Premium で選べます。Free では Forest を使います。")
            SettingsNote(text: "文字の大きさは、iPhoneの「設定」→「画面表示と明るさ」→「テキストサイズを変更」で変えられます。")
        }
    }

    private var appearanceBinding: Binding<LifeAppearanceMode> {
        Binding(
            get: { appState.appearanceMode },
            set: { appState.setAppearanceMode($0) }
        )
    }
}

#Preview {
    NavigationStack {
        DisplaySettingsView()
    }
    .environment(AppState())
    .environment(LifeStore())
}
