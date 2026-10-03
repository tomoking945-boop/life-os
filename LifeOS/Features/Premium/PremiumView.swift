import SwiftUI

struct PremiumView: View {
    @State private var viewModel: PremiumViewModel

    init(appState: AppState) {
        _viewModel = State(initialValue: PremiumViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                header
                featureCard
                themeSection
                trialBadge
                planOptions

                LifeButton(viewModel.ctaTitle) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.startTrial()
                    }
                }
                .disabled(viewModel.isPremium)

                Text("試作版のため、実際の購入・課金は行われません。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            Text(viewModel.title)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
            Text(viewModel.catchCopy)
                .font(LifeTypography.display)
                .foregroundStyle(LifeColors.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var featureCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                ForEach(viewModel.features, id: \.self) { feature in
                    HStack(spacing: LifeSpacing.sm) {
                        Image(systemName: "checkmark")
                            .font(LifeTypography.footnote.weight(.semibold))
                            .foregroundStyle(LifeColors.accent)
                            .accessibilityHidden(true)
                        Text(feature)
                            .font(LifeTypography.body)
                            .foregroundStyle(LifeColors.text)
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget - LifeSpacing.xs)
                }
            }
        }
    }

    // MARK: - LifeOS Themes

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            Text("THEMES")
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            Text(viewModel.themeSectionTitle)
                .font(LifeTypography.editorialHeadline)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LifeSpacing.sm) {
                    ForEach(viewModel.themes) { theme in
                        themePreview(theme)
                    }
                }
                .padding(.vertical, LifeSpacing.xxs)
            }

            Text("テーマはPremiumで使えるようになる予定です。今は見た目の確認だけで、アプリの色は変わりません。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func themePreview(_ theme: LifeTheme) -> some View {
        let isSelected = viewModel.previewTheme == theme
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.previewTheme = theme
            }
        } label: {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous)
                        .fill(theme.primary)
                        .frame(height: LifeSpacing.xxl)
                        .overlay(alignment: .bottomLeading) {
                            Text("Good morning.")
                                .font(LifeTypography.themePreviewTitle)
                                .foregroundStyle(theme.background)
                                .padding(LifeSpacing.xs)
                        }
                    HStack(spacing: LifeSpacing.xxs) {
                        LifeCategoryDot(color: theme.accent)
                        RoundedRectangle(cornerRadius: LifeSpacing.categoryBar)
                            .fill(theme.text.opacity(0.25))
                            .frame(height: LifeSpacing.xxs)
                    }
                    RoundedRectangle(cornerRadius: LifeSpacing.categoryBar)
                        .fill(theme.text.opacity(0.15))
                        .frame(width: LifeSpacing.xxl, height: LifeSpacing.xxs)
                }
                .padding(LifeSpacing.xs)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous)
                        .fill(theme.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous)
                        .stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: isSelected ? 2 : 1)
                )

                Text(theme.name)
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                Text(theme.caption)
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .frame(width: LifeSpacing.themePreviewWidth, height: LifeSpacing.themePreviewHeight + LifeSpacing.xxl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("テーマ \(theme.name)、\(theme.caption)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var trialBadge: some View {
        Text(viewModel.trialText)
            .font(LifeTypography.bodyEmphasis)
            .foregroundStyle(LifeColors.text)
            .padding(.horizontal, LifeSpacing.md)
            .padding(.vertical, LifeSpacing.xs)
            .background(Capsule().fill(LifeColors.accentSubtle))
            .frame(maxWidth: .infinity)
    }

    private var planOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: LifeSpacing.sm) {
                ForEach(viewModel.options) { option in
                    planCard(option)
                }
            }
            VStack(spacing: LifeSpacing.sm) {
                ForEach(viewModel.options) { option in
                    planCard(option)
                }
            }
        }
    }

    private func planCard(_ option: PremiumBillingOption) -> some View {
        let isSelected = viewModel.selectedOption == option
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedOption = option
            }
        } label: {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                HStack {
                    Text(option.label)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                    Spacer(minLength: LifeSpacing.xs)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? LifeColors.primary : LifeColors.divider)
                        .accessibilityHidden(true)
                }
                Text(viewModel.priceText(for: option))
                    .font(LifeTypography.amountLarge)
                    .foregroundStyle(LifeColors.text)
                if let note = option.note {
                    Text(note)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(LifeSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous)
                    .fill(LifeColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous)
                    .stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([option.label, viewModel.spokenPrice(for: option), option.note].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

#Preview {
    let appState = AppState()
    return NavigationStack {
        PremiumView(appState: appState)
    }
    .environment(appState)
}
