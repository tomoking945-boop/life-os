import Foundation

/// どの項目を端末の外（Firestore）へ送ってよいか（パートナー共有 2026-10-11、仕様 1・5）。
///
/// - 送ってよいのは「共有」（`Ownership.shared`）の、予定・ToDo・家事・買い物だけ
/// - 個人（`Ownership.personal`）の項目は、どんな種類でも絶対に送らない
/// - 支払予定・習慣は、仕様の共有の対象（予定・ToDo・家事・買い物）に無いため送らない（TODO：共有したい場合は仕様で決める）
///
/// サーバー側の Security Rules（firestore.rules）と通知の判定（firebase/functions/src/notificationPolicy.js）も、同じ4種類だけを受け付ける。
enum SharedSyncPolicy {
    /// 共有の保存先へ送れる種類
    static let syncableKinds: Set<LifeItemKind> = [.event, .todo, .chore, .shopping]

    /// 端末の外へ送ってよい項目か
    static func isSyncable(_ item: LifeItem) -> Bool {
        item.ownership == .shared && syncableKinds.contains(item.kind)
    }

    /// 送ってよい項目だけを取り出す
    static func syncableItems(_ items: [LifeItem]) -> [LifeItem] {
        items.filter(isSyncable)
    }
}
