import UIKit
import UserNotifications

/// iPhone の通知の許可と APNs への登録（本物）。許可画面を出すのは requestAuthorization だけ（2026-10-28 Build 8）
final class SystemPushPermission: PushPermissionProviding {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> PushAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
