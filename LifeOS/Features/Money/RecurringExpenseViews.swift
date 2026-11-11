import SwiftUI

// 固定費・定期支出の一覧と設定の画面（2026-11-11 Build 25。docs/BUILD_25_RECURRING_EXPENSES.md）
//
// - 「お金」の画面の、予算のカードの下・「支出を追加」の上に出す
// - 支出は自動で作らない。「今月分を追加」→ ふつうの支出の確認画面で「保存」を押したときだけ支出を1件作る
// - 状態（未確認・追加済み・今月は追加しない・停止中）は色だけでなく文字で出す。押す場所は 44pt 以上。VoiceOver で読める
// - 名前・金額はログに出さない

/// 定期支出のまとまり（「すべて」は自分だけ・わが家で共有を分けて出す）
struct RecurringExpensesSection: View {
    let viewModel: MoneyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("定期支出", trailing: viewModel.displayedMonth.title)
                .accessibilityAddTraits(.isHeader)
            ForEach(viewModel.recurringScopes, id: \.self) { scope in
                RecurringScopeCard(viewModel: viewModel, scope: scope)
            }
            if let message = viewModel.recurringMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
                    .accessibilityIdentifier("money.recurring.message")
            }
            LifeButton("定期支出を登録", systemImage: "arrow.triangle.2.circlepath", kind: .secondary) {
                viewModel.startAddingRecurring()
            }
            .accessibilityHint("家賃・通信費・サブスクなど、毎月くり返す支出を登録します。支出は自動では作りません")
            .accessibilityIdentifier("money.recurring.add")
        }
    }
}

/// 1つのまとまり（自分だけ、またはわが家で共有）
private struct RecurringScopeCard: View {
    let viewModel: MoneyViewModel
    let scope: BudgetScope

    var body: some View {
        let rows = viewModel.recurringRows(for: scope)
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: scope == .personal ? LifeCategoryColors.warmGold : LifeCategoryColors.sage)
                Text(scope.label)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                if scope == .household {
                    HouseholdSharedMark()
                }
            }
            if rows.isEmpty {
                Text("登録した定期支出はありません")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget, alignment: .leading)
            } else {
                ForEach(rows) { row in
                    LifeDivider()
                    RecurringRowView(viewModel: viewModel, row: row)
                }
                LifeDivider()
            }
            Text(viewModel.recurringNote(for: scope))
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LifeSpacing.md)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
    }
}

/// 1行：名前・状態（文字）・目安金額・支払日と、操作のボタン
private struct RecurringRowView: View {
    let viewModel: MoneyViewModel
    let row: RecurringRow

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(row.template.title)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.text)
                        .lineLimit(2)
                    Text("\(row.stateText)・\(viewModel.recurringDueText(row))・\(row.template.category.label)")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                Spacer(minLength: LifeSpacing.xs)
                Text("目安 \(LifeFormatters.yen(row.template.expectedAmount))")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.recurringSpokenLabel(row))
            .accessibilityIdentifier("money.recurring.row")

            actions
        }
        .padding(.vertical, LifeSpacing.xxs)
    }

    @ViewBuilder
    private var actions: some View {
        let canAct = viewModel.canActOnRecurring(row.template)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LifeSpacing.xs) { actionButtons(canAct: canAct) }
            VStack(alignment: .leading, spacing: 0) { actionButtons(canAct: canAct) }
        }
    }

    @ViewBuilder
    private func actionButtons(canAct: Bool) -> some View {
        if let candidate = row.candidate {
            switch candidate.state {
            case .unconfirmed:
                actionButton("今月分を追加", identifier: "money.recurring.addThisMonth", hint: "支出の確認画面を開きます。「保存」を押すまで支出は作りません") {
                    viewModel.startRecurringExpense(candidate)
                }
                .disabled(!viewModel.canAddRecurring(candidate))
                actionButton("今月は追加しない", identifier: "money.recurring.skip", hint: "確認のあと、この月の支出を作らないことにします。あとで取り消せます") {
                    viewModel.confirmRecurringSkip(candidate)
                }
                .disabled(!canAct)
            case .skipped:
                actionButton("未確認に戻す", identifier: "money.recurring.undoSkip", hint: "「今月は追加しない」を取り消します") {
                    viewModel.undoRecurringSkip(candidate)
                }
                .disabled(!canAct)
            case .created:
                EmptyView()
            }
        }
        if canAct {
            actionButton("編集", identifier: "money.recurring.edit", hint: "未確認の月と、これから先の候補に反映します。作った支出は変わりません") {
                viewModel.startEditingRecurring(row.template)
            }
            if row.template.isActive {
                actionButton("停止", identifier: "money.recurring.pause", hint: "新しい月の候補を出さなくなります。作った支出と記録は消えません") {
                    viewModel.pauseRecurring(row.template)
                }
            } else {
                actionButton("再開", identifier: "money.recurring.resume", hint: "今月から候補を出します") {
                    viewModel.resumeRecurring(row.template)
                }
            }
        }
    }

    private func actionButton(_ title: String, identifier: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(LifeTypography.footnote)
            .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
            .contentShape(Rectangle())
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
    }
}

/// 設定の入力の欄（Build 22 と同じ方法でキーボードを閉じる）
enum RecurringEditorField: Hashable {
    case title
    case amount
}

/// 定期支出の設定（名前・目安金額・カテゴリー・支払日・開始月・保存先）。保存するまで設定は変わらない
struct RecurringExpenseEditorSheet: View {
    let viewModel: MoneyViewModel
    @State private var draft: RecurringExpenseDraft
    /// 「保存」で断られた理由
    @State private var message: String?
    @FocusState private var focusedField: RecurringEditorField?

    init(viewModel: MoneyViewModel, draft: RecurringExpenseDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    /// 開始月に選べる月（今月の12か月前〜24か月後。2000年1月〜2099年12月の中だけ）
    private var startMonths: [BudgetMonth] {
        let current = BudgetMonth(date: viewModel.now)
        var months: [BudgetMonth] = []
        var month = current
        for _ in 0..<12 where month.previous.isStorable { month = month.previous }
        for _ in 0..<37 {
            if month.isStorable { months.append(month) }
            month = month.next
        }
        if !months.contains(draft.startMonth), draft.startMonth.isStorable {
            months.append(draft.startMonth)
            months.sort()
        }
        return months
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前（必須。例：家賃）", text: $draft.title)
                        .focused($focusedField, equals: .title)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("定期支出の名前")
                        .accessibilityHint("80文字以内。改行は使えません")
                        .accessibilityIdentifier("money.recurring.title")
                    TextField("目安金額（円・必須）", text: $draft.amountText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amount)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("目安金額（円）")
                        .accessibilityHint("1円から999,999,999円までの整数で入れます")
                        .accessibilityIdentifier("money.recurring.amount")
                    Picker("カテゴリー", selection: $draft.category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    Picker("支払日", selection: $draft.dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("毎月\(day)日").tag(day)
                        }
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityIdentifier("money.recurring.dueDay")
                    Picker("開始月", selection: $draft.startMonth) {
                        ForEach(startMonths) { month in
                            Text(month.title).tag(month)
                        }
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityIdentifier("money.recurring.startMonth")
                } footer: {
                    Text("その日が無い月（2月の30日など）は、その月の最終日にします。開始月より前の月には候補を出しません。")
                }

                Section {
                    if draft.isNew {
                        Picker("保存先", selection: $draft.destination) {
                            ForEach(SaveDestination.allCases) { destination in
                                Text(destination.title).tag(destination)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!viewModel.canChooseHouseholdRecurring)
                        .accessibilityIdentifier("money.recurring.destination")
                    } else {
                        Text(draft.destination.title)
                            .foregroundStyle(LifeColors.text)
                            .frame(minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                    }
                } header: {
                    Text("保存先")
                } footer: {
                    Text(viewModel.recurringDestinationNote(for: draft))
                }

                if let problem = message ?? (draft.title.isEmpty && draft.amountText.isEmpty ? nil : draft.problem?.message) {
                    Section {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .foregroundStyle(LifeColors.text)
                            .accessibilityLabel(problem)
                            .accessibilityIdentifier("money.recurring.problem")
                    }
                }

                Section {
                    Text("支出は自動では作りません。毎月「今月分を追加」を押して、内容を確かめてから保存します。通知は送りません。")
                        .foregroundStyle(LifeColors.secondaryText)
                    if !draft.isNew {
                        Text("編集は、未確認の月と、これから先の候補にだけ反映します。作った支出は変わりません。")
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .scrollContentBackground(.hidden)
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle(draft.isNew ? "定期支出を登録" : "定期支出を編集")
            .navigationBarTitleDisplayMode(.inline)
            .lifeKeyboardDismissal()
            .lifeKeyboardDoneButton { focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { viewModel.cancelRecurringEditing() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        focusedField = nil
                        message = viewModel.saveRecurring(draft)?.message
                    }
                    .accessibilityIdentifier("money.recurring.save")
                }
            }
        }
    }
}
