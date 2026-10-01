import SwiftUI

/// 「整理する」の結果確認画面（Mock AI）
struct QuickAddConfirmView: View {
    @Bindable var viewModel: QuickAddViewModel
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                Text(viewModel.foundText)
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    LifeSectionTitle("追加先")
                    LifeSegmentControl(Ownership.allCases, selection: $viewModel.ownership) { $0.label }
                }

                LifeCard {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                            if index > 0 {
                                LifeDivider()
                            }
                            candidateRow(candidate)
                        }
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.lg)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            LifeButton(viewModel.addButtonTitle) {
                viewModel.addSelected()
                onComplete()
            }
            .disabled(!viewModel.canAdd)
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.sm)
            .background(LifeColors.background)
        }
    }

    private func candidateRow(_ candidate: QuickAddCandidate) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.toggleCandidate(candidate.id)
            }
        } label: {
            HStack(spacing: LifeSpacing.sm) {
                Image(systemName: candidate.isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(candidate.isSelected ? LifeColors.primary : LifeColors.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(viewModel.displayTitle(for: candidate.item))
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Text(candidate.item.kind.label)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.displayTitle(for: candidate.item))、\(candidate.item.kind.label)")
        .accessibilityValue(candidate.isSelected ? "選択中" : "未選択")
        .accessibilityAddTraits(.isButton)
    }
}
