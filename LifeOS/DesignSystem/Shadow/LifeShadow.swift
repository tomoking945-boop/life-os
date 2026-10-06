import SwiftUI

/// 影の定義。影はかなり弱く、上品に。
struct LifeShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum LifeShadow {
    /// カード
    static let card = LifeShadowStyle(color: LifeColors.shadow, radius: 18, x: 0, y: 6)
    /// 浮いているボタン（なんでも追加）
    static let floating = LifeShadowStyle(color: LifeColors.floatingShadow, radius: 14, x: 0, y: 6)
    /// 影なし（Calm Future の Surface で、奥行きを付けない面に使う）
    static let flat = LifeShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    /// 少しだけ浮かせる（Calm Future：提案・浮遊する面）
    static let lifted = LifeShadowStyle(color: LifeColors.shadow, radius: 24, x: 0, y: 10)
}

extension View {
    /// DesignSystem の影を適用する
    func lifeShadow(_ style: LifeShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
