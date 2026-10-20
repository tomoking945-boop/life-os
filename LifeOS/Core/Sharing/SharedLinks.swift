import CryptoKit
import Foundation

/// 招待リンク（Universal Link）：`https://kurashi-os-production.web.app/invite?token=<43文字>`
/// （2026-10-21 招待リンクの土台。docs/FIREBASE_INVITE_LINK_FOUNDATION.md）
///
/// 次をすべて満たすリンクだけを招待として受け付ける（ほかはすべて nil）：
/// - `https`
/// - ホストが `kurashi-os-production.web.app` と同じ（大文字・小文字は区別しない。似たドメイン・別ドメイン・末尾の点は不可）
/// - パスが `/invite` と同じ（`/invite/`・大文字・別のパス・文字の置き換え（%）は不可）
/// - 問い合わせ（?）が `token=<43文字>` の1つだけ（空・重複・ほかの項目・`#` 以降は不可）
/// - トークンは 32 バイトの乱数を base64url にした 43 文字（英数字・`-`・`_` だけ。サーバーの invites.js と同じ）
/// - ユーザー名・パスワード・ポート番号の付いたリンク、長すぎるリンクは不可
///
/// ドメインは、招待を作る Cloud Function（index.js の inviteBaseURL：`https://<プロジェクト ID>.web.app`）・
/// GoogleService-Info.plist のプロジェクト ID・AASA（firebase/hosting/.well-known）・LifeOS.entitlements と同じ（テストで確認）。
///
/// トークンは画面・ログ・エラー文に出さず、端末にも保存しない。アプリを開いているあいだのメモリだけで持つ。
struct InviteLink: Equatable {
    /// 招待リンクを配信するドメイン（Firebase Hosting の既定のドメイン）
    static let host = "kurashi-os-production.web.app"
    /// 招待のパス
    static let path = "/invite"
    /// トークンの長さ（32バイトの乱数を base64url にしたもの）
    static let tokenLength = 43
    /// これより長いリンクは調べずに断る
    static let maxURLLength = 256

    private static let tokenCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// 招待トークン（次の段階の「招待への参加」だけが使う。表示・保存・ログに出さない）
    let token: String
    /// 同じリンクかを見分ける印（トークンの SHA-256。メモリの中だけで使う）
    let fingerprint: String

    /// 招待のリンクなら作れる（それ以外は nil）
    init?(url: URL) {
        guard url.absoluteString.utf8.count <= Self.maxURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.percentEncodedUser == nil,
              components.percentEncodedPassword == nil,
              components.port == nil,
              components.percentEncodedFragment == nil,
              components.percentEncodedHost?.lowercased() == Self.host,
              components.percentEncodedPath == Self.path,
              let items = components.percentEncodedQueryItems,
              items.count == 1,
              items[0].name == "token",
              let value = items[0].value,
              Self.isValidToken(value) else {
            return nil
        }
        token = value
        fingerprint = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// トークンの形が正しいか（43文字・英数字と `-` `_` だけ）
    static func isValidToken(_ token: String) -> Bool {
        token.unicodeScalars.count == tokenLength && token.unicodeScalars.allSatisfy { tokenCharacters.contains($0) }
    }
}

/// 文字にしたとき・デバッグで中身を見たときも、トークンを出さない
extension InviteLink: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "InviteLink(トークンは表示しません)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }
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
