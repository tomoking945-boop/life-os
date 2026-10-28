import UIKit
import UserNotifications

/// 共有の通知（2026-10-28 Build 8。docs/SHARED_PUSH_NOTIFICATIONS.md）のための AppDelegate
///
/// - Firebase の設定は、これまでどおり LifeOSApp の init（App Check → Firebase の順）。ここでは Firebase を設定しない
/// - 起動時に通知の許可を求めない（許可は「わが家の設定」でオンにしたときだけ）
/// - APNs のトークンを Firebase Messaging へ渡す（Info.plist で自動の置き換えを止めているため）
/// - 通知センターの窓口：共有の通知だけ、アプリを開いているときもバナーを出す。タップしたら「やること」「買い物」を開く
///   ローカル通知（予定・やること・保証書）は、これまでどおり、アプリを開いているときは出さない
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SharedPushService.live.apnsTokenDidArrive(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // エラーの中身は出さない（シミュレーターなどでは APNs を使えない）
        SharedPushService.live.apnsRegistrationFailed()
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        completionHandler(SharedPushRouter.showsInForeground(userInfo: userInfo) ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 開く画面を決めるだけ（項目の編集・完了・削除はしない）
        SharedPushRouter.shared.open(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
