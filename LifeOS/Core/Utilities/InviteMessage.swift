import Foundation

/// 家族招待の Mock 文面。
/// Universal Links や招待のバックエンドはまだ作らないため、リンクは表示用のダミー。
/// TODO: Universal Links ／ Firebase 接続時に、本物の招待リンク（相手ごと・期限付き）を発行する。
enum InviteMessage {
    /// 表示用のダミーリンク（開いても何も起きない）
    static let mockLink = "https://example.com/lifeos/invite/mock"

    static func text(inviterName: String, groupName: String, item: LifeItem?) -> String {
        var lines = ["\(inviterName)さんから、生活OSの「\(groupName)」に招待されています。"]
        if let item {
            let time = item.showsTime ? " \(LifeFormatters.time(item.displayDate))" : ""
            lines.append("\(LifeFormatters.shortDate(item.displayDate))\(time) \(item.title) を一緒に管理しませんか？")
        }
        lines.append("参加する：\(mockLink)")
        lines.append("（試作版のため、このリンクはまだ使えません）")
        return lines.joined(separator: "\n")
    }
}
