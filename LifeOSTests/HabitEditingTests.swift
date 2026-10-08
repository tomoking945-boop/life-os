import XCTest
@testable import LifeOS

// 習慣を自分で追加・編集（2026-10-08）のテスト
// 日時は 2026/10/2（金）9:10 に固定（TestDates.friday）

final class HabitStoreTests: XCTestCase {
    func testAddHabitStartsTodayAndRejectsDuplicates() throws {
        let store = makeStore()
        let habit = try XCTUnwrap(store.addHabit(title: "  白湯を飲む ", isLight: true, repeatRule: .daily, startedAt: TestDates.friday))
        XCTAssertEqual(habit.title, "白湯を飲む")
        XCTAssertTrue(habit.isLight)
        XCTAssertTrue(store.habits(on: TestDates.friday).contains { $0.id == habit.id })
        XCTAssertFalse(habit.isActive(on: TestDates.daysAgo(1, from: TestDates.friday)), "始める前の日には出さない")

        XCTAssertNil(store.addHabit(title: "白湯を飲む", isLight: false, repeatRule: .daily, startedAt: TestDates.friday))
        XCTAssertNil(store.addHabit(title: "   ", isLight: false, repeatRule: .daily, startedAt: TestDates.friday))
    }

    /// 編集しても、できた日の記録は残る
    func testUpdateKeepsRecords() throws {
        let store = makeStore()
        let water = try XCTUnwrap(store.habits.first { $0.title == "水を飲む" })
        store.updateHabit(water.id, title: "水を2杯飲む", isLight: false, repeatRule: .weekdays([2, 4, 6]))

        let updated = try XCTUnwrap(store.habits.first { $0.id == water.id })
        XCTAssertEqual(updated.title, "水を2杯飲む")
        XCTAssertFalse(updated.isLight)
        XCTAssertEqual(updated.repeatRule, .weekdays([2, 4, 6]))
        XCTAssertEqual(updated.doneDays, water.doneDays)

        store.updateHabit(water.id, title: "  ", isLight: false, repeatRule: .daily)
        XCTAssertEqual(store.habits.first { $0.id == water.id }?.title, "水を2杯飲む", "空の名前では変えない")
    }

    func testRemoveAndRestoreAtSamePlace() throws {
        let store = makeStore()
        let water = try XCTUnwrap(store.habits.first)
        let removed = try XCTUnwrap(store.removeHabit(water.id))
        XCTAssertFalse(store.habits.contains { $0.id == water.id })

        store.restoreHabit(removed.habit, at: removed.index)
        XCTAssertEqual(store.habits.first, water)
    }

    /// 種類「習慣」で追加した項目（Inbox の修正など）は、毎日くり返す習慣にもなる。「元に戻す」で一緒に消える
    func testHabitKindItemRegistersHabit() throws {
        let store = makeStore()
        var suggestion = InboxClassifier.suggest(for: "日記を書く")
        suggestion.kind = .habit
        let item = suggestion.makeItem(today: TestDates.friday)
        store.add([item])

        let habit = try XCTUnwrap(store.habits.first { $0.title == "日記を書く" })
        XCTAssertEqual(habit.id, item.id)
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        XCTAssertTrue(viewModel.visibleHabits.contains { $0.title == "日記を書く" })
        XCTAssertTrue(viewModel.legacyHabitItems.isEmpty, "同じ名前の行を重ねて出さない")

        store.removeItems(withIDs: [item.id])
        XCTAssertFalse(store.habits.contains { $0.title == "日記を書く" })
    }

    func testSameTitleHabitItemDoesNotDuplicate() {
        let store = makeStore()
        let count = store.habits.count
        store.add([LifeItem(title: "水を飲む", kind: .habit, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(store.habits.count, count)
    }
}

final class HabitsScreenTests: XCTestCase {
    func testAddWithUndo() {
        let store = makeStore()
        let viewModel = HabitsViewModel(store: store, now: TestDates.friday)
        XCTAssertFalse(viewModel.canAdd)

        viewModel.newTitle = "水を飲む"
        XCTAssertFalse(viewModel.canAdd)
        XCTAssertEqual(viewModel.duplicateNote, "「水を飲む」はもうあります")

        viewModel.newTitle = "散歩"
        viewModel.newIsLight = true
        XCTAssertTrue(viewModel.add())
        XCTAssertEqual(viewModel.newTitle, "")
        XCTAssertFalse(viewModel.newIsLight)
        XCTAssertEqual(store.habits.last?.title, "散歩")
        XCTAssertEqual(store.habits.last?.isLight, true)
        XCTAssertEqual(viewModel.feedback?.message, "「散歩」を習慣にしました")

        viewModel.performUndo()
        XCTAssertFalse(store.habits.contains { $0.title == "散歩" })
    }

    func testEditDraftAndRepeatText() throws {
        let store = makeStore()
        let viewModel = HabitsViewModel(store: store, now: TestDates.friday)
        let stretch = try XCTUnwrap(store.habits.first { $0.title == "ストレッチ" })
        XCTAssertEqual(viewModel.detailText(stretch), "毎日")

        viewModel.startEditing(stretch)
        var draft = try XCTUnwrap(viewModel.editing)
        XCTAssertTrue(draft.isDaily)
        draft.isDaily = false
        draft.weekdays = [6, 2, 4]
        draft.isLight = true
        viewModel.save(draft)
        XCTAssertNil(viewModel.editing)

        let updated = try XCTUnwrap(store.habits.first { $0.id == stretch.id })
        XCTAssertEqual(updated.repeatRule, .weekdays([2, 4, 6]))
        XCTAssertEqual(viewModel.detailText(updated), "月・水・金・軽い習慣")
        XCTAssertFalse(viewModel.isRestDay(updated), "10/2 は金曜")
    }

    /// 曜日を選ばなければ毎日
    func testEmptyWeekdaysMeansDaily() throws {
        let store = makeStore()
        let water = try XCTUnwrap(store.habits.first)
        var draft = HabitDraft(habit: water)
        draft.isDaily = false
        draft.weekdays = []
        XCTAssertEqual(draft.repeatRule, .daily)
    }

    /// 曜日の習慣は、お休みの曜日には今日画面に出ない
    func testWeekdayHabitRestsOnOtherDays() throws {
        let store = makeStore()
        let water = try XCTUnwrap(store.habits.first { $0.title == "水を飲む" })
        store.updateHabit(water.id, title: water.title, isLight: true, repeatRule: .weekdays([7]))

        let friday = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        XCTAssertFalse(friday.visibleHabits.contains { $0.id == water.id })
        let saturday = TodayViewModel(store: store, appState: AppState(), now: TestDates.saturday)
        XCTAssertTrue(saturday.visibleHabits.contains { $0.id == water.id })
        XCTAssertTrue(HabitsViewModel(store: store, now: TestDates.friday).isRestDay(try XCTUnwrap(store.habits.first { $0.id == water.id })))
    }

    func testDeleteWithUndoKeepsRecords() throws {
        let store = makeStore()
        let viewModel = HabitsViewModel(store: store, now: TestDates.friday)
        let water = try XCTUnwrap(store.habits.first)
        viewModel.delete(water.id)
        XCTAssertFalse(store.habits.contains { $0.id == water.id })
        XCTAssertEqual(viewModel.feedback?.message, "「水を飲む」を習慣から外しました")

        viewModel.performUndo()
        XCTAssertEqual(store.habits.first, water)
    }
}
