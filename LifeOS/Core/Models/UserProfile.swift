import Foundation

/// 生活グループのメンバー
struct Member: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var isCurrentUser: Bool

    init(id: UUID = UUID(), name: String, isCurrentUser: Bool) {
        self.id = id
        self.name = name
        self.isCurrentUser = isCurrentUser
    }
}

/// 通知のON/OFF（Mock。実際の通知は送らない）
/// TODO: Push通知の接続時に、各項目の通知タイミング（何分前に知らせるか等）を決める。
struct NotificationSettings: Hashable, Codable {
    /// 今日の予定のお知らせ
    var todaySchedule = true
    /// やることのリマインド
    var taskReminder = true
    /// 共有メンバーが追加・更新したとき
    var sharedUpdates = false
}

/// 本人のプロフィール
struct UserProfile: Hashable, Codable {
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
