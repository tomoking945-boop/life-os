import SwiftUI

/// セクション見出し（NEXT / TODAY / SHARED / MONEY など）
struct LifeSectionTitle: View {
    private let title: String
    private let trailing: String?
    private let spokenTitle: String?

    /// - Parameters:
    ///   - title: 表示する見出し
    ///   - trailing: 右側に添える補足テキスト
    ///   - spokenTitle: VoiceOver で読み上げる見出し（英字ラベルに日本語の意味を添える場合など）
    init(_ title: String, trailing: String? = nil, spokenTitle: String? = nil) {
        self.title = title
        self.trailing = trailing
        self.spokenTitle = spokenTitle
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityLabel(spokenTitle ?? title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LifeSpacing.xs)
            if let trailing {
                Text(trailing)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
    }
}

#Preview {
    LifeSectionTitle("TODAY", trailing: "3件", spokenTitle: "今日のやること")
        .padding()
        .background(LifeColors.background)
}
