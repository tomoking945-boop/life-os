import SwiftUI

/// 生活OS のセグメント切り替え（すべて / 自分 / 共有 など）
struct LifeSegmentControl<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option
    private let title: (Option) -> String

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: LifeSpacing.xxs) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(LifeSpacing.xxs)
        .background(Capsule().fill(LifeColors.surface))
        .overlay(Capsule().stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline))
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(isSelected ? LifeTypography.bodyEmphasis : LifeTypography.body)
                .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, LifeSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(LifeColors.primary)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    LifeSegmentControl(["すべて", "自分", "共有"], selection: .constant("すべて")) { $0 }
        .padding()
        .background(LifeColors.background)
}
