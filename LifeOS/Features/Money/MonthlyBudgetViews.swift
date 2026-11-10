import SwiftUI

// 月の予算のカードと入力の画面（2026-11-10 Build 24。docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md）
//
// - 「すべて」では、自分だけの予算とわが家の共有予算を別々のカードで出す（足して1つにしない）
// - 使った割合は控えめな細い線。上回っても強い赤・強い警告にしない（「予算を○円上回っています」と文字で出す）
// - 色だけで状態を伝えない（残り・上回り・未設定を文字でも出す）。VoiceOver で読める。押す場所は 44pt 以上
// - 「1日あたりの目安」は、残りの予算を残りの日数で割った参考の値（使い方のおすすめ・お金の助言ではない）

/// 予算のカード（1つの予算：自分だけ、またはわが家で共有）
struct MonthlyBudgetCard: View {
    let viewModel: MoneyViewModel
    let summary: MonthlyBudgetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: summary.scope == .personal ? LifeCategoryColors.warmGold : LifeCategoryColors.sage)
                LifeSectionTitle(summary.scope.budgetTitle, trailing: summary.scope.label)
                if summary.scope == .household {
                    HouseholdSharedMark()
                }
            }

            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text("使った金額")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(LifeFormatters.yen(summary.spent))
                    .font(LifeTypography.bigNumeral)
                    .foregroundStyle(LifeColors.text)
            }
            .accessibilityHidden(true)

            if let plan = summary.plan {
                ProgressView(value: summary.barRatio)
                    .tint(LifeCategoryColors.warmGold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    LifeDivider()
                    LifeMoneyRow(title: "予算", amount: plan.totalAmount)
                    LifeDivider()
                    if let overAmount = summary.overAmount {
                        LifeMoneyRow(title: "予算を上回った金額", amount: overAmount)
                    } else {
                        LifeMoneyRow(title: "残り", amount: summary.remaining ?? 0)
                    }
                    LifeDivider()
                }
                .accessibilityHidden(true)
                Text(detailLine)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                if let daily = summary.dailyAllowance {
                    Text("1日あたりの目安 \(LifeFormatters.yen(daily))（残り\(summary.daysRemaining)日。残りの予算を日数で割った参考の値です）")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            } else {
                Text("予算は未設定です")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityHidden(true)
            }

            if viewModel.canEditBudget(summary.scope) {
                LifeButton(buttonTitle, systemImage: summary.hasBudget ? "pencil" : "plus", kind: .secondary) {
                    viewModel.startEditingBudget(summary.scope)
                }
                .accessibilityHint(summary.scope == .personal ? "自分だけの予算を設定します。この iPhone の中だけに保存します" : "わが家の共有予算を設定します。わが家のメンバーにも表示されます")
            }
            Text(viewModel.budgetNote(for: summary.scope))
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.categoryLines.isEmpty {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text("カテゴリー別")
                        .font(LifeTypography.label)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    LifeRuledList(summary.categoryLines) { line in
                        categoryRow(line)
                    }
                }
            }
        }
        .padding(LifeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(viewModel.budgetSpokenLabel(summary))
    }

    private var buttonTitle: String {
        if summary.hasBudget { return "予算を変更" }
        return viewModel.isShowingCurrentMonth ? "今月の予算を設定" : "\(summary.month.title)の予算を設定"
    }

    /// 残り・上回り・使用割合（色だけに頼らず文字で）
    private var detailLine: String {
        var parts = [summary.statusText]
        if let percent = summary.usagePercentText { parts.append("使用割合 \(percent)") }
        if summary.daysRemaining > 0, viewModel.isShowingCurrentMonth { parts.append("残り\(summary.daysRemaining)日") }
        return parts.joined(separator: "・")
    }

    /// カテゴリー1つ：名前・使った金額（右寄せ）。予算があれば予算・残り・割合と細い線。無ければ使った金額だけ
    private func categoryRow(_ line: BudgetCategoryLine) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                Text(line.category.label)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                Spacer(minLength: LifeSpacing.xs)
                Text(LifeFormatters.yen(line.spent))
                    .font(LifeTypography.amount)
                    .foregroundStyle(LifeColors.text)
            }
            if let budget = line.budget {
                Text(Self.categoryDetail(line, budget: budget))
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                if let ratio = line.usageRatio {
                    ProgressView(value: min(max(ratio, 0), 1))
                        .tint(LifeCategoryColors.warmGold)
                }
            } else {
                Text("予算は未設定（使った金額だけ）")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
        .padding(.vertical, LifeSpacing.xxs)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.categorySpokenLabel(line))
    }

    /// 「予算 ¥30,000・残り ¥12,000・60%」「予算 ¥0・予算を¥500上回っています」
    static func categoryDetail(_ line: BudgetCategoryLine, budget: Int) -> String {
        var parts = ["予算 \(LifeFormatters.yen(budget))"]
        if let remaining = line.remaining {
            parts.append(remaining < 0 ? "予算を\(LifeFormatters.yen(-remaining))上回っています" : "残り \(LifeFormatters.yen(remaining))")
        }
        if let ratio = line.usageRatio { parts.append("\(Int(min(ratio * 100, 1_000_000).rounded()))%") }
        return parts.joined(separator: "・")
    }
}

/// 予算の入力欄
enum BudgetEditorField: Hashable {
    case total
    case category(ExpenseCategory)
}

/// 月の予算・カテゴリーの予算の入力（保存・キャンセルは1回のタップ。正しくなければ理由を出し、保存しない）
struct MonthlyBudgetEditorSheet: View {
    let viewModel: MoneyViewModel
    @State private var draft: MonthlyBudgetDraft
    /// 「保存」で断られた理由
    @State private var message: String?
    @State private var isConfirmingRemoval = false
    /// 入力中の欄（Build 22 と同じ方法でキーボードを閉じる）
    @FocusState private var focusedField: BudgetEditorField?

    init(viewModel: MoneyViewModel, draft: MonthlyBudgetDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("月の予算（円・必須）", text: $draft.totalText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .total)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("月の予算（円）")
                        .accessibilityHint("1円から999,999,999円までの整数で入れます")
                } header: {
                    Text("\(draft.month.title)・\(draft.scope.budgetTitle)")
                } footer: {
                    Text(draft.scope == .personal
                         ? "自分だけの予算は、この iPhone の中だけに保存します。自分だけの支出だけを数えます。"
                         : "わが家の共有予算は、わが家のメンバーにも表示され、メンバーなら変えられます。共有の支出だけを数えます。")
                }

                Section {
                    ForEach(ExpenseCategory.allCases) { category in
                        HStack(spacing: LifeSpacing.sm) {
                            Text(category.label)
                                .foregroundStyle(LifeColors.text)
                            Spacer(minLength: LifeSpacing.xs)
                            TextField("未設定", text: Binding(
                                get: { draft.text(for: category) },
                                set: { draft.categoryTexts[category] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .category(category))
                            .frame(minWidth: LifeSpacing.minTapTarget * 2, minHeight: LifeSpacing.minTapTarget)
                            .accessibilityLabel("\(category.label)の予算（円。空なら未設定）")
                        }
                    }
                } header: {
                    Text("カテゴリー別の予算（任意）")
                } footer: {
                    Text("空のカテゴリーは未設定（使った金額だけを出します）。0円も設定できます。カテゴリーの予算の合計 \(LifeFormatters.yen(draft.enteredCategoryTotal)) は、月の予算以下にしてください。")
                }

                if let problem = message ?? draft.problem?.message, !draft.totalText.isEmpty || message != nil {
                    Section {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .foregroundStyle(LifeColors.text)
                            .accessibilityLabel(problem)
                    }
                }

                if let previous = viewModel.previousMonthPlan(for: draft) {
                    Section {
                        Button("前月の予算をコピー") {
                            draft.fill(from: previous)
                            message = nil
                        }
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityHint("前月（\(draft.month.previous.title)）の予算を欄に入れます。「保存」を押すまで保存しません")
                    } footer: {
                        Text("予算は翌月へ自動ではコピーしません。")
                    }
                }

                if draft.isExisting {
                    Section {
                        Button("この月の予算を解除", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                        .frame(minHeight: LifeSpacing.minTapTarget)
                    } footer: {
                        Text("解除しても、支出は消えません。")
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .scrollContentBackground(.hidden)
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle(draft.isExisting ? "予算を変更" : "予算を設定")
            .navigationBarTitleDisplayMode(.inline)
            .lifeKeyboardDismissal()
            .lifeKeyboardDoneButton { focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { viewModel.cancelBudgetEditing() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        focusedField = nil
                        message = viewModel.saveBudget(draft)?.message
                    }
                }
            }
            .confirmationDialog("この月の予算を解除しますか？", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("予算を解除", role: .destructive) {
                    message = viewModel.removeBudget(draft)?.message
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(draft.month.title)の\(draft.scope.budgetTitle)（カテゴリー別も）を解除します。支出は消えません。")
            }
        }
    }
}
