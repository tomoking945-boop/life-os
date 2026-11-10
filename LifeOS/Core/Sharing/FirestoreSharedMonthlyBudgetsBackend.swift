import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// わが家の共有予算を Firestore で読み書きする実装（2026-11-10 Build 24。docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md）
///
/// - 読み書きするのは groups/{groupID}/monthlyBudgets だけ（月ごとに文書1つ。文書の ID は YYYY-MM）
/// - 書く項目は SharedMonthlyBudgetPayload が決めたものと、updatedBy（サインインしている本人の UID）・updatedAt（サーバーの時刻）だけ
/// - サインインしていなければ書かない
/// - オフラインのあいだの変更は、Firestore が端末にためておき、つながったら送る（標準の設定のまま）
/// - 端末の中の Firestore の片付け（FirestoreLocalCacheRepair）が終わってから使う
/// - エラーの中身・金額は画面・ログに出さず、決まった種類（SharedItemsFailure）に分けるだけ
final class FirestoreSharedMonthlyBudgetsBackend: SharedMonthlyBudgetsBackend {
    private var db: Firestore { Firestore.firestore() }

    private func budgets(_ groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("monthlyBudgets")
    }

    func listen(groupID: String, onChange: @escaping ([SharedMonthlyBudgetSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        let holder = BudgetListenerHolder()
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            holder.attach { self.startListening(groupID: groupID, onChange: onChange, onError: onError) }
        }
        return RepositoryObservation { holder.cancel() }
    }

    private func startListening(groupID: String, onChange: @escaping ([SharedMonthlyBudgetSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> ListenerRegistration {
        budgets(groupID).addSnapshotListener { snapshot, error in
            if let error {
                onError(Self.failure(from: error))
                return
            }
            guard let snapshot else { return }
            onChange(snapshot.documents.compactMap { document in
                SharedMonthlyBudgetPayload.snapshot(documentID: document.documentID, data: document.data())
            })
        }
    }

    func set(groupID: String, month: BudgetMonth, fields: [String: Any], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.notSignedIn)
            return
        }
        var data = fields
        data["updatedBy"] = uid
        data["updatedAt"] = FieldValue.serverTimestamp()
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.budgets(groupID).document(month.key).setData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func delete(groupID: String, month: BudgetMonth, completion: @escaping (SharedItemsFailure?) -> Void) {
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.budgets(groupID).document(month.key).delete { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    /// Firestore のエラーを、画面で説明できる種類に分ける（エラーの中身は出さない）。
    /// コードは gRPC と同じ番号（7：権限が無い、16：サインインしていない、14・4：通信できない）
    private static func failure(from error: Error) -> SharedItemsFailure {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else { return .other }
        switch nsError.code {
        case 7: return .permissionDenied
        case 16: return .notSignedIn
        case 14, 4: return .unavailable
        default: return .other
        }
    }
}

/// 見張りの登録を持つ（片付けを待つあいだに解除されたら、始めない）
private final class BudgetListenerHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: ListenerRegistration?
    private var isCancelled = false

    func attach(_ start: () -> ListenerRegistration) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled, registration == nil else { return }
        registration = start()
    }

    func cancel() {
        lock.lock()
        let current = registration
        registration = nil
        isCancelled = true
        lock.unlock()
        current?.remove()
    }
}
#endif
