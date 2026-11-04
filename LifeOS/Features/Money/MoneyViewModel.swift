import Foundation
import Observation
import UniformTypeIdentifiers

/// 支出の入力の下書き（追加・編集。2026-11-01 Build 13）
struct ExpenseDraft: Equatable, Identifiable {
    /// 支出の ID（追加なら新しい ID。文書の ID にもなる）
    let id: UUID
    let isNew: Bool
    var title: String
    /// 金額（入力した文字。全角・カンマ・円も読む）
    var amountText: String
    var category: ExpenseCategory
    var date: Date
    /// 保存先（追加の初期値は必ず「自分だけ」）
    var destination: SaveDestination
    /// 編集を始めたときの保存先
    let originalDestination: SaveDestination
    /// レシートから作った下書きのときの一言（読み取れなかった項目など。Build 18）。保存しない
    var receiptNotes: [String] = []
    /// レシートから作った下書きか（Build 18）
    private(set) var isFromReceipt = false
    /// レシートで見つけた店名の候補（Build 19。最大5件）。確認画面で選ぶための一時的な候補。
    /// 保存しない（保存するのはタイトル欄の1つだけ）。確認画面を閉じたら下書きごと手放す
    private(set) var storeCandidates: [String] = []

    /// 新しい支出（保存先の初期値は「自分だけ」。入力の内容から共有を選ばない）
    init(newOn date: Date) {
        id = UUID()
        isNew = true
        title = ""
        amountText = ""
        category = .other
        self.date = LifeCalendar.startOfDay(date)
        destination = .initial
        originalDestination = .initial
    }

    /// レシートの読み取りから作る新しい支出（Build 18）。保存先の初期値は必ず「自分だけ」。
    /// 候補が無いとき（読み取れなかった）は、タイトル「レシート」・金額は空・今日・その他で始める（手入力できる）
    init(receipt proposal: ReceiptExtractionProposal?, today: Date, failure: String? = nil) {
        self.init(newOn: today)
        isFromReceipt = true
        if let proposal {
            title = proposal.title
            storeCandidates = Array(proposal.storeCandidates.prefix(ReceiptFieldExtractor.maxStoreCandidates))
            amountText = proposal.amount.map { String($0) } ?? ""
            category = proposal.category
            date = LifeCalendar.startOfDay(proposal.date)
            receiptNotes = proposal.notes
        } else {
            title = ReceiptFieldExtractor.fallbackTitle
            receiptNotes = [failure ?? ReceiptImageError.unreadable.message]
        }
    }

    /// 店名の候補を選ぶ（Build 19）：タイトル欄へ入れる。候補に無い名前は入れない（手入力はタイトル欄で）
    mutating func selectStoreCandidate(_ name: String) {
        guard storeCandidates.contains(name) else { return }
        title = name
    }

    /// 選ばれている候補（タイトル欄が候補と同じとき）
    func isSelectedStoreCandidate(_ name: String) -> Bool {
        trimmedTitle == name
    }

    /// 今ある支出の編集
    init(editing expense: Expense) {
        id = expense.id
        isNew = false
        title = expense.title
        amountText = String(expense.amount)
        category = expense.category
        date = expense.date
        destination = expense.isShared ? .household : .personal
        originalDestination = destination
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 金額（1〜999,999,999 円。読めなければ nil）
    var amount: Int? {
        let digits = (amountText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? amountText)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let value = Int(digits), (1...SharedExpensePayload.maxAmount).contains(value) else { return nil }
        return value
    }

    /// 保存できるか（タイトルがあり、金額が 1〜999,999,999 円）
    var canSave: Bool { !trimmedTitle.isEmpty && amount != nil }

    /// 保存する内容（保存先は LifeStore が決める）
    func makeExpense() -> Expense? {
        guard canSave, let amount else { return nil }
        return Expense(
            id: id,
            title: SharedExpensePayload.title(trimmedTitle),
            amount: amount,
            category: category,
            date: date,
            ownership: originalDestination == .household ? .shared : .personal
        )
    }
}

/// カテゴリーごとの合計（表示している範囲・その月）
struct ExpenseCategoryTotal: Equatable, Identifiable {
    let category: ExpenseCategory
    let amount: Int
    var id: ExpenseCategory { category }
}

@Observable
final class MoneyViewModel {
    /// v2 第6回：LifeStore ではなく Repository の窓口を通して読む
    private let repository: any ExpenseRepository
    private let appState: AppState
    /// 基準の日時（その月を集計する）
    private(set) var now: Date

    /// nil のときは「すべて」
    var selectedCategory: ExpenseCategory?
    /// 追加・編集のシートの下書き（開いていなければ nil）
    var draft: ExpenseDraft?
    /// 削除の確認を出している支出
    var pendingDeletion: Expense?

    // MARK: レシートの読み取り（Build 18）

    /// 「カメラで撮る／写真から選ぶ」を出している
    var isChoosingReceiptSource = false
    /// 端末の中で読み取っている
    private(set) var isReadingReceipt = false
    /// 文字を読み取る窓口（テストでは偽物）
    @ObservationIgnored private let receiptRecognizer: any ReceiptTextRecognizing
    /// 読み取りの処理（キャンセル・終わったら nil。写真のデータはこの処理の中だけで持つ）
    @ObservationIgnored private var receiptTask: Task<Void, Never>?
    /// 読み取りの回数（キャンセルしたあとに届いた結果を捨てるため）
    @ObservationIgnored private var receiptGeneration = 0

    init(
        store repository: any ExpenseRepository,
        appState: AppState = AppState(),
        now: Date = LifeCalendar.now,
        receiptRecognizer: any ReceiptTextRecognizing = ReceiptTextRecognizer()
    ) {
        self.repository = repository
        self.appState = appState
        self.now = now
        self.receiptRecognizer = receiptRecognizer
    }

    func refreshNow(_ date: Date = LifeCalendar.now) {
        if !LifeCalendar.isSameDay(date, now) { now = date }
    }

    // MARK: - 表示の範囲（すべて／自分／共有。Build 13）

    var scope: ScopeFilter {
        get { appState.scope }
        set { appState.scope = newValue }
    }

    /// 一人モードでは「すべて / 自分 / 共有」を出さない
    var showsScopeFilter: Bool { appState.usageStyle.showsScopeFilter }

    private var effectiveScope: ScopeFilter { appState.effectiveScope }

    /// 表示している範囲の支出（すべての月。同じ支出は1回だけ）
    private var scopedExpenses: [Expense] {
        repository.visibleExpenses(scope: effectiveScope)
    }

    /// 表示している範囲の、今月の支出
    private var monthExpenses: [Expense] {
        let month = LifeCalendar.startOfMonth(now)
        return scopedExpenses.filter { LifeCalendar.startOfMonth($0.date) == month }
    }

    // MARK: - 今月のまとめ（表示している範囲の合計。予算は端末の設定）

    var spent: Int { monthExpenses.reduce(0) { $0 + $1.amount } }
    /// 月の予算（端末の中だけ。Firestore へは送らない）
    var budget: Int { repository.budget.budget }
    var remaining: Int { budget - spent }
    var usageRatio: Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(spent) / Double(budget), 0), 1)
    }

    var usagePercentText: String {
        "\(Int((usageRatio * 100).rounded()))%"
    }

    /// 今月のカテゴリーごとの合計（表示している範囲。0円のカテゴリーは出さない）
    var categoryTotals: [ExpenseCategoryTotal] {
        let expenses = monthExpenses
        return ExpenseCategory.allCases.compactMap { category in
            let total = expenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
            return total > 0 ? ExpenseCategoryTotal(category: category, amount: total) : nil
        }
    }

    var summaryTitle: String {
        switch effectiveScope {
        case .all: return "今月の支出"
        case .mine: return "今月の支出（自分）"
        case .shared: return "今月の支出（共有）"
        }
    }

    // MARK: - 支出一覧

    let categories = ExpenseCategory.allCases

    var expenses: [Expense] {
        scopedExpenses
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }

    func detailText(for expense: Expense) -> String {
        var parts = [expense.category.label, LifeFormatters.shortDate(expense.date)]
        if showsScopeFilter { parts.append(expense.ownership.label) }
        return parts.joined(separator: "・")
    }

    /// ID の支出（自分だけ・共有のどちらでも）
    func expense(id: Expense.ID) -> Expense? {
        repository.visibleExpenses(scope: .all).first { $0.id == id }
    }

    func select(_ category: ExpenseCategory?) {
        selectedCategory = category
    }

    // MARK: - 追加・編集（Build 13）

    /// 「わが家で共有」を新しく選べない理由（選べるなら nil）
    var sharingBlock: ExpenseSharingBlock? {
        showsScopeFilter ? repository.expenseSharingBlock : .soloMode
    }

    func startAdding() {
        draft = ExpenseDraft(newOn: now)
    }

    func startEditing(_ expense: Expense) {
        draft = ExpenseDraft(editing: expense)
    }

    func cancelEditing() {
        draft = nil
    }

    /// 下書きで選べる保存先か
    func canChoose(_ destination: SaveDestination, in draft: ExpenseDraft) -> Bool {
        switch (draft.originalDestination, destination) {
        case (.personal, .personal):
            return true
        case (.personal, .household):
            return sharingBlock == nil
        case (.household, .household):
            return repository.canEditSharedExpenses
        case (.household, .personal):
            return repository.canEditSharedExpenses
        }
    }

    /// 選べないときの理由（画面に出す）
    func destinationNote(for draft: ExpenseDraft) -> String {
        if draft.originalDestination == .household {
            return repository.canEditSharedExpenses
                ? "わが家で共有している支出です。変更・削除はパートナーの画面にも反映されます。"
                : "わが家に参加していないため、共有の支出は変更できません。"
        }
        if let block = sharingBlock { return block.message }
        return "「わが家で共有」にすると、タイトル・金額・カテゴリー・日付がパートナーの画面にも表示されます。予算・レシート・メモは共有しません。"
    }

    /// 保存する。追加は選んだ保存先へ（共有できないときは自分だけ）。編集は、その支出の保存先だけに反映する
    /// - Returns: 保存したら true（シートを閉じる）
    @discardableResult
    func save(_ draft: ExpenseDraft) -> Bool {
        guard let expense = draft.makeExpense() else { return false }
        // Build 18：同じ新しい支出を2回保存しない（保存ボタンを続けて押したとき・閉じる前のもう一度の保存）
        if draft.isNew, self.expense(id: expense.id) != nil {
            if self.draft?.id == draft.id { self.draft = nil }
            return false
        }
        let destination = canChoose(draft.destination, in: draft) ? draft.destination : draft.originalDestination
        if draft.isNew {
            repository.addExpense(expense, destination: destination == .household && sharingBlock == nil ? .household : .personal)
            self.draft = nil
            return true
        }
        var saved = false
        switch (draft.originalDestination, destination) {
        case (.personal, .household):
            // 先に端末の内容を新しくしてから、共有へ変える（共有の保存が確かめられるまで端末の支出は消えない）
            saved = repository.updateExpense(expense)
            if saved { repository.changeExpenseDestination(expense.id, to: .household) }
        case (.household, .personal):
            // 先に端末へ保存してから共有の支出を消し、そのあと端末の内容だけを新しくする
            saved = repository.changeExpenseDestination(expense.id, to: .personal)
            if saved {
                var personal = expense
                personal.ownership = .personal
                repository.updateExpense(personal)
            }
        default:
            saved = repository.updateExpense(expense)
        }
        if saved { self.draft = nil }
        return saved
    }

    // MARK: - レシートの読み取り（Build 18。docs/BUILD_18_RECEIPT_TO_BUDGET.md）

    /// 「レシートを読み取る」を押せるか（読み取り中・入力中は押せない）
    var canStartReceiptScan: Bool { !isReadingReceipt && draft == nil }

    /// 「レシートを読み取る」：撮るか選ぶかを出す
    func startReceiptScan() {
        guard canStartReceiptScan else { return }
        isChoosingReceiptSource = true
    }

    /// 写真を受け取って、端末の中で読み取る（1枚だけ）。読み取り中なら何もしない（二重に始めない）。
    /// 読み取りが終わったら、候補を入れた支出の追加画面を開く（保存するまで支出は作らない）。
    /// 写真が大きすぎる・形式が違う・読めないときも、手入力できる追加画面を開く
    func readReceipt(_ data: Data, contentType: UTType? = nil) {
        guard !isReadingReceipt, draft == nil else { return }
        isChoosingReceiptSource = false
        if let error = ReceiptTextRecognizer.validate(data, contentType: contentType) {
            openReceiptDraft(lines: nil, failure: error)
            return
        }
        isReadingReceipt = true
        receiptGeneration += 1
        let generation = receiptGeneration
        let recognizer = receiptRecognizer
        receiptTask = Task { @MainActor [weak self] in
            let lines = try? await recognizer.recognizeLines(in: data)
            guard let self, self.receiptGeneration == generation, !Task.isCancelled else { return }
            self.finishReceiptReading(lines: lines)
        }
    }

    /// 写真を読み込めなかった・カメラで撮れなかった（アプリは止めず、手入力できる画面を開く）
    func receiptImageFailed(_ error: ReceiptImageError = .loadFailed) {
        guard !isReadingReceipt, draft == nil else { return }
        isChoosingReceiptSource = false
        openReceiptDraft(lines: nil, failure: error)
    }

    /// 読み取りの「キャンセル」：何も保存しない。読み取った結果が後から届いても捨てる
    func cancelReceiptReading() {
        receiptGeneration += 1
        receiptTask?.cancel()
        receiptTask = nil
        isReadingReceipt = false
        isChoosingReceiptSource = false
    }

    /// 読み取りの処理を持っているか（確認用。終わった・キャンセルしたら false）
    var isHoldingReceiptWork: Bool { receiptTask != nil }

    /// 読み取りが終わるまで待つ（テスト・画面の確認用）
    func waitForReceiptReading() async {
        let task = receiptTask
        await task?.value
    }

    private func finishReceiptReading(lines: [String]?) {
        receiptTask = nil
        isReadingReceipt = false
        openReceiptDraft(lines: lines, failure: .unreadable)
    }

    /// 候補（または手入力用の空の下書き）で支出の追加画面を開く。読み取った文字はここで捨てる（下書きには4項目だけ）
    private func openReceiptDraft(lines: [String]?, failure: ReceiptImageError) {
        let proposal = lines.flatMap { lines -> ReceiptExtractionProposal? in
            let usable = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return usable.isEmpty ? nil : ReceiptFieldExtractor.extract(from: usable, today: now)
        }
        draft = ExpenseDraft(receipt: proposal, today: now, failure: proposal == nil ? failure.message : nil)
    }

    // MARK: - 削除（Build 13）

    /// 消せるか（自分だけの支出はいつも。共有の支出は、わが家に参加しているとき）
    func canDelete(_ expense: Expense) -> Bool {
        !expense.isShared || repository.canEditSharedExpenses
    }

    func requestDelete(_ expense: Expense) {
        guard canDelete(expense) else { return }
        pendingDeletion = expense
    }

    func cancelDelete() {
        pendingDeletion = nil
    }

    /// 確認のあとで消す（その支出の保存先だけ）
    @discardableResult
    func confirmDelete() -> Bool {
        guard let expense = pendingDeletion else { return false }
        pendingDeletion = nil
        let deleted = repository.deleteExpense(expense.id)
        if deleted, draft?.id == expense.id { draft = nil }
        return deleted
    }

    func deleteMessage(for expense: Expense) -> String {
        expense.isShared ? "わが家で共有している支出です。パートナーの画面からも消えます。" : "この iPhone から消えます。"
    }
}
