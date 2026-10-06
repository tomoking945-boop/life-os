import SwiftUI

/// 操作のあとに静かに現れる一言と「元に戻す」（Calm Future）。
/// すりガラスの面に浮かべる。強い色・警告色は使わない。
/// `onUndo` が nil のときは一言だけを出す。
struct LifeUndoBanner: View {
    let message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: LifeSpacing.sm) {
            Image(systemName: "checkmark")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.primary)
                .accessibilityHidden(true)
            Text(message)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LifeSpacing.xs)
            if let onUndo {
                Button(action: onUndo) {
                    Text("元に戻す")
                        .font(LifeTypography.footnoteEmphasis)
                        .foregroundStyle(LifeColors.primary)
                        .padding(.horizontal, LifeSpacing.sm)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("直前の操作を取り消します")
            }
        }
        .padding(.leading, LifeSpacing.md)
        .padding(.trailing, onUndo == nil ? LifeSpacing.md : LifeSpacing.xxs)
        .padding(.vertical, LifeSpacing.xxs)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .lifeGlassSurface(cornerRadius: LifeRadius.medium)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: LifeSpacing.md) {
        LifeUndoBanner(message: "「ゴミ出し」を明日に回しました") {}
        LifeUndoBanner(message: "元に戻しました")
    }
    .padding()
    .background(LifeAmbientBackground(timeOfDay: .morning))
}
