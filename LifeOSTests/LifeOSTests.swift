import XCTest
@testable import LifeOS

// v2 仕様 24 のテスト候補：ScopeFilter / Free・Premium / QuickAdd 金額解析 / Inbox 分類 /
// 今日これだけ / Ownership / 未完了救済 / 暮らしメモリーの表示条件（＋あとで・買い物・家事）

final class ScopeFilterTests: XCTestCase {
    func testAllIncludesBoth() {
        XCTAssertTrue(ScopeFilter.all.includes(.personal))
        XCTAssertTrue(ScopeFilter.all.includes(.shared))
    }

    func testMineIncludesOnlyPersonal() {
        XCTAssertTrue(ScopeFilter.mine.includes(.personal))
        XCTAssertFalse(ScopeFilter.mine.includes(.shared))
    }

    func testSharedIncludesOnlyShared() {
        XCTAssertFalse(ScopeFilter.shared.includes(.personal))
        XCTAssertTrue(ScopeFilter.shared.includes(.shared))
    }
}

final class OwnershipTests: XCTestCase {
    func testStoreFiltersByOwnership() {
        let store = makeStore()
        let mine = store.items(on: TestDates.friday, scope: .mine)
        let shared = store.items(on: TestDates.friday, scope: .shared)
        let all = store.items(on: TestDates.friday, scope: .all)

        XCTAssertFalse(mine.isEmpty)
        XCTAssertFalse(shared.isEmpty)
        XCTAssertTrue(mine.allSatisfy { $0.ownership == .personal })
        XCTAssertTrue(shared.allSatisfy { $0.ownership == .shared })
        XCTAssertEqual(all.count, mine.count + shared.count)
    }

    func testSoloModeAlwaysUsesAllScope() {
        let state = AppState()
        state.scope = .shared
        state.usageStyle = .solo
        XCTAssertEqual(state.effectiveScope, .all)
        state.usageStyle = .shared
        XCTAssertEqual(state.effectiveScope, .shared)
    }
}

final class PlanTests: XCTestCase {
    func testFreeShowsAdAndPremiumHidesIt() {
        let state = AppState()
        let viewModel = TodayViewModel(store: makeStore(), appState: state, now: TestDates.friday)

        state.plan = .free
        XCTAssertFalse(state.isPremium)
        XCTAssertTrue(viewModel.showsAd)

        state.plan = .premium
        XCTAssertTrue(state.isPremium)
        XCTAssertFalse(viewModel.showsAd)
    }

    func testPremiumPricesAreUnchanged() {
        XCTAssertEqual(PremiumBillingOption.monthly.price, 480)
        XCTAssertEqual(PremiumBillingOption.annual.price, 5_280)
        XCTAssertEqual(PremiumBillingOption.annual.note, "年額なら1か月分お得")
    }
}

final class QuickAddExpenseParsingTests: XCTestCase {
    func testParsesTitleAndAmount() {
        let parsed = QuickAddViewModel.parseExpense("ランチ 1200")
        XCTAssertEqual(parsed?.title, "ランチ")
        XCTAssertEqual(parsed?.amount, 1_200)
    }

    func testParsesCommaAndYen() {
        let parsed = QuickAddViewModel.parseExpense("スーパー 3,520円")
        XCTAssertEqual(parsed?.title, "スーパー")
        XCTAssertEqual(parsed?.amount, 3_520)
    }

    func testParsesFullWidthDigits() {
        XCTAssertEqual(QuickAddViewModel.parseExpense("コーヒー ５００")?.amount, 500)
    }

    func testUsesDefaultTitleWhenOnlyAmount() {
        XCTAssertEqual(QuickAddViewModel.parseExpense("980")?.title, "支出")
    }

    func testReturnsNilWithoutAmount() {
        XCTAssertNil(QuickAddViewModel.parseExpense("ランチ"))
    }
}

final class InboxClassifierTests: XCTestCase {
    func testShoppingTomorrow() {
        let suggestion = InboxClassifier.suggest(for: "明日牛乳買う")
        XCTAssertEqual(suggestion.kind, .shopping)
        XCTAssertEqual(suggestion.day, .tomorrow)
        XCTAssertEqual(suggestion.ownership, .personal)
        XCTAssertEqual(suggestion.title, "牛乳を買う")
        XCTAssertEqual(suggestion.summary, "買い物・明日")
    }

    func testSharedTodo() {
        let suggestion = InboxClassifier.suggest(for: "妻と旅行相談")
        XCTAssertEqual(suggestion.kind, .todo)
        XCTAssertEqual(suggestion.ownership, .shared)
        XCTAssertEqual(suggestion.summary, "共有ToDo・今日")
    }

    func testPayment() {
        XCTAssertEqual(InboxClassifier.suggest(for: "電気代を払う").kind, .payment)
    }

    func testDefaultIsTodoToday() {
        let suggestion = InboxClassifier.suggest(for: "美容院を予約する")
        XCTAssertEqual(suggestion.kind, .todo)
        XCTAssertEqual(suggestion.day, .today)
    }
}

final class TodayFocusTests: XCTestCase {
    func testPicksThreeItemsInExpectedOrder() {
        let store = makeStore()
        let split = TodayFocusSelector.split(store.items(on: TestDates.friday, scope: .all))

        XCTAssertEqual(split.focus.map(\.title), ["ゴミ出し", "歯医者", "牛乳を買う"])
        XCTAssertEqual(split.focus.count, TodayFocusSelector.maxCount)
        XCTAssertFalse(split.rest.contains { $0.isHabit })
        XCTAssertFalse(split.focus.contains { $0.isHabit })
    }

    func testPartnerItemsGoToRest() {
        let store = makeStore()
        let split = TodayFocusSelector.split(store.items(on: TestDates.friday, scope: .all))
        XCTAssertFalse(split.focus.contains { $0.assignee == .partner })
        XCTAssertTrue(split.rest.contains { $0.title == "クリーニング受取" })
    }

    func testCompletedItemsMoveDownButStayInFocus() {
        let store = makeStore()
        let state = AppState()
        let viewModel = TodayViewModel(store: store, appState: state, now: TestDates.friday)
        let first = viewModel.focusItems[0]

        viewModel.toggle(first)

        XCTAssertEqual(viewModel.focusItems.count, 3)
        XCTAssertEqual(viewModel.focusItems.last?.id, first.id)
        XCTAssertFalse(viewModel.isFocusCompleted)
    }
}

final class LeftoverRescueTests: XCTestCase {
    func testYesterdayIncompleteTasksAreLeftovers() {
        let store = makeStore()
        let leftovers = store.leftovers(before: TestDates.friday, scope: .all)
        XCTAssertEqual(Set(leftovers.map(\.title)), ["粗大ゴミの申し込み", "郵便を出す"])
    }

    func testShowTodayKeepsOriginalDate() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.leftovers(before: TestDates.friday, scope: .all).first)
        let originalDate = item.date

        store.reschedule(item.id, to: LifeCalendar.startOfDay(TestDates.friday))

        let updated = try XCTUnwrap(store.items.first { $0.id == item.id })
        XCTAssertEqual(updated.date, originalDate, "元の日付は書き換えない")
        XCTAssertTrue(store.items(on: TestDates.friday, scope: .all).contains { $0.id == item.id })
        XCTAssertFalse(store.leftovers(before: TestDates.friday, scope: .all).contains { $0.id == item.id })
    }

    func testDropHidesWithoutDeleting() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.leftovers(before: TestDates.friday, scope: .all).first)
        let countBefore = store.items.count

        store.drop(item.id, at: TestDates.friday)

        XCTAssertEqual(store.items.count, countBefore, "削除はしない")
        XCTAssertFalse(store.leftovers(before: TestDates.friday, scope: .all).contains { $0.id == item.id })
    }

    func testCompletedAndHabitsAreNotLeftovers() {
        let yesterday = TestDates.daysAgo(1, from: TestDates.friday)
        let store = LifeStore(items: [
            LifeItem(title: "済み", kind: .todo, ownership: .personal, date: yesterday, isCompleted: true),
            LifeItem(title: "習慣", kind: .habit, ownership: .personal, date: yesterday),
            LifeItem(title: "予定", kind: .event, ownership: .personal, date: yesterday)
        ])
        XCTAssertTrue(store.leftovers(before: TestDates.friday, scope: .all).isEmpty)
    }
}

final class PostponeOptionTests: XCTestCase {
    private func weekday(_ date: Date) -> Int {
        LifeCalendar.calendar.component(.weekday, from: date)
    }

    func testTonightIsTwentyOClockToday() {
        let date = PostponeOption.tonight.date(from: TestDates.friday)
        XCTAssertTrue(LifeCalendar.isSameDay(date, TestDates.friday))
        XCTAssertEqual(LifeCalendar.calendar.component(.hour, from: date), 20)
    }

    func testTomorrow() {
        XCTAssertTrue(LifeCalendar.isSameDay(PostponeOption.tomorrow.date(from: TestDates.friday), TestDates.saturday))
    }

    func testWeekendFromWeekdayIsSaturday() {
        XCTAssertEqual(weekday(PostponeOption.weekend.date(from: TestDates.friday)), 7)
    }

    func testWeekendFromSaturdayIsSunday() {
        XCTAssertTrue(LifeCalendar.isSameDay(PostponeOption.weekend.date(from: TestDates.saturday), TestDates.sunday))
    }

    func testNextWeekIsMonday() {
        XCTAssertEqual(weekday(PostponeOption.nextWeek.date(from: TestDates.friday)), 2)
        XCTAssertEqual(weekday(PostponeOption.nextWeek.date(from: TestDates.sunday)), 2)
    }
}

final class LifeMemoryTests: XCTestCase {
    func testSinceLastIsDueAfterInterval() {
        let now = TestDates.friday
        let due = LifeMemory(title: "シャンプー",
                             rule: .sinceLast(lastDate: TestDates.daysAgo(49, from: now), dueAfterDays: 42),
                             action: .addToShopping("シャンプーを買う"))
        let notDue = LifeMemory(title: "シャンプー",
                                rule: .sinceLast(lastDate: TestDates.daysAgo(10, from: now), dueAfterDays: 42),
                                action: .addToShopping("シャンプーを買う"))
        XCTAssertTrue(LifeMemoryEvaluator.isDue(due, now: now))
        XCTAssertFalse(LifeMemoryEvaluator.isDue(notDue, now: now))
        XCTAssertEqual(LifeMemoryEvaluator.message(due, now: now), "そろそろ買う頃です")
        XCTAssertEqual(LifeMemoryEvaluator.cycleText(due, now: now), "前回購入から7週間")
    }

    func testHiddenUntilFutureIsNotDue() {
        let now = TestDates.friday
        let memory = LifeMemory(title: "歯医者",
                                rule: .sinceLast(lastDate: TestDates.daysAgo(200, from: now), dueAfterDays: 180),
                                action: .addToTodo("歯医者を予約する"),
                                hiddenUntil: TestDates.saturday)
        XCTAssertFalse(LifeMemoryEvaluator.isDue(memory, now: now))
        XCTAssertTrue(LifeMemoryEvaluator.isDue(memory, now: TestDates.sunday))
    }

    func testWeekdays() {
        let trash = LifeMemory(title: "ゴミ", rule: .weekdays([3, 6]), action: .notifyOnly)
        XCTAssertTrue(LifeMemoryEvaluator.isDue(trash, now: TestDates.friday))
        XCTAssertFalse(LifeMemoryEvaluator.isDue(trash, now: TestDates.saturday))
        XCTAssertEqual(LifeMemoryEvaluator.cycleText(trash, now: TestDates.friday), "火曜・金曜")
    }

    func testMonthlyDayNotice() {
        let rent = LifeMemory(title: "家賃", rule: .monthlyDay(day: 27, noticeDaysBefore: 3), action: .addToTodo("家賃を払う"))
        XCTAssertTrue(LifeMemoryEvaluator.isDue(rent, now: TestDates.october25))
        XCTAssertFalse(LifeMemoryEvaluator.isDue(rent, now: TestDates.october10))
    }

    func testSkipRestartsCycle() throws {
        let store = makeStore()
        let shampoo = try XCTUnwrap(store.memories.first { $0.title == "シャンプー" })
        XCTAssertTrue(LifeMemoryEvaluator.isDue(shampoo, now: TestDates.friday))

        store.restartMemoryCycle(shampoo.id, from: TestDates.friday)

        let updated = try XCTUnwrap(store.memories.first { $0.id == shampoo.id })
        XCTAssertFalse(LifeMemoryEvaluator.isDue(updated, now: TestDates.friday))
    }
}

final class ShoppingTests: XCTestCase {
    func testAutoCategories() {
        XCTAssertEqual(ShoppingCategorizer.categories(for: "牛乳を買う"), [.food, .chilled])
        XCTAssertEqual(ShoppingCategorizer.aisle(for: "牛乳を買う"), .chilled)
        XCTAssertEqual(ShoppingCategorizer.aisle(for: "ティッシュ"), .dailyGoods)
        XCTAssertEqual(ShoppingCategorizer.aisle(for: "よく分からないもの"), .other)
    }

    func testItemName() {
        XCTAssertEqual(ShoppingCategorizer.itemName(from: "牛乳を買う"), "牛乳")
        XCTAssertEqual(ShoppingCategorizer.itemName(from: "卵"), "卵")
    }

    func testAddShoppingSkipsDuplicates() {
        let store = makeStore()
        // Mock には「牛乳を買う」が未完了で入っている
        XCTAssertEqual(store.addShopping(["牛乳", "玉ねぎ"], ownership: .personal, now: TestDates.friday), 1)
        XCTAssertEqual(store.addShopping(["玉ねぎ"], ownership: .personal, now: TestDates.friday), 0)
    }
}

final class ChoreAutopilotTests: XCTestCase {
    func testChoresIncreaseWithEnergy() {
        let templates = MockData.choreTemplates
        XCTAssertEqual(ChoreTemplate.chores(for: .low, from: templates).count, 2)
        XCTAssertEqual(ChoreTemplate.chores(for: .normal, from: templates).count, 3)
        XCTAssertEqual(ChoreTemplate.chores(for: .high, from: templates).count, 5)
    }

    func testAutopilotResetsOnNewDay() {
        let store = makeStore()
        store.setEnergy(.high, now: TestDates.friday)
        store.toggleChore("trash", now: TestDates.friday)
        XCTAssertEqual(store.autopilotDay(for: TestDates.friday).energy, .high)
        XCTAssertEqual(store.autopilotDay(for: TestDates.friday).doneChoreIDs, ["trash"])

        let nextDay = store.autopilotDay(for: TestDates.saturday)
        XCTAssertNil(nextDay.energy)
        XCTAssertTrue(nextDay.doneChoreIDs.isEmpty)
    }
}
