import SwiftUI

/// 小さな選択チップ（すぐ追加 / 支出カテゴリーなど）
struct LifeChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LifeSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(LifeTypography.callout)
            .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.text)
            .padding(.horizontal, LifeSpacing.md)
            .frame(minHeight: LifeSpacing.minTapTarget)
            .background(Capsule().fill(isSelected ? LifeColors.primary : LifeColors.surface))
            .overlay(Capsule().stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    HStack {
        LifeChip(title: "ToDo", systemImage: "checkmark.circle", isSelected: true) {}
        LifeChip(title: "予定", systemImage: "calendar") {}
    }
    .padding()
    .background(LifeColors.background)
}
