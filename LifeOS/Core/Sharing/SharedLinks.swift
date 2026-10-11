import Foundation

/// 招待リンク（Universal Link）：`https://<ドメイン>/invite?token=<43文字>`（仕様 3・8）
enum InviteLink {
    /// トークンの形（32バイトの乱数を base64url にしたもの。サーバーの invites.js と同じ）
    private static let tokenLength = 43
    private static let tokenCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// 招待のリンクなら、トークンを返す（それ以外は nil）。トークンはアプリの中だけで使い、保存しない
    static func token(from url: URL) -> String? {
        guard url.scheme == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == "/invite" || components.path == "/invite/",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              isValidToken(token) else {
            return nil
        }
        return token
    }

    static func isValidToken(_ token: String) -> Bool {
        token.count == tokenLength && token.unicodeScalars.allSatisfy { tokenCharacters.contains($0) }
    }
}

/// 通知をタップしたときに開く共有項目（仕様 7-6）。通知の data には groupID・itemID・type だけが入る（項目名は入らない）
struct SharedItemRoute: Hashable {
    let groupID: String
    let itemID: UUID
    /// eventAdded / eventChanged / taskAdded（無ければ nil）
    let type: String?

    private static let groupIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// 通知の userInfo から読み取る。形が正しくなければ nil（何も開かない）
    init?(userInfo: [AnyHashable: Any]) {
        guard let groupID = userInfo["groupID"] as? String,
              !groupID.isEmpty, groupID.count <= 128,
              groupID.unicodeScalars.allSatisfy({ Self.groupIDCharacters.contains($0) }),
              let itemText = userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: itemText) else {
            return nil
        }
        self.groupID = groupID
        self.itemID = itemID
        self.type = userInfo["type"] as? String
    }
}
