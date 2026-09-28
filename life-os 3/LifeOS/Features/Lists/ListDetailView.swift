import SwiftUI

/// リスト詳細
/// TODO: リスト内の項目の追加・編集・並び替えは仕様未定のため未実装（現状は表示のみ）。
struct ListDetailView: View {
    let list: LifeList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                if let list {
                    Text(list.title)
                        .font(LifeTypography.display)
                        .foregroundStyle(LifeColors.text)
                        .accessibilityAddTraits(.isHeader)

                    LifeCard {
                        if list.items.isEmpty {
                            LifeEmptyState(systemImage: "list.bullet", title: "まだ項目がありません")
                        } else {
                            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                                ForEach(list.items) { item in
                                    Text(item.title)
                                        .font(LifeTypography.body)
                                        .foregroundStyle(LifeColors.text)
                                        .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                                }
                            }
                        }
                    }
                } else {
                    LifeEmptyState(systemImage: "exclamationmark.circle", title: "リストが見つかりません")
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}

#Preview {
    NavigationStack {
        ListDetailView(list: LifeList(title: "行きたい場所"))
    }
    .environment(AppState())
}
