import SwiftUI

/// 中身が仕様未定の設定項目（アカウント / 生活グループ / 通知 / 表示設定）の仮画面
/// TODO: 各画面の内容は仕様未定。Apple Sign In・Push通知などは今回やらない。
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
