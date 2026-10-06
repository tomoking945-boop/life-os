import SwiftUI

/// 時間帯でごく弱く変わる背景（Calm Future）。
/// Warm Ivory の上に、時間帯の色を上から薄く重ね、右上にだけ弱い光を置く。
/// 文字の可読性を優先し、画面の中ほどから下は通常の背景色のまま。
struct LifeAmbientBackground: View {
    let timeOfDay: LifeTimeOfDay

    var body: some View {
        ZStack {
            LifeColors.background
            LinearGradient(
                colors: [
                    timeOfDay.ambientWash.opacity(timeOfDay.ambientWashOpacity),
                    LifeColors.background.opacity(0)
                ],
                startPoint: .top,
                endPoint: .center
            )
            RadialGradient(
                colors: [
                    timeOfDay.ambientGlow.opacity(LifeAmbientColors.glowOpacity),
                    timeOfDay.ambientGlow.opacity(0)
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: LifeSpacing.ambientGlowRadius
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 0) {
        ForEach(LifeTimeOfDay.allCases) { timeOfDay in
            LifeAmbientBackground(timeOfDay: timeOfDay)
                .overlay(Text(timeOfDay.label).font(LifeTypography.caption))
        }
    }
}
