import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// わが家の共有の支出の商品明細を Firestore で読み書きする実装（2026-11-08 Build 21。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md）
///
/// - 読み書きするのは groups/{groupID}/expenseLineItems だけ（支出1件に文書1つ。文書の ID は支出の UUID）
/// - 書く項目は schemaVersion と rows だけ（SharedExpenseLineItemsPayload が作る）。UID・端末の情報は書かない
/// - サインインしていなければ書かない
/// - オフラインのあいだの変更は、Firestore が端末にためておき、つながったら送る（標準の設定のまま）。
///   支出の作成のあとに明細を置き、明細を消してから支出を消す（同じ Firestore の送信の列に、頼んだ順に並ぶ）
/// - 端末の中の Firestore の片付け（FirestoreLocalCacheRepair）が終わってから使う
/// - エラーの中身・商品名・金額は画面・ログに出さず、決まった種類（SharedItemsFailure）に分けるだけ
final class FirestoreSharedExpenseLineItemsBackend: SharedExpenseLineItemsBackend {
    private var db: Firestore { Firestore.firestore() }

    private func lineItems(_ groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("expenseLineItems")
    }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseLineItemsSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        let holder = LineItemsListenerHolder()
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            holder.attach { self.startListening(groupID: groupID, onChange: onChange, onError: onError) }
        }
        return RepositoryObservation { holder.cancel() }
    }

    private func startListening(groupID: String, onChange: @escaping ([SharedExpenseLineItemsSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> ListenerRegistration {
        lineItems(groupID).addSnapshotListener { snapshot, error in
            if let error {
                onError(Self.failure(from: error))
                return
            }
            guard let snapshot else { return }
            onChange(snapshot.documents.compactMap { document in
                SharedExpenseLineItemsPayload.items(documentID: document.documentID, data: document.data())
            })
        }
    }

    func set(groupID: String, expenseID: UUID, rows: [String], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion(.notSignedIn)
            return
        }
        let data: [String: Any] = [
            "schemaVersion": SharedExpenseLineItemsPayload.schemaVersion,
            "rows": rows,
        ]
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.lineItems(groupID).document(expenseID.uuidString).setData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func delete(groupID: String, expenseID: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.lineItems(groupID).document(expenseID.uuidString).delete { error in
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
private final class LineItemsListenerHolder: @unchecked Sendable {
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
