import CryptoKit
import Foundation
import Security

// パートナー共有の土台：Firebase 接続と「Appleでサインイン」（2026-10-19）
// docs/FIREBASE_APPLE_AUTH_FOUNDATION.md
//
// 画面（SwiftUI）は Firebase SDK を直接使わない。ここで決めた型と窓口（protocol）だけを使い、
// Firebase の実装（FirebaseAuthBackend）と Apple の画面（AppleSignInCoordinator）は差し替えられる。
// テストでは偽物を渡し、実際のネットワークを使わない。
//
// 今回は「誰か」を確かめるところまで。予定やタスクなどの生活データは送らない。Firestore にも書き込まない。

/// サインインしている人（Firebase の利用者）
struct AuthAccount: Equatable {
    /// Firebase の利用者 ID（端末の外にはこの ID だけが Firebase に記録される）
    let uid: String

    /// 画面に出すときは一部だけ（例：abcd…wxyz）
    var maskedUID: String {
        guard uid.count > 8 else { return uid }
        return "\(uid.prefix(4))…\(uid.suffix(4))"
    }
}

/// 処理中の内容
enum AuthOperation: Equatable {
    case signingIn
    case signingOut
    case deletingAccount

    var message: String {
        switch self {
        case .signingIn: return "サインインしています…"
        case .signingOut: return "サインアウトしています…"
        case .deletingAccount: return "アカウントを削除しています…"
        }
    }
}

/// Firebase に接続できない理由
enum AuthUnavailableReason: Equatable {
    /// 設定ファイル（GoogleService-Info.plist）が無い
    case missingConfiguration
    /// 設定ファイルが壊れている・このアプリ用ではない
    case invalidConfiguration
    /// テスト・プレビュー中（Firebase に接続しない）
    case notStarted

    var message: String {
        switch self {
        case .missingConfiguration, .invalidConfiguration:
            return "いまは共有用のサインインを使えません。くらしOSのほかの機能は、これまでどおり使えます。"
        case .notStarted:
            return "共有用のサインインは準備中です。くらしOSのほかの機能は、これまでどおり使えます。"
        }
    }
}

/// サインイン・サインアウト・削除がうまくいかなかった理由
enum AuthFailure: Error, Equatable {
    /// 利用者がやめた（エラーとしては扱わない）
    case canceled
    /// Apple の画面でうまくいかなかった
    case appleFailed
    /// Apple から必要な情報（トークン）が届かなかった
    case missingToken
    /// 通信できなかった・Firebase が一時的に使えない
    case network
    /// もう一度 Apple で確かめる必要がある
    case requiresRecentLogin
    /// Firebase に接続していない
    case unavailable
    /// そのほか（内容は画面に出さない）
    case other

    var message: String {
        switch self {
        case .canceled: return "やめました。"
        case .appleFailed: return "Appleでのサインインができませんでした。もう一度お試しください。"
        case .missingToken: return "Appleからサインインの情報を受け取れませんでした。もう一度お試しください。"
        case .network: return "通信できませんでした。電波のよい場所で、もう一度お試しください。"
        case .requiresRecentLogin: return "安全のため、もう一度Appleで確かめてから操作してください。"
        case .unavailable: return AuthUnavailableReason.missingConfiguration.message
        case .other: return "うまくいきませんでした。時間をおいて、もう一度お試しください。"
        }
    }
}

/// 認証の状態（Firebase 未接続・サインアウト中・処理中・サインイン済み・エラー）
enum AuthStatus: Equatable {
    case unavailable(AuthUnavailableReason)
    case signedOut
    case working(AuthOperation, account: AuthAccount?)
    case signedIn(AuthAccount)
    case failed(AuthFailure, account: AuthAccount?)

    var account: AuthAccount? {
        switch self {
        case .signedIn(let account): return account
        case .working(_, let account), .failed(_, let account): return account
        case .unavailable, .signedOut: return nil
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// プロフィールの一覧に出す短い表示
    var shortLabel: String {
        switch self {
        case .unavailable: return "使えません"
        case .signedOut: return "未サインイン"
        case .working: return "処理中"
        case .signedIn: return "サインイン済み"
        case .failed(_, let account): return account == nil ? "未サインイン" : "サインイン済み"
        }
    }
}

/// Apple から受け取ったサインインの情報
struct AppleCredential: Equatable {
    /// Firebase に渡す ID トークン
    let identityToken: String
    /// トークンの失効（アカウント削除）に使うコード
    let authorizationCode: String?
}

// MARK: - 窓口（テストでは偽物に差し替える）

/// Firebase Authentication の窓口
protocol AuthBackend: AnyObject {
    /// いまサインインしている人
    var currentAccount: AuthAccount? { get }
    /// Apple の ID トークンで Firebase にサインインする
    func signIn(with credential: AppleCredential, rawNonce: String) async throws -> AuthAccount
    func signOut() throws
    /// 削除の前に、Apple でもう一度確かめる
    func reauthenticate(with credential: AppleCredential, rawNonce: String) async throws
    /// Apple のトークンを失効させる（authorization code を使う）
    func revokeAppleToken(authorizationCode: String) async throws
    /// Firebase の利用者を削除する
    func deleteCurrentUser() async throws
}

/// 「Appleでサインイン」の画面の窓口
protocol AppleSignInProviding: AnyObject {
    /// Apple のサインイン画面を出し、情報を受け取る。やめたときは AuthFailure.canceled
    /// - Parameter hashedNonce: 使い捨ての文字列（nonce）の SHA-256
    func requestCredential(hashedNonce: String) async throws -> AppleCredential
}

// MARK: - nonce（なりすまし・使い回しを防ぐ使い捨ての文字列）

enum AuthNonce {
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    /// 安全な乱数で作る（端末の中だけ。Apple にはハッシュ、Firebase には元の文字列を渡して照合する）
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // 乱数を作れないときは、システムの乱数で代わりに作る
            return String((0..<length).map { _ in characters.randomElement()! })
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    /// Apple に渡すハッシュ（16進数）
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
