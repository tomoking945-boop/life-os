import Foundation

/// 既存の共有データを、承認のうえで一度だけ Firestore へ移す計画（仕様 9）。
///
/// - 対象は端末内の `ownership == .shared` で、共有できる種類（予定・ToDo・家事・買い物）の項目だけ
/// - 「もうやらない」にした項目は移さない（新しい解釈：相手の画面に出す必要が無いため）
/// - 個人項目は端末内のまま（件数だけ伝える）
/// - itemID は既存の UUID をそのまま使い、二重登録を防ぐ。移行済み（完了フラグ）なら何もしない
struct SharedMigrationPlan: Equatable {
    /// プレビューして、承認されたら送る項目（元の順番のまま）
    let itemsToUpload: [LifeItem]
    /// 端末内に残る個人項目の数
    let personalCount: Int
    /// 共有だが移さない項目の数（支払予定・習慣・もうやらない・送信済み）
    let skippedSharedCount: Int

    var isEmpty: Bool { itemsToUpload.isEmpty }

    /// - Parameters:
    ///   - items: 端末内の項目
    ///   - isAlreadyMigrated: 移行完了フラグ（端末またはユーザー情報）が立っているか
    ///   - uploadedIDs: すでに Firestore にある項目の ID（途中で止まったときの再開用）
    static func make(items: [LifeItem], isAlreadyMigrated: Bool, uploadedIDs: Set<UUID> = []) -> SharedMigrationPlan {
        let personal = items.filter { $0.ownership == .personal }.count
        guard !isAlreadyMigrated else {
            return SharedMigrationPlan(itemsToUpload: [], personalCount: personal, skippedSharedCount: 0)
        }
        let shared = items.filter { $0.ownership == .shared }
        let upload = shared.filter { item in
            SharedSyncPolicy.isSyncable(item) && !item.isDropped && !uploadedIDs.contains(item.id)
        }
        return SharedMigrationPlan(
            itemsToUpload: upload,
            personalCount: personal,
            skippedSharedCount: shared.count - upload.count
        )
    }
}
