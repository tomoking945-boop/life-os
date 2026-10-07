import SwiftUI

/// 将来機能「献立 → 買い物」の UI プロトタイプ（v2 仕様 12）。
/// 献立は固定データ。［買い物リストを作成］で材料を出し、選んだものを買い物に追加する。
/// Calm Future 第4段階：時間帯の背景、献立は紙色の面に曜日をセリフ体で並べる。
struct MealPlanView: View {
    let viewModel: ShoppingViewModel

    @State private var generated: [String] = []
    @State private var selected: Set<String> = []
    @State private var resultMessage: String?

    private let plan = MockData.mealPlan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.xl) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("MEAL PLAN")
                        .font(LifeTypography.label)
                        .tracking(LifeTypography.labelTracking)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                    Text("今週の献立")
                        .font(LifeTypography.editorialTitle)
                        .foregroundStyle(LifeColors.text)
                        .accessibilityAddTraits(.isHeader)
                }

                LifeGroupedSection {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(plan.enumerated()), id: \.element.id) { index, day in
                            if index > 0 {
                                LifeDivider()
                            }
                            HStack(spacing: LifeSpacing.md) {
                                Text(day.dayLabel)
                                    .font(LifeTypography.editorialHeadline)
                                    .foregroundStyle(LifeColors.accent)
                                    .frame(width: LifeSpacing.xl)
                                Text(day.dish)
                                    .font(LifeTypography.body)
                                    .foregroundStyle(LifeColors.text)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: LifeSpacing.buttonHeight)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(day.dayLabel)曜日、\(day.dish)")
                        }
                    }
                }

                LifeButton("買い物リストを作成", systemImage: "sparkles", kind: generated.isEmpty ? .primary : .secondary) {
                    withLifeAnimation(reduceMotion: reduceMotion) {
                        generated = plan.flatMap(\.ingredients)
                        selected = Set(generated)
                        resultMessage = nil
                    }
                }

                if !generated.isEmpty {
                    generatedSection
                }

                Text("試作版のため、献立と材料は固定です。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .navigationTitle("献立")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var generatedSection: some View {
        LifeEditorialCard(eyebrow: "SHOPPING", title: "材料", tint: LifeCategoryColors.sage) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(generated, id: \.self) { name in
                    let isOn = selected.contains(name)
                    Button {
                        if isOn { selected.remove(name) } else { selected.insert(name) }
                    } label: {
                        HStack(spacing: LifeSpacing.sm) {
                            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(isOn ? LifeColors.primary : LifeColors.secondaryText)
                                .accessibilityHidden(true)
                            Text(name)
                                .font(LifeTypography.body)
                                .foregroundStyle(LifeColors.text)
                            Spacer(minLength: 0)
                            Text(ShoppingCategorizer.categories(for: name).map(\.label).joined(separator: " / "))
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityValue(isOn ? "選択中" : "未選択")
                }
            }

            LifeButton("\(selected.count)件を買い物に追加", systemImage: "bag") {
                let names = generated.filter { selected.contains($0) }
                let added = viewModel.addFromMealPlan(names)
                resultMessage = added == names.count
                    ? "\(added)件を追加しました"
                    : "\(added)件を追加しました（リストにあるものは除きました）"
            }
            .disabled(selected.isEmpty)

            if let message = resultMessage {
                Text(message)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.text)
            }
        }
    }
}
