import Foundation
import Observation

// わが家で共有する家計簿の支出（2026-11-01 Build 13）。docs/BUILD_13_SHARED_HOUSEHOLD_BUDGET_AND_EVENT_DELETE.md
//
// - 共有するのは、利用者が「わが家で共有」を選んだ支出の明細だけ。保存先は Firestore の groups/{groupID}/expenses/{expenseID}
//   （共有 ToDo・買い物の items とは別のコレクション。形も別）
// - 送るのは：schemaVersion・タイトル・金額・カテゴリー・日付・作成者・更新者・作成日時・更新日時だけ
// - 送らないもの：月の予算・レシートの画像・メモ・メールアドレス・端末の情報・個人の支出・保証書・予定
// - 個人の支出は、これまでどおり端末の中（life-store.json）だけ。共有の支出は端末に保存しない（起動中だけ持ち、Firestore から読み直す）
// - 文書の ID は支出の UUID（同じ操作をくり返しても1件のまま）
// - 共有の支出の通知は作らない（Functions の通知は items だけ）
// - UID・トークン・金額・支出名はログに出さない

/// groups/{groupID}/expenses/{expenseID} に書く内容・読む内容
enum SharedExpensePayload {
    /// 保存の形の版
    static let schemaVersion = 1
    /// タイトルの長さの上限（Security Rules と同じ 200）
    static let maxTitleLength = 200
    /// 金額の上限（Security Rules と同じ）
    static let maxAmount = 999_999_999

    /// 共有できる支出か（タイトルが空でなく、金額が 1〜999,999,999 円）
    static func canShare(_ expense: Expense) -> Bool {
        !SharedItemPayload.title(expense.title).isEmpty && (1...maxAmount).contains(expense.amount)
    }

    /// 作るときに送る項目（決まった項目だけ）。共有できない支出なら nil
    static func createFields(for expense: Expense) -> [String: SharedItemValue]? {
        guard canShare(expense) else { return nil }
        return [
            "schemaVersion": .int(schemaVersion),
            "title": .string(title(expense.title)),
            "amount": .int(expense.amount),
            "category": .string(expense.category.rawValue),
            "date": .date(expense.date),
            "createdBy": .currentUser,
            "updatedBy": .currentUser,
            "createdAt": .serverTimestamp,
            "updatedAt": .serverTimestamp,
        ]
    }

    /// 変えるときに送る項目（作成者・作成日時・schemaVersion は送らない＝変えない）
    static func updateFields(for expense: Expense) -> [String: SharedItemValue]? {
        guard canShare(expense) else { return nil }
        return [
            "title": .string(title(expense.title)),
            "amount": .int(expense.amount),
            "category": .string(expense.category.rawValue),
            "date": .date(expense.date),
            "updatedBy": .currentUser,
            "updatedAt": .serverTimestamp,
        ]
    }

    static func title(_ text: String) -> String {
        SharedItemPayload.title(text)
    }

    /// 受け取った文書を、画面に出す支出にする（日時は Date にしてから渡す）。形が違うものは nil（表示しない）
    static func expense(documentID: String, data: [String: Any]) -> Expense? {
        guard let id = UUID(uuidString: documentID),
              let title = data["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = data["amount"] as? Int,
              (1...maxAmount).contains(amount),
              let categoryText = data["category"] as? String,
              let category = ExpenseCategory(rawValue: categoryText),
              let date = data["date"] as? Date else {
            return nil
        }
        return Expense(id: id, title: title, amount: amount, category: category, date: date, ownership: .shared)
    }
}

/// 受け取った共有の支出1件
struct SharedExpenseSnapshot: Equatable {
    let expense: Expense
    /// サーバーで保存が確かめられたか（まだ送信待ちの自分の変更なら false）
    let isConfirmed: Bool
}

/// 「わが家で共有」を選べない理由（画面に日本語で出す）
enum ExpenseSharingBlock: Equatable {
    /// 一人で使う設定
    case soloMode
    /// Firebase に接続していない
    case notConnected
    /// サインインしていない
    case notSignedIn
    /// わが家に参加していない
    case notJoined
    /// わが家の設定で「家計簿」がオフ
    case moneyOff

    var message: String {
        switch self {
        case .soloMode: return "一人で使う設定のため、自分だけに保存します。"
        case .notConnected: return "共有の準備ができていないため、自分だけに保存します。"
        case .notSignedIn: return "Appleでサインインして、わが家に参加すると共有できます。"
        case .notJoined: return "わが家に参加すると共有できます。"
        case .moneyOff: return "わが家の設定で「家計簿」がオフのため、共有できません。"
        }
    }
}

// MARK: - 窓口（テストでは偽物に差し替える）

/// 共有の支出の保存先（Firestore）。オフラインのときは Firestore が端末にためて、つながったら送る
protocol SharedExpensesBackend: AnyObject {
    /// groups/{groupID}/expenses を見張る。変わるたびに一覧で呼ぶ（自分の送信待ちの変更も含む）
    func listen(groupID: String, onChange: @escaping ([SharedExpenseSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// 作る（文書の ID は支出の UUID）。completion はサーバーが受け付けた・断ったとき（オフラインのあいだは呼ばれない）
    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void)
}

/// LifeStore から共有の支出の保存を頼む先
protocol HouseholdExpenseSyncing: AnyObject {
    /// 新しく「わが家で共有」にできない理由（できるなら nil）
    var expenseSharingBlock: ExpenseSharingBlock? { get }
    /// 共有の支出を変更・削除できるか（わが家に参加していれば、家計簿がオフでもできる）
    var canEditSharedExpenses: Bool { get }
    /// 作る。convertingPersonal は「自分だけの支出を共有に変える」とき（保存が確かめられてから端末の支出を片付ける）
    func createSharedExpense(_ expense: Expense, convertingPersonal: Bool)
    func updateSharedExpense(_ expense: Expense)
    /// 消す。keepingPersonalCopy は「共有を自分だけに変える」とき（失敗したら端末の写しを片付けて共有のまま残す）
    func deleteSharedExpense(_ expense: Expense, keepingPersonalCopy: Bool)
}

// MARK: - わが家の共有の支出をまとめる

/// わが家の共有の支出の見張り・保存（画面はこのクラスと LifeStore だけを使う。Firestore は直接使わない）
@Observable
final class SharedExpensesService: HouseholdExpenseSyncing {
    enum Status: Equatable {
        case off
        case connecting
        case live
        case failed(SharedItemsFailure)
    }

    private(set) var status: Status = .off
    /// 共有の操作がうまくいかなかったときの一言（画面で閉じる）
    private(set) var notice: String?
    private(set) var lastFailure: SharedItemsFailure?
    /// わが家の設定で「家計簿」がオンか
    private(set) var isMoneyEnabled = false
    /// わが家に参加しているか（見張りの対象があるか）
    private(set) var isJoined = false
    /// サインインしているか（理由の表示に使う）
    private(set) var isSignedIn = false
    /// 見張っているわが家（文書の ID。画面・ログには出さない）
    @ObservationIgnored private(set) var groupID: String?

    @ObservationIgnored private let backend: SharedExpensesBackend?
    @ObservationIgnored private weak var store: LifeStore?
    @ObservationIgnored private var observation: RepositoryObservation?
    /// 確認用：見張りを始めた回数。見張りは常に最大1つ（activeListenerCount）
    @ObservationIgnored private(set) var listenStartCount = 0
    var activeListenerCount: Int { observation == nil ? 0 : 1 }

    init(backend: SharedExpensesBackend?) {
        self.backend = backend
    }

    var isAvailable: Bool { backend != nil }

    /// 端末の支出の置き場とつなぐ（起動時に1回）
    func attach(_ store: LifeStore) {
        guard self.store !== store else { return }
        self.store = store
        store.expenseSync = self
    }

    /// わが家の情報が変わったとき（参加・退出・削除・サインアウト・設定の変更）。何度呼ばれても見張りは1つ
    func apply(household: HouseholdSummary?, isSignedIn: Bool) {
        if self.isSignedIn != isSignedIn { self.isSignedIn = isSignedIn }
        let moneyOn = household?.allowsSharing(.money) ?? false
        if isMoneyEnabled != moneyOn { isMoneyEnabled = moneyOn }
        let newGroupID = (backend == nil || !isSignedIn) ? nil : household?.groupID
        if isJoined != (newGroupID != nil) { isJoined = newGroupID != nil }
        guard newGroupID != groupID else { return }

        // わが家が変わった・抜けた：前の見張りをやめ、共有の支出の表示だけを消す（端末の個人の支出は消さない）
        observation?.cancel()
        observation = nil
        groupID = newGroupID
        store?.clearHouseholdExpenses()
        guard let backend, let newGroupID else {
            status = .off
            return
        }
        status = .connecting
        listenStartCount += 1
        observation = backend.listen(groupID: newGroupID, onChange: { [weak self] snapshots in
            guard let self, self.groupID == newGroupID else { return }
            if self.status != .live { self.status = .live }
            self.store?.applySharedExpenseSnapshot(snapshots)
        }, onError: { [weak self] failure in
            guard let self, self.groupID == newGroupID else { return }
            self.status = .failed(failure)
            self.lastFailure = failure
            if failure == .permissionDenied {
                self.store?.clearHouseholdExpenses()
            }
        })
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: HouseholdExpenseSyncing

    var expenseSharingBlock: ExpenseSharingBlock? {
        if backend == nil { return .notConnected }
        if !isSignedIn { return .notSignedIn }
        if !isJoined || groupID == nil { return .notJoined }
        if !isMoneyEnabled { return .moneyOff }
        return nil
    }

    var canEditSharedExpenses: Bool {
        backend != nil && isJoined && groupID != nil
    }

    func createSharedExpense(_ expense: Expense, convertingPersonal: Bool) {
        guard expenseSharingBlock == nil, let backend, let groupID,
              let fields = SharedExpensePayload.createFields(for: expense) else {
            store?.sharedExpenseCreateFailed(expense, convertingPersonal: convertingPersonal)
            report(.other, fallback: true)
            return
        }
        backend.create(groupID: groupID, id: expense.id, fields: fields) { [weak self] failure in
            guard let self else { return }
            if let failure {
                // 断られた：「自分だけ」の支出として端末に残す（消さない。2件にしない）
                self.store?.sharedExpenseCreateFailed(expense, convertingPersonal: convertingPersonal)
                self.report(failure, fallback: true)
            } else {
                // サーバーに保存できた：送信待ちの印を外す。変換なら、ここで初めて端末の個人の支出を片付ける
                self.store?.finishSharedExpenseCreate(expense.id, convertingPersonal: convertingPersonal)
            }
        }
    }

    func updateSharedExpense(_ expense: Expense) {
        guard canEditSharedExpenses, let backend, let groupID,
              let fields = SharedExpensePayload.updateFields(for: expense) else { return }
        backend.update(groupID: groupID, id: expense.id, fields: fields) { [weak self] failure in
            guard let failure else { return }
            self?.lastFailure = failure
            self?.notice = "共有の支出の変更を保存できませんでした（\(failure.reason)）。"
        }
    }

    func deleteSharedExpense(_ expense: Expense, keepingPersonalCopy: Bool) {
        guard canEditSharedExpenses, let backend, let groupID else {
            if keepingPersonalCopy { store?.sharedExpenseConversionFailed(expense) }
            return
        }
        backend.delete(groupID: groupID, id: expense.id) { [weak self] failure in
            guard let self, let failure else { return }
            self.lastFailure = failure
            if keepingPersonalCopy {
                // 共有から自分だけへの変更に失敗：端末の写しを片付け、共有のまま残す（データを失わない・2件にしない）
                self.store?.sharedExpenseConversionFailed(expense)
                self.notice = "自分だけに変更できませんでした（\(failure.reason)）。共有のまま残しています。"
            } else {
                self.notice = "共有の支出の削除を保存できませんでした（\(failure.reason)）。"
            }
        }
    }

    private func report(_ failure: SharedItemsFailure, fallback: Bool) {
        lastFailure = failure
        notice = fallback ? failure.fallbackNotice : failure.message
    }
}

extension SharedExpensesService {
    /// アプリ全体で使う1つ（起動時の Firebase の設定の結果に合わせて作る）
    static let live: SharedExpensesService = {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        if FirebaseBootstrap.result == .configured {
            return SharedExpensesService(backend: FirestoreSharedExpensesBackend())
        }
        #endif
        return SharedExpensesService(backend: nil)
    }()
}
