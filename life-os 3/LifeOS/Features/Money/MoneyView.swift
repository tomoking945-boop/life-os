import SwiftUI

struct MoneyView: View {
    @State private var viewModel: MoneyViewModel

    init(store: LifeStore) {
        _viewModel = State(initialValue: MoneyViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                Text("お金")
                    .font(LifeTypography.display)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)

                summaryCard
                categoryChips
                expenseList
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
    }

    // MARK: - 今月

    private var summaryCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.md) {
                LifeSectionTitle("今月")

                LifeMoneyRow(title: "支出", amount: viewModel.spent, isEmphasized: true)

                ProgressView(value: viewModel.usageRatio)
                    .tint(LifeColors.primary)
                    .accessibilityLabel("予算の使用率")
                    .accessibilityValue(viewModel.usagePercentText)

                LifeDivider()
                LifeMoneyRow(title: "予算", amount: viewModel.budget)
                LifeDivider()
                LifeMoneyRow(title: "残り", amount: viewModel.remaining)
            }
        }
    }

    // MARK: - カテゴリー

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("カテゴリー")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LifeSpacing.xs) {
                    LifeChip(title: "すべて", isSelected: viewModel.selectedCategory == nil) {
                        viewModel.select(nil)
                    }
                    ForEach(viewModel.categories) { category in
                        LifeChip(title: category.label, isSelected: viewModel.selectedCategory == category) {
                            viewModel.select(category)
                        }
                    }
                }
                .padding(.vertical, LifeSpacing.xxs)
            }
        }
    }

    // MARK: - 支出一覧

    private var expenseList: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("支出一覧", trailing: "\(viewModel.expenses.count)件")
            LifeCard {
                if viewModel.expenses.isEmpty {
                    LifeEmptyState(systemImage: "yensign.circle", title: "支出はありません")
                } else {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        ForEach(Array(viewModel.expenses.enumerated()), id: \.element.id) { index, expense in
                            if index > 0 {
                                LifeDivider()
                            }
                            LifeMoneyRow(
                                title: expense.title,
                                amount: expense.amount,
                                detail: viewModel.detailText(for: expense)
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        MoneyView(store: store)
    }
    .environment(appState)
    .environment(store)
}
