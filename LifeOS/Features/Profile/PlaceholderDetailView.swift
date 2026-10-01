import SwiftUI

/// 中身が未定の画面の仮表示（2026-10-01 時点で未使用。今後の仮画面用に残している）
struct PlaceholderDetailView: View {
    let title: String

    var body: some View {
        ScrollView {
            LifeCard {
                LifeEmptyState(
                    systemImage: "hammer",
                    title: "準備中です",
                    message: "「\(title)」の内容は今後追加します。"
                )
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}
