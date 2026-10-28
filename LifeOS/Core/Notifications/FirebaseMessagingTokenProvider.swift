import Foundation

#if canImport(FirebaseMessaging)
import FirebaseMessaging

/// 通知用のトークン（Firebase Cloud Messaging）。2026-10-28 Build 8。docs/SHARED_PUSH_NOTIFICATIONS.md
///
/// - Info.plist の FirebaseMessagingAutoInitEnabled = NO：利用者がオンにするまでトークンを作らない
/// - FirebaseAppDelegateProxyEnabled = NO：APNs のトークンは AppDelegate から setAPNsToken で渡す
/// - トークンは画面・ログに出さない。端末の文書（自分の users/{uid}/devices）に書くだけ
final class FirebaseMessagingTokenProvider: NSObject, PushTokenProviding, MessagingDelegate {
    var onTokenRefresh: ((String) -> Void)?

    private var messaging: Messaging { Messaging.messaging() }

    override init() {
        super.init()
        messaging.delegate = self
    }

    func setAutoInit(_ enabled: Bool) {
        messaging.isAutoInitEnabled = enabled
    }

    func setAPNsToken(_ token: Data) {
        messaging.apnsToken = token
    }

    func currentToken() async throws -> String {
        try await messaging.token()
    }

    func deleteToken() async {
        try? await messaging.deleteToken()
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        onTokenRefresh?(fcmToken)
    }
}
#endif
