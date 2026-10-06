import XCTest
@testable import LifeOS

// Calm Future 第2段階のテスト：LifeOSの理解 / 生活コンソール / Inbox ワークスペース / まとめて整理のサマリー
// 日時は 2026/10/2（金）9:10 に固定

final class UnderstandingTests: XCTestCase {
    func testWeekdayCall() throws {
        let suggestion = InboxClassifier.suggest(for: "土曜に母へ電話")
        XCTAssertEqual(suggestion.kind, .todo)
        XCTAssertEqual(suggestion.day, .saturday)
        XCTAssertEqual(suggestion.title, "母へ電話")
        XCTAssertEqual(suggestion.makeItem(today: TestDates.friday).date, LifeCalendar.startOfDay(TestDates.saturday))
        XCTAssertEqual(suggestion.timingText(now: TestDates.friday), "10/3（土）")
    }

    func testSaturdayOnSaturdayIsToday() {
        XCTAssertEqual(InboxDay.saturday.date(from: TestDates.saturday), LifeCalendar.startOfDay(TestDates.saturday))
        XCTAssertEqual(InboxDay.sunday.date(from: TestDates.saturday), LifeCalendar.startOfDay(TestDates.sunday))
    }

    func testProductListIsShoppingOnTheWayHome() {
        let suggestion = InboxClassifier.suggest(for: "牛乳とティッシュ")
        XCTAssertEqual(suggestion.kind, .shopping)
        XCTAssertEqual(suggestion.softTime, .onTheWayHome)
        XCTAssertEqual(suggestion.categoryText, "買い物・食品／冷蔵")
        XCTAssertEqual(suggestion.timingText(now: TestDates.friday), "帰宅時に表示")

        let split = InboxClassifier.suggestions(for: "牛乳とティッシュ")
        XCTAssertEqual(split.map(\.title), ["牛乳を買う", "ティッシュを買う"])
    }

    func testSentenceWithObjectIsNotShopping() {
        XCTAssertEqual(InboxClassifier.suggest(for: "水を飲む").kind, .todo)
    }

    func testWordsThatOnlyContainProductNamesAreNotShopping() {
        XCTAssertEqual(InboxClassifier.suggest(for: "水曜に会議").kind, .todo)
        XCTAssertEqual(InboxClassifier.suggest(for: "パンフレット").kind, .todo)
        XCTAssertEqual(InboxClassifier.suggest(for: "低脂肪牛乳").kind, .shopping)
    }

    func testCountsAreNotExpenses() {
        XCTAssertNil(LifeInterpreter.expense(in: "1000歩 歩く"))
        XCTAssertNil(LifeInterpreter.expense(in: "2026年 健診"))
        XCTAssertNotNil(LifeInterpreter.expense(in: "日用品 800"))
    }

    func testExistingSummariesAreUnchanged() {
        XCTAssertEqual(InboxClassifier.suggest(for: "明日牛乳買う").summary, "買い物・明日")
        XCTAssertNil(InboxClassifier.suggest(for: "明日牛乳買う").softTime)
        XCTAssertEqual(InboxClassifier.suggest(for: "妻と旅行相談").summary, "共有ToDo・今日")
    }

    func testExpenseUnderstanding() throws {
        let understanding = try XCTUnwrap(LifeInterpreter.understand("ランチ 1200"))
        XCTAssertEqual(understanding.outcome, .expense(title: "ランチ", amount: 1200, category: .diningOut))
        XCTAssertEqual(understanding.headline, "支出・外食")
    }

    func testTimeIsNotExpense() throws {
        let understanding = try XCTUnwrap(LifeInterpreter.understand("歯医者 10:30"))
        if case .expense(_, _, _) = understanding.outcome {
            XCTFail("時刻を金額と読まない")
        }
        XCTAssertNil(LifeInterpreter.understand("   "))
    }
}

final class LifeConsoleTests: XCTestCase {
    func testAddAsSuggestedSplitsProducts() {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        let before = store.items.count
        viewModel.inputText = "牛乳とティッシュ"

        XCTAssertEqual(viewModel.addAsSuggestedTitle, "提案どおり追加（2件）")
        XCTAssertTrue(viewModel.addAsSuggested(usageStyle: .shared))
        XCTAssertEqual(store.items.count, before + 2)
        XCTAssertEqual(store.items.last?.softTime, .onTheWayHome)
        XCTAssertEqual(viewModel.inputText, "")
    }

    func testSoloModeAddsAsPersonal() {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        viewModel.inputText = "妻と旅行相談"
        viewModel.addAsSuggested(usageStyle: .solo)
        XCTAssertEqual(store.items.last?.ownership, .personal)
    }

    func testAddExpense() {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        let before = store.expenses.count
        viewModel.inputText = "ランチ 1200"
        XCTAssertFalse(viewModel.canRefine)
        viewModel.addAsSuggested(usageStyle: .shared)
        XCTAssertEqual(store.expenses.count, before + 1)
        XCTAssertEqual(store.expenses.last?.category, .diningOut)
    }

    func testRefineUsesUnderstandingAndEmptyShowsExample() {
        let viewModel = QuickAddViewModel(store: makeStore(), now: TestDates.friday)
        viewModel.inputText = "牛乳とティッシュ"
        viewModel.refine(usageStyle: .shared)
        XCTAssertEqual(viewModel.candidates.map(\.item.title), ["牛乳を買う", "ティッシュを買う"])

        viewModel.inputText = ""
        viewModel.refine(usageStyle: .shared)
        XCTAssertEqual(viewModel.candidates.count, 3)
        XCTAssertTrue(viewModel.isShowingResults)
    }
}

final class InboxWorkspaceTests: XCTestCase {
    func testAddAsIsAndUndo() throws {
        let store = makeStore()
        let viewModel = InboxViewModel(store: store, now: TestDates.friday)
        let memo = try XCTUnwrap(store.inbox.first { $0.text == "電気代を払う" })
        let itemCount = store.items.count

        viewModel.addAsIs(memo)
        XCTAssertEqual(store.items.count, itemCount + 1)
        XCTAssertFalse(store.inbox.contains { $0.id == memo.id })

        viewModel.performUndo()
        XCTAssertEqual(store.items.count, itemCount)
        XCTAssertTrue(store.inbox.contains { $0.id == memo.id })
    }

    func testPostponeAndUndo() throws {
        let store = makeStore()
        let viewModel = InboxViewModel(store: store, now: TestDates.friday)
        let memo = try XCTUnwrap(store.inbox.first)

        viewModel.postpone(memo)
        XCTAssertEqual(viewModel.readyCount, 3)
        viewModel.performUndo()
        XCTAssertEqual(viewModel.readyCount, 4)
    }

    func testEditChangesReasonAndSoftTime() throws {
        let store = makeStore()
        let viewModel = InboxViewModel(store: store, now: TestDates.friday)
        let memo = try XCTUnwrap(store.inbox.first { $0.text == "明日牛乳買う" })
        var edited = viewModel.suggestion(for: memo)
        edited.day = .today

        viewModel.update(memo.id, with: edited)
        let current = viewModel.suggestion(for: memo)
        XCTAssertTrue(viewModel.isEdited(memo))
        XCTAssertEqual(current.softTime, .onTheWayHome)
        XCTAssertEqual(current.reasonText, "修正した内容で追加します")
    }
}

final class TidyUpSummaryTests: XCTestCase {
    func testSummaryGroupsForMockInbox() {
        let viewModel = TidyUpViewModel(store: makeStore(), now: TestDates.friday)
        XCTAssertTrue(viewModel.isShowingSummary)
        XCTAssertEqual(viewModel.summaryTitle, "4件を整理しました")
        XCTAssertEqual(Set(viewModel.summaryGroups.map(\.title)), ["買い物へ", "家族と共有へ", "支払いへ", "やることへ"])
        XCTAssertEqual(viewModel.summaryGroups.map(\.count).reduce(0, +), 4)
    }

    func testDestinationForTomorrowTodo() {
        let suggestion = InboxSuggestion(title: "書類を出す", kind: .todo, ownership: .personal, day: .tomorrow)
        XCTAssertEqual(TidyUpViewModel.destination(of: suggestion), "明日へ")
    }

    func testApplyAllAndUndo() {
        let store = makeStore()
        let viewModel = TidyUpViewModel(store: store, now: TestDates.friday)
        let itemCount = store.items.count

        viewModel.approveAll()
        XCTAssertEqual(store.items.count, itemCount + 4)
        XCTAssertTrue(store.inbox.isEmpty)
        XCTAssertEqual(viewModel.finishedText, "4件を反映しました")

        viewModel.undoApply()
        XCTAssertEqual(store.items.count, itemCount)
        XCTAssertEqual(store.inbox.count, 4)
        XCTAssertTrue(viewModel.isShowingSummary)
        XCTAssertEqual(viewModel.entries.count, 4)
    }

    func testSoloModeOrganizesAsPersonal() {
        let viewModel = TidyUpViewModel(store: makeStore(), now: TestDates.friday, usageStyle: .solo)
        XCTAssertFalse(viewModel.summaryGroups.contains { $0.title == "家族と共有へ" })
    }

    func testEditsFromInboxCarryOver() throws {
        let store = makeStore()
        let memo = try XCTUnwrap(store.inbox.first { $0.text == "美容院を予約する" })
        var edited = InboxClassifier.suggest(for: memo.text)
        edited.ownership = .shared
        let viewModel = TidyUpViewModel(store: store, now: TestDates.friday, edits: [memo.id: edited])
        XCTAssertEqual(viewModel.entries.first { $0.id == memo.id }?.suggestion.ownership, .shared)
    }
}
