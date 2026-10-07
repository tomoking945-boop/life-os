import SwiftUI

/// やること画面の「買い物」に表示する、買い物専用の画面部分
/// Calm Future 第4段階：売り場ごとの一覧はカードに入れず、カテゴリー色の点と細い線で区切る。
struct ShoppingSection: View {
    @Bindable var viewModel: ShoppingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            Toggle(isOn: $viewModel.isStoreMode) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("お店モード")
                        .font(LifeTypography.bodyEmphasis)
                        .foregroundStyle(LifeColors.text)
                    Text("店内で押しやすい、大きなチェック表示にします")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .tint(LifeColors.primary)
            .frame(minHeight: LifeSpacing.minTapTarget)

            if let message = viewModel.feedbackMessage {
                // 今日画面・Inbox と同じ、すりガラスの一言
                LifeUndoBanner(message: message)
                    .transition(.opacity)
            }

            listSection

            if !viewModel.isStoreMode {
                if !viewModel.repurchaseCandidates.isEmpty {
                    repurchaseSection
                }
                frequentSection
                mealPlanLink
            }
        }
        .task(id: viewModel.feedbackMessage) {
            guard viewModel.feedbackMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            animate { viewModel.feedbackMessage = nil }
        }
    }

    private func animate(_ changes: () -> Void) {
        withLifeAnimation(reduceMotion: reduceMotion, changes)
    }

    // MARK: - 買い物リスト（売り場ごと）

    private var listSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            if viewModel.groups.isEmpty {
                LifeEmptyState(systemImage: "bag", title: "買うものはありません", message: "よく買うものから、ワンタップで追加できます。")
                    .frame(maxWidth: .infinity)
                    .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            } else {
                ForEach(viewModel.groups) { group in
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        HStack(spacing: LifeSpacing.xs) {
                            LifeCategoryDot(color: LifeCategoryColors.sage)
                            LifeSectionTitle(group.category.label, trailing: "\(group.items.count)件")
                        }
                        LifeRuledList(group.items) { item in
                            shoppingRow(item)
                        }
                    }
                }
            }

            if !viewModel.boughtItems.isEmpty {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    LifeSectionTitle("かごに入れたもの", trailing: "\(viewModel.boughtItems.count)件")
                    ForEach(viewModel.boughtItems) { item in
                        LifeTaskRow(title: item.title, isCompleted: true, tint: LifeItemKind.shopping.tint) {
                            animate { viewModel.toggle(item) }
                        }
                    }
                }
                .padding(.horizontal, LifeSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func shoppingRow(_ item: LifeItem) -> some View {
        if viewModel.isStoreMode {
            Button {
                animate { viewModel.toggle(item) }
            } label: {
                HStack(spacing: LifeSpacing.md) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.largeTitle)
                        .foregroundStyle(item.isCompleted ? LifeColors.primary : LifeCategoryColors.sage)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Text(ShoppingCategorizer.itemName(from: item.title))
                        .font(LifeTypography.editorialTitle)
                        .foregroundStyle(LifeColors.text)
                        .strikethrough(item.isCompleted, color: LifeColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: LifeSpacing.buttonHeight + LifeSpacing.md, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.isCompleted ? "かごに入れた" : "まだ")
            .accessibilityHint("ダブルタップでかごに入れたことにします")
        } else {
            LifeTaskRow(
                title: item.title,
                detail: viewModel.categoryText(for: item),
                isCompleted: item.isCompleted,
                tint: LifeItemKind.shopping.tint
            ) {
                animate { viewModel.toggle(item) }
            }
        }
    }

    // MARK: - 再購入候補

    private var repurchaseSection: some View {
        LifeEditorialCard(eyebrow: "AGAIN", title: "そろそろ買う頃", tint: LifeCategoryColors.sage) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.repurchaseCandidates.enumerated()), id: \.element.id) { index, purchase in
                    if index > 0 {
                        LifeDivider()
                    }
                    HStack(spacing: LifeSpacing.sm) {
                        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                            Text(purchase.title)
                                .font(LifeTypography.body)
                                .foregroundStyle(LifeColors.text)
                            Text("\(purchase.categoryText)・\(viewModel.lastPurchasedText(purchase))")
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: LifeSpacing.xs)
                        Button {
                            animate { viewModel.add(purchase) }
                        } label: {
                            Label("追加", systemImage: "plus")
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.text)
                                .padding(.horizontal, LifeSpacing.sm)
                                .frame(minHeight: LifeSpacing.minTapTarget)
                                .background(Capsule().fill(LifeColors.surface))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(purchase.title)を買い物に追加")
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .padding(.vertical, LifeSpacing.xxs)
                }
            }
        }
    }

    // MARK: - よく買うもの（ワンタップ追加）

    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("よく買うもの")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LifeSpacing.xs) {
                    ForEach(viewModel.frequentPurchases) { purchase in
                        let inList = viewModel.isInList(purchase)
                        LifeChip(
                            title: purchase.title,
                            systemImage: inList ? "checkmark" : "plus",
                            isSelected: inList
                        ) {
                            animate { viewModel.add(purchase) }
                        }
                        .accessibilityHint(inList ? "リストにあります" : "ワンタップで買い物に追加します")
                    }
                }
                .padding(.vertical, LifeSpacing.xxs)
            }
        }
    }

    // MARK: - 献立から作る

    private var mealPlanLink: some View {
        NavigationLink {
            MealPlanView(viewModel: viewModel)
        } label: {
            HStack(spacing: LifeSpacing.sm) {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(LifeColors.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("今週の献立から作る")
                        .font(LifeTypography.editorialHeadline)
                        .foregroundStyle(LifeColors.text)
                    Text("献立の材料を、まとめて買い物リストへ")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                Spacer(minLength: LifeSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(LifeSpacing.cardPadding)
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
