import SwiftUI

/// 表示設定（Mock）：決定済みの表示ルールを確認できる画面。
/// 決定済み：見た目だけの画面を用意する（2026-10-01）。
/// TODO: ダークモード対応や週の始まりを利用者が選べるようにするかは、デザインを詰める段階で決める。
struct DisplaySettingsView: View {
    var body: some View {
        SettingsScreen(title: "表示設定") {
            LifeGroupedSection {
                VStack(spacing: 0) {
                    SettingsValueRow(title: "テーマ", value: "ライト")
                    LifeDivider()
                    SettingsValueRow(title: "週の始まり", value: "日曜日")
                    LifeDivider()
                    SettingsValueRow(title: "文字の大きさ", value: "iPhoneの設定に合わせる")
                }
            }

            SettingsNote(text: "文字の大きさは、iPhoneの「設定」→「画面表示と明るさ」→「テキストサイズを変更」で変えられます。")
        }
    }
}

#Preview {
    NavigationStack {
        DisplaySettingsView()
    }
    .environment(AppState())
}
