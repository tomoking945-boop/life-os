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
