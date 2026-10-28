import Foundation

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

/// 共有の通知を受け取る端末の文書（自分の users/{uid}/devices/{deviceID} だけ）。2026-10-28 Build 8
///
/// - 書くのは Cloud Function（onSharedItemWritten）が使う決まった項目だけ：
///   fcmToken・platform（ios）・notificationsEnabled・sharedUpdatesEnabled・showsPreview・updatedAt（サーバーの時刻）
/// - UID は Firebase Authentication から読んで場所を決めるだけ（画面・ログに出さない）
/// - 端末の名前・広告の識別子・メール・項目名は書かない
final class FirestoreDeviceRegistry: PushDeviceRegistry {
    private func device(_ deviceID: String) throws -> DocumentReference {
        guard let uid = Auth.auth().currentUser?.uid else { throw SharedItemsFailure.notSignedIn }
        return Firestore.firestore().collection("users").document(uid).collection("devices").document(deviceID)
    }

    func save(deviceID: String, record: PushDeviceRecord) async throws {
        let data: [String: Any] = [
            "fcmToken": record.token,
            "platform": "ios",
            "notificationsEnabled": true,
            "sharedUpdatesEnabled": true,
            "showsPreview": record.showsPreview,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        // 同じ端末 ID の文書をまるごと上書きする（トークンが新しくなっても1つのまま）
        try await device(deviceID).setData(data)
    }

    func remove(deviceID: String) async throws {
        try await device(deviceID).delete()
    }
}
#endif
