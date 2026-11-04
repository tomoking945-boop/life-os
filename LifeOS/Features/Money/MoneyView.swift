import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// お金。Calm Future 第4段階：今日画面の MONEY と同じ「大きな数字と予算の細い線」、一覧は細い線で区切る。
/// Build 13（2026-11-01）：支出の追加・編集・削除、「すべて／自分／共有」、表示している範囲の今月の合計とカテゴリーの合計。
/// Build 18（2026-11-02）：「レシートを読み取る」。カメラで撮る・写真から選ぶ → この iPhone の中で読み取る →
/// 候補を入れた支出の追加画面で確認・修正 → 「保存」を押したときだけ支出になる（docs/BUILD_18_RECEIPT_TO_BUDGET.md）
struct MoneyView: View {
    @State private var viewModel: MoneyViewModel
    @Environment(\.scenePhase) private var scenePhase
    /// レシートのカメラ（保証書と同じ部品。案内の文言だけ変える）
    @State private var isShowingReceiptCamera = false
    /// カメラで撮ったレシート（カメラの画面が閉じてから読み取りへ渡し、すぐに手放す）
    @State private var capturedReceipt: CapturedReceipt?
    /// 写真から選ぶ（1枚だけ）
    @State private var isShowingReceiptPhotoPicker = false
    @State private var receiptPhotoItem: PhotosPickerItem?

    private struct CapturedReceipt {
        let data: Data
        let type: UTType
    }

    init(store: LifeStore, appState: AppState) {
        _viewModel = State(initialValue: MoneyViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "MONEY", title: "お金")

                if viewModel.showsScopeFilter {
                    LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                }

                summaryCard
                VStack(spacing: LifeSpacing.sm) {
                    LifeButton("支出を追加", systemImage: "plus") {
                        viewModel.startAdding()
                    }
                    // レシートを読み取る（Build 18）。読み取り中・入力中は押せない（二重に始めない）
                    LifeButton("レシートを読み取る", systemImage: "doc.text.viewfinder", kind: .secondary) {
                        viewModel.startReceiptScan()
                    }
                    .disabled(!viewModel.canStartReceiptScan)
                    .accessibilityHint("レシートを撮るか写真から選んで、この iPhone の中で読み取ります")
                    .accessibilityIdentifier("money.scanReceipt")
                }
                categorySection
                expenseList
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .onAppear { viewModel.refreshNow() }
        // レシートの読み取り中（Build 18）。キャンセルできる
        .overlay {
            if viewModel.isReadingReceipt {
                receiptReadingCard
            }
        }
        .confirmationDialog(
            "レシートを読み取る",
            isPresented: $viewModel.isChoosingReceiptSource,
            titleVisibility: .visible
        ) {
            Button("カメラで撮る") { isShowingReceiptCamera = true }
            Button("写真から選ぶ") { isShowingReceiptPhotoPicker = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("レシート1枚を、この iPhone の中で読み取ります。写真と読み取った文字は保存しません。")
        }
        .fullScreenCover(isPresented: $isShowingReceiptCamera, onDismiss: readCapturedReceipt) {
            // カメラを使えない・許可されていないときは、保証書と同じく理由を出す（アプリは止まらない）
            WarrantyCameraView(guide: WarrantyCameraView.receiptGuide) { data, type in
                capturedReceipt = CapturedReceipt(data: data, type: type)
            }
        }
        .photosPicker(
            isPresented: $isShowingReceiptPhotoPicker,
            selection: $receiptPhotoItem,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: receiptPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadReceiptPhoto(item) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshNow() }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.draft != nil },
            set: { isPresented in if !isPresented { viewModel.cancelEditing() } }
        )) {
            if let draft = viewModel.draft {
                ExpenseEditorSheet(viewModel: viewModel, draft: draft)
                    .presentationDetents([.large])
                    .lifeSheetPresentation()
            }
        }
        .alert(
            "この支出を削除しますか？",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil && viewModel.draft == nil },
                set: { isPresented in if !isPresented { viewModel.cancelDelete() } }
            ),
            presenting: viewModel.pendingDeletion
        ) { _ in
            Button("支出を削除", role: .destructive) { viewModel.confirmDelete() }
            Button("キャンセル", role: .cancel) { viewModel.cancelDelete() }
        } message: { expense in
            Text(viewModel.deleteMessage(for: expense))
        }
    }

    // MARK: - レシートの読み取り（Build 18）

    private var receiptReadingCard: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: LifeSpacing.md) {
                ProgressView()
                    .accessibilityHidden(true)
                Text("このiPhoneの中でレシートを読み取っています…")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.text)
                    .multilineTextAlignment(.center)
                Button("キャンセル") {
                    viewModel.cancelReceiptReading()
                }
                .font(LifeTypography.button)
                .frame(minWidth: LifeSpacing.minTapTarget * 2, minHeight: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
                .accessibilityLabel("レシートの読み取りをキャンセル")
                .accessibilityIdentifier("money.cancelReceiptReading")
            }
            .padding(LifeSpacing.lg)
            .lifeSurface(.floating, cornerRadius: LifeRadius.band)
            .padding(LifeSpacing.screenHorizontal)
            .accessibilityElement(children: .contain)
        }
    }

    /// カメラの画面が閉じたら、撮ったレシートを読み取りへ渡す（ここでは持ち続けない）
    private func readCapturedReceipt() {
        guard let captured = capturedReceipt else { return }
        capturedReceipt = nil
        viewModel.readReceipt(captured.data, contentType: captured.type)
    }

    /// 選んだ写真を読み込む（PhotosPicker は別の画面で動くため、写真全体へのアクセス許可は不要）
    @MainActor
    private func loadReceiptPhoto(_ item: PhotosPickerItem) async {
        defer { receiptPhotoItem = nil }
        guard let type = item.supportedContentTypes.first(where: { WarrantyAttachmentStorage.supportedType($0) != nil }) else {
            viewModel.receiptImageFailed(.unsupportedType)
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            viewModel.receiptImageFailed(.loadFailed)
            return
        }
        viewModel.readReceipt(data, contentType: type)
    }

    // MARK: - 今月

    /// カードに入れず、大きなセリフ体の数字と細い線で見せる
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeCategoryColors.warmGold)
                LifeSectionTitle(viewModel.summaryTitle)
            }

            Text(LifeFormatters.yen(viewModel.spent))
                .font(LifeTypography.bigNumeral)
                .foregroundStyle(LifeColors.text)
                .accessibilityLabel("\(viewModel.summaryTitle) \(LifeFormatters.yenSpoken(viewModel.spent))")

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

    private var categorySection: some View {
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
            // 今月のカテゴリーごとの合計（表示している範囲）
            if !viewModel.categoryTotals.isEmpty {
                LifeRuledList(viewModel.categoryTotals) { total in
                    LifeMoneyRow(title: total.category.label, amount: total.amount)
                }
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
                    Button {
                        viewModel.startEditing(expense)
                    } label: {
                        HStack(spacing: LifeSpacing.sm) {
                            LifeCategoryDot(color: LifeCategoryColors.warmGold)
                            LifeMoneyRow(
                                title: expense.title,
                                amount: expense.amount,
                                detail: viewModel.detailText(for: expense)
                            )
                            if expense.isShared {
                                HouseholdSharedMark()
                            }
                        }
                        .padding(.vertical, LifeSpacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("編集します")
                    .contextMenu {
                        if viewModel.canDelete(expense) {
                            Button(role: .destructive) {
                                viewModel.requestDelete(expense)
                            } label: {
                                Label("支出を削除", systemImage: "trash")
                            }
                        }
                    }
                    .accessibilityAction(named: "支出を削除") {
                        viewModel.requestDelete(expense)
                    }
                }
            }
        }
    }
}

/// 支出の追加・編集（タイトル・金額・カテゴリー・日付・保存先。編集では削除も）
struct ExpenseEditorSheet: View {
    let viewModel: MoneyViewModel
    @State private var draft: ExpenseDraft
    @State private var isConfirmingDelete = false

    init(viewModel: MoneyViewModel, draft: ExpenseDraft) {
        self.viewModel = viewModel
        _draft = State(initialValue: draft)
    }

    /// 編集している支出（追加のときは nil）
    private var existing: Expense? {
        draft.isNew ? nil : viewModel.expense(id: draft.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル（必須）", text: $draft.title)
                        .accessibilityLabel("支出のタイトル")
                    TextField("金額（円）", text: $draft.amountText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("金額（円）")
                    Picker("カテゴリー", selection: $draft.category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                } footer: {
                    if !draft.amountText.isEmpty, draft.amount == nil {
                        Text("金額は 1〜999,999,999 円の数字で入れてください。")
                    } else if draft.isFromReceipt, draft.amountText.isEmpty {
                        // レシートから：金額が空のままでは保存できない（推測した金額は入れない。Build 18）
                        Text("金額を入れると保存できます（1〜999,999,999 円）。")
                    }
                }

                // 店名の候補（Build 19）。レシートから開いたときだけ。タップでタイトル欄へ入れる
                if draft.isFromReceipt, !draft.storeCandidates.isEmpty {
                    Section {
                        ForEach(draft.storeCandidates, id: \.self) { candidate in
                            Button {
                                draft.selectStoreCandidate(candidate)
                            } label: {
                                HStack(spacing: LifeSpacing.sm) {
                                    Text(candidate)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(LifeColors.text)
                                    Spacer(minLength: LifeSpacing.xs)
                                    if draft.isSelectedStoreCandidate(candidate) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(LifeColors.primary)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(minHeight: LifeSpacing.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // 省略して表示しても、VoiceOver は全文を読む
                            .accessibilityLabel(candidate)
                            .accessibilityHint("タイトルにします")
                            .accessibilityAddTraits(draft.isSelectedStoreCandidate(candidate) ? [.isSelected] : [])
                        }
                    } header: {
                        Text("店名候補")
                    } footer: {
                        Text("候補を選ぶか、上のタイトル欄に入力できます。")
                    }
                }

                // レシートから作った候補（Build 18）。保存するまで家計簿には入らない
                if draft.isFromReceipt {
                    Section {
                        ForEach(draft.receiptNotes, id: \.self) { note in
                            Text(note)
                        }
                        Text("この iPhone の中で読み取った候補です。内容を確かめて「保存」を押すと家計簿に入ります。写真と読み取った文字は保存しません。")
                            .foregroundStyle(LifeColors.secondaryText)
                    } header: {
                        Text("レシートから")
                    }
                }

                Section {
                    Picker("保存先", selection: $draft.destination) {
                        ForEach(SaveDestination.allCases) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)
                    // 選べない保存先があるときは切り替えられない（理由は下に出す）
                    .disabled(!(viewModel.canChoose(.household, in: draft) && viewModel.canChoose(.personal, in: draft)))
                } header: {
                    Text("保存先")
                } footer: {
                    Text(viewModel.destinationNote(for: draft))
                }

                if let existing, viewModel.canDelete(existing) {
                    Section {
                        Button("支出を削除", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.calendar, LifeCalendar.calendar)
            .scrollContentBackground(.hidden)
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle(draft.isFromReceipt ? "レシートから追加" : (draft.isNew ? "支出を追加" : "支出を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { viewModel.cancelEditing() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { viewModel.save(draft) }
                        .disabled(!draft.canSave)
                }
            }
            .alert("この支出を削除しますか？", isPresented: $isConfirmingDelete) {
                Button("支出を削除", role: .destructive) {
                    if let existing {
                        viewModel.requestDelete(existing)
                        viewModel.confirmDelete()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                if let existing {
                    Text(viewModel.deleteMessage(for: existing))
                }
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        MoneyView(store: store, appState: appState)
    }
    .environment(appState)
    .environment(store)
}
