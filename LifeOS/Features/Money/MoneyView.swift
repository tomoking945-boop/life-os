import SwiftUI

/// お金。Calm Future 第4段階：今日画面の MONEY と同じ「大きな数字と予算の細い線」、一覧は細い線で区切る。
struct MoneyView: View {
    @State private var viewModel: MoneyViewModel

    init(store: LifeStore) {
        _viewModel = State(initialValue: MoneyViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "MONEY", title: "お金")

                summaryCard
                categoryChips
                expenseList
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
    }

    // MARK: - 今月

    /// カードに入れず、大きなセリフ体の数字と細い線で見せる
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeCategoryColors.warmGold)
                LifeSectionTitle("今月の支出")
            }

            Text(LifeFormatters.yen(viewModel.spent))
                .font(LifeTypography.bigNumeral)
                .foregroundStyle(LifeColors.text)
                .accessibilityLabel("今月の支出 \(LifeFormatters.yenSpoken(viewModel.spent))")

            ProgressView(value: viewModel.usageRatio)
                .tint(LifeCategoryColors.warmGold)
                .accessibilityLabel("予算の使用率")
                .accessibilityValue(viewModel.usagePercentText)

            VStack(alignment: .leading, spacing: 0) {
                LifeDivider()
                LifeMoneyRow(title: "予算", amount: viewModel.budget)
                LifeDivider()
                LifeMoneyRow(title: "残り", amount: viewModel.remaining)
                LifeDivider()
            }
            .padding(.top, LifeSpacing.xs)
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
            if viewModel.expenses.isEmpty {
                LifeEmptyState(systemImage: "yensign.circle", title: "支出はありません")
                    .frame(maxWidth: .infinity)
                    .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            } else {
                LifeRuledList(viewModel.expenses) { expense in
                    HStack(spacing: LifeSpacing.sm) {
                        LifeCategoryDot(color: LifeCategoryColors.warmGold)
                        LifeMoneyRow(
                            title: expense.title,
                            amount: expense.amount,
                            detail: viewModel.detailText(for: expense)
                        )
                    }
                    .padding(.vertical, LifeSpacing.xxs)
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
