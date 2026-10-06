import XCTest
@testable import LifeOS

// Calm Future 第1段階のテスト：時間帯 / Living Timeline / Ambient Header / 元に戻す / 保存データの互換性

final class TimeOfDayTests: XCTestCase {
    func testHoursMapToTimeOfDay() {
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.make(2026, 10, 2, 7, 0)), .morning)
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.friday), .morning)
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.make(2026, 10, 2, 13, 0)), .day)
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.make(2026, 10, 2, 17, 30)), .evening)
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.make(2026, 10, 2, 22, 0)), .night)
        XCTAssertEqual(LifeTimeOfDay(date: TestDates.make(2026, 10, 2, 3, 0)), .night)
    }

    func testGreetingFollowsPreview() {
        let state = AppState()
        let viewModel = TodayViewModel(store: makeStore(), appState: state, now: TestDates.friday)
        XCTAssertEqual(viewModel.greeting, "Good morning.")
        state.ambientPreview = .evening
        XCTAssertEqual(viewModel.timeOfDay, .evening)
        XCTAssertEqual(viewModel.greeting, "Good evening.")
    }
}

final class LivingTimelineTests: XCTestCase {
    /// 仕様の例（NOW ゴミ / 10:30 歯医者 / 帰宅時 牛乳 …）と同じ並びになる
    func testMockDayMatchesSpecExample() {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        let sections = viewModel.timelineSections

        XCTAssertEqual(sections.map(\.slot), [
            .now,
            .time(TestDates.make(2026, 10, 2, 10, 30)),
            .soft(.onTheWayHome),
            .time(TestDates.make(2026, 10, 2, 20, 0))
        ])
        XCTAssertEqual(sections.map { $0.items.map(\.title) }, [["ゴミ出し"], ["歯医者"], ["牛乳を買う"], ["外食"]])
        XCTAssertEqual(Set(viewModel.extraItems.map(\.title)), ["電気代を払う", "筋トレ", "クリーニング受取"])
        XCTAssertEqual(viewModel.restToggleTitle, "あと3件")
    }

    func testFocusNumbersStayWhenCompleted() throws {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        let trash = try XCTUnwrap(viewModel.timelineSections.first?.items.first)
        XCTAssertEqual(viewModel.focusNumber(for: trash), "01")
        viewModel.toggle(trash)
        XCTAssertEqual(viewModel.focusNumber(for: trash), "01")
    }

    func testSoftTimeOverridesDefaultSlot() {
        let item = LifeItem(title: "シーツを洗う", kind: .chore, ownership: .personal,
                            date: TestDates.friday, softTime: .thisWeek)
        XCTAssertEqual(LivingTimelineBuilder.slot(forFocus: item), .soft(.thisWeek))
    }

    func testSoftSlotsNeverComeBeforeNow() {
        let night = TestDates.make(2026, 10, 2, 20, 30)
        let chore = LifeItem(title: "ゴミ出し", kind: .chore, ownership: .personal, date: night)
        let shopping = LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .personal, date: night)
        let timeline = LivingTimelineBuilder.build(focus: [shopping, chore], rest: [], now: night)
        XCTAssertEqual(timeline.sections.map(\.slot), [.now, .soft(.onTheWayHome)])
    }
}

final class AmbientHeaderTests: XCTestCase {
    func testMessagesForMockDay() {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.ambientMessage, "10:30の歯医者まで1時間20分")
        XCTAssertEqual(viewModel.ambientSubMessage, "今日は3つだけで十分です")
    }

    func testLowEnergyIsGentle() {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        viewModel.selectEnergy(.low)
        XCTAssertEqual(viewModel.ambientSubMessage, "今日は軽めで大丈夫です")
    }

    func testDurationFormatter() {
        let now = TestDates.friday
        XCTAssertEqual(LifeFormatters.duration(from: now, to: TestDates.make(2026, 10, 2, 10, 30)), "1時間20分")
        XCTAssertEqual(LifeFormatters.duration(from: now, to: TestDates.make(2026, 10, 2, 10, 10)), "1時間")
        XCTAssertEqual(LifeFormatters.duration(from: now, to: TestDates.make(2026, 10, 2, 9, 52)), "42分")
        XCTAssertNil(LifeFormatters.duration(from: now, to: TestDates.make(2026, 10, 2, 9, 0)))
    }
}

final class UndoTests: XCTestCase {
    func testUndoPostpone() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let trash = try XCTUnwrap(store.items.first { $0.title == "ゴミ出し" })

        viewModel.postpone(trash, to: .tomorrow)
        XCTAssertNotNil(store.items.first { $0.id == trash.id }?.deferredTo)
        XCTAssertNotNil(viewModel.feedback?.undo)

        viewModel.performUndo()
        XCTAssertNil(store.items.first { $0.id == trash.id }?.deferredTo)
        XCTAssertEqual(viewModel.feedback?.message, "元に戻しました")
        XCTAssertNil(viewModel.feedback?.undo)
    }

    func testUndoDropKeepsCompletion() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let leftover = try XCTUnwrap(viewModel.leftovers.first)

        viewModel.dropLeftover(leftover)
        XCTAssertFalse(viewModel.leftovers.contains { $0.id == leftover.id })
        viewModel.performUndo()
        XCTAssertTrue(viewModel.leftovers.contains { $0.id == leftover.id })
    }

    func testUndoMemoryActionRemovesAddedItem() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let shampoo = try XCTUnwrap(store.memories.first { $0.title == "シャンプー" })
        let countBefore = store.items.count

        viewModel.performMemoryAction(shampoo)
        XCTAssertEqual(store.items.count, countBefore + 1)
        XCTAssertNotNil(store.memories.first { $0.id == shampoo.id }?.hiddenUntil)

        viewModel.performUndo()
        XCTAssertEqual(store.items.count, countBefore)
        XCTAssertNil(store.memories.first { $0.id == shampoo.id }?.hiddenUntil)
    }
}

final class CompatibilityTests: XCTestCase {
    /// Calm Future より前の保存データ（softTime が無い）もそのまま読める
    func testDecodesItemWithoutSoftTime() throws {
        let json = """
        {"id":"7C0A6D2E-9F0B-4C1A-8E0D-2B1C3D4E5F60","title":"牛乳を買う","kind":"shopping",
         "ownership":"shared","date":0,"hasTime":false,"assignee":"either","isCompleted":false}
        """
        let item = try JSONDecoder().decode(LifeItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.title, "牛乳を買う")
        XCTAssertNil(item.softTime)
        XCTAssertNil(item.deferredTo)
    }

    func testSoftTimeRoundTrips() throws {
        let item = LifeItem(title: "母へ電話", kind: .todo, ownership: .personal, date: TestDates.friday, softTime: .thisWeek)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(LifeItem.self, from: data)
        XCTAssertEqual(decoded.softTime, .thisWeek)
    }
}

final class LeftoverPresentationTests: XCTestCase {
    func testYesterdayOnlyTitleAndNoToggle() {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.leftoverTitle, "昨日残ったもの")
        XCTAssertEqual(viewModel.visibleLeftovers.count, 2)
        XCTAssertFalse(viewModel.hasHiddenLeftovers)
    }

    func testOlderItemsChangeTitleAndCollapse() {
        let store = makeStore()
        let older = TestDates.daysAgo(3, from: TestDates.friday)
        store.add([
            LifeItem(title: "書類を出す", kind: .todo, ownership: .personal, date: older, assignee: .me),
            LifeItem(title: "電球を替える", kind: .chore, ownership: .personal, date: older, assignee: .me)
        ])
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)

        XCTAssertEqual(viewModel.leftoverTitle, "残っているもの")
        XCTAssertEqual(viewModel.leftovers.count, 4)
        XCTAssertEqual(viewModel.visibleLeftovers.count, 3)
        XCTAssertEqual(viewModel.leftoverToggleTitle, "あと1件")

        viewModel.isShowingAllLeftovers = true
        XCTAssertEqual(viewModel.visibleLeftovers.count, 4)
    }
}
