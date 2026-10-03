import Foundation
@testable import LifeOS

/// テストで使う固定の日時
enum TestDates {
    /// 2026年10月2日（金）9:10（アプリの Mock の現在時刻と同じ時刻）
    static let friday = make(2026, 10, 2, 9, 10)
    /// 2026年10月3日（土）
    static let saturday = make(2026, 10, 3, 9, 10)
    /// 2026年10月4日（日）
    static let sunday = make(2026, 10, 4, 9, 10)
    /// 2026年10月25日（日）
    static let october25 = make(2026, 10, 25, 9, 10)
    /// 2026年10月10日（土）
    static let october10 = make(2026, 10, 10, 9, 10)

    static func make(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = LifeCalendar.calendar.date(from: components) else {
            fatalError("テスト用の日時を作れませんでした")
        }
        return date
    }

    static func daysAgo(_ days: Int, from date: Date) -> Date {
        LifeCalendar.calendar.date(byAdding: .day, value: -days, to: LifeCalendar.startOfDay(date)) ?? date
    }
}

/// テスト用の保存しない LifeStore（Mock データ・固定日時）
func makeStore(now: Date = TestDates.friday) -> LifeStore {
    LifeStore(
        items: MockData.items(now: now),
        expenses: MockData.expenses(now: now),
        budget: MockData.budget(now: now),
        lists: MockData.lists,
        inbox: MockData.inbox(now: now),
        memories: MockData.memories(now: now),
        choreTemplates: MockData.choreTemplates,
        autopilot: nil,
        frequentPurchases: MockData.frequentPurchases(now: now)
    )
}
