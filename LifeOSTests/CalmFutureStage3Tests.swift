import XCTest
@testable import LifeOS

// Calm Future 第3段階のテスト：習慣のリズムと毎日のくり返し / 暮らしメモリーの記録 / LifeOSからの提案
// 日時は 2026/10/2（金）9:10 に固定（TestDates.friday）

final class HabitRhythmTests: XCTestCase {
    private func mockHabit(_ title: String, now: Date = TestDates.friday) throws -> Habit {
        try XCTUnwrap(MockData.habits(now: now).first { $0.title == title })
    }

    /// 7日の点：古い日 → 今日。できた日は done、まだは open（今日は輪付き）
    func testSevenDaysForMockWater() throws {
        let habit = try mockHabit("水を飲む")
        let days = HabitRhythm.days(for: habit, now: TestDates.friday)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.state), [.done, .done, .done, .open, .done, .done, .open])
        XCTAssertEqual(days.map(\.isToday), [false, false, false, false, false, false, true])
        XCTAssertTrue(LifeCalendar.isSameDay(days.last?.date ?? .distantPast, TestDates.friday))
    }

    /// ストリークではなく、責めない言い方
    func testMessagesForMockHabits() throws {
        XCTAssertEqual(HabitRhythm.message(for: try mockHabit("水を飲む"), now: TestDates.friday), "最近、自然に続いています")
        XCTAssertEqual(HabitRhythm.message(for: try mockHabit("ストレッチ"), now: TestDates.friday), "少しずつ、リズムができています")
    }

    func testNewAndQuietHabitsAreNotBlamed() {
        let new = Habit(title: "日記", startedAt: TestDates.friday)
        XCTAssertEqual(HabitRhythm.message(for: new, now: TestDates.friday), "始めたばかりです")
        let started = Habit(title: "日記", startedAt: TestDates.friday, doneDays: [TestDates.friday])
        XCTAssertEqual(HabitRhythm.message(for: started, now: TestDates.friday), "いいスタートです")
        let quiet = Habit(title: "日記", startedAt: TestDates.daysAgo(30, from: TestDates.friday))
        XCTAssertEqual(HabitRhythm.message(for: quiet, now: TestDates.friday), "できる日に、また始めれば大丈夫です")
        // 始める前の日は「できなかった日」として数えない
        XCTAssertEqual(HabitRhythm.days(for: new, now: TestDates.friday).filter { $0.state == .inactive }.count, 6)
    }

    /// Mock の日付に依存せず、毎日くり返す
    func testHabitsRepeatEveryDay() {
        let store = makeStore()
        let later = TestDates.make(2026, 10, 20, 9, 10)
        XCTAssertEqual(store.habits(on: TestDates.friday).map(\.title), ["水を飲む", "ストレッチ"])
        XCTAssertEqual(store.habits(on: later).map(\.title), ["水を飲む", "ストレッチ"])
        // 始めた日より前には出さない
        let habit = Habit(title: "日記", startedAt: TestDates.october10)
        XCTAssertFalse(habit.isActive(on: TestDates.friday))
        XCTAssertTrue(habit.isActive(on: TestDates.october10))
        // 曜日のくり返し（構造のみ）
        let weekly = Habit(title: "植物に水", repeatRule: .weekdays([7]), startedAt: TestDates.daysAgo(30, from: TestDates.friday))
        XCTAssertFalse(weekly.isActive(on: TestDates.friday))
        XCTAssertTrue(weekly.isActive(on: TestDates.saturday))
    }

    func testToggleHabitRecordsOnlyThatDay() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let water = try XCTUnwrap(viewModel.visibleHabits.first { $0.title == "水を飲む" })
        XCTAssertFalse(viewModel.isHabitDone(water))

        viewModel.toggleHabit(water)
        let updated = try XCTUnwrap(store.habits.first { $0.id == water.id })
        XCTAssertTrue(viewModel.isHabitDone(updated))
        XCTAssertEqual(viewModel.rhythmDays(updated).last?.state, .done)
        XCTAssertEqual(updated.doneDays.count, water.doneDays.count + 1)

        viewModel.toggleHabit(updated)
        let reverted = try XCTUnwrap(store.habits.first { $0.id == water.id })
        XCTAssertFalse(viewModel.isHabitDone(reverted))
        XCTAssertEqual(reverted.doneDays.count, water.doneDays.count)
    }

    /// 余力が少ない日は軽い習慣だけ。開けば全部
    func testLowEnergyShowsOnlyLightHabits() {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.visibleHabits.map(\.title), ["水を飲む", "ストレッチ"])
        XCTAssertFalse(viewModel.canToggleHabits)
        XCTAssertEqual(viewModel.habitFootnote, "できた日だけ、チェックすれば十分です。")

        viewModel.selectEnergy(.low)
        XCTAssertEqual(viewModel.visibleHabits.map(\.title), ["水を飲む"])
        XCTAssertTrue(viewModel.canToggleHabits)
        XCTAssertEqual(viewModel.habitToggleTitle, "ほかの習慣 1件")
        XCTAssertEqual(viewModel.habitFootnote, "今日は軽い習慣だけで十分です。")

        viewModel.isShowingAllHabits = true
        XCTAssertEqual(viewModel.visibleHabits.count, 2)
    }

    /// 第3段階より前に日付つきで追加した習慣も表示を続ける（同じ名前の習慣があれば重ねない）
    func testLegacyHabitItemsStayVisible() {
        let store = makeStore()
        store.add([
            LifeItem(title: "読書", kind: .habit, ownership: .personal, date: TestDates.friday, assignee: .me),
            LifeItem(title: "水を飲む", kind: .habit, ownership: .personal, date: TestDates.friday, assignee: .me)
        ])
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.legacyHabitItems.map(\.title), ["読書"])
        XCTAssertTrue(viewModel.hasHabits)
    }

    /// 以前の保存データ：日付つきの習慣の項目から、毎日くり返す習慣を作る
    func testMigratesHabitItems() throws {
        let yesterday = TestDates.daysAgo(1, from: TestDates.friday)
        let items = [
            LifeItem(title: "水を飲む", kind: .habit, ownership: .personal, date: yesterday, isCompleted: true),
            LifeItem(title: "水を飲む", kind: .habit, ownership: .personal, date: TestDates.friday),
            LifeItem(title: "ストレッチ", kind: .habit, ownership: .personal, date: TestDates.friday),
            LifeItem(title: "ゴミ出し", kind: .chore, ownership: .personal, date: TestDates.friday)
        ]
        let habits = LifeStore.migratedHabits(from: items)
        XCTAssertEqual(habits.map(\.title), ["水を飲む", "ストレッチ"])
        let water = try XCTUnwrap(habits.first)
        XCTAssertTrue(water.isLight)
        XCTAssertTrue(water.isDone(on: yesterday))
        XCTAssertFalse(water.isDone(on: TestDates.friday))
        XCTAssertTrue(LifeCalendar.isSameDay(water.startedAt, yesterday))
        XCTAssertFalse(habits[1].isLight)
    }

    func testMigrationWithoutHabitItemsUsesMock() {
        let habits = LifeStore.migratedHabits(from: [])
        XCTAssertEqual(habits.map(\.title), ["水を飲む", "ストレッチ"])
    }

    func testHabitRoundTrips() throws {
        let habit = Habit(title: "植物に水", repeatRule: .weekdays([1, 7]), isLight: true,
                          startedAt: TestDates.friday, doneDays: [TestDates.friday])
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit))
        XCTAssertEqual(decoded, habit)
    }
}

final class LifeSuggestionTests: XCTestCase {
    /// 仕様の例と同じ形：予定が多い日に、時刻の決まっていないものを週末へ
    func testBusyMockDaySuggestsMovingWorkout() throws {
        let viewModel = TodayViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        let suggestion = try XCTUnwrap(viewModel.suggestion)
        XCTAssertEqual(suggestion.itemTitle, "筋トレ")
        XCTAssertTrue(LifeCalendar.isSameDay(suggestion.targetDate, TestDates.saturday))
        XCTAssertEqual(suggestion.message, "今日は予定が多いため、「筋トレ」を10/3（土）へ移すと余裕ができます。")
        XCTAssertEqual(suggestion.reason, "今日の予定・やることが7つあります。時刻の決まっていないものから選びました。")
        XCTAssertEqual(suggestion.acceptTitle, "移動する")
    }

    /// 自動では変えない。「移動する」で変え、「元に戻す」で戻る
    func testAcceptMovesAndUndoRestores() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let suggestion = try XCTUnwrap(viewModel.suggestion)
        XCTAssertNil(store.items.first { $0.id == suggestion.itemID }?.deferredTo, "表示しただけでは変えない")

        viewModel.acceptSuggestion(suggestion)
        let moved = try XCTUnwrap(store.items.first { $0.id == suggestion.itemID })
        XCTAssertTrue(LifeCalendar.isSameDay(moved.displayDate, TestDates.saturday))
        XCTAssertTrue(LifeCalendar.isSameDay(moved.date, TestDates.friday), "元の日付は変えない")
        XCTAssertNil(viewModel.suggestion, "同じ日に二度は出さない")
        XCTAssertEqual(store.suggestionDecisions.map(\.choice), [.accepted])
        XCTAssertEqual(viewModel.feedback?.message, "「筋トレ」を10/3（土）へ移しました。今日に少し余裕ができます")
        XCTAssertNotNil(viewModel.feedback?.undo)

        viewModel.performUndo()
        XCTAssertNil(store.items.first { $0.id == suggestion.itemID }?.deferredTo)
        XCTAssertTrue(store.suggestionDecisions.isEmpty)
        XCTAssertNotNil(viewModel.suggestion)
    }

    func testKeepChangesNothing() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let suggestion = try XCTUnwrap(viewModel.suggestion)

        viewModel.keepSuggestion(suggestion)
        XCTAssertNil(store.items.first { $0.id == suggestion.itemID }?.deferredTo)
        XCTAssertNil(viewModel.suggestion)
        XCTAssertEqual(store.suggestionDecisions.map(\.choice), [.kept])

        viewModel.performUndo()
        XCTAssertNotNil(viewModel.suggestion)
    }

    /// 「自分」だけなら4件で多くない。余力が少なければ提案する
    func testLowEnergyLowersThreshold() throws {
        let state = AppState()
        state.scope = .mine
        let viewModel = TodayViewModel(store: makeStore(), appState: state, now: TestDates.friday)
        XCTAssertNil(viewModel.suggestion)

        viewModel.selectEnergy(.low)
        let suggestion = try XCTUnwrap(viewModel.suggestion)
        XCTAssertEqual(suggestion.itemTitle, "筋トレ")
        XCTAssertTrue(suggestion.message.hasPrefix("今日は余力が少ないため"))
    }

    /// パートナー担当・支払予定・時刻のあるものは動かさない
    func testCandidateSkipsPartnerPaymentAndTimed() {
        let friday = TestDates.friday
        let items = [
            LifeItem(title: "電気代を払う", kind: .payment, ownership: .personal, date: friday, assignee: .me),
            LifeItem(title: "クリーニング受取", kind: .chore, ownership: .shared, date: friday, assignee: .partner),
            LifeItem(title: "美容院", kind: .todo, ownership: .personal,
                     date: TestDates.make(2026, 10, 2, 19, 0), hasTime: true, assignee: .me)
        ]
        XCTAssertNil(LifeSuggestionEngine.candidate(from: items))

        let chore = LifeItem(title: "シーツを洗う", kind: .chore, ownership: .shared, date: friday, assignee: .either)
        let todo = LifeItem(title: "本を返す", kind: .todo, ownership: .personal, date: friday, assignee: .me)
        XCTAssertEqual(LifeSuggestionEngine.candidate(from: items + [todo, chore])?.title, "本を返す",
                       "共有で担当が「どちらでも」の家事は、自分だけでは動かさない")
        let myChore = LifeItem(title: "シーツを洗う", kind: .chore, ownership: .personal, date: friday, assignee: .me)
        XCTAssertEqual(LifeSuggestionEngine.candidate(from: [todo, myChore])?.title, "シーツを洗う", "家事を先に選ぶ")
    }

    /// 前の日に答えた記録は、今日の提案を止めない
    func testYesterdaysDecisionDoesNotBlockToday() {
        let store = makeStore()
        store.recordSuggestion(SuggestionDecision(kind: .lightenDay, subject: "筋トレ",
                                                  decidedAt: TestDates.daysAgo(1, from: TestDates.friday), choice: .kept))
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        XCTAssertNotNil(viewModel.suggestion)
    }
}

final class LifeMemoryRecordTests: XCTestCase {
    private func mockMemory(_ title: String, store: LifeStore) throws -> LifeMemory {
        try XCTUnwrap(store.memories.first { $0.title == title })
    }

    /// 前回・平均周期・誰が対応したか・提案の履歴
    func testMockShampooRecords() throws {
        let shampoo = try mockMemory("シャンプー", store: makeStore())
        let lastDate = try XCTUnwrap(LifeMemoryEvaluator.lastDate(shampoo))
        XCTAssertTrue(LifeCalendar.isSameDay(lastDate, TestDates.daysAgo(49, from: TestDates.friday)))
        XCTAssertEqual(LifeMemoryEvaluator.lastHandler(shampoo), .partner)
        XCTAssertEqual(LifeMemoryEvaluator.averageCycleDays(shampoo), 46)
        XCTAssertEqual(LifeMemoryEvaluator.decisionSummary(shampoo), "提案を2回使いました")
        let next = try XCTUnwrap(LifeMemoryEvaluator.nextExpectedDate(shampoo, now: TestDates.friday))
        XCTAssertTrue(LifeCalendar.isSameDay(next, TestDates.daysAgo(7, from: TestDates.friday)))
    }

    func testMemoryViewLines() throws {
        let store = makeStore()
        let viewModel = LifeMemoryViewModel(store: store, now: TestDates.friday)
        let shampoo = try mockMemory("シャンプー", store: store)
        let lines = viewModel.recordLines(shampoo, profile: MockData.profile)
        XCTAssertEqual(lines.first, "前回 8/14（金）・妻")
        XCTAssertTrue(lines.contains("平均 約6週間ごと"))
        XCTAssertTrue(lines.contains("次の目安 もうその頃です"))
        XCTAssertTrue(lines.contains("提案を2回使いました"))

        let trash = try mockMemory("ゴミ", store: store)
        XCTAssertEqual(viewModel.recordLines(trash, profile: MockData.profile), ["次は 10/2（金）"])
    }

    /// メモリーから追加した項目を完了すると「前回」を記録し、取り消すと記録も消える
    func testCompletingMemoryItemRecordsHistory() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let shampoo = try mockMemory("シャンプー", store: store)
        let historyCount = shampoo.history?.count ?? 0

        viewModel.performMemoryAction(shampoo)
        let added = try XCTUnwrap(store.items.first { $0.memoryID == shampoo.id })
        viewModel.toggle(added)

        let recorded = try mockMemory("シャンプー", store: store)
        XCTAssertEqual(recorded.history?.count, historyCount + 1)
        XCTAssertEqual(LifeMemoryEvaluator.lastHandler(recorded), .me)
        XCTAssertTrue(LifeCalendar.isSameDay(LifeMemoryEvaluator.lastDate(recorded) ?? .distantPast, TestDates.friday))
        var visibleAgain = recorded
        visibleAgain.hiddenUntil = nil
        XCTAssertFalse(LifeMemoryEvaluator.isDue(visibleAgain, now: TestDates.friday), "買えたら周期は今日から")

        viewModel.toggle(added)
        let reverted = try mockMemory("シャンプー", store: store)
        XCTAssertEqual(reverted.history?.count, historyCount)
        XCTAssertTrue(LifeCalendar.isSameDay(LifeMemoryEvaluator.lastDate(reverted) ?? .distantPast,
                                             TestDates.daysAgo(49, from: TestDates.friday)))
    }

    /// 提案を採用／スキップした履歴を残し、「元に戻す」で消える
    func testDecisionsAreRecordedAndUndone() throws {
        let store = makeStore()
        let viewModel = TodayViewModel(store: store, appState: AppState(), now: TestDates.friday)
        let aircon = try mockMemory("エアコンフィルター掃除", store: store)
        let before = aircon.decisions?.count ?? 0

        viewModel.skipMemory(aircon)
        XCTAssertEqual(try mockMemory("エアコンフィルター掃除", store: store).decisions?.last?.choice, .skipped)
        viewModel.performUndo()
        XCTAssertEqual(try mockMemory("エアコンフィルター掃除", store: store).decisions?.count ?? 0, before)

        let shampoo = try mockMemory("シャンプー", store: store)
        viewModel.performMemoryAction(shampoo)
        XCTAssertEqual(try mockMemory("シャンプー", store: store).decisions?.last?.choice, .accepted)
        viewModel.performUndo()
        XCTAssertEqual(try mockMemory("シャンプー", store: store).decisions?.count, shampoo.decisions?.count)
    }

    /// 季節による変化：指定の月だけ周期を変える
    func testSeasonalCycle() {
        let july = TestDates.make(2026, 7, 15, 9, 10)
        let memory = LifeMemory(
            title: "エアコンフィルター掃除",
            rule: .sinceLast(lastDate: TestDates.daysAgo(40, from: july), dueAfterDays: 60),
            action: .addOnSaturday("エアコンフィルター掃除"),
            seasonal: SeasonalCycle(months: [6, 7, 8, 9], dueAfterDays: 30, note: "夏")
        )
        XCTAssertEqual(LifeMemoryEvaluator.effectiveDueAfterDays(memory, now: july), 30)
        XCTAssertTrue(LifeMemoryEvaluator.isDue(memory, now: july))

        let october = TestDates.make(2026, 10, 5, 9, 10)
        var autumn = memory
        autumn.rule = .sinceLast(lastDate: TestDates.daysAgo(40, from: october), dueAfterDays: 60)
        XCTAssertEqual(LifeMemoryEvaluator.effectiveDueAfterDays(autumn, now: october), 60)
        XCTAssertFalse(LifeMemoryEvaluator.isDue(autumn, now: october))
    }

    func testNextExpectedForMonthlyAndWeekdays() throws {
        let rent = LifeMemory(title: "家賃", rule: .monthlyDay(day: 27, noticeDaysBefore: 3), action: .addToTodo("家賃を払う"))
        let rentNext = try XCTUnwrap(LifeMemoryEvaluator.nextExpectedDate(rent, now: TestDates.friday))
        XCTAssertTrue(LifeCalendar.isSameDay(rentNext, TestDates.make(2026, 10, 27)))

        let trash = LifeMemory(title: "ゴミ", rule: .weekdays([3]), action: .notifyOnly)
        let trashNext = try XCTUnwrap(LifeMemoryEvaluator.nextExpectedDate(trash, now: TestDates.friday))
        XCTAssertTrue(LifeCalendar.isSameDay(trashNext, TestDates.make(2026, 10, 6)))
    }

    /// 以前の保存データ（記録・履歴・季節が無い）もそのまま読める
    func testMemoryWithoutNewFieldsRoundTrips() throws {
        let memory = LifeMemory(title: "家賃", rule: .monthlyDay(day: 27, noticeDaysBefore: 3), action: .addToTodo("家賃を払う"))
        let data = try JSONEncoder().encode(memory)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("history"), "無い項目は保存データにも書かない")
        let decoded = try JSONDecoder().decode(LifeMemory.self, from: data)
        XCTAssertEqual(decoded, memory)
        XCTAssertNil(decoded.history)
        XCTAssertNil(LifeMemoryEvaluator.averageCycleDays(decoded))
        XCTAssertNil(LifeMemoryEvaluator.decisionSummary(decoded))
    }

    func testItemWithoutMemoryIDDecodes() throws {
        let json = """
        {"id":"7C0A6D2E-9F0B-4C1A-8E0D-2B1C3D4E5F60","title":"牛乳を買う","kind":"shopping",
         "ownership":"shared","date":0,"hasTime":false,"assignee":"either","isCompleted":false}
        """
        let item = try JSONDecoder().decode(LifeItem.self, from: Data(json.utf8))
        XCTAssertNil(item.memoryID)
    }
}
