import SwiftUI

/// ボタンの種類
enum LifeButtonKind {
    /// 主要アクション（primary 塗り）
    case primary
    /// 副次アクション（白地＋枠線）
    case secondary
    /// 削除など注意が必要な操作
    case destructive
}

/// ボタンの見た目だけを描く View。
/// PhotosPicker など、Button 以外のコントロールのラベルとしても使う。
struct LifeButtonLabel: View {
    let title: String
    var systemImage: String?
    var kind: LifeButtonKind = .primary
    var isFullWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: LifeSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(LifeTypography.button)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, LifeSpacing.lg)
        .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: LifeSpacing.buttonHeight)
        .background(Capsule().fill(backgroundColor))
        .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: return LifeColors.onPrimary
        case .secondary: return LifeColors.primary
        case .destructive: return LifeColors.text
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary: return LifeColors.primary
        case .secondary, .destructive: return LifeColors.surface
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return LifeColors.primary
        case .secondary, .destructive: return LifeColors.divider
        }
    }
}

/// 生活OS の標準ボタン
struct LifeButton: View {
    private let title: String
    private let systemImage: String?
    private let kind: LifeButtonKind
    private let isFullWidth: Bool
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        kind: LifeButtonKind = .primary,
        isFullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            LifeButtonLabel(title: title, systemImage: systemImage, kind: kind, isFullWidth: isFullWidth)
        }
        .buttonStyle(LifePressButtonStyle())
    }
}

/// 押下時に少しだけ沈む控えめなボタンスタイル
struct LifePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: LifeSpacing.md) {
        LifeButton("整理する") {}
        LifeButton("音声入力", systemImage: "mic", kind: .secondary) {}
        LifeButton("現在の写真を削除", systemImage: "trash", kind: .destructive) {}
    }
    .padding()
    .background(LifeColors.background)
}
