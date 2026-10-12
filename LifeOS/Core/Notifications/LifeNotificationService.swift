import Foundation
import UserNotifications

// 統合通知スケジューラー（保証書管理 2026-10-13：docs/WARRANTY_MANAGEMENT_MVP_SPEC.md 8）
//
// iOS の保留中の通知には上限（64件）があるため、アプリが管理する通知をここで1か所にまとめ、合計59件以内にする。
// - 保証書：期限が近い6件 × 最大3通知 = 18件
// - 時刻つき予定：直近40件
// - 未完了タスク：最大1件
//
// 決定（2026-10-13 池上さん）：今回作るのは保証書の通知だけ。
// 予定10分前・当日20時の未完了タスクの通知は、GitHub の main にまだ無いため作らない。
// TODO: 予定・タスクの通知を作るときは、`events`・`tasks` に予約したい通知を渡す（枠はすでに用意してある）。
//
// アプリが管理する通知の識別子は「lifeos.」で始まる。それ以外の通知（ほかの仕組みが予約したもの）は消さない。

/// 通知の種類と、それぞれの枠
enum LifeNotificationCategory: String, CaseIterable, Hashable {
    case warranty
    case event
    case task

    /// 種類ごとの上限
    var budget: Int {
        switch self {
        case .warranty: return LifeNotificationPlanner.warrantyDocumentLimit * WarrantyDocument.reminderOffsetChoices.count
        case .event: return 40
        case .task: return 1
        }
    }
}

/// 予約する通知1件
struct LifeNotificationRequest: Hashable, Identifiable {
    var identifier: String
    var category: LifeNotificationCategory
    var title: String
    var body: String
    var fireDate: Date

    var id: String { identifier }
}

/// どの通知を予約するかを決める（端末の通知センターには触れない。テストしやすいように分けている）
enum LifeNotificationPlanner {
    /// アプリが管理する通知の合計の上限
    static let totalLimit = 59
    /// 保証書の通知を予約するのは、期限が近い何件までか
    static let warrantyDocumentLimit = 6
    /// アプリが管理する通知の識別子の頭
    static let identifierPrefix = "lifeos."
    /// 保証書の通知の時刻（9:00）
    static let warrantyReminderHour = 9

    /// 予約する通知の一覧（種類ごとの枠と、合計59件の上限を守る）
    static func plan(
        warranty: [LifeNotificationRequest],
        events: [LifeNotificationRequest] = [],
        tasks: [LifeNotificationRequest] = []
    ) -> [LifeNotificationRequest] {
        let limited = [(LifeNotificationCategory.warranty, warranty), (.event, events), (.task, tasks)].flatMap { category, requests in
            requests
                .filter { $0.category == category }
                .sorted { $0.fireDate < $1.fireDate }
                .prefix(category.budget)
        }
        return Array(limited.sorted { $0.fireDate < $1.fireDate }.prefix(totalLimit))
    }

    /// 保証書の通知（spec 8）
    /// - 終了日が無い・終了済み・通知 OFF の保証書は予約しない
    /// - 通知日が過去なら予約しない
    /// - 期限が近い6件まで。1件につき 30日前・7日前・当日（9:00）のうち選んだもの
    /// - 本文に製造番号・保管場所・写真の内容は出さない
    static func warrantyRequests(
        documents: [WarrantyDocument],
        now: Date,
        calendar: Calendar = LifeCalendar.calendar
    ) -> [LifeNotificationRequest] {
        let candidates = documents
            .filter { document in
                guard let expiresAt = document.warrantyExpiresAt, !document.reminderOffsetsInDays.isEmpty else { return false }
                return WarrantyExpiration.daysRemaining(until: expiresAt, now: now, calendar: calendar) >= 0
            }
            .sorted { ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture) }

        var requests: [LifeNotificationRequest] = []
        var documentCount = 0
        for document in candidates {
            guard documentCount < warrantyDocumentLimit, let expiresAt = document.warrantyExpiresAt else { break }
            let documentRequests = document.reminderOffsetsInDays.sorted(by: >).compactMap { offset -> LifeNotificationRequest? in
                guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: expiresAt)),
                      let fireDate = calendar.date(bySettingHour: warrantyReminderHour, minute: 0, second: 0, of: day),
                      fireDate > now else { return nil }
                return LifeNotificationRequest(
                    identifier: "\(identifierPrefix)warranty.\(document.id.uuidString).\(offset)",
                    category: .warranty,
                    title: "保証の期限",
                    body: warrantyBody(title: document.title, daysBefore: offset),
                    fireDate: fireDate
                )
            }
            guard !documentRequests.isEmpty else { continue }
            requests += documentRequests
            documentCount += 1
        }
        return requests
    }

    /// 「冷蔵庫の保証終了まであと30日です」「冷蔵庫の保証は今日までです」
    static func warrantyBody(title: String, daysBefore: Int) -> String {
        daysBefore == 0 ? "\(title)の保証は今日までです" : "\(title)の保証終了まであと\(daysBefore)日です"
    }
}

// MARK: - 端末の通知センター

/// 通知センターの窓口（テストでは偽物に差し替える）
protocol LifeNotificationCenter: AnyObject {
    func pendingRequestIdentifiers() async -> [String]
    func add(_ request: LifeNotificationRequest, calendar: Calendar) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
    /// 通知が許可されているか（未確認なら nil）
    func isAuthorized() async -> Bool?
    /// 許可をお願いする。許可されたら true
    func requestAuthorization() async -> Bool
}

/// 本物の通知センター（端末内のローカル通知。外部へは送らない）
final class SystemLifeNotificationCenter: LifeNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func pendingRequestIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ request: LifeNotificationRequest, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.threadIdentifier = request.category.rawValue
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func isAuthorized() async -> Bool? {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return nil
        @unknown default: return false
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// アプリの通知をまとめて予約し直す
final class LifeNotificationService {
    static let shared = LifeNotificationService()

    private let center: LifeNotificationCenter
    private let calendar: Calendar

    init(center: LifeNotificationCenter = SystemLifeNotificationCenter(), calendar: Calendar = LifeCalendar.calendar) {
        self.center = center
        self.calendar = calendar
    }

    /// いま予約するべき通知（Premium でない・保証書の通知 OFF なら保証書の分は無し）
    static func plannedRequests(
        warranties: [WarrantyDocument],
        isPremium: Bool,
        warrantyRemindersEnabled: Bool,
        now: Date
    ) -> [LifeNotificationRequest] {
        let access = WarrantyAccess.resolve(isPremium: isPremium, hasSavedDocuments: !warranties.isEmpty)
        let warrantyRequests = access.canScheduleReminders && warrantyRemindersEnabled
            ? LifeNotificationPlanner.warrantyRequests(documents: warranties, now: now)
            : []
        // TODO: 予定・タスクの通知を作るときは events・tasks に渡す（いまは無し）
        return LifeNotificationPlanner.plan(warranty: warrantyRequests, events: [], tasks: [])
    }

    /// 全体を予約し直す（起動時・保証書の追加・編集・削除・通知設定やプランの変更時）。
    /// 「lifeos.」で始まる予約だけを入れ替える。許可されていなければ何も予約しない
    func resync(warranties: [WarrantyDocument], isPremium: Bool, warrantyRemindersEnabled: Bool, now: Date = Date()) async {
        let planned = Self.plannedRequests(
            warranties: warranties,
            isPremium: isPremium,
            warrantyRemindersEnabled: warrantyRemindersEnabled,
            now: now
        )
        let managed = await center.pendingRequestIdentifiers().filter { $0.hasPrefix(LifeNotificationPlanner.identifierPrefix) }
        let plannedIDs = Set(planned.map(\.identifier))
        let stale = managed.filter { !plannedIDs.contains($0) }
        if !stale.isEmpty {
            center.removePendingRequests(withIdentifiers: stale)
        }
        guard !planned.isEmpty, await center.isAuthorized() == true else {
            // 許可が無いときは、予約済みのアプリの通知も残さない
            let remaining = managed.filter { plannedIDs.contains($0) }
            if !remaining.isEmpty {
                center.removePendingRequests(withIdentifiers: remaining)
            }
            return
        }
        for request in planned {
            // 同じ識別子なら置き換わる（タイトル・期限を変えたときは新しい内容になる）
            try? await center.add(request, calendar: calendar)
        }
    }

    /// アプリの状態から予約し直す
    func resync(store: LifeStore, appState: AppState) async {
        await resync(
            warranties: store.warranties,
            isPremium: appState.isPremium,
            warrantyRemindersEnabled: appState.notificationSettings.warrantyRemindersEnabled
        )
    }

    /// 保証書の通知を使うとき（保存時）に一度だけ許可をお願いする
    func requestAuthorizationIfNeeded() async {
        if await center.isAuthorized() == nil {
            _ = await center.requestAuthorization()
        }
    }
}
