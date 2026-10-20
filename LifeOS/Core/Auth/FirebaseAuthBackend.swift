import Foundation

#if canImport(FirebaseCore) && canImport(FirebaseAuth)
import FirebaseAuth

// 起動時の Firebase の設定は FirebaseBootstrap.swift（2026-10-20 に App Check とあわせて移動）

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
