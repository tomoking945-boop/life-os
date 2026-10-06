import SwiftUI

/// 細いタイムラインの1区間（Calm Future の Living Timeline）。
/// 左に細い線と点、右に見出し（NOW / 10:30 / ON THE WAY HOME）と中身を置く。
/// 点の色はカテゴリー色。色だけに頼らず、見出しの文字で置き場所が分かるようにする。
struct LifeTimelineSection<Content: View>: View {
    private let eyebrow: String
    private let japaneseLabel: String?
    private let spokenLabel: String
    private let tint: Color
    private let isTime: Bool
    private let isCurrent: Bool
    private let isLast: Bool
    private let content: Content

    /// - Parameters:
    ///   - eyebrow: 小さな見出し（NOW / 10:30 / ON THE WAY HOME）
    ///   - japaneseLabel: 見出しに添える日本語（いま / 帰宅時）
    ///   - spokenLabel: VoiceOver で読む見出し
    ///   - tint: 点の色（カテゴリー色）
    ///   - isTime: 見出しが時刻か（時刻はセリフ体で少し大きく）
    ///   - isCurrent: 「いま」の区間か（点のまわりに細い輪を付ける）
    ///   - isLast: 最後の区間か（下に線を伸ばさない）
    init(
        eyebrow: String,
        japaneseLabel: String? = nil,
        spokenLabel: String,
        tint: Color,
        isTime: Bool = false,
        isCurrent: Bool = false,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.japaneseLabel = japaneseLabel
        self.spokenLabel = spokenLabel
        self.tint = tint
        self.isTime = isTime
        self.isCurrent = isCurrent
        self.isLast = isLast
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: LifeSpacing.md) {
            rail
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                header
                content
            }
            .padding(.bottom, isLast ? 0 : LifeSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 線を中身の高さまで伸ばすため、縦だけ中身に合わせる
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rail: some View {
        VStack(spacing: 0) {
            ZStack {
                if isCurrent {
                    Circle()
                        .stroke(tint.opacity(LifeTimelineStyle.ringOpacity), lineWidth: LifeSpacing.timelineLine)
                        .frame(width: LifeSpacing.timelineRing, height: LifeSpacing.timelineRing)
                }
                Circle()
                    .fill(tint)
                    .frame(width: LifeSpacing.timelineDot, height: LifeSpacing.timelineDot)
            }
            .frame(width: LifeSpacing.timelineRail, height: LifeSpacing.timelineMarkerHeight)

            Rectangle()
                .fill(isLast ? Color.clear : LifeColors.divider)
                .frame(width: LifeSpacing.timelineLine)
                .frame(maxHeight: .infinity)
        }
        .frame(width: LifeSpacing.timelineRail)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.xs) {
            Text(eyebrow)
                .font(isTime ? LifeTypography.timelineTime : LifeTypography.label)
                .tracking(isTime ? 0 : LifeTypography.labelTracking)
                .foregroundStyle(isCurrent || isTime ? LifeColors.text : LifeColors.secondaryText)
            if let japaneseLabel {
                Text(japaneseLabel)
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
        .frame(minHeight: LifeSpacing.timelineMarkerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isHeader)
    }
}

/// タイムラインの見た目の数値
enum LifeTimelineStyle {
    /// 「いま」の輪の濃さ
    static let ringOpacity: Double = 0.45
    /// 「余力があれば」など、控えめな区間の点の色
    static let quietDot = LifeColors.secondaryText.opacity(0.4)
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        LifeTimelineSection(eyebrow: "NOW", japaneseLabel: "いま", spokenLabel: "いま", tint: LifeCategoryColors.terracotta, isCurrent: true) {
            Text("ゴミ出し").font(LifeTypography.body)
        }
        LifeTimelineSection(eyebrow: "10:30", spokenLabel: "10:30", tint: LifeCategoryColors.mistBlue, isTime: true) {
            Text("歯医者").font(LifeTypography.body)
        }
        LifeTimelineSection(eyebrow: "ON THE WAY HOME", japaneseLabel: "帰宅時", spokenLabel: "帰宅時", tint: LifeCategoryColors.sage, isLast: true) {
            Text("牛乳を買う").font(LifeTypography.body)
        }
    }
    .padding()
    .background(LifeAmbientBackground(timeOfDay: .morning))
}
