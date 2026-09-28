import SwiftUI

/// ネイティブ広告を想定した Mock 広告カード（Free のみ表示）。
/// TODO: AdMob 接続は今回やらない。広告の中身・タップ時の動作は仕様未定。
struct MockAdCard: View {
    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                Text("PR")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.text)
                    .padding(.horizontal, LifeSpacing.xs)
                    .padding(.vertical, LifeSpacing.xxs)
                    .background(Capsule().fill(LifeColors.accentSubtle))
                Text("広告スペース")
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PR、広告スペース")
    }
}

#Preview {
    MockAdCard()
        .padding()
        .background(LifeColors.background)
}
