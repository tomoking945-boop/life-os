import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// わが家の共有項目を Firestore で読み書きする実装（2026-10-28。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）
///
/// - アプリの中で Firestore を使うのは、このファイルだけ。読み書きするのは groups/{groupID}/items だけ
/// - 書く項目は SharedItemPayload が決めたものだけ。作成者・更新者には、サインインしている本人の UID を入れる（画面・ログには出さない）
/// - 作成日時・更新日時はサーバーの時刻（端末の時刻で競合を決めない）
/// - オフラインのあいだの変更は、Firestore が端末にためておき、つながったら送る（標準の設定のまま）
/// - エラーの中身は画面・ログに出さず、決まった種類（SharedItemsFailure）に分けるだけ
final class FirestoreSharedItemsBackend: SharedItemsBackend {
    private var db: Firestore { Firestore.firestore() }

    private func items(_ groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("items")
    }

    func listen(groupID: String, onChange: @escaping ([SharedItemSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation {
        // includeMetadataChanges：送信待ち → サーバーで確かめられた、の変化も受け取る（共有への変換の片付けに使う）
        let registration = items(groupID).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error {
                onError(Self.failure(from: error))
                return
            }
            guard let snapshot else { return }
            let result = snapshot.documents.compactMap { document -> SharedItemSnapshot? in
                guard let item = SharedItemPayload.item(documentID: document.documentID, data: Self.plain(document.data())) else {
                    return nil
                }
                return SharedItemSnapshot(item: item, isConfirmed: !document.metadata.hasPendingWrites)
            }
            onChange(result)
        }
        return RepositoryObservation { registration.remove() }
    }

    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        items(groupID).document(id.uuidString).setData(data) { error in
            completion(error.map(Self.failure(from:)))
        }
    }

    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void) {
        guard let data = firestoreData(fields) else {
            completion(.notSignedIn)
            return
        }
        items(groupID).document(id.uuidString).updateData(data) { error in
            completion(error.map(Self.failure(from:)))
        }
    }

    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void) {
        items(groupID).document(id.uuidString).delete { error in
            completion(error.map(Self.failure(from:)))
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

    // MARK: - 共有の状態の確認（読み取りだけ。2026-10-28 Build 9）

    /// サインイン・サインインの更新・わが家の文書・自分のメンバー文書・共有項目の読み取りを、サーバーに直接たずねる。
    /// 書き込みはしない。結果は決まった番号だけ（エラーの文・UID・トークンは出さない・保存しない）
    func diagnose(groupID: String) async -> SharedSyncCheck {
        var check = SharedSyncCheck.notAvailable
        guard let user = Auth.auth().currentUser else { return check }
        check.isSignedIn = true
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: true)
            check.tokenRefresh = .ok
        } catch {
            check.tokenRefresh = .failed(code: (error as NSError).code)
        }
        let groupRef = db.collection("groups").document(groupID)
        do {
            let group = try await groupRef.getDocument(source: .server)
            check.groupRead = group.exists ? .ok : .missing
            let kinds = group.get("sharedKinds") as? [String] ?? []
            check.serverKinds = kinds.filter { name in HouseholdItemPolicy.kinds.contains { $0.rawValue == name } }
        } catch {
            check.groupRead = .failed(code: (error as NSError).code)
        }
        do {
            let member = try await groupRef.collection("members").document(user.uid).getDocument(source: .server)
            check.memberDocument = member.exists ? .ok : .missing
        } catch {
            check.memberDocument = .failed(code: (error as NSError).code)
        }
        do {
            _ = try await items(groupID).limit(to: 1).getDocuments(source: .server)
            check.itemsRead = .ok
        } catch {
            check.itemsRead = .failed(code: (error as NSError).code)
        }
        return check
    }
}
#endif
