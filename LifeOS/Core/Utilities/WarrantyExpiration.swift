import Foundation

/// 保証終了日の計算と、期限の状態（spec 5・3・9）
enum WarrantyExpiration {
    /// 「期限が近い」とみなす日数（今日画面・一覧）
    static let soonThresholdDays = 30

    /// 購入日＋保証期間。応当日が無い場合（例：1/31 ＋ 1か月、2/29 ＋ 1年）は、その月の末日にする。
    /// Foundation の暦計算は、日が無いとき月末に合わせるため、そのまま使う（テストで確認）。
    static func expirationDate(
        purchaseDate: Date,
        duration: WarrantyDuration,
        calendar: Calendar = LifeCalendar.calendar
    ) -> Date? {
        guard WarrantyDuration.valueRange.contains(duration.value) else { return nil }
        let start = calendar.startOfDay(for: purchaseDate)
        guard let date = calendar.date(byAdding: duration.unit.calendarComponent, value: duration.value, to: start) else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    /// 算出根拠：「購入日 2026/10/13 ＋ 1年」
    static func basisText(purchaseDate: Date, duration: WarrantyDuration) -> String {
        "購入日 \(dateText(purchaseDate)) ＋ \(duration.label)"
    }

    /// 2026/10/13
    static func dateText(_ date: Date) -> String {
        let components = LifeCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 今日から保証終了日までの日数（当日は 0、過ぎていれば負）
    static func daysRemaining(until expiresAt: Date, now: Date, calendar: Calendar = LifeCalendar.calendar) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: expiresAt)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func status(of document: WarrantyDocument, now: Date) -> WarrantyStatus {
        guard let expiresAt = document.warrantyExpiresAt else { return .noExpiration }
        let days = daysRemaining(until: expiresAt, now: now)
        if days < 0 { return .expired }
        if days <= soonThresholdDays { return .expiringSoon(days: days) }
        return .active(days: days)
    }

    /// 期限が30日以内（今日を含み、終了済みは除く）で、最も近い1件（今日画面・リストの入口）
    static func nearestExpiringSoon(_ documents: [WarrantyDocument], now: Date) -> WarrantyDocument? {
        documents
            .filter { if case .expiringSoon = status(of: $0, now: now) { return true } else { return false } }
            .min { ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture) }
    }

    /// 期限が終わっていない中で、最も近い1件（リストの「次の期限」）
    static func nextExpiring(_ documents: [WarrantyDocument], now: Date) -> WarrantyDocument? {
        documents
            .filter { document in
                guard let expiresAt = document.warrantyExpiresAt else { return false }
                return daysRemaining(until: expiresAt, now: now) >= 0
            }
            .min { ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture) }
    }

    /// 「あと28日」「今日まで」「終了」
    static func remainingText(for document: WarrantyDocument, now: Date) -> String {
        switch status(of: document, now: now) {
        case .expiringSoon(let days), .active(let days):
            return days == 0 ? "今日まで" : "あと\(days)日"
        case .expired:
            return "保証終了"
        case .noExpiration:
            return "終了日 未入力"
        }
    }
}

/// 保証の状態
enum WarrantyStatus: Hashable {
    /// 保証終了まで30日以内（当日を含む）
    case expiringSoon(days: Int)
    /// 保証期間中（30日より先）
    case active(days: Int)
    /// 保証終了
    case expired
    /// 終了日が入っていない
    case noExpiration
}

/// 一覧のまとまり（spec 3：「期限が近い」「保証期間中」「期限終了」の順）
enum WarrantyListSection: Int, CaseIterable, Identifiable, Hashable {
    case expiringSoon
    case active
    case expired
    /// 新しい解釈：終了日が無い保証書は、どの順にも入らないため最後にまとめる
    case noExpiration

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .expiringSoon: return "期限が近い"
        case .active: return "保証期間中"
        case .expired: return "期限終了"
        case .noExpiration: return "終了日 未入力"
        }
    }

    init(status: WarrantyStatus) {
        switch status {
        case .expiringSoon: self = .expiringSoon
        case .active: self = .active
        case .expired: self = .expired
        case .noExpiration: self = .noExpiration
        }
    }

    /// まとまりごとに並べる（期限が近い順。終了済みは新しく終わった順、未入力は製品名順）
    static func group(_ documents: [WarrantyDocument], now: Date) -> [WarrantyListGroup] {
        let grouped = Dictionary(grouping: documents) { WarrantyListSection(status: WarrantyExpiration.status(of: $0, now: now)) }
        return allCases.compactMap { section in
            guard var list = grouped[section], !list.isEmpty else { return nil }
            switch section {
            case .expiringSoon, .active:
                list.sort { ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture) }
            case .expired:
                list.sort { ($0.warrantyExpiresAt ?? .distantPast) > ($1.warrantyExpiresAt ?? .distantPast) }
            case .noExpiration:
                list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            return WarrantyListGroup(section: section, documents: list)
        }
    }
}

/// 一覧のまとまり1つ
struct WarrantyListGroup: Identifiable, Hashable {
    let section: WarrantyListSection
    let documents: [WarrantyDocument]

    var id: WarrantyListSection { section }
}

/// 保証書の機能を、いまのプランで何に使えるか（spec 3）
enum WarrantyAccess: Hashable {
    /// Free（保存済みの保証書が無い）：説明と Premium 案内だけ
    case locked
    /// Premium：すべて使える
    case full
    /// Premium 終了後（保存済みの保証書がある Free）：閲覧・写真表示・書き出し・削除だけ
    case readOnly

    /// 新しい解釈：Premium 終了後かどうかは、保存済みの保証書があるかで決める（解約時にデータは消さないため）
    static func resolve(isPremium: Bool, hasSavedDocuments: Bool) -> WarrantyAccess {
        if isPremium { return .full }
        return hasSavedDocuments ? .readOnly : .locked
    }

    var canCreate: Bool { self == .full }
    var canEdit: Bool { self == .full }
    var canRecognizeText: Bool { self == .full }
    var canScheduleReminders: Bool { self == .full }
    var canView: Bool { self != .locked }
    var canExport: Bool { self != .locked }
    var canDelete: Bool { self != .locked }
}
