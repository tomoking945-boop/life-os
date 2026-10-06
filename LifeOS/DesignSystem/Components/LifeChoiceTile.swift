import SwiftUI

/// 小さな選択タイル（Calm Future）。
/// 記号（絵文字）を上、文字を下に置くので、3つ並べても文字が切れにくい。
/// 選択中は Deep Forest の面にし、色だけでなく「選択中」の読み上げでも分かるようにする。
struct LifeChoiceTile: View {
    let symbol: String
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: LifeSpacing.xxs) {
                Text(symbol)
                    .font(LifeTypography.headline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(LifeTypography.footnoteEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.text)
            .padding(.horizontal, LifeSpacing.xs)
            .padding(.vertical, LifeSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous)
                    .fill(isSelected ? LifeColors.primary : LifeColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous)
                    .stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: LifeSpacing.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous))
        }
        .buttonStyle(LifePressButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    HStack(spacing: LifeSpacing.xs) {
        LifeChoiceTile(symbol: "😮‍💨", title: "少ない") {}
        LifeChoiceTile(symbol: "🙂", title: "普通", isSelected: true) {}
        LifeChoiceTile(symbol: "💪", title: "余裕あり") {}
    }
    .padding()
    .background(LifeColors.paper)
}
