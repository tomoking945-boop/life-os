import XCTest
@testable import LifeOS

// 2026-10-17：確定済みだったが GitHub に入っていなかった変更の統合
// - 予定10分前・未完了タスク20時の通知（統合通知スケジューラー）
// - 表示名「くらしOS」と Bundle Identifier
// - 生活グループ名の例は「わが家」

final class EventAndTaskNotificationTests: XCTestCase {
    /// 2026年10月2日（金）9:10
    private let now = TestDates.friday

    private func event(_ title: String, at date: Date, hasTime: Bool = true) -> LifeItem {
        LifeItem(title: title, kind: .event, ownership: .personal, date: date, hasTime: hasTime)
    }

    private func task(_ title: String, kind: LifeItemKind = .todo, on date: Date = TestDates.friday,
                      assignee: Assignee = .me, isCompleted: Bool = false, droppedAt: Date? = nil) -> LifeItem {
        LifeItem(title: title, kind: kind, ownership: .personal, date: LifeCalendar.startOfDay(date),
                 assignee: assignee, isCompleted: isCompleted, droppedAt: droppedAt)
    }

    // MARK: - 予定

    /// 時刻つき予定は、ちょうど10分前に予約される
    func testEventIsScheduledExactlyTenMinutesBefore() throws {
        let dentist = event("歯医者", at: TestDates.make(2026, 10, 2, 10, 30))
        let requests = LifeNotificationPlanner.eventRequests(items: [dentist], now: now)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.fireDate, TestDates.make(2026, 10, 2, 10, 20))
        XCTAssertEqual(request.category, .event)
        XCTAssertEqual(request.identifier, "lifeos.event.\(dentist.id.uuidString)")
        XCTAssertEqual(request.body, "10:30 歯医者（10分後）")
    }

    /// 「あとで」で動かした予定は、動かした先の時刻の10分前
    func testDeferredEventUsesNewTime() throws {
        var dinner = event("外食", at: TestDates.make(2026, 10, 2, 19, 0))
        dinner.deferredTo = TestDates.make(2026, 10, 3, 19, 30)
        let request = try XCTUnwrap(LifeNotificationPlanner.eventRequests(items: [dinner], now: now).first)
        XCTAssertEqual(request.fireDate, TestDates.make(2026, 10, 3, 19, 20))
    }

    /// 時刻なし・通知時刻が過ぎた・完了済み・もうやらない予定は通知しない
    func testEventsThatAreNotNotified() {
        var done = event("終わった予定", at: TestDates.make(2026, 10, 2, 15, 0))
        done.isCompleted = true
        var dropped = event("やめた予定", at: TestDates.make(2026, 10, 2, 16, 0))
        dropped.droppedAt = now
        let items = [
            event("時刻なし", at: TestDates.make(2026, 10, 2), hasTime: false),
            event("まもなく", at: TestDates.make(2026, 10, 2, 9, 15)),
            done,
            dropped
        ]
        XCTAssertTrue(LifeNotificationPlanner.eventRequests(items: items, now: now).isEmpty)
    }

    /// 予定は直近40件まで
    func testEventsAreLimitedToNearestForty() {
        let items = (1...50).map { event("予定\($0)", at: now.addingTimeInterval(Double($0) * 3600)) }
        let planned = LifeNotificationService.plannedRequests(
            warranties: [], isPremium: false, warrantyRemindersEnabled: false,
            items: items, eventRemindersEnabled: true, taskRemindersEnabled: false, now: now
        )
        XCTAssertEqual(planned.count, 40)
        XCTAssertEqual(planned.last?.body.hasSuffix("予定40（10分後）"), true, "近いものから40件")
    }

    // MARK: - 未完了タスク

    /// 当日の未完了タスクは、20時に1件だけ。習慣・予定・完了済み・もうやらない・パートナー担当は数えない
    func testUnfinishedTasksAreRemindedAtEightPM() throws {
        let items = [
            task("書類を出す"),
            task("洗濯", kind: .chore),
            task("水を飲む", kind: .habit),
            event("歯医者", at: TestDates.make(2026, 10, 2, 10, 30)),
            task("済んだこと", isCompleted: true),
            task("やめたこと", droppedAt: now),
            task("パートナーの用事", assignee: .partner),
            task("明日のこと", on: TestDates.saturday)
        ]
        let requests = LifeNotificationPlanner.taskRequests(items: items, now: now)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.fireDate, TestDates.make(2026, 10, 2, 20, 0))
        XCTAssertEqual(request.identifier, "lifeos.task.evening")
        XCTAssertEqual(request.body, "まだ終わっていないやることが2件あります")
    }

    func testNoTaskReminderWhenAllDone() {
        XCTAssertTrue(LifeNotificationPlanner.taskRequests(items: [task("済んだこと", isCompleted: true)], now: now).isEmpty)
        XCTAssertTrue(LifeNotificationPlanner.taskRequests(items: [], now: now).isEmpty)
    }

    /// 新しい解釈：20時を過ぎてから開いたときは、明日のやることを明日の20時に
    func testAfterEightPMTomorrowIsUsed() throws {
        let lateNight = TestDates.make(2026, 10, 2, 20, 30)
        let items = [task("今日の残り"), task("明日のこと", on: TestDates.saturday)]
        let request = try XCTUnwrap(LifeNotificationPlanner.taskRequests(items: items, now: lateNight).first)
        XCTAssertEqual(request.fireDate, TestDates.make(2026, 10, 3, 20, 0))
        XCTAssertEqual(request.body, "まだ終わっていないやることが1件あります")
    }

    // MARK: - 設定・合計

    /// 通知設定が OFF なら予約しない
    func testSettingsOffSchedulesNothing() {
        let items = [event("歯医者", at: TestDates.make(2026, 10, 2, 10, 30)), task("書類を出す")]
        let off = LifeNotificationService.plannedRequests(
            warranties: [], isPremium: true, warrantyRemindersEnabled: false,
            items: items, eventRemindersEnabled: false, taskRemindersEnabled: false, now: now
        )
        XCTAssertTrue(off.isEmpty)
        let onlyEvents = LifeNotificationService.plannedRequests(
            warranties: [], isPremium: true, warrantyRemindersEnabled: false,
            items: items, eventRemindersEnabled: true, taskRemindersEnabled: false, now: now
        )
        XCTAssertEqual(onlyEvents.map(\.category), [.event])
        let onlyTasks = LifeNotificationService.plannedRequests(
            warranties: [], isPremium: true, warrantyRemindersEnabled: false,
            items: items, eventRemindersEnabled: false, taskRemindersEnabled: true, now: now
        )
        XCTAssertEqual(onlyTasks.map(\.category), [.task])
    }

    /// 保証書18件・予定40件・タスク1件で、アプリ全体は最大59件
    func testWarrantyEventAndTaskTotalIsAtMostFiftyNine() {
        let warranties = (1...10).map { index in
            WarrantyDocument(
                title: "製品\(index)",
                warrantyExpiresAt: LifeCalendar.calendar.date(byAdding: .day, value: 40 + index, to: LifeCalendar.startOfDay(now)),
                expirationSource: .manual, createdAt: now, updatedAt: now
            )
        }
        let items = (1...60).map { event("予定\($0)", at: now.addingTimeInterval(Double($0) * 1800)) } + [task("書類を出す")]
        let planned = LifeNotificationService.plannedRequests(
            warranties: warranties, isPremium: true, warrantyRemindersEnabled: true,
            items: items, eventRemindersEnabled: true, taskRemindersEnabled: true, now: now
        )
        XCTAssertLessThanOrEqual(planned.count, 59)
        XCTAssertEqual(planned.count, 59)
        XCTAssertEqual(planned.filter { $0.category == .warranty }.count, 18)
        XCTAssertEqual(planned.filter { $0.category == .event }.count, 40)
        XCTAssertEqual(planned.filter { $0.category == .task }.count, 1)
    }

    /// アプリの状態から予約し直す：予定の通知が入り、設定を OFF にすると消える。ほかの通知は消さない
    func testResyncFromAppStateFollowsSettings() async {
        let center = FakeNotificationCenter(pending: ["other.reminder"])
        let service = LifeNotificationService(center: center)
        let store = LifeStore(items: [], warranties: [])
        store.items = [event("打ち合わせ", at: Date().addingTimeInterval(3 * 3600))]
        let appState = AppState()
        appState.notificationSettings.todaySchedule = true
        appState.notificationSettings.taskReminder = false

        await service.resync(store: store, appState: appState)
        XCTAssertEqual(center.pending.filter { $0.hasPrefix("lifeos.event.") }.count, 1)

        appState.notificationSettings.todaySchedule = false
        await service.resync(store: store, appState: appState)
        XCTAssertEqual(center.pending, ["other.reminder"])
    }
}

// MARK: - 表示名・Bundle Identifier・文言

final class AppIdentityTests: XCTestCase {
    func testDisplayNameAndBundleIdentifiers() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "くらしOS")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.tomoking945boop.lifeos")
        XCTAssertEqual(Bundle(for: AppIdentityTests.self).bundleIdentifier, "com.tomoking945boop.lifeos.tests")
    }

    func testUserFacingNameIsKurashiOS() {
        XCTAssertEqual(PremiumViewModel(appState: AppState()).title, "くらしOS Premium")
        let invite = InviteMessage.text(inviterName: "わたし", groupName: "わが家", item: nil)
        XCTAssertTrue(invite.contains("くらしOSの「わが家」"))
        XCTAssertFalse(invite.contains("生活OS"))
    }

    /// 生活グループ名の例は「わが家」
    func testGroupNameExampleIsWagaya() {
        XCTAssertEqual(MockData.profile.groupName, "わが家")
        XCTAssertEqual(AppState.newUserProfile.groupName, "わが家")
    }

    /// 「共有の更新」は、本物のパートナー同期ができるまで使えない
    func testSharedUpdatesStayDisabled() {
        let state = AppState()
        state.partnerJoined = true
        state.notificationSettings.sharedUpdates = true
        XCTAssertFalse(state.canUseSharedUpdates)
    }
}

// MARK: - 実際の現在時刻

final class CurrentTimeTests: XCTestCase {
    /// 製品版の共通時刻は、見本用の9:10固定ではなく端末の現在時刻を返す。
    func testLifeCalendarNowUsesDeviceClock() {
        let before = Date()
        let actual = LifeCalendar.now
        let after = Date()

        XCTAssertGreaterThanOrEqual(actual, before)
        XCTAssertLessThanOrEqual(actual, after)
    }

    /// 今日画面は時刻を更新でき、残り時間も新しい基準時刻から計算する。
    func testTodayRefreshesRemainingTime() {
        let start = TestDates.make(2026, 10, 2, 20, 10)
        let eventTime = TestDates.make(2026, 10, 2, 20, 30)
        let event = LifeItem(title: "通知テスト", kind: .event, ownership: .personal,
                             date: eventTime, hasTime: true)
        let store = LifeStore(items: [event], warranties: [])
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)

        viewModel.refreshNow(start)

        XCTAssertEqual(viewModel.nextEvent?.id, event.id)
        XCTAssertEqual(viewModel.remainingText(for: event), "あと20分")
    }
}
