import AuthenticationServices
import UIKit

/// 「Appleでサインイン」の画面を出す（AuthenticationServices）
///
/// - 名前とメールアドレスは求めない（requestedScopes は空）。共有する人を確かめるためだけに使う
/// - nonce は SHA-256 にしてから Apple に渡す（元の文字列は Firebase での照合に使う）
final class AppleSignInCoordinator: NSObject, AppleSignInProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?

    @MainActor
    func requestCredential(hashedNonce: String) async throws -> AppleCredential {
        // 前の画面が残っていたら終わらせる
        continuation?.resume(throwing: AuthFailure.canceled)
        continuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleID = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleID.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(.failure(AuthFailure.missingToken))
            return
        }
        let code = appleID.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(.success(AppleCredential(identityToken: token, authorizationCode: code)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
            finish(.failure(AuthFailure.canceled))
        } else {
            finish(.failure(AuthFailure.appleFailed))
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}
