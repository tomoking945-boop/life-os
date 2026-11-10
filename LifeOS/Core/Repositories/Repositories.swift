import Foundation

// v2 仕様 22：Repository 化の準備。
// 画面（ViewModel）は LifeStore そのものではなく、この「データの出し入れの窓口」を通して読み書きする。
// 今は LifeStore（端末内の JSON 保存）が全部を担当しているが、将来 Firestore に移すときは
// 同じ窓口を持つ FirestoreXxxRepository を作って差し替える。設計は docs/REPOSITORY_DESIGN.md を参照。
//
// 段階的に移行する：第6回では お金（MoneyViewModel）と リスト（ListsViewModel）を切り替え済み。
// TODO: 今日・カレンダー・やること・Inbox・暮らしメモリー・家事・買い物の ViewModel も順に切り替える。

/// 予定・ToDo・家事・買い物・支払予定・習慣
protocol LifeItemRepository: AnyObject {
    var items: [LifeItem] { get }
    func items(on day: Date, scope: ScopeFilter) -> [LifeItem]
    func leftovers(before day: Date, scope: ScopeFilter) -> [LifeItem]
    func add(_ newItems: [LifeItem])
    func toggleCompletion(of id: LifeItem.ID)
    func reschedule(_ id: LifeItem.ID, to date: Date)
    func drop(_ id: LifeItem.ID, at date: Date)
    func share(_ id: LifeItem.ID)
    /// 予定を1件だけ消す（2026-11-01 Build 13）。予定でない項目（ToDo・買い物・家事など）・共有項目は消さない
    @discardableResult func deleteEvent(_ id: LifeItem.ID) -> Bool

    // MARK: パートナー共有（2026-10-11）：非同期・監視の窓口（後方互換：既定の実装あり）
    // Firestore では書き込みの失敗・オフラインがあり、相手の変更を受け取る必要があるため追加した。
    // 端末内（LifeStore）は失敗しないので、既定の実装は同期の処理をそのまま呼ぶ。

    /// 項目の変更を監視する。登録した直後に今の一覧で1回呼ばれ、変わるたびに呼ばれる
    func observeItems(_ onChange: @escaping ([LifeItem]) -> Void) -> RepositoryObservation

    func addAsync(_ newItems: [LifeItem]) async throws
    func toggleCompletionAsync(of id: LifeItem.ID) async throws
    func rescheduleAsync(_ id: LifeItem.ID, to date: Date) async throws
    func dropAsync(_ id: LifeItem.ID, at date: Date) async throws
    func shareAsync(_ id: LifeItem.ID) async throws
}

extension LifeItemRepository {
    /// 既定：今の一覧で1回だけ呼ぶ（変更を知らせる仕組みが無い保存先向け）
    func observeItems(_ onChange: @escaping ([LifeItem]) -> Void) -> RepositoryObservation {
        onChange(items)
        return RepositoryObservation {}
    }

    func addAsync(_ newItems: [LifeItem]) async throws { add(newItems) }
    func toggleCompletionAsync(of id: LifeItem.ID) async throws { toggleCompletion(of: id) }
    func rescheduleAsync(_ id: LifeItem.ID, to date: Date) async throws { reschedule(id, to: date) }
    func dropAsync(_ id: LifeItem.ID, at date: Date) async throws { drop(id, at: date) }
    func shareAsync(_ id: LifeItem.ID) async throws { share(id) }
}

/// 監視の解除（Firestore の Listener を外すのと同じ役目）。cancel を呼ぶか、手放すと解除される
final class RepositoryObservation {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit {
        cancel()
    }
}

/// 保存先の失敗（Firestore 接続後に使う。端末内では起きない）
enum RepositoryError: Error, Equatable {
    /// サインインしていない
    case notSignedIn
    /// 権限が無い（生活グループのメンバーでない など）
    case permissionDenied
    /// 共有できない項目（個人項目など）を共有の保存先へ送ろうとした
    case notShareable
    /// そのほか
    case failed(String)
}

/// お金（支出と今月の予算）
protocol ExpenseRepository: AnyObject {
    /// 端末に保存している「自分だけ」の支出
    var expenses: [Expense] { get }
    var budget: MonthlyBudget { get }
    func add(_ expense: Expense)

    // MARK: 家計簿：自分だけ／わが家で共有（2026-11-01 Build 13）
    /// 画面に出す支出（自分だけ＋共有。範囲で絞る。同じ支出は1回だけ）
    func visibleExpenses(scope: ScopeFilter) -> [Expense]
    /// 新しく「わが家で共有」にできない理由（できるなら nil）
    var expenseSharingBlock: ExpenseSharingBlock? { get }
    /// 共有の支出を変更・削除できるか
    var canEditSharedExpenses: Bool { get }
    @discardableResult func addExpense(_ expense: Expense, destination: SaveDestination) -> Bool
    @discardableResult func updateExpense(_ updated: Expense) -> Bool
    @discardableResult func deleteExpense(_ id: Expense.ID) -> Bool
    @discardableResult func changeExpenseDestination(_ id: Expense.ID, to destination: SaveDestination) -> Bool

    // MARK: 支出の商品明細（2026-11-08 Build 21）
    /// 支出を、確かめた商品明細と一緒に足す（同じ ID の支出がすでにあれば何もしない）
    @discardableResult func addExpense(_ expense: Expense, destination: SaveDestination, lineItems: [ExpenseLineItem]) -> Bool
    /// 支出の商品明細（表示順。無ければ空）
    func lineItems(for id: Expense.ID) -> [ExpenseLineItem]
    /// 複数の支出の商品明細をまとめて（Build 23。検索・購入履歴用。明細の無い支出は入らない）。
    /// 1件ずつの lineItems(for:) と同じ決まり（自分だけの支出は端末の明細、共有の支出はわが家の明細）
    func lineItemsByExpense(_ ids: [Expense.ID]) -> [Expense.ID: [ExpenseLineItem]]

    // MARK: 月の予算（2026-11-10 Build 24）
    /// その月の予算（未設定なら nil）。自分だけは端末、わが家で共有は Firestore の予算
    func monthlyBudget(for month: BudgetMonth, scope: BudgetScope) -> MonthlyBudgetPlan?
    /// 月の予算を置く・解除する（nil なら解除）。保存できなければ理由（元の予算のまま）
    @discardableResult func setMonthlyBudget(_ plan: MonthlyBudgetPlan?, for month: BudgetMonth, scope: BudgetScope) -> BudgetInputError?
    /// 新しく、わが家の予算を作れない理由（作れるなら nil）
    var householdBudgetBlock: ExpenseSharingBlock? { get }
    /// すでにある、わが家の予算を変える・解除できるか
    var canEditHouseholdBudgets: Bool { get }
    /// 明細1件を直す
    @discardableResult func updateLineItem(_ item: ExpenseLineItem, in id: Expense.ID) -> Result<[ExpenseLineItem], ExpenseLineItemSaveError>
    /// 明細1件を消す（支出そのものは消さない）
    @discardableResult func deleteLineItem(_ itemID: ExpenseLineItem.ID, in id: Expense.ID) -> Result<[ExpenseLineItem], ExpenseLineItemSaveError>
}

/// リスト（行きたい場所・観たいもの など）
protocol ListRepository: AnyObject {
    var lists: [LifeList] { get }
    func list(id: LifeList.ID) -> LifeList?
    func addList(title: String)
    func addItem(_ title: String, toList id: LifeList.ID)
    func removeItems(at offsets: IndexSet, fromList id: LifeList.ID)
}

/// おまかせInbox
protocol InboxRepository: AnyObject {
    var inbox: [InboxItem] { get }
    func addToInbox(_ text: String, now: Date)
    func removeFromInbox(_ ids: Set<InboxItem.ID>)
    func postponeInbox(_ ids: Set<InboxItem.ID>, until date: Date)
}

/// 保証書（Premium「大切な書類」2026-10-13）。端末内にだけ保存する
protocol WarrantyRepository: AnyObject {
    var warranties: [WarrantyDocument] { get }
    var warrantyAttachments: [WarrantyAttachment] { get }
    var warrantyStorage: WarrantyAttachmentStorage { get }
    func warranty(id: WarrantyDocument.ID) -> WarrantyDocument?
    func attachments(for documentID: WarrantyDocument.ID) -> [WarrantyAttachment]
    func warrantyContainingImage(sha256: String) -> WarrantyDocument?
    @discardableResult
    func saveWarranty(
        _ document: WarrantyDocument,
        adding newFiles: [WarrantyStagedFile],
        removing removedAttachmentIDs: Set<WarrantyAttachment.ID>,
        now: Date
    ) throws -> WarrantyDocument
    func deleteWarranty(id: WarrantyDocument.ID)
    func deleteWarrantyAttachment(id: WarrantyAttachment.ID)
}

// 今は LifeStore がすべての窓口を担当する（メソッドはすでに同じ形で持っている）
extension LifeStore: LifeItemRepository {}
extension LifeStore: ExpenseRepository {}
extension LifeStore: ListRepository {}
extension LifeStore: InboxRepository {}
extension LifeStore: WarrantyRepository {}
