import SwiftUI

/// 商品明細の入力欄（Build 22）
enum LineItemEditorField: Hashable {
    case name
    case quantity
    case unitPrice
    case amount
}

/// 支出の詳細（2026-11-08 Build 21。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md）。
///
/// - 店名（タイトル）・合計金額・カテゴリー・日付・自分だけ／共有・商品明細・明細の合計・レシートの合計との比較を出す
/// - 商品明細は1件ずつ直す・消すことができる（確認の画面は出さない。保存できなければ元の内容のまま、理由を出す）
/// - 支出そのものの変更・削除は「支出を編集」から（明細の削除とは分ける）
/// - 商品明細の無い支出（以前の支出・手入力の支出）は「商品明細はありません」
struct ExpenseDetailSheet: View {
    let viewModel: MoneyViewModel
    let expenseID: Expense.ID

    /// 直している明細（1件だけ）
    @State private var editingItemID: ExpenseLineItem.ID?
    @State private var editName = ""
    @State private var editQuantity = ""
    @State private var editUnitPrice = ""
    @State private var editAmount = ""
    /// 直せなかった・消せなかった理由
    @State private var message: String?
    /// 入力中の欄（Build 22）
    @FocusState private var focusedField: LineItemEditorField?

    init(viewModel: MoneyViewModel, expenseID: Expense.ID) {
        self.viewModel = viewModel
        self.expenseID = expenseID
    }

    private var expense: Expense? { viewModel.expense(id: expenseID) }

    var body: some View {
        NavigationStack {
            Group {
                if let expense {
                    content(expense)
                } else {
                    LifeEmptyState(systemImage: "yensign.circle", title: "この支出は見つかりません")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle("支出の詳細")
            .navigationBarTitleDisplayMode(.inline)
            // Build 22：キーボードを閉じやすくする（スクロール・背景のタップ・「完了」・画面を離れたとき）
            .lifeKeyboardDismissal()
            .lifeKeyboardDoneButton { focusedField = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { viewModel.closeDetail() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
        }
    }

    private func content(_ expense: Expense) -> some View {
        let items = viewModel.lineItems(for: expense)
        return Form {
            Section {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text(expense.title)
                        .font(LifeTypography.title)
                        .foregroundStyle(LifeColors.text)
                    Text(LifeFormatters.yen(expense.amount))
                        .font(LifeTypography.amountLarge)
                        .foregroundStyle(LifeColors.text)
                }
                .padding(.vertical, LifeSpacing.xxs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(expense.title)、合計 \(LifeFormatters.yenSpoken(expense.amount))")
                LabeledContent("カテゴリー", value: expense.category.label)
                LabeledContent("日付", value: LifeFormatters.shortDate(expense.date))
                HStack(spacing: LifeSpacing.xs) {
                    Text("保存先")
                        .foregroundStyle(LifeColors.text)
                    Spacer(minLength: LifeSpacing.xs)
                    if expense.isShared {
                        HouseholdSharedMark()
                    }
                    Text(viewModel.destinationLabel(for: expense))
                        .foregroundStyle(LifeColors.secondaryText)
                }
                .frame(minHeight: LifeSpacing.minTapTarget)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("保存先 \(viewModel.destinationLabel(for: expense))")
            }

            Section {
                if items.isEmpty {
                    Text("商品明細はありません")
                        .foregroundStyle(LifeColors.secondaryText)
                } else {
                    ForEach(items) { item in
                        if editingItemID == item.id {
                            editor(for: item, in: expense)
                        } else {
                            row(for: item, in: expense)
                        }
                    }
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(LifeColors.text)
                        .accessibilityLabel(message)
                }
            } header: {
                Text("商品明細")
            } footer: {
                if !items.isEmpty, viewModel.canEditLineItems(expense) {
                    Text(expense.isShared
                         ? "明細をタップすると直せます。共有の支出の明細は、わが家のメンバーにも表示されます。"
                         : "明細をタップすると直せます。この iPhone の中だけに保存しています。")
                }
            }

            if !items.isEmpty {
                Section {
                    LifeMoneyRow(title: "商品明細の合計", amount: viewModel.lineItemsTotal(for: expense))
                    let comparison = viewModel.lineItemComparison(for: expense)
                    Label(comparison.message, systemImage: comparison.isMismatch ? "exclamationmark.triangle" : (comparison == .insufficient ? "questionmark.circle" : "checkmark.circle"))
                        .foregroundStyle(LifeColors.text)
                        .accessibilityLabel(comparison.message)
                } header: {
                    Text("レシートの合計との比較")
                }
            }

            Section {
                Button("支出を編集（タイトル・金額・保存先・削除）") {
                    viewModel.editFromDetail()
                }
                .frame(minHeight: LifeSpacing.minTapTarget)
                .accessibilityHint("詳細を閉じて、支出の編集画面を開きます")
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
    }

    /// 明細1件：商品名が主・数量と単価は補助・金額は右。タップで直す。ごみ箱で1件だけ消す
    private func row(for item: ExpenseLineItem, in expense: Expense) -> some View {
        HStack(spacing: LifeSpacing.sm) {
            Button {
                startEditing(item)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                    VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                        Text(item.name)
                            .font(LifeTypography.body)
                            .foregroundStyle(LifeColors.text)
                            .multilineTextAlignment(.leading)
                        if let detail = item.detailText {
                            Text(detail)
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                    }
                    Spacer(minLength: LifeSpacing.xs)
                    Text(LifeFormatters.yen(item.amount))
                        .font(LifeTypography.amount)
                        .foregroundStyle(LifeColors.text)
                }
                .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canEditLineItems(expense))
            .accessibilityLabel(item.spokenLabel)
            .accessibilityHint("この明細を直します")
            if viewModel.canEditLineItems(expense) {
                Button {
                    message = viewModel.deleteLineItem(item, in: expense)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name)の明細を削除")
                .accessibilityHint("この明細だけを消します。支出は消しません")
            }
        }
    }

    /// 明細1件を直す欄（「保存」で確かめてから反映。正しくなければ理由を出し、元の明細はそのまま）
    private func editor(for item: ExpenseLineItem, in expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            TextField("商品名（必須）", text: $editName)
                .focused($focusedField, equals: .name)
                .frame(minHeight: LifeSpacing.minTapTarget)
                .accessibilityLabel("商品名")
            HStack(spacing: LifeSpacing.sm) {
                TextField("数量", text: $editQuantity)
                    .focused($focusedField, equals: .quantity)
                    .keyboardType(.decimalPad)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityLabel("数量（分からなければ空）")
                TextField("単価（円）", text: $editUnitPrice)
                    .focused($focusedField, equals: .unitPrice)
                    .keyboardType(.numberPad)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityLabel("単価（円。分からなければ空）")
                TextField("金額（円）", text: $editAmount)
                    .focused($focusedField, equals: .amount)
                    .keyboardType(.numberPad)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityLabel("金額（円）")
            }
            HStack(spacing: LifeSpacing.sm) {
                Button("やめる") {
                    editingItemID = nil
                    message = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(LifeColors.secondaryText)
                .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
                Spacer(minLength: LifeSpacing.xs)
                Button("保存") {
                    let error = viewModel.updateLineItem(
                        item, in: expense,
                        name: editName, quantityText: editQuantity, unitPriceText: editUnitPrice, amountText: editAmount
                    )
                    message = error
                    if error == nil { editingItemID = nil }
                }
                .buttonStyle(.plain)
                .foregroundStyle(LifeColors.primary)
                .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
                .accessibilityHint("この明細の変更を保存します")
            }
        }
    }

    private func startEditing(_ item: ExpenseLineItem) {
        editingItemID = item.id
        editName = item.name
        editQuantity = item.quantity.map(ExpenseLineItemRules.text(for:)) ?? ""
        editUnitPrice = item.unitPrice.map(String.init) ?? ""
        editAmount = String(item.amount)
        message = nil
    }
}
