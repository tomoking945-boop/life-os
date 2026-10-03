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
}

/// お金（支出と今月の予算）
protocol ExpenseRepository: AnyObject {
    var expenses: [Expense] { get }
    var budget: MonthlyBudget { get }
    func add(_ expense: Expense)
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

// 今は LifeStore がすべての窓口を担当する（メソッドはすでに同じ形で持っている）
extension LifeStore: LifeItemRepository {}
extension LifeStore: ExpenseRepository {}
extension LifeStore: ListRepository {}
extension LifeStore: InboxRepository {}
