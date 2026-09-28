import SwiftUI

/// 表示するものがないときの案内
struct LifeEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: LifeSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(LifeColors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(LifeTypography.headline)
                .foregroundStyle(LifeColors.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LifeSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LifeEmptyState(systemImage: "checkmark.circle", title: "やることはありません", message: "ゆっくり過ごしましょう。")
        .background(LifeColors.background)
}
