import SwiftUI

/// 小さな気づきのカード（Calm Future）。
/// 暮らしメモリーなどを、横スクロールで静かに並べるときに使う。
/// 上辺にカテゴリー色の細い光を置く（色だけに頼らず、タイトルで内容が分かるようにする）。
struct LifeInsightCard<Actions: View>: View {
    private let title: String
    private let message: String
    private let detail: String?
    private let tint: Color
    private let actions: Actions

    init(
        title: String,
        message: String,
        detail: String? = nil,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.detail = detail
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                HStack(spacing: LifeSpacing.xs) {
                    LifeCategoryDot(color: tint)
                    Text(title)
                        .font(LifeTypography.footnoteEmphasis)
                        .foregroundStyle(LifeColors.text)
                }
                Text(message)
                    .font(LifeTypography.editorialCopy)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
            actions
        }
        .padding(LifeSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(tint)
                .frame(width: LifeSpacing.insightAccentLength, height: LifeSpacing.categoryBar)
                .padding(.leading, LifeSpacing.md)
                .accessibilityHidden(true)
        }
        .lifeSurface(.normal, cornerRadius: LifeRadius.insight)
    }
}

extension LifeInsightCard where Actions == EmptyView {
    init(title: String, message: String, detail: String? = nil, tint: Color) {
        self.init(title: title, message: message, detail: detail, tint: tint) { EmptyView() }
    }
}

/// LifeOS からの短い提案（Calm Future）。
/// AI チャットを常設せず、短い提案と2つの選択肢だけを出す。
/// 「今日はそのまま」を選べば何も変えない。理由も一緒に見せる。
struct LifeSuggestionCard: View {
    private let eyebrow: String
    private let message: String
    private let reason: String?
    private let primaryTitle: String
    private let primarySystemImage: String?
    private let onPrimary: () -> Void
    private let secondaryTitle: String?
    private let onSecondary: (() -> Void)?

    init(
        eyebrow: String = "LifeOSからの提案",
        message: String,
        reason: String? = nil,
        primaryTitle: String,
        primarySystemImage: String? = nil,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = "今日はそのまま",
        onSecondary: (() -> Void)? = nil
    ) {
        self.eyebrow = eyebrow
        self.message = message
        self.reason = reason
        self.primaryTitle = primaryTitle
        self.primarySystemImage = primarySystemImage
        self.onPrimary = onPrimary
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                HStack(spacing: LifeSpacing.xs) {
                    LifeCategoryDot(color: LifeColors.accent)
                    Text(eyebrow)
                        .font(LifeTypography.label)
                        .tracking(LifeTypography.labelTracking)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                Text(message)
                    .font(LifeTypography.editorialCopy)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LifeSpacing.xs) {
                    buttons
                }
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    buttons
                }
            }
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.suggestion)
    }

    @ViewBuilder
    private var buttons: some View {
        LifeCapsuleButton(primaryTitle, systemImage: primarySystemImage, isProminent: true, action: onPrimary)
        if let secondaryTitle, let onSecondary {
            LifeCapsuleButton(secondaryTitle, action: onSecondary)
        }
    }
}

/// 小さなカプセル型のボタン（Calm Future）。
/// 全幅の LifeButton ほど強くしたくない操作に使う。タップ領域は 44pt 以上。
struct LifeCapsuleButton: View {
    private let title: String
    private let systemImage: String?
    private let isProminent: Bool
    private let isFullWidth: Bool
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isProminent: Bool = false,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isProminent = isProminent
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LifeSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(LifeTypography.footnoteEmphasis)
            .foregroundStyle(isProminent ? LifeColors.onPrimary : LifeColors.text)
            .padding(.horizontal, LifeSpacing.md)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: LifeSpacing.minTapTarget)
            .background(Capsule().fill(isProminent ? LifeColors.primary : LifeColors.surface))
            .overlay(Capsule().stroke(isProminent ? LifeColors.primary : LifeColors.divider, lineWidth: LifeSpacing.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(LifePressButtonStyle())
    }
}

#Preview {
    ScrollView {
        VStack(spacing: LifeSpacing.lg) {
            LifeInsightCard(title: "シャンプー", message: "そろそろ買う頃です", detail: "前回から7週間", tint: LifeCategoryColors.sage) {
                LifeCapsuleButton("買い物に追加", systemImage: "plus") {}
            }
            .frame(width: LifeSpacing.insightCardWidth)
            LifeSuggestionCard(
                message: "今日は予定が多いため、「エアコン掃除」を土曜へ移すと余裕ができます。",
                reason: "今日は予定が3つあります",
                primaryTitle: "移動する",
                onPrimary: {},
                onSecondary: {}
            )
        }
        .padding()
    }
    .background(LifeAmbientBackground(timeOfDay: .day))
}
