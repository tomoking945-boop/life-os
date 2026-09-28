import Foundation

/// 生活グループのメンバー
struct Member: Identifiable, Hashable {
    let id: UUID
    var name: String
    var isCurrentUser: Bool

    init(id: UUID = UUID(), name: String, isCurrentUser: Bool) {
        self.id = id
        self.name = name
        self.isCurrentUser = isCurrentUser
    }
}

/// 本人のプロフィール
struct UserProfile: Hashable {
    var name: String
    var groupName: String
    var members: [Member]

    /// パートナーの表示名（Mock では「妻」）
    var partnerName: String {
        members.first(where: { !$0.isCurrentUser })?.name ?? "パートナー"
    }

    /// 担当者の表示名
    func displayName(for assignee: Assignee) -> String {
        switch assignee {
        case .me: return "自分"
        case .partner: return partnerName
        case .either: return "どちらでも"
        }
    }
}
