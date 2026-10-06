import SwiftUI

/// 面の奥行きの段階（Calm Future）。
/// 白いカードを並べるのではなく、用途に合わせて面の強さを変える。
enum LifeSurfaceLevel {
    /// 背景面の切り替え（紙色・影なし）。セクションをカードにせず、面だけで区切る
    case sunken
    /// 通常の面（白・細い線・弱い影）
    case normal
    /// 浮遊する面（少し強い影）
    case floating
    /// 選択中の面（Deep Forest をごく薄く）
    case selected
    /// LifeOS からの提案の面（Brass をごく薄く）
    case suggestion
}

/// 面の見た目
struct LifeSurfaceStyle {
    let fill: Color
    let stroke: Color
    let shadow: LifeShadowStyle
}

extension LifeSurfaceLevel {
    var style: LifeSurfaceStyle {
        switch self {
        case .sunken:
            return LifeSurfaceStyle(fill: LifeColors.paper, stroke: .clear, shadow: LifeShadow.flat)
        case .normal:
            return LifeSurfaceStyle(fill: LifeColors.surface, stroke: LifeColors.divider, shadow: LifeShadow.card)
        case .floating:
            return LifeSurfaceStyle(fill: LifeColors.surface, stroke: LifeColors.divider, shadow: LifeShadow.lifted)
        case .selected:
            return LifeSurfaceStyle(fill: LifeColors.selectedSurface, stroke: LifeColors.selectedStroke, shadow: LifeShadow.flat)
        case .suggestion:
            return LifeSurfaceStyle(fill: LifeColors.suggestionSurface, stroke: LifeColors.suggestionStroke, shadow: LifeShadow.flat)
        }
    }
}

extension LifeColors {
    /// 選択中の面
    static let selectedSurface = primary.opacity(0.06)
    static let selectedStroke = primary.opacity(0.22)
    /// 提案の面（Brass をごく薄く）
    static let suggestionSurface = accent.opacity(0.08)
    static let suggestionStroke = accent.opacity(0.30)
    /// ガラスの面に重ねる白
    static let glassTint = surface.opacity(0.55)
    /// ガラスの面の縁
    static let glassStroke = divider
}

extension View {
    /// DesignSystem の面（奥行きの段階）を適用する
    func lifeSurface(_ level: LifeSurfaceLevel, cornerRadius: CGFloat = LifeRadius.card) -> some View {
        let style = level.style
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(style.fill))
            .overlay(shape.stroke(style.stroke, lineWidth: LifeSpacing.hairline))
            .lifeShadow(style.shadow)
    }

    /// すりガラスの面（Calm Future）。
    /// 「透明度を下げる」がオンのときは、透けない白い面にする。
    func lifeGlassSurface(cornerRadius: CGFloat = LifeRadius.card) -> some View {
        modifier(LifeGlassSurface(cornerRadius: cornerRadius))
    }
}

/// すりガラスの面。浮かんで現れる表示（元に戻す など）に使う。
struct LifeGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                if reduceTransparency {
                    shape.fill(LifeColors.surface)
                } else {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(LifeColors.glassTint)
                    }
                }
            }
            .overlay(shape.stroke(LifeColors.glassStroke, lineWidth: LifeSpacing.hairline))
            .lifeShadow(LifeShadow.floating)
    }
}

#Preview {
    VStack(spacing: LifeSpacing.md) {
        Text("sunken").frame(maxWidth: .infinity).padding().lifeSurface(.sunken)
        Text("normal").frame(maxWidth: .infinity).padding().lifeSurface(.normal)
        Text("floating").frame(maxWidth: .infinity).padding().lifeSurface(.floating)
        Text("selected").frame(maxWidth: .infinity).padding().lifeSurface(.selected)
        Text("suggestion").frame(maxWidth: .infinity).padding().lifeSurface(.suggestion)
        Text("glass").frame(maxWidth: .infinity).padding().lifeGlassSurface()
    }
    .padding()
    .background(LifeAmbientBackground(timeOfDay: .evening))
}
