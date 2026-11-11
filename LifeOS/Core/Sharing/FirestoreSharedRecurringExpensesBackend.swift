import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// わが家で共有の定期支出を Firestore で読み書きする実装（2026-11-11 Build 25。docs/BUILD_25_RECURRING_EXPENSES.md）
///
/// - 読み書きするのは groups/{groupID}/recurringExpenses・recurringExpenseOccurrences と、
///   「今月分を追加」のときの groups/{groupID}/expenses（共有の支出）だけ
/// - 「今月分を追加」は、共有の支出と「追加済み」の記録を1回の書き込み（WriteBatch）で一緒に送る。
///   全部が成功するか、全部が失敗する（片方だけにはならない）。同じ月の記録がすでにあれば Security Rules が断る
/// - 書く項目は SharedRecurringExpensePayload・SharedExpensePayload が決めたものだけ（本人の UID・サーバーの時刻は、ここで入れる）
/// - サインインしていなければ書かない
/// - 端末の中の Firestore の片付け（FirestoreLocalCacheRepair）が終わってから使う
/// - エラーの中身・名前・金額は画面・ログに出さず、決まった種類（SharedItemsFailure）に分けるだけ
final class FirestoreSharedRecurringExpensesBackend: SharedRecurringExpensesBackend {
    private var db: Firestore { Firestore.firestore() }

    private func group(_ groupID: String) -> DocumentReference {
        db.collection("groups").document(groupID)
    }

    func listenTemplates(groupID: String, onChange: @escaping ([RecurringExpenseTemplate]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listen(group(groupID).collection("recurringExpenses"), onError: onError) { documents in
            onChange(documents.compactMap { SharedRecurringExpensePayload.template(documentID: $0.documentID, data: $0.data()) })
        }
    }

    func listenOccurrences(groupID: String, onChange: @escaping ([RecurringOccurrence]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        listen(group(groupID).collection("recurringExpenseOccurrences"), onError: onError) { documents in
            onChange(documents.compactMap { SharedRecurringExpensePayload.occurrence(documentID: $0.documentID, data: $0.data()) })
        }
    }

    private func listen(_ collection: CollectionReference, onError: @escaping (SharedItemsFailure) -> Void, onChange: @escaping ([QueryDocumentSnapshot]) -> Void) -> RepositoryObservation {
        let holder = RecurringListenerHolder()
        FirestoreAccessGate.shared.whenOpen {
            holder.attach {
                collection.addSnapshotListener { snapshot, error in
                    if let error {
                        onError(Self.failure(from: error))
                        return
                    }
                    guard let snapshot else { return }
                    onChange(snapshot.documents)
                }
            }
        }
        return RepositoryObservation { holder.cancel() }
    }

    func createTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.group(groupID).collection("recurringExpenses").document(id.uuidString).setData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func updateTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.group(groupID).collection("recurringExpenses").document(id.uuidString).updateData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func createSkippedOccurrence(groupID: String, occurrenceID: String, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.group(groupID).collection("recurringExpenseOccurrences").document(occurrenceID).setData(data) { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func deleteSkippedOccurrence(groupID: String, occurrenceID: String, completion: @escaping (SharedItemsFailure?) -> Void) {
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            self.group(groupID).collection("recurringExpenseOccurrences").document(occurrenceID).delete { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    func createExpenseWithOccurrence(
        groupID: String,
        expenseID: UUID,
        expenseFields: [String: SharedItemValue],
        occurrenceID: String,
        occurrenceFields: [String: SharedItemValue],
        completion: @escaping (SharedItemsFailure?) -> Void
    ) {
        guard let expenseData = firestoreData(expenseFields), let occurrenceData = firestoreData(occurrenceFields) else {
            completion(.notSignedIn)
            return
        }
        FirestoreAccessGate.shared.whenOpen { [weak self] in
            guard let self else { return }
            // 1回の書き込み：共有の支出と「追加済み」の記録を一緒に（全部が成功するか、全部が失敗する）
            let batch = self.db.batch()
            batch.setData(expenseData, forDocument: self.group(groupID).collection("expenses").document(expenseID.uuidString))
            batch.setData(occurrenceData, forDocument: self.group(groupID).collection("recurringExpenseOccurrences").document(occurrenceID))
            batch.commit { error in
                completion(error.map(Self.failure(from:)))
            }
        }
    }

    /// 送る値を Firestore の値にする（本人の UID・サーバーの時刻はここで入れる）。サインインしていなければ nil
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
private final class RecurringListenerHolder: @unchecked Sendable {
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
