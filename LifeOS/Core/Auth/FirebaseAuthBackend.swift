import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseCore

/// 起動時に Firebase を安全に設定する（2026-10-19）
///
/// - 設定ファイル（GoogleService-Info.plist）が無い・壊れている・このアプリ用でないときは設定しない（アプリは普通に起動する）
/// - テスト中は設定しない（テストでネットワークを使わないため）
/// - Firestore はここでは使わない（生活データは送らない）
enum FirebaseBootstrap {
    enum Result: Equatable {
        case notStarted
        case configured
        case missingConfiguration
        case invalidConfiguration
        case skippedForTests
    }

    /// 起動時の結果（AuthService.live が使う）
    private(set) static var result: Result = .notStarted

    @discardableResult
    static func configureIfPossible(
        bundle: Bundle = .main,
        isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    ) -> Result {
        let outcome = evaluate(bundle: bundle, isRunningTests: isRunningTests)
        result = outcome
        return outcome
    }

    private static func evaluate(bundle: Bundle, isRunningTests: Bool) -> Result {
        if FirebaseApp.app() != nil { return .configured }
        if isRunningTests { return .skippedForTests }
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return .missingConfiguration
        }
        guard let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == bundle.bundleIdentifier else {
            return .invalidConfiguration
        }
        FirebaseApp.configure(options: options)
        return FirebaseApp.app() != nil ? .configured : .invalidConfiguration
    }
}

/// Firebase Authentication を使う実装（Apple の ID トークンでサインイン）
final class FirebaseAuthBackend: AuthBackend {
    private var auth: Auth { Auth.auth() }

    var currentAccount: AuthAccount? {
        auth.currentUser.map { AuthAccount(uid: $0.uid) }
    }

    func signIn(with credential: AppleCredential, rawNonce: String) async throws -> AuthAccount {
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: credential.identityToken,
            rawNonce: rawNonce,
            fullName: nil
        )
        do {
            let result = try await auth.signIn(with: firebaseCredential)
            return AuthAccount(uid: result.user.uid)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func signOut() throws {
        do {
            try auth.signOut()
        } catch {
            throw Self.failure(from: error)
        }
    }

    func reauthenticate(with credential: AppleCredential, rawNonce: String) async throws {
        guard let user = auth.currentUser else { throw AuthFailure.other }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: credential.identityToken,
            rawNonce: rawNonce,
            fullName: nil
        )
        do {
            _ = try await user.reauthenticate(with: firebaseCredential)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        do {
            try await auth.revokeToken(withAuthorizationCode: authorizationCode)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else { return }
        do {
            try await user.delete()
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Firebase のエラーを、画面で説明できる種類に分ける（エラーの中身は画面に出さない）
    static func failure(from error: Error) -> AuthFailure {
        let nsError = error as NSError
        // Firebase Authentication のエラーの種類（AuthErrorDomain と同じ値）
        guard nsError.domain == "FIRAuthErrorDomain" else { return .other }
        switch nsError.code {
        case AuthErrorCode.networkError.rawValue,
             AuthErrorCode.tooManyRequests.rawValue,
             AuthErrorCode.internalError.rawValue:
            return .network
        case AuthErrorCode.requiresRecentLogin.rawValue,
             AuthErrorCode.userTokenExpired.rawValue:
            return .requiresRecentLogin
        case AuthErrorCode.invalidCredential.rawValue,
             AuthErrorCode.missingOrInvalidNonce.rawValue:
            return .appleFailed
        default:
            return .other
        }
    }
}
#endif
