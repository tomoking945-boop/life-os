import Foundation

/// Firestore の `groups/{groupID}/items/{itemID}` に保存する形（仕様 4）。
/// 共有する項目だけをこの形にする。個人項目からは作れない（init が nil を返す）。
///
/// 送らないもの：柔らかい時間（帰宅時など）・暮らしメモリーとのつながり・持ち主の区別。
/// これらは端末ごとの見え方や個人の記録なので、端末の中だけに置く。
/// createdAt・updatedAt はサーバーの時刻を使う（Firestore に書き込むときに付ける。Security Rules で確認している）。
struct SharedItemRecord: Codable, Hashable {
    var title: String
    /// event / todo / chore / shopping
    var kind: String
    var date: Date
    var hasTime: Bool
    /// 担当（生活グループのメンバーの uid）。「どちらでも」は nil
    var assigneeUID: String?
    var isCompleted: Bool
    var deferredTo: Date?
    var droppedAt: Date?
    var createdBy: String
    var updatedBy: String

    /// 共有の項目から作る。個人項目・共有できない種類なら nil
    /// - Parameters:
    ///   - myUID: この端末の利用者
    ///   - partnerUID: 相手（担当が「パートナー」のときに使う。分からなければ担当なし）
    ///   - createdBy: 作成者（新しく作るときは自分。既にあるものは元の作成者）
    init?(item: LifeItem, myUID: String, partnerUID: String?, createdBy: String? = nil) {
        guard SharedSyncPolicy.isSyncable(item) else { return nil }
        title = item.title
        kind = item.kind.rawValue
        date = item.date
        hasTime = item.hasTime
        switch item.assignee {
        case .me: assigneeUID = myUID
        case .partner: assigneeUID = partnerUID
        case .either, .none: assigneeUID = nil
        }
        isCompleted = item.isCompleted
        deferredTo = item.deferredTo
        droppedAt = item.droppedAt
        self.createdBy = createdBy ?? myUID
        updatedBy = myUID
    }

    /// 受け取った共有項目を、この端末の項目にする（ID は Firestore のドキュメント ID ＝元の UUID）
    func makeItem(id: UUID, myUID: String) -> LifeItem? {
        guard let kind = LifeItemKind(rawValue: self.kind), SharedSyncPolicy.syncableKinds.contains(kind) else { return nil }
        let assignee: Assignee
        switch assigneeUID {
        case .none: assignee = .either
        case .some(let uid) where uid == myUID: assignee = .me
        case .some: assignee = .partner
        }
        return LifeItem(
            id: id,
            title: title,
            kind: kind,
            ownership: .shared,
            date: date,
            hasTime: hasTime,
            assignee: assignee,
            isCompleted: isCompleted,
            deferredTo: deferredTo,
            droppedAt: droppedAt
        )
    }
}
