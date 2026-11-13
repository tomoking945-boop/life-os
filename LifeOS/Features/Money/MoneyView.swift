import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// お金。Calm Future 第4段階：今日画面の MONEY と同じ「大きな数字と予算の細い線」、一覧は細い線で区切る。
/// Build 13（2026-11-01）：支出の追加・編集・削除、「すべて／自分／共有」、表示している範囲の今月の合計とカテゴリーの合計。
/// Build 18（2026-11-02）：「レシートを読み取る」。カメラで撮る・写真から選ぶ → この iPhone の中で読み取る →
/// 候補を入れた支出の追加画面で確認・修正 → 「保存」を押したときだけ支出になる（docs/BUILD_18_RECEIPT_TO_BUDGET.md）
/// Build 20：カメラは、使えるときは iOS の書類スキャン（輪郭の検出・傾きの補正・切り抜き）。使えないときは今までのカメラ。
/// 合計金額の候補・商品明細（確認用）を確認画面に出す（docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md）
/// Build 21：確認画面に残っている商品明細を支出と一緒に保存する。支出をタップすると詳細画面を開き、
/// 商品明細を見返し・直し・消すことができる（docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md）
/// Build 23：画面上部の検索欄で、店名・支出のタイトル・商品名から支出を探す（端末に読み込んである支出と明細だけを調べる）。
/// すべて／自分／共有・月・カテゴリーで絞り込める（docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md）
/// Build 24：上部に月の予算のカード（自分だけ／わが家で共有を別々に）と月の切り替え。カテゴリー別の予算は縦の一覧
/// （docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md）
/// Build 26：予算のカードの下に「月次レポート」のカード。「詳しく見る」で前月との差・最近6か月の推移・カテゴリー別を見る。
/// カテゴリー・「支出一覧を見る」からは、下の支出一覧を月・カテゴリーで絞り込んで見せる（docs/BUILD_26_MONTHLY_SPENDING_REPORT.md）
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
    /// 書類スキャン（Build 20）
    @State private var isShowingReceiptScanner = false
    /// 書類スキャンで撮ったレシート（画面が閉じてから読み取りへ渡し、すぐに手放す）
    @State private var scannedReceipt: CapturedReceipt?
    /// 書類スキャンが失敗した（閉じたら今までのカメラを開く）
    @State private var receiptScannerFailed = false
    /// 検索欄に入力中か（Build 23。「完了」・背景のタップ・スクロールでキーボードを閉じる。Build 22 と同じ）
    @FocusState private var isSearchFocused: Bool

    private struct CapturedReceipt {
        let data: Data
        let type: UTType
    }

    init(store: LifeStore, appState: AppState) {
        _viewModel = State(initialValue: MoneyViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollViewReader { proxy in
            moneyScroll
                // Build 26：月次レポートから「支出一覧を見る」・カテゴリーを選んだら、閉じたあと支出一覧まで動かす（アニメーションなし）
                .onChange(of: viewModel.listScrollRequest) {
                    proxy.scrollTo(Self.expenseListAnchor, anchor: .top)
                }
        }
    }

    /// 支出一覧の場所（Build 26：月次レポートから戻ったときに動かす先）
    private static let expenseListAnchor = "money.expenseList"

    private var moneyScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "MONEY", title: "お金")

                // Build 23：家計簿の検索（画面上部）
                searchField

                if viewModel.showsScopeFilter {
                    LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                }

                if viewModel.isSearching {
                    searchResultsSection
                } else {
                    budgetSection
                    // Build 26：月次レポート（予算のカードの下、定期支出の上。控えめなカード）
                    MonthlyReportCard(viewModel: viewModel)
                    // Build 25：定期支出（予算のカードの下、追加ボタンの上）
                    RecurringExpensesSection(viewModel: viewModel)
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
                        .id(Self.expenseListAnchor)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        // Build 23：検索欄のキーボードも、Build 22 と同じ方法で閉じる（スクロール・背景のタップ・「完了」・画面を離れたとき）
        .lifeKeyboardDismissal()
        .lifeKeyboardDoneButton { isSearchFocused = false }
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
            Button("カメラで撮る") { startReceiptCamera() }
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
        // 書類スキャン（Build 20）。結果は1回だけ受け取り、画面が閉じてから読み取りへ渡す
        .fullScreenCover(isPresented: $isShowingReceiptScanner, onDismiss: finishReceiptScanner) {
            ReceiptDocumentScannerView { outcome in
                switch outcome {
                case .scanned(let data):
                    scannedReceipt = CapturedReceipt(data: data, type: .jpeg)
                case .failed:
                    receiptScannerFailed = true
                case .cancelled:
                    break
                }
                isShowingReceiptScanner = false
            }
            .ignoresSafeArea()
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
        // 定期支出の設定の入力（Build 25）。保存するまで設定は変わらない
        .sheet(item: $viewModel.recurringDraft) { draft in
            RecurringExpenseEditorSheet(viewModel: viewModel, draft: draft)
                .presentationDetents([.large])
                .lifeSheetPresentation()
        }
        // 「今月は追加しない」の確認（Build 25。支出は作らない。あとで「未確認に戻す」で取り消せる）
        .confirmationDialog(
            "今月は追加しませんか？",
            isPresented: Binding(
                get: { viewModel.pendingRecurringSkip != nil },
                set: { isPresented in if !isPresented { viewModel.pendingRecurringSkip = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingRecurringSkip
        ) { candidate in
            Button("今月は追加しない") { viewModel.skipRecurring(candidate) }
            Button("キャンセル", role: .cancel) { viewModel.pendingRecurringSkip = nil }
        } message: { candidate in
            Text("\(candidate.month.title)の支出は作りません（予算にも入りません）。あとで「未確認に戻す」で取り消せます。")
        }
        // 月次レポート（Build 26）。閉じたら、支出一覧を開く操作だったときだけ一覧まで動かす
        .sheet(isPresented: $viewModel.isShowingMonthlyReport, onDismiss: { viewModel.monthlyReportDidClose() }) {
            MonthlyReportSheet(viewModel: viewModel)
                .presentationDetents([.large])
                .lifeSheetPresentation()
        }
        // 月の予算の入力（Build 24）。保存するまで予算は変わらない
        .sheet(item: $viewModel.budgetDraft) { draft in
            MonthlyBudgetEditorSheet(viewModel: viewModel, draft: draft)
                .presentationDetents([.large])
                .lifeSheetPresentation()
        }
        // 支出の詳細（Build 21）。「支出を編集」は詳細を閉じてから編集画面を開く（画面を重ねない）
        .sheet(item: $viewModel.detailTarget, onDismiss: { viewModel.detailDidClose() }) { target in
            ExpenseDetailSheet(viewModel: viewModel, expenseID: target.id)
                .presentationDetents([.large])
                .lifeSheetPresentation()
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

    /// 「カメラで撮る」（Build 20）：書類スキャンを使えれば書類スキャン、使えなければ今までのカメラ
    private func startReceiptCamera() {
        guard viewModel.canStartReceiptScan else { return }
        switch ReceiptCaptureMode.preferred() {
        case .documentScanner:
            isShowingReceiptScanner = true
        case .camera:
            isShowingReceiptCamera = true
        }
    }

    /// 書類スキャンの画面が閉じたら：撮れたら読み取りへ渡す（すでに傾きを直しているので、範囲の検出はしない）。
    /// 失敗したら今までのカメラを開く。キャンセルなら何もしない
    private func finishReceiptScanner() {
        if let scanned = scannedReceipt {
            scannedReceipt = nil
            receiptScannerFailed = false
            viewModel.readReceipt(scanned.data, contentType: scanned.type, detectsDocument: false)
        } else if receiptScannerFailed {
            receiptScannerFailed = false
            if ReceiptScanOutcome.failed.fallsBackToCamera, viewModel.canStartReceiptScan {
                isShowingReceiptCamera = true
            }
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

    // MARK: - 家計簿の検索（Build 23）

    /// 検索欄（店名・商品名）。入力した言葉は保存しない。消すボタンで通常の一覧へ戻る
    private var searchField: some View {
        HStack(spacing: LifeSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            TextField("店名・商品名で探す", text: $viewModel.searchText)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
                .frame(minHeight: LifeSpacing.minTapTarget)
                .accessibilityLabel("支出を探す")
                .accessibilityHint("店名・支出のタイトル・商品名で探します。この iPhone の中だけで探し、検索した言葉は保存しません")
                .accessibilityIdentifier("money.search")
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索語を消す")
                .accessibilityHint("検索をやめて、支出の一覧に戻ります")
            }
        }
        .padding(.leading, LifeSpacing.md)
        .background(Capsule().fill(LifeColors.surface))
        .overlay(Capsule().stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline))
    }

    /// 検索結果（件数・絞り込み・結果の一覧）。結果をタップすると、今までの支出の詳細を開く
    private var searchResultsSection: some View {
        let results = viewModel.searchResults
        return VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            searchFilters
            LifeSectionTitle("検索結果", trailing: "\(results.count)件")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("検索結果 \(results.count)件")
            if results.isEmpty {
                LifeEmptyState(
                    systemImage: "magnifyingglass",
                    title: "該当する支出はありません",
                    message: "店名・商品名の一部でも探せます。絞り込みを「すべて」に戻すと見つかることがあります。"
                )
                .frame(maxWidth: .infinity)
                .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            } else {
                LifeRuledList(results) { result in
                    searchResultRow(result)
                }
            }
            Text("この iPhone に読み込んである支出と商品明細の中だけで探します。検索した言葉は保存しません。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 月・カテゴリーの絞り込み（すべて／自分／共有は、上の切り替えと同じ）
    private var searchFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LifeSpacing.xs) {
                Menu {
                    Picker("月", selection: $viewModel.searchMonth) {
                        Text("すべての月").tag(Date?.none)
                        ForEach(viewModel.searchMonths, id: \.self) { month in
                            Text(LifeFormatters.month(month)).tag(Date?.some(month))
                        }
                    }
                } label: {
                    searchFilterLabel(viewModel.searchMonthTitle, systemImage: "calendar", isActive: viewModel.searchMonth != nil)
                }
                .accessibilityLabel("月で絞り込む、\(viewModel.searchMonthTitle)")
                Menu {
                    Picker("カテゴリー", selection: $viewModel.searchCategory) {
                        Text("すべてのカテゴリー").tag(ExpenseCategory?.none)
                        ForEach(viewModel.categories) { category in
                            Text(category.label).tag(ExpenseCategory?.some(category))
                        }
                    }
                } label: {
                    searchFilterLabel(viewModel.searchCategoryTitle, systemImage: "tag", isActive: viewModel.searchCategory != nil)
                }
                .accessibilityLabel("カテゴリーで絞り込む、\(viewModel.searchCategoryTitle)")
            }
            .padding(.vertical, LifeSpacing.xxs)
        }
    }

    private func searchFilterLabel(_ title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: LifeSpacing.xxs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(LifeTypography.caption)
                .accessibilityHidden(true)
        }
        .font(LifeTypography.callout)
        .foregroundStyle(isActive ? LifeColors.onPrimary : LifeColors.text)
        .padding(.horizontal, LifeSpacing.md)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .background(Capsule().fill(isActive ? LifeColors.primary : LifeColors.surface))
        .overlay(Capsule().stroke(isActive ? LifeColors.primary : LifeColors.divider, lineWidth: 1))
        .contentShape(Capsule())
    }

    /// 検索結果の1行：店名・カテゴリー・日付・自分だけ／共有・合計（右寄せ）。商品名で一致したときは、その商品名と金額
    private func searchResultRow(_ result: ExpenseSearchResult) -> some View {
        Button {
            isSearchFocused = false
            viewModel.showDetail(result.expense)
        } label: {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                HStack(spacing: LifeSpacing.sm) {
                    LifeCategoryDot(color: LifeCategoryColors.warmGold)
                    LifeMoneyRow(
                        title: result.expense.title,
                        amount: result.expense.amount,
                        detail: viewModel.searchDetailText(for: result.expense)
                    )
                    if result.expense.isShared {
                        HouseholdSharedMark()
                    }
                }
                ForEach(Array(result.matchedItems.prefix(ExpenseSearch.maxMatchedItemsShown))) { item in
                    HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                        Text("一致した商品：\(item.name)")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                            .lineLimit(2)
                        Spacer(minLength: LifeSpacing.xs)
                        Text(LifeFormatters.yen(item.amount))
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                }
                if result.matchedItems.count > ExpenseSearch.maxMatchedItemsShown {
                    Text("ほか\(result.matchedItems.count - ExpenseSearch.maxMatchedItemsShown)件の商品が一致")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .padding(.vertical, LifeSpacing.xxs)
            .frame(minHeight: LifeSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.searchSpokenLabel(for: result))
        .accessibilityHint("詳細を開きます（商品明細と購入履歴を見られます）")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 月の予算（Build 24）

    /// 月の切り替えと、予算のカード（「すべて」は自分だけ・わが家で共有の2枚。足して1つにしない）
    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            monthSwitcher
            ForEach(viewModel.budgetSummaries) { summary in
                MonthlyBudgetCard(viewModel: viewModel, summary: summary)
            }
        }
    }

    /// 前の月・次の月・今月に戻る（44pt 以上。表示している月を文字で出す）
    private var monthSwitcher: some View {
        VStack(spacing: 0) {
            monthSwitcherRow
            if !viewModel.isShowingCurrentMonth {
                Button("今月に戻る") { viewModel.showCurrentMonth() }
                    .font(LifeTypography.footnote)
                    .frame(minWidth: LifeSpacing.minTapTarget * 2, minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
        }
    }

    private var monthSwitcherRow: some View {
        HStack(spacing: LifeSpacing.xs) {
            Button {
                viewModel.showPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(LifeColors.text)
                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canShowPreviousMonth)
            .accessibilityLabel("前の月")
            Spacer(minLength: LifeSpacing.xs)
            Text(viewModel.displayedMonthTitle)
                .font(LifeTypography.headline)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LifeSpacing.xs)
            Button {
                viewModel.showNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(LifeColors.text)
                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canShowNextMonth)
            .accessibilityLabel("次の月")
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
            // Build 24：カテゴリーごとの合計は、上の予算のカードに「カテゴリー別」として出す（ここでは支出一覧の絞り込みだけ）
        }
    }

    // MARK: - 支出一覧

    private var expenseList: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("支出一覧", trailing: "\(viewModel.expenses.count)件")
            // Build 26：月次レポートから開いたときの月の絞り込み（外せる）
            if let monthTitle = viewModel.listMonthTitle {
                HStack(spacing: LifeSpacing.xs) {
                    Text(monthTitle)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.text)
                    Spacer(minLength: LifeSpacing.xs)
                    Button("月の絞り込みを外す") { viewModel.clearListMonth() }
                        .font(LifeTypography.footnote)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                        .accessibilityHint("すべての月の支出を見ます")
                        .accessibilityIdentifier("money.expenseList.clearMonth")
                }
                .accessibilityElement(children: .contain)
            }
            if viewModel.expenses.isEmpty {
                LifeEmptyState(systemImage: "yensign.circle", title: "支出はありません")
                    .frame(maxWidth: .infinity)
                    .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            } else {
                LifeRuledList(viewModel.expenses) { expense in
                    Button {
                        viewModel.showDetail(expense)
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
                    .accessibilityHint("詳細を開きます（商品明細を見返せます）")
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

/// 支出の追加・編集の入力欄（Build 22）
enum ExpenseEditorField: Hashable {
    case title
    case amount
}

/// 支出の追加・編集（タイトル・金額・カテゴリー・日付・保存先。編集では削除も）
/// Build 20：レシートから開いたときは、合計金額の候補と商品明細（確認用）も出す
struct ExpenseEditorSheet: View {
    let viewModel: MoneyViewModel
    @State private var draft: ExpenseDraft
    @State private var isConfirmingDelete = false
    /// 商品明細（確認用）を開いているか（Build 20。はじめは閉じている）
    @State private var isShowingLineItems = false
    /// 入力中の欄（Build 22。「完了」・背景のタップ・スクロールでキーボードを閉じる）
    @FocusState private var focusedField: ExpenseEditorField?

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
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("支出のタイトル")
                    TextField("金額（円）", text: $draft.amountText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amount)
                        .accessibilityLabel("金額（円）")
                    Picker("カテゴリー", selection: $draft.category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    if let recurring = draft.recurring {
                        // Build 25：定期支出の「今月分を追加」は、対象の月の中の日付だけ
                        DatePicker("日付", selection: $draft.date, in: recurring.month.dayRange(), displayedComponents: .date)
                            .accessibilityIdentifier("money.recurring.date")
                    } else {
                        DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    }
                } footer: {
                    if let message = viewModel.draftMessage {
                        // Build 25：保存できなかった理由（支出は作っていない）
                        Text(message)
                            .foregroundStyle(LifeColors.text)
                            .accessibilityIdentifier("money.recurring.draftMessage")
                    } else if let recurring = draft.recurring {
                        Text("定期支出の\(recurring.month.title)分です。内容を確かめて「保存」を押すと家計簿に入ります（日付は\(recurring.month.title)の中から選べます）。")
                    } else if !draft.amountText.isEmpty, draft.amount == nil {
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

                // 合計金額の候補（Build 20）。レシートから開いたときだけ。タップで金額欄へ入れる
                if draft.isFromReceipt, !draft.amountCandidates.isEmpty {
                    amountCandidatesSection
                }

                // 商品明細（確認用。Build 20）。Build 21 から、ここに残っている明細を支出と一緒に保存する
                if draft.isFromReceipt {
                    lineItemsSection
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
            .navigationTitle(draft.recurring != nil ? "定期支出を追加" : (draft.isFromReceipt ? "レシートから追加" : (draft.isNew ? "支出を追加" : "支出を編集")))
            .navigationBarTitleDisplayMode(.inline)
            // Build 22：キーボードを閉じやすくする（スクロール・背景のタップ・画面を離れたとき。タップは候補・保存・キャンセルへ届く）
            .lifeKeyboardDismissal()
            .lifeKeyboardDoneButton { focusedField = nil }
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

// MARK: - 合計金額の候補・商品明細（Build 20）

extension ExpenseEditorSheet {
    /// 合計金額の候補（最大5件）。選んだ候補にチェック。金額欄はいつでも手入力できる。候補は保存しない
    private var amountCandidatesSection: some View {
        Section {
            ForEach(draft.amountCandidates) { candidate in
                Button {
                    draft.selectAmountCandidate(candidate)
                } label: {
                    HStack(spacing: LifeSpacing.sm) {
                        Text(candidate.displayText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(candidate.isRecommended ? LifeColors.text : LifeColors.secondaryText)
                        Spacer(minLength: LifeSpacing.xs)
                        if draft.isSelectedAmountCandidate(candidate) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(LifeColors.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.spokenLabel)
                .accessibilityHint("金額欄に入れます")
                .accessibilityAddTraits(draft.isSelectedAmountCandidate(candidate) ? [.isSelected] : [])
            }
        } header: {
            Text("合計金額の候補")
        } footer: {
            Text("候補を選ぶか、上の金額欄に入力できます。小計は合計ではないため、選ぶ前にレシートを確かめてください。")
        }
    }

    /// 商品明細（確認用）。直す・消すことができる。Build 21：残っている明細（正しいものだけ）を支出と一緒に保存する
    private var lineItemsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isShowingLineItems) {
                if draft.lineItems.isEmpty {
                    Text(ReceiptLineItemComparison.noItemsMessage)
                        .foregroundStyle(LifeColors.secondaryText)
                } else {
                    ForEach($draft.lineItems) { $item in
                        ReceiptLineItemRow(item: $item) {
                            draft.removeLineItem(item.id)
                        }
                    }
                }
            } label: {
                Text(draft.lineItems.isEmpty ? "商品明細" : "商品明細（\(draft.lineItems.count)件）")
                    .foregroundStyle(LifeColors.text)
                    .frame(minHeight: LifeSpacing.minTapTarget)
            }
            .accessibilityHint(isShowingLineItems ? "商品明細を閉じます" : "商品明細を開きます")
            if !draft.lineItems.isEmpty {
                Text(draft.lineItemComparison.message)
                    .foregroundStyle(draft.lineItemComparison.isMismatch ? LifeColors.accent : LifeColors.text)
                Text("商品明細の合計 \(LifeFormatters.yen(draft.lineItemsTotal))")
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityLabel("商品明細の合計 \(LifeFormatters.yenSpoken(draft.lineItemsTotal))")
            }
            // Build 21：保存されない明細と理由（商品名が空・金額が正しくない・51件目以降）。色だけに頼らず、印と文字で出す
            ForEach(draft.lineItemProblems) { problem in
                Label(problem.message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(LifeColors.text)
                    .accessibilityLabel(problem.message)
            }
            Text("ここに残っている商品明細は、支出と一緒に保存されます（あとから支出の詳細で見返し・修正できます）。わが家で共有にした支出の明細は、わが家のメンバーにも表示されます。")
                .foregroundStyle(LifeColors.secondaryText)
        } header: {
            Text("商品明細（確認用）")
        } footer: {
            Text("一致しなくても支出は保存できます（値引き・税・軽減税率などで一致しないことがあります）。")
        }
    }
}

/// 商品明細の1行（Build 20）。タップで修正欄を開く。ごみ箱で一覧から外す（外した明細は保存しない。Build 21）
struct ReceiptLineItemRow: View {
    @Binding var item: ReceiptLineItem
    let onDelete: () -> Void
    @State private var isEditing = false
    /// 入力中の欄（Build 22。「完了」・背景のタップ・スクロールでキーボードを閉じる）
    @FocusState private var focusedField: LineItemEditorField?

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            HStack(spacing: LifeSpacing.sm) {
                Button {
                    isEditing.toggle()
                } label: {
                    Text(item.displayText)
                        .foregroundStyle(LifeColors.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.spokenLabel)
                .accessibilityHint(isEditing ? "修正欄を閉じます" : "この明細を修正します")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name.isEmpty ? "この" : item.name)の明細を削除")
            }
            if isEditing {
                TextField("商品名", text: $item.name)
                    .focused($focusedField, equals: .name)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityLabel("商品名")
                HStack(spacing: LifeSpacing.sm) {
                    TextField("数量", text: $item.quantityText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .quantity)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("数量")
                    TextField("単価（円）", text: $item.unitPriceText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .unitPrice)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("単価（円）")
                    TextField("金額（円）", text: $item.amountText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amount)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .accessibilityLabel("金額（円）")
                }
            }
            // Build 22：数量×単価が金額と合わないときは知らせる（読み違いかもしれない。値は変えない。色だけに頼らない）
            if item.hasArithmeticMismatch {
                Label("数量×単価と金額が合いません。レシートで確かめてください。", systemImage: "exclamationmark.triangle")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.text)
            }
        }
    }
}
