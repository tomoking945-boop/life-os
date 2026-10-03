import SwiftUI

/// 「あとで」の Bottom Sheet。詳細編集画面を開かずに、延期先を1タップで選ぶ。
struct PostponeSheet: View {
    let itemTitle: String
    let onSelect: (PostponeOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                Text("あとで")
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(itemTitle)
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }

            VStack(spacing: LifeSpacing.sm) {
                ForEach(PostponeOption.sheetOptions) { option in
                    LifeButton(option.label, systemImage: option.systemImage, kind: .secondary) {
                        onSelect(option)
                        dismiss()
                    }
                }
            }

            Text("元の日付はそのまま残ります。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
        .padding(LifeSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// 「あとで」シートを出す（item が入ったら表示）
    func postponeSheet(item: Binding<LifeItem?>, onSelect: @escaping (LifeItem, PostponeOption) -> Void) -> some View {
        sheet(item: item) { target in
            PostponeSheet(itemTitle: target.title) { option in
                onSelect(target, option)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(LifeRadius.sheet)
            .presentationBackground(LifeColors.background)
        }
    }
}

#Preview {
    PostponeSheet(itemTitle: "牛乳を買う") { _ in }
        .background(LifeColors.background)
}
