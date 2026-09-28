import SwiftUI

/// 大きめの角丸・弱い影のカード。
struct LifeCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = LifeSpacing.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .fill(LifeColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline)
        )
        .lifeShadow(LifeShadow.card)
    }
}

/// カード内の区切り線
struct LifeDivider: View {
    var body: some View {
        Rectangle()
            .fill(LifeColors.divider)
            .frame(height: LifeSpacing.hairline)
            .accessibilityHidden(true)
    }
}

#Preview {
    LifeCard {
        Text("LifeCard")
            .font(LifeTypography.body)
    }
    .padding()
    .background(LifeColors.background)
}
