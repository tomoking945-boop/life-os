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
    private(set) var originalDestination: SaveDestination
    /// レシートから作った下書きのときの一言（読み取れなかった項目など。Build 18）。保存しない
    var receiptNotes: [String] = []
    /// レシートから作った下書きか（Build 18）
    private(set) var isFromReceipt = false
    /// レシートで見つけた店名の候補（Build 19。最大5件）。確認画面で選ぶための一時的な候補。
    /// 保存しない（保存するのはタイトル欄の1つだけ）。確認画面を閉じたら下書きごと手放す
    private(set) var storeCandidates: [String] = []
    /// 合計金額の候補（Build 20。最大5件。小計は「選択非推奨」の参考）。確認画面で選ぶための一時的な候補。
    /// 保存しない（保存するのは金額欄の1つだけ）。確認画面を閉じたら下書きごと手放す
    private(set) var amountCandidates: [ReceiptAmountCandidate] = []
    /// 選んでいる合計金額の候補（Build 20）
    private(set) var selectedAmountCandidateID: String?
    /// 商品明細（Build 20。確認用）。確認画面で直す・消すことができる。保存・共有・送信しない。
    /// 支出を保存する・閉じる・キャンセルすると、下書きごと手放す
    var lineItems: [ReceiptLineItem] = []
    /// 定期支出の「今月分を追加」から開いた下書き（Build 25。保存先は設定と同じで変えられない。日付は対象の月の中だけ）
    private(set) var recurring: RecurringExpenseContext?

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
            let candidates = Array(proposal.amountCandidates.prefix(ReceiptFieldExtractor.maxAmountCandidates))
            amountCandidates = candidates
            // 自動で入れた金額は、その金額の（選んでよい）いちばん上の候補にチェックを付ける
            selectedAmountCandidateID = proposal.amount.flatMap { amount in
                candidates.first { $0.isRecommended && $0.amount == amount }?.id
            }
            lineItems = Array(proposal.lineItems.prefix(ReceiptFieldExtractor.maxLineItems))
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

    /// 合計金額の候補を選ぶ（Build 20）：金額欄へ入れる（小計も、利用者が選べば入れる）。候補に無いものは入れない
    mutating func selectAmountCandidate(_ candidate: ReceiptAmountCandidate) {
        guard amountCandidates.contains(where: { $0.id == candidate.id }) else { return }
        amountText = String(candidate.amount)
        selectedAmountCandidateID = candidate.id
    }

    /// 選ばれている合計金額の候補（金額欄を手で変えたら、どれも選ばれていない）
    func isSelectedAmountCandidate(_ candidate: ReceiptAmountCandidate) -> Bool {
        selectedAmountCandidateID == candidate.id && amount == candidate.amount
    }

    /// 商品明細の行を消す（Build 20。確認用の一覧から外すだけ）
    mutating func removeLineItem(_ id: ReceiptLineItem.ID) {
        lineItems.removeAll { $0.id == id }
    }

    /// 商品明細の合計とレシートの合計（金額欄）の比較（Build 20）。一致しなくても保存できる
    var lineItemComparison: ReceiptLineItemComparison {
        ReceiptLineItemComparison.compare(items: lineItems, receiptTotal: amount)
    }

    /// 商品明細の金額の合計（金額が読めた明細だけ）
    var lineItemsTotal: Int {
        lineItems.compactMap(\.amount).reduce(0, +)
    }

    /// 保存する商品明細と、保存されない明細の理由（Build 21）。確認画面に残っている明細だけを保存する
    /// （消した明細は入らない。商品名が空・金額が正しくない・51件目以降は保存しない）
    var lineItemPreparation: ExpenseLineItemPreparation {
        ExpenseLineItemRules.prepare(lineItems)
    }

    /// 保存されない明細の理由（画面に出す。Build 21）
    var lineItemProblems: [ExpenseLineItemProblem] {
        lineItemPreparation.problems
    }

    /// 定期支出の「今月分を追加」（Build 25）：名前・目安金額・カテゴリー・支払予定日・設定の保存先を入れておく。
    /// 保存を押すまで支出は作らない（金額・日付・名前は直せる。保存先は変えられない）
    init(recurring candidate: RecurringCandidate) {
        self.init(newOn: candidate.dueDate)
        title = candidate.template.title
        amountText = String(candidate.template.expectedAmount)
        category = candidate.template.category
        let shared: SaveDestination = candidate.template.isShared ? .household : .personal
        destination = shared
        originalDestination = shared
        recurring = RecurringExpenseContext(templateID: candidate.template.id, month: candidate.month, isShared: candidate.template.isShared)
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

/// 定期支出から開いた支出の下書きの情報（Build 25）
struct RecurringExpenseContext: Equatable {
    let templateID: UUID
    /// 対象の月（日付はこの月の中だけ）
    let month: BudgetMonth
    let isShared: Bool
}

/// 定期支出の一覧の1行（Build 25。候補か、停止中・開始前の設定）
struct RecurringRow: Identifiable, Equatable {
    let template: RecurringExpenseTemplate
    /// その月の候補（停止中で記録の無い月・開始前の月は nil）
    let candidate: RecurringCandidate?
    var id: UUID { template.id }

    /// 状態（色だけに頼らず文字で）：未確認・追加済み・今月は追加しない・停止中・開始前
    var stateText: String {
        if let candidate {
            return template.isActive ? candidate.state.label : "\(candidate.state.label)（停止中）"
        }
        if !template.isActive { return "停止中" }
        return "\(template.startMonth?.title ?? "")から"
    }
}

/// 詳細画面で開く支出（Build 21）
struct ExpenseDetailTarget: Identifiable, Hashable {
    let id: Expense.ID
}

/// 購入履歴で開く商品（Build 23。整えた商品名。詳細画面のあいだだけ持つ。保存・送信しない）
struct ProductHistoryTarget: Identifiable, Hashable {
    let key: String
    var id: String { key }
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
    /// 詳細画面で開いている支出（Build 21。開いていなければ nil）
    var detailTarget: ExpenseDetailTarget?
    /// 詳細画面の「支出を編集」：詳細画面が閉じてから編集画面を開く支出
    @ObservationIgnored private var editAfterDetail: Expense.ID?

    // MARK: 家計簿の検索（Build 23。画面のあいだだけ持つ。保存・送信・ログ出力しない）

    /// 検索欄の文字
    var searchText = ""
    /// 月で絞り込む（月の初日。nil はすべての月）
    var searchMonth: Date?
    /// カテゴリーで絞り込む（nil はすべて）
    var searchCategory: ExpenseCategory?

    // MARK: 月の予算（Build 24）

    /// 表示している月（予算と実績。はじめは今月）
    var displayedMonth: BudgetMonth
    /// 予算の入力の画面（開いていなければ nil。保存するまで予算は変わらない）
    var budgetDraft: MonthlyBudgetDraft?

    // MARK: 定期支出（Build 25）

    /// 定期支出の設定の入力の画面（開いていなければ nil。保存するまで設定は変わらない）
    var recurringDraft: RecurringExpenseDraft?
    /// 「今月は追加しない」の確認を出している候補
    var pendingRecurringSkip: RecurringCandidate?
    /// 定期支出の操作の結果の一言（できなかった理由など。日本語）
    var recurringMessage: String?
    /// 支出の確認画面に出す理由（定期支出の「今月分を追加」が保存できなかったとき。日本語）
    var draftMessage: String?

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
        self.displayedMonth = BudgetMonth(date: now)
    }

    func refreshNow(_ date: Date = LifeCalendar.now) {
        guard !LifeCalendar.isSameDay(date, now) else { return }
        // 今月を見ていたら、月が変わったときも今月を見る（ほかの月を見ているときは、そのまま）
        let wasShowingCurrentMonth = displayedMonth == BudgetMonth(date: now)
        now = date
        if wasShowingCurrentMonth { displayedMonth = BudgetMonth(date: date) }
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

    /// 表示している範囲の、表示している月の支出（支出の日付で数える。Build 24 から月を切り替えられる。はじめは今月）
    private var monthExpenses: [Expense] {
        MonthlyBudgetCalculator.expenses(scopedExpenses, in: displayedMonth)
    }

    // MARK: - 表示している月のまとめ（表示している範囲の合計）

    var spent: Int { monthExpenses.reduce(0) { MonthlyBudgetCalculator.saturatingAdd($0, $1.amount) } }
    /// 以前（Build 13〜23）の端末の「予算」の値（設定の画面は無く、見本の値か 0）。Build 24 から画面には出さない。
    /// 月の予算は budgetSummary(for:)（自分だけ・わが家で共有を別々に）
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
        let month = isShowingCurrentMonth ? "今月" : displayedMonth.title
        switch effectiveScope {
        case .all: return "\(month)の支出"
        case .mine: return "\(month)の支出（自分）"
        case .shared: return "\(month)の支出（共有）"
        }
    }

    // MARK: - 月の予算（Build 24。docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md）

    /// 今月を見ているか
    var isShowingCurrentMonth: Bool { displayedMonth == BudgetMonth(date: now) }

    /// 「今月」または「2026年10月」
    var displayedMonthTitle: String { isShowingCurrentMonth ? "今月（\(displayedMonth.title)）" : displayedMonth.title }

    func showPreviousMonth() {
        let previous = displayedMonth.previous
        guard previous.isStorable else { return }
        displayedMonth = previous
    }

    func showNextMonth() {
        let next = displayedMonth.next
        guard next.isStorable else { return }
        displayedMonth = next
    }

    func showCurrentMonth() {
        displayedMonth = BudgetMonth(date: now)
    }

    var canShowPreviousMonth: Bool { displayedMonth.previous.isStorable }
    var canShowNextMonth: Bool { displayedMonth.next.isStorable }

    /// 出す予算のカード（「すべて」は自分だけ・わが家で共有の2枚。足して1つにしない。一人で使う設定は自分だけ）
    var budgetScopes: [BudgetScope] {
        BudgetScope.cards(showsScopeFilter: showsScopeFilter, effectiveScope: effectiveScope)
    }

    /// その予算の、表示している月の予算と実績（自分だけの予算は自分だけの支出、共有の予算は共有の支出だけを数える）
    func budgetSummary(for scope: BudgetScope) -> MonthlyBudgetSummary {
        MonthlyBudgetCalculator.summary(
            month: displayedMonth,
            scope: scope,
            plan: repository.monthlyBudget(for: displayedMonth, scope: scope),
            expenses: repository.visibleExpenses(scope: scope.expenseScope),
            today: now
        )
    }

    var budgetSummaries: [MonthlyBudgetSummary] { budgetScopes.map(budgetSummary(for:)) }

    /// 予算を設定・変更できるか（わが家の予算は、新しく作るときは家計簿の共有がオンのときだけ。あれば参加中なら変えられる）
    func canEditBudget(_ scope: BudgetScope) -> Bool {
        guard displayedMonth.isStorable else { return false }
        switch scope {
        case .personal:
            return true
        case .household:
            return repository.monthlyBudget(for: displayedMonth, scope: .household) == nil
                ? repository.householdBudgetBlock == nil
                : repository.canEditHouseholdBudgets
        }
    }

    /// 変えられないときの理由・保存先の説明（画面に出す）
    func budgetNote(for scope: BudgetScope) -> String {
        switch scope {
        case .personal:
            return "自分だけの予算は、この iPhone の中だけに保存します（わが家には送りません）。"
        case .household:
            if canEditBudget(.household) {
                return "わが家の共有予算は、わが家のメンバー（オーナーとパートナー）が見て、変えられます。共有の支出だけを数えます。"
            }
            return repository.householdBudgetBlock?.message ?? ExpenseSharingBlock.notJoined.message
        }
    }

    /// 予算の入力の画面を開く（表示している月）
    func startEditingBudget(_ scope: BudgetScope) {
        guard canEditBudget(scope) else { return }
        budgetDraft = MonthlyBudgetDraft(month: displayedMonth, scope: scope, plan: repository.monthlyBudget(for: displayedMonth, scope: scope))
    }

    func cancelBudgetEditing() {
        budgetDraft = nil
    }

    /// 前の月の予算（「前月の予算をコピー」に使う。無ければ nil）
    func previousMonthPlan(for draft: MonthlyBudgetDraft) -> MonthlyBudgetPlan? {
        repository.monthlyBudget(for: draft.month.previous, scope: draft.scope)
    }

    /// 保存する。正しくなければ理由を返し、画面は開いたまま（予算は変わらない）
    @discardableResult
    func saveBudget(_ draft: MonthlyBudgetDraft) -> BudgetInputError? {
        switch draft.validated() {
        case .failure(let error):
            return error
        case .success(let plan):
            if let error = repository.setMonthlyBudget(plan, for: draft.month, scope: draft.scope) { return error }
            if budgetDraft?.id == draft.id { budgetDraft = nil }
            return nil
        }
    }

    /// その月の予算を解除する（カテゴリーの予算も一緒に。支出は消さない）
    @discardableResult
    func removeBudget(_ draft: MonthlyBudgetDraft) -> BudgetInputError? {
        if let error = repository.setMonthlyBudget(nil, for: draft.month, scope: draft.scope) { return error }
        if budgetDraft?.id == draft.id { budgetDraft = nil }
        return nil
    }

    /// カードの VoiceOver（予算・使った金額・残り・割合・1日あたりの目安。色だけに頼らない）
    func budgetSpokenLabel(_ summary: MonthlyBudgetSummary) -> String {
        var parts = [summary.scope.budgetTitle, displayedMonth.title, "使った金額 \(LifeFormatters.yenSpoken(summary.spent))"]
        if let plan = summary.plan {
            parts.append("予算 \(LifeFormatters.yenSpoken(plan.totalAmount))")
            if let overAmount = summary.overAmount {
                parts.append("予算を\(LifeFormatters.yenSpoken(overAmount))上回っています")
            } else if let remaining = summary.remaining {
                parts.append("残り \(LifeFormatters.yenSpoken(remaining))")
            }
            if let percent = summary.usagePercentText { parts.append("使用割合 \(percent)") }
            if let daily = summary.dailyAllowance {
                parts.append("残り\(summary.daysRemaining)日、1日あたりの目安 \(LifeFormatters.yenSpoken(daily))")
            }
        } else {
            parts.append("予算は未設定です")
        }
        return parts.joined(separator: "、")
    }

    /// カテゴリー1つの VoiceOver
    func categorySpokenLabel(_ line: BudgetCategoryLine) -> String {
        var parts = [line.category.label, "使った金額 \(LifeFormatters.yenSpoken(line.spent))"]
        if let budget = line.budget {
            parts.append("予算 \(LifeFormatters.yenSpoken(budget))")
            if let remaining = line.remaining {
                parts.append(remaining < 0 ? "予算を\(LifeFormatters.yenSpoken(-remaining))上回っています" : "残り \(LifeFormatters.yenSpoken(remaining))")
            }
            if let ratio = line.usageRatio { parts.append("使用割合 \(Int(min(ratio * 100, 1_000_000).rounded()))%") }
        } else {
            parts.append("予算は未設定")
        }
        return parts.joined(separator: "、")
    }

    // MARK: - 固定費・定期支出（Build 25。docs/BUILD_25_RECURRING_EXPENSES.md）

    /// 出す定期支出のまとまり（予算のカードと同じ。「すべて」は自分だけ・わが家で共有を分けて出す）
    var recurringScopes: [BudgetScope] { budgetScopes }

    /// 表示している月の候補（候補は支出ではない：予算・集計・検索に入れない）
    func recurringCandidates(for scope: BudgetScope) -> [RecurringCandidate] {
        RecurringExpenseSchedule.candidates(
            templates: repository.recurringTemplates(scope: scope),
            occurrences: repository.recurringOccurrences(scope: scope),
            month: displayedMonth
        )
    }

    /// 一覧の行（候補と、停止中・開始前の設定。停止中・開始前の設定も、編集・再開できるように出す）
    func recurringRows(for scope: BudgetScope) -> [RecurringRow] {
        let candidates = recurringCandidates(for: scope)
        let byTemplate = Dictionary(candidates.map { ($0.template.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shown = candidates.map { RecurringRow(template: $0.template, candidate: $0) }
        let others = repository.recurringTemplates(scope: scope)
            .filter { byTemplate[$0.id] == nil }
            .sorted { $0.title == $1.title ? $0.id.uuidString < $1.id.uuidString : $0.title < $1.title }
            .map { RecurringRow(template: $0, candidate: nil) }
        return shown + others
    }

    /// その設定を操作（今月分を追加・今月は追加しない・編集・停止・再開）できるか
    func canActOnRecurring(_ template: RecurringExpenseTemplate) -> Bool {
        template.isShared ? repository.canEditHouseholdRecurring : true
    }

    /// 「今月分を追加」を押せるか（未確認・動いている設定。共有は家計簿の共有がオンのとき）
    func canAddRecurring(_ candidate: RecurringCandidate) -> Bool {
        guard candidate.state == .unconfirmed, candidate.template.isActive, draft == nil else { return false }
        guard candidate.template.isShared else { return true }
        return repository.canEditHouseholdRecurring && repository.expenseSharingBlock == nil
    }

    /// まとまりの説明（保存先・変えられない理由）
    func recurringNote(for scope: BudgetScope) -> String {
        switch scope {
        case .personal:
            return "自分だけの定期支出は、この iPhone の中だけに保存します（わが家には送りません）。"
        case .household:
            if repository.canEditHouseholdRecurring {
                return "わが家で共有の定期支出は、オーナーとパートナーが見て、追加・編集できます。"
            }
            return (repository.householdRecurringBlock ?? .notJoined).recurringMessage
        }
    }

    /// 新しい設定を作る画面を開く（保存先の初期値は「自分だけ」）
    func startAddingRecurring() {
        recurringMessage = nil
        recurringDraft = RecurringExpenseDraft(newIn: BudgetMonth(date: now))
    }

    /// 設定の編集の画面を開く（保存先は変えない）
    func startEditingRecurring(_ template: RecurringExpenseTemplate) {
        guard canActOnRecurring(template) else {
            recurringMessage = (repository.householdRecurringBlock ?? .notJoined).recurringMessage
            return
        }
        recurringMessage = nil
        recurringDraft = RecurringExpenseDraft(editing: template, fallbackMonth: BudgetMonth(date: now))
    }

    func cancelRecurringEditing() {
        recurringDraft = nil
    }

    /// 新しい設定で「わが家で共有」を選べるか（一人で使う設定・わが家に参加していない・家計簿の共有がオフは選べない）
    var canChooseHouseholdRecurring: Bool {
        showsScopeFilter && repository.householdRecurringBlock == nil
    }

    /// 設定の保存先の説明
    func recurringDestinationNote(for draft: RecurringExpenseDraft) -> String {
        if !draft.isNew {
            return "保存先はあとから変えられません。変えたいときは、この定期支出を停止して、新しく作ってください。"
        }
        if draft.destination == .household {
            return "「わが家で共有」にすると、名前・目安金額・カテゴリー・支払日がパートナーの画面にも表示されます。"
        }
        if !showsScopeFilter { return ExpenseSharingBlock.soloMode.recurringMessage }
        if let block = repository.householdRecurringBlock { return block.recurringMessage }
        return "自分だけの定期支出は、この iPhone の中だけに保存します。"
    }

    /// 設定を保存する。正しくなければ理由を返し、画面は開いたまま（設定は変わらない）
    @discardableResult
    func saveRecurring(_ draft: RecurringExpenseDraft) -> RecurringExpenseError? {
        var draft = draft
        if draft.isNew, draft.destination == .household, !canChooseHouseholdRecurring {
            let block: ExpenseSharingBlock = showsScopeFilter ? (repository.householdRecurringBlock ?? .notJoined) : .soloMode
            return .notEditable(block.recurringMessage)
        }
        if !draft.isNew, let existing = repository.recurringTemplate(id: draft.id) {
            draft.destination = existing.isShared ? .household : .personal
        }
        switch draft.validated() {
        case .failure(let error):
            return error
        case .success(let template):
            if let error = repository.saveRecurringTemplate(template) { return error }
            if recurringDraft?.id == draft.id { recurringDraft = nil }
            return nil
        }
    }

    /// 停止する（作った支出・記録は消さない。新しい月の候補を出さない）
    @discardableResult
    func pauseRecurring(_ template: RecurringExpenseTemplate) -> RecurringExpenseError? {
        let error = repository.setRecurringTemplateActive(template.id, isActive: false, resumingIn: BudgetMonth(date: now))
        recurringMessage = error?.message
        if error == nil, recurringDraft?.id == template.id { recurringDraft = nil }
        return error
    }

    /// 再開する（再開した月以降の候補を出す。止めていたあいだの月の候補は出さない）
    @discardableResult
    func resumeRecurring(_ template: RecurringExpenseTemplate) -> RecurringExpenseError? {
        let error = repository.setRecurringTemplateActive(template.id, isActive: true, resumingIn: BudgetMonth(date: now))
        recurringMessage = error?.message
        if error == nil, recurringDraft?.id == template.id { recurringDraft = nil }
        return error
    }

    /// 「今月分を追加」：支出の確認画面を開く（保存を押すまで支出は作らない）
    func startRecurringExpense(_ candidate: RecurringCandidate) {
        guard canAddRecurring(candidate) else {
            if candidate.template.isShared, let block = repository.expenseSharingBlock ?? repository.householdRecurringBlock {
                recurringMessage = block.recurringMessage
            }
            return
        }
        recurringMessage = nil
        draftMessage = nil
        draft = ExpenseDraft(recurring: candidate)
    }

    /// 「今月は追加しない」の確認を出す
    func confirmRecurringSkip(_ candidate: RecurringCandidate) {
        guard candidate.state == .unconfirmed, canActOnRecurring(candidate.template) else { return }
        pendingRecurringSkip = candidate
    }

    /// 確認のあと「今月は追加しない」にする（支出は作らない）
    @discardableResult
    func skipRecurring(_ candidate: RecurringCandidate) -> RecurringExpenseError? {
        pendingRecurringSkip = nil
        let error = repository.skipRecurring(templateID: candidate.template.id, month: candidate.month)
        recurringMessage = error?.message
        return error
    }

    /// 「未確認に戻す」（今月は追加しない だけ。追加済みは戻せない）
    @discardableResult
    func undoRecurringSkip(_ candidate: RecurringCandidate) -> RecurringExpenseError? {
        let error = repository.undoRecurringSkip(templateID: candidate.template.id, month: candidate.month)
        recurringMessage = error?.message
        return error
    }

    /// 支払予定日の文（「毎月27日」・その月の日付）
    func recurringDueText(_ row: RecurringRow) -> String {
        var text = "毎月\(row.template.dueDay)日"
        if let candidate = row.candidate {
            text += "（\(LifeFormatters.shortDate(candidate.dueDate))）"
        }
        return text
    }

    /// 行の VoiceOver（名前・状態・目安金額・支払日・カテゴリー・保存先）
    func recurringSpokenLabel(_ row: RecurringRow) -> String {
        [
            row.template.title,
            row.stateText,
            "目安 \(LifeFormatters.yenSpoken(row.template.expectedAmount))",
            recurringDueText(row),
            row.template.category.label,
            row.template.isShared ? "わが家で共有" : "自分だけ",
        ].joined(separator: "、")
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

    // MARK: - 家計簿の検索（Build 23。docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md）

    /// 検索中か（整えた検索語が空でなければ。空なら通常の一覧）
    var isSearching: Bool { !ExpenseSearchText.normalized(searchText).isEmpty }

    /// 今の絞り込み（すべて／自分／共有は、画面上部の切り替えと同じ）
    var searchFilter: ExpenseSearchFilter {
        ExpenseSearchFilter(scope: effectiveScope, month: searchMonth, category: searchCategory)
    }

    /// 検索の結果と調べた数。端末に読み込んである支出と明細だけを、その場で調べる（問い合わせ・見張りを増やさない）
    var searchOutcome: ExpenseSearchOutcome {
        guard isSearching else { return .empty }
        let expenses = scopedExpenses
        return ExpenseSearch.search(
            searchText,
            expenses: expenses,
            lineItems: repository.lineItemsByExpense(expenses.map(\.id)),
            filter: searchFilter
        )
    }

    /// 検索結果（同じ支出は1件だけ。新しい順）
    var searchResults: [ExpenseSearchResult] { searchOutcome.results }

    /// 月の絞り込みに出す月（表示している範囲で、支出のある月。新しい順）
    var searchMonths: [Date] { ExpenseSearch.months(in: scopedExpenses) }

    var searchMonthTitle: String { searchMonth.map(LifeFormatters.month) ?? "すべての月" }
    var searchCategoryTitle: String { searchCategory?.label ?? "すべてのカテゴリー" }

    /// 検索をやめる（検索語・月・カテゴリーの絞り込みを空にして、通常の一覧へ戻る）
    func clearSearch() {
        searchText = ""
        searchMonth = nil
        searchCategory = nil
    }

    /// 検索結果の補足（カテゴリー・日付・自分だけ／わが家で共有。色だけに頼らず文字で）
    func searchDetailText(for expense: Expense) -> String {
        [expense.category.label, LifeFormatters.dateNoting(expense.date, now: now), destinationLabel(for: expense)].joined(separator: "・")
    }

    /// 検索結果の VoiceOver（店名・補足・合計・一致した商品）
    func searchSpokenLabel(for result: ExpenseSearchResult) -> String {
        var parts = [result.expense.title, searchDetailText(for: result.expense), "合計 \(LifeFormatters.yenSpoken(result.expense.amount))"]
        let shown = result.matchedItems.prefix(ExpenseSearch.maxMatchedItemsShown)
        if !shown.isEmpty {
            parts.append("一致した商品 " + shown.map { "\($0.name) \(LifeFormatters.yenSpoken($0.amount))" }.joined(separator: "、"))
        }
        if result.matchedItems.count > shown.count {
            parts.append("ほか\(result.matchedItems.count - shown.count)件の商品が一致")
        }
        return parts.joined(separator: "、")
    }

    // MARK: - 商品の購入履歴・過去の参考価格（Build 23）

    /// 明細から開く購入履歴（整えた商品名が同じものだけをまとめる）
    func historyTarget(for item: ExpenseLineItem) -> ProductHistoryTarget {
        ProductHistoryTarget(key: PurchaseHistory.key(for: item.name))
    }

    /// その商品の購入履歴（表示している範囲の支出だけ。新しい順）。開くたびに、今の支出と明細から作る
    func purchaseHistory(for target: ProductHistoryTarget) -> ProductPurchaseHistory {
        let expenses = scopedExpenses
        return PurchaseHistory.history(
            forKey: target.key,
            expenses: expenses,
            lineItems: repository.lineItemsByExpense(expenses.map(\.id)),
            scope: effectiveScope
        )
    }

    /// 購入履歴で見ている範囲（色だけに頼らず文字で）
    var historyScopeText: String {
        switch effectiveScope {
        case .all: return showsScopeFilter ? "自分だけ・わが家で共有の両方" : "すべての支出"
        case .mine: return "自分だけ"
        case .shared: return "わが家で共有"
        }
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
        draftMessage = nil
    }

    /// 下書きで選べる保存先か
    func canChoose(_ destination: SaveDestination, in draft: ExpenseDraft) -> Bool {
        // Build 25：定期支出から開いた下書きは、設定と同じ保存先だけ（自分だけに切り替えない）
        if draft.recurring != nil { return destination == draft.originalDestination }
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
        if let recurring = draft.recurring {
            return recurring.isShared
                ? "わが家で共有の定期支出から追加します。保存先は変えられません（共有に保存できないときは、支出を作りません）。"
                : "自分だけの定期支出から追加します。この iPhone の中だけに保存します。"
        }
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
        // Build 25：定期支出の「今月分を追加」。支出1件と「追加済み」を一緒に保存する（自分だけには切り替えない）
        if let recurring = draft.recurring {
            if let error = repository.addRecurringExpense(expense, templateID: recurring.templateID, month: recurring.month) {
                draftMessage = error.message
                return false
            }
            draftMessage = nil
            if self.draft?.id == draft.id { self.draft = nil }
            return true
        }
        let destination = canChoose(draft.destination, in: draft) ? draft.destination : draft.originalDestination
        if draft.isNew {
            // Build 21：レシートから開いたときは、確認画面に残っている商品明細も一緒に保存する（正しい明細だけ）
            let lineItems = draft.isFromReceipt ? draft.lineItemPreparation.items : []
            repository.addExpense(
                expense,
                destination: destination == .household && sharingBlock == nil ? .household : .personal,
                lineItems: lineItems
            )
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
    /// - Parameter detectsDocument: 写真の中のレシートの範囲を見つけて傾きを直すか（書類スキャンで撮ったものは直っているので false。Build 20）
    func readReceipt(_ data: Data, contentType: UTType? = nil, detectsDocument: Bool = true) {
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
            let lines = try? await recognizer.recognizeReceipt(in: data, detectsDocument: detectsDocument)
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

    private func finishReceiptReading(lines: [ReceiptRecognizedLine]?) {
        receiptTask = nil
        isReadingReceipt = false
        openReceiptDraft(lines: lines, failure: .unreadable)
    }

    /// 候補（または手入力用の空の下書き）で支出の追加画面を開く。読み取った文字・位置・信頼度はここで捨てる
    /// （下書きには4項目と、確認用の候補だけ。Build 20：合計の候補・商品明細も確認画面のあいだだけ持つ）
    private func openReceiptDraft(lines: [ReceiptRecognizedLine]?, failure: ReceiptImageError) {
        let proposal = lines.flatMap { lines -> ReceiptExtractionProposal? in
            let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return usable.isEmpty ? nil : ReceiptFieldExtractor.extract(from: usable, today: now)
        }
        draft = ExpenseDraft(receipt: proposal, today: now, failure: proposal == nil ? failure.message : nil)
    }

    // MARK: - 支出の詳細・商品明細（Build 21。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md）

    /// 支出をタップしたとき：詳細画面を開く
    func showDetail(_ expense: Expense) {
        guard draft == nil else { return }
        detailTarget = ExpenseDetailTarget(id: expense.id)
    }

    func closeDetail() {
        detailTarget = nil
    }

    /// 詳細画面の「支出を編集」：詳細画面を閉じ、閉じ終わってから編集画面を開く（画面を重ねない）
    func editFromDetail() {
        guard let id = detailTarget?.id else { return }
        editAfterDetail = id
        detailTarget = nil
    }

    /// 詳細画面が閉じたとき（MoneyView の onDismiss）
    func detailDidClose() {
        guard let id = editAfterDetail else { return }
        editAfterDetail = nil
        if let expense = expense(id: id) { startEditing(expense) }
    }

    /// 支出の商品明細（表示順）。明細の無い支出（古い支出・手入力の支出）は空
    func lineItems(for expense: Expense) -> [ExpenseLineItem] {
        repository.lineItems(for: expense.id)
    }

    /// 商品明細の金額の合計
    func lineItemsTotal(for expense: Expense) -> Int {
        lineItems(for: expense).reduce(0) { $0 + $1.amount }
    }

    /// 商品明細の合計と支出の金額（レシートの合計）の比較
    func lineItemComparison(for expense: Expense) -> ReceiptLineItemComparison {
        ReceiptLineItemComparison.compare(saved: lineItems(for: expense), receiptTotal: expense.amount)
    }

    /// 明細を直せるか（自分だけの支出はいつも。共有の支出は、わが家に参加しているとき）
    func canEditLineItems(_ expense: Expense) -> Bool {
        !expense.isShared || repository.canEditSharedExpenses
    }

    /// 保存先の表示（色だけに頼らず、文字で出す）
    func destinationLabel(for expense: Expense) -> String {
        expense.isShared ? "わが家で共有" : "自分だけ"
    }

    /// 明細1件を直す。直せなければ、理由（画面に出す）を返す。元の明細は失わない
    func updateLineItem(_ original: ExpenseLineItem, in expense: Expense, name: String, quantityText: String, unitPriceText: String, amountText: String) -> String? {
        guard canEditLineItems(expense) else { return ExpenseLineItemSaveError.notEditable.message }
        switch ExpenseLineItemRules.edited(original, name: name, quantityText: quantityText, unitPriceText: unitPriceText, amountText: amountText) {
        case .failure(let error):
            return error.message
        case .success(let item):
            if case .failure(let error) = repository.updateLineItem(item, in: expense.id) { return error.message }
            return nil
        }
    }

    /// 明細1件を消す（支出そのものは消さない）。消せなければ、理由を返す
    func deleteLineItem(_ item: ExpenseLineItem, in expense: Expense) -> String? {
        guard canEditLineItems(expense) else { return ExpenseLineItemSaveError.notEditable.message }
        if case .failure(let error) = repository.deleteLineItem(item.id, in: expense.id) { return error.message }
        return nil
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
