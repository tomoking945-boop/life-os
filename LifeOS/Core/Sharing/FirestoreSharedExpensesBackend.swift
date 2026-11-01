import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// わが家の共有の支出を Firestore で読み書きする実装（2026-11-01 Build 13。docs/BUILD_13_SHARED_HOUSEHOLD_BUDGET_AND_EVENT_DELETE.md）
///
/// - 読み書きするのは groups/{groupID}/expenses だけ（共有 ToDo・買い物の items とは別）
/// - 書く項目は SharedExpensePayload が決めたものだけ。作成者・更新者には、サインインしている本人の UID を入れる（画面・ログには出さない）
/// - 作成日時・更新日時はサーバーの時刻
/// - オフラインのあいだの変更は、Firestore が端末にためておき、つながったら送る（標準の設定のまま）
/// - 端末の中の Firestore の片付け（FirestoreLocalCacheRepair）が終わってから使う
/// - エラーの中身・金額・支出名は画面・ログに出さず、決まった種類（SharedItemsFailure）に分けるだけ
final class FirestoreSharedExpensesBackend: SharedExpensesBackend {
    private var db: Firestore { Firestore.firestore() }

    private func expenses(_ groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("expenses")
    }

    func listen(groupID: String, onChange: @escaping ([SharedExpenseSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        let holder = ExpenseListenerHolder()
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            holder.attach { self.startListening(groupID: groupID, onChange: onChange, onError: onError) }
        }
        return RepositoryObservation { holder.cancel() }
    }

    private func startListening(groupID: String, onChange: @escaping ([SharedExpenseSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> ListenerRegistration {
        // 送信待ち → サーバーで確かめられた、の変化も受け取る（保存先の変更の片付けに使う）。
        // 同じ内容なら LifeStore が入れ替えないので、印の変化だけで画面を描き直し続けることはない
        expenses(groupID).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error {
                onError(Self.failure(from: error))
                return
            }
            guard let snapshot else { return }
            let result = snapshot.documents.compactMap { document -> SharedExpenseSnapshot? in
                guard let expense = SharedExpensePayload.expense(documentID: document.documentID, data: Self.plain(document.data())) else {
                    return nil
                }
                return SharedExpenseSnapshot(expense: expense, isConfirmed: !document.metadata.hasPendingWrites)
            }
            onChange(result)
        }
    }

    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.expenses(groupID).document(id.uuidString).setData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.expenses(groupID).document(id.uuidString).updateData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.expenses(groupID).document(id.uuidString).delete { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    /// 決まった値を Firestore の値にする。サインインしていなければ nil（送らない）
    private func firestoreData(_ fields: [String: SharedItemValue]) -> [String: Any]? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        var data: [String: Any] = [:]
        for (key, value) in fields {
            switch value {
            case .string(let text): data[key] = text
            case .bool(let flag): data[key] = flag
            case .int(let number): data[key] = number
            case .date(let date): data[key] = Timestamp(date: date)
            case .null: data[key] = NSNull()
            case .serverTimestamp: data[key] = FieldValue.serverTimestamp()
            case .currentUser: data[key] = uid
            }
        }
        return data
    }

    /// 受け取った値の日時（Timestamp）を Date にする
    private static func plain(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in data {
            if let timestamp = value as? Timestamp {
                result[key] = timestamp.dateValue()
            } else {
                result[key] = value
            }
        }
        return result
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
private final class ExpenseListenerHolder: @unchecked Sendable {
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
