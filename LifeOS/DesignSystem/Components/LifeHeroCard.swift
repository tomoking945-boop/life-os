import SwiftUI

/// 雑誌の扉のような大きなカード（Editorial Living）。
/// 今は写真を使わず、ごく弱いグラデーションと抽象的な植物の形で雰囲気を出す。
/// TODO: 将来、植物・自然光・紙や布の質感の画像素材を背景に差し替えられるようにする。
struct LifeHeroCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, minHeight: LifeSpacing.heroMinHeight, alignment: .bottomLeading)
        .padding(LifeSpacing.cardPadding)
        .background {
            ZStack {
                LinearGradient(
                    colors: [LifeColors.heroSoft, LifeColors.heroDeep],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                LifeLeafOrnament()
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LifeRadius.hero, style: .continuous))
        .lifeShadow(LifeShadow.card)
    }
}

/// 抽象的な植物の形（重ねた楕円の葉）
struct LifeLeafOrnament: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Ellipse()
                        .fill(LifeColors.heroOrnament)
                        .frame(width: size.width * 0.32, height: size.height * 0.95)
                        .rotationEffect(.degrees(Double(index) * 28 - 20), anchor: .bottom)
                        .offset(x: size.width * 0.34, y: size.height * 0.08)
                }
                Circle()
                    .stroke(LifeColors.heroOrnament, lineWidth: 1)
                    .frame(width: size.height * 0.9)
                    .offset(x: size.width * 0.42, y: -size.height * 0.36)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// 見出し付きのカード（Editorial Living）。
/// `tint` を渡すと、カテゴリー色の淡い背景になる。
struct LifeEditorialCard<Content: View>: View {
    private let eyebrow: String
    private let title: String?
    private let spokenTitle: String?
    private let tint: Color?
    private let content: Content

    init(
        eyebrow: String,
        title: String? = nil,
        spokenTitle: String? = nil,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.spokenTitle = spokenTitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            Text(eyebrow)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(title != nil)
            if let title {
                Text(title)
                    .font(LifeTypography.editorialHeadline)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityLabel(spokenTitle ?? title)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LifeSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .fill(tint.map { $0.opacity(LifeCategoryColors.subtleOpacity) } ?? LifeColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .stroke(tint == nil ? LifeColors.divider : Color.clear, lineWidth: LifeSpacing.hairline)
        )
    }
}

/// カテゴリー色の小さなドット（色だけに頼らないよう、種類の文字と一緒に使う）
struct LifeCategoryDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: LifeSpacing.categoryDot, height: LifeSpacing.categoryDot)
            .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: LifeSpacing.lg) {
            LifeHeroCard {
                Text("Good morning.")
                    .font(LifeTypography.heroTitle)
                    .foregroundStyle(LifeColors.onHero)
                Text("今日も、無理なく。")
                    .font(LifeTypography.editorialCopy)
                    .foregroundStyle(LifeColors.onHeroSecondary)
            }
            LifeEditorialCard(eyebrow: "MEMORY", title: "暮らしメモリー", tint: LifeCategoryColors.sage) {
                Text("シャンプー そろそろ買う頃です")
            }
        }
        .padding()
    }
    .background(LifeColors.background)
}
