import XCTest
@testable import LifeOS

// 「入力をもっと賢く」（2026-10-07）のテスト：時刻の読み取り / いつごろの選択 / Inbox の修正内容の保存
// 日時は 2026/10/2（金）9:10 に固定（TestDates.friday）

final class TimeReaderTests: XCTestCase {
    func testReadsColonAndJapaneseStyles() throws {
        let colon = try XCTUnwrap(TimeReader.read("10:30 歯医者"))
        XCTAssertEqual(colon.time, ClockTime(hour: 10, minute: 30))
        XCTAssertEqual(colon.remainingText, "歯医者")
        XCTAssertEqual(colon.clue, "10:30")

        let particle = try XCTUnwrap(TimeReader.read("19時に美容院"))
        XCTAssertEqual(particle.time, ClockTime(hour: 19, minute: 0))
        XCTAssertEqual(particle.remainingText, "美容院")
        XCTAssertEqual(particle.clue, "19時")

        XCTAssertEqual(TimeReader.read("明日10時半 会議")?.time, ClockTime(hour: 10, minute: 30))
        XCTAssertEqual(TimeReader.read("9時15分 電話")?.time, ClockTime(hour: 9, minute: 15))
        XCTAssertEqual(TimeReader.read("歯医者 10:30")?.remainingText, "歯医者")
        XCTAssertEqual(TimeReader.read("１０：３０ 歯医者")?.time, ClockTime(hour: 10, minute: 30))
    }

    func testMorningAndAfternoon() {
        XCTAssertEqual(TimeReader.read("午後3時 銀行")?.time, ClockTime(hour: 15, minute: 0))
        XCTAssertEqual(TimeReader.read("3時 銀行")?.time, ClockTime(hour: 15, minute: 0), "午前・午後が無い1〜6時は午後")
        XCTAssertEqual(TimeReader.read("午前6時 散歩")?.time, ClockTime(hour: 6, minute: 0))
        XCTAssertEqual(TimeReader.read("7時 起きる")?.time, ClockTime(hour: 7, minute: 0))
    }

    func testDoesNotReadDurationsOrInvalidTimes() {
        XCTAssertNil(TimeReader.read("1時間 ジョギング"))
        XCTAssertNil(TimeReader.read("25時 なにか"))
        XCTAssertNil(TimeReader.read("10:75 なにか"))
        XCTAssertNil(TimeReader.read("ランチ 1200"))
        XCTAssertNil(TimeReader.read("牛乳とティッシュ"))
    }
}

final class TimedUnderstandingTests: XCTestCase {
    func testTimeMakesEvent() throws {
        let suggestion = InboxClassifier.suggest(for: "10:30 歯医者")
        XCTAssertEqual(suggestion.kind, .event)
        XCTAssertEqual(suggestion.title, "歯医者")
        XCTAssertEqual(suggestion.time, ClockTime(hour: 10, minute: 30))
        XCTAssertNil(suggestion.softTime)
        XCTAssertEqual(suggestion.timingText(now: TestDates.friday), "今日 10:30")
        XCTAssertEqual(suggestion.reasonText, "「10:30」を手がかりにしました")

        let item = suggestion.makeItem(today: TestDates.friday)
        XCTAssertTrue(item.hasTime)
        XCTAssertEqual(item.date, TestDates.make(2026, 10, 2, 10, 30))
    }

    func testDayAndTimeTogether() {
        let suggestion = InboxClassifier.suggest(for: "明日10時半 会議")
        XCTAssertEqual(suggestion.title, "会議")
        XCTAssertEqual(suggestion.day, .tomorrow)
        XCTAssertEqual(suggestion.makeItem(today: TestDates.friday).date, TestDates.make(2026, 10, 3, 10, 30))
        XCTAssertEqual(suggestion.timingText(now: TestDates.friday), "明日 10/3（土） 10:30")
    }

    func testKeywordKindStaysWithTime() {
        let suggestion = InboxClassifier.suggest(for: "21時 ゴミ出し")
        XCTAssertEqual(suggestion.kind, .chore)
        XCTAssertEqual(suggestion.time, ClockTime(hour: 21, minute: 0))
    }

    func testOnlyTimeIsKeptAsText() {
        let suggestion = InboxClassifier.suggest(for: "10:30")
        XCTAssertNil(suggestion.time)
        XCTAssertEqual(suggestion.title, "10:30")
    }

    /// これまでの読み取りは変わらない
    func testExistingUnderstandingUnchanged() {
        XCTAssertNil(InboxClassifier.suggest(for: "土曜に母へ電話").time)
        XCTAssertEqual(InboxClassifier.suggest(for: "牛乳とティッシュ").softTime, .onTheWayHome)
        XCTAssertNotNil(LifeInterpreter.understand("ランチ 1200").flatMap { understanding -> Bool? in
            if case .expense(_, _, _) = understanding.outcome { return true }
            return nil
        })
    }

    func testAddAsSuggestedAddsTimedEvent() throws {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        viewModel.inputText = "19時に美容院"
        XCTAssertEqual(viewModel.understandingTiming, "今日 19:00")
        viewModel.addAsSuggested(usageStyle: .shared)

        let added = try XCTUnwrap(store.items.last)
        XCTAssertEqual(added.title, "美容院")
        XCTAssertEqual(added.kind, .event)
        XCTAssertTrue(added.hasTime)
        XCTAssertEqual(added.date, TestDates.make(2026, 10, 2, 19, 0))
    }

    /// 「種類を決めて追加」の予定も時刻を読む
    func testQuickAddEventReadsTime() throws {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        viewModel.inputText = "19時 美容院"
        XCTAssertTrue(viewModel.quickAdd(.event))
        let added = try XCTUnwrap(store.items.last)
        XCTAssertEqual(added.title, "美容院")
        XCTAssertTrue(added.hasTime)
        XCTAssertEqual(added.date, TestDates.make(2026, 10, 2, 19, 0))

        viewModel.inputText = "実家に帰る"
        XCTAssertTrue(viewModel.quickAdd(.event))
        XCTAssertFalse(try XCTUnwrap(store.items.last).hasTime)
    }
}

final class SoftTimeChoiceTests: XCTestCase {
    /// 「詳しく整える」で、いつごろを選べる
    func testRefineCanChooseSoftTime() throws {
        let store = makeStore()
        let viewModel = QuickAddViewModel(store: store, now: TestDates.friday)
        viewModel.inputText = "母へ電話"
        viewModel.refine(usageStyle: .shared)
        let candidate = try XCTUnwrap(viewModel.candidates.first)
        XCTAssertTrue(viewModel.canChooseSoftTime(candidate.item))

        viewModel.setSoftTime(.evening, for: candidate.id)
        XCTAssertEqual(viewModel.detailText(for: try XCTUnwrap(viewModel.candidates.first).item), "ToDo・夜")
        viewModel.addSelected()
        XCTAssertEqual(store.items.last?.softTime, .evening)
    }

    /// 時刻のある項目は時刻を優先し、いつごろは選べない
    func testTimedCandidateCannotChooseSoftTime() throws {
        let viewModel = QuickAddViewModel(store: makeStore(), now: TestDates.friday)
        viewModel.inputText = "10:30 歯医者"
        viewModel.refine(usageStyle: .shared)
        let candidate = try XCTUnwrap(viewModel.candidates.first)
        XCTAssertFalse(viewModel.canChooseSoftTime(candidate.item))
        viewModel.setSoftTime(.evening, for: candidate.id)
        XCTAssertNil(viewModel.candidates.first?.item.softTime)
    }

    func testSoftTimeOptions() {
        XCTAssertEqual(QuickAddViewModel.softTimeOptions.map(QuickAddViewModel.softTimeLabel),
                       ["決めない", "帰宅時", "夜", "余力があれば", "今週中"])
    }

    /// 修正で選んだいつごろは、自動で上書きしない
    func testChosenSoftTimeSurvivesEdit() {
        var suggestion = InboxClassifier.suggest(for: "牛乳を買う")
        suggestion.softTime = .thisWeek
        suggestion.isSoftTimeChosen = true
        suggestion.applyUserEdit()
        XCTAssertEqual(suggestion.softTime, .thisWeek)

        var timed = InboxClassifier.suggest(for: "母へ電話")
        timed.softTime = .evening
        timed.time = ClockTime(hour: 20, minute: 0)
        timed.applyUserEdit()
        XCTAssertNil(timed.softTime, "時刻があれば時刻を優先")
        XCTAssertTrue(timed.makeItem(today: TestDates.friday).hasTime)
    }
}

final class InboxEditPersistenceTests: XCTestCase {
    /// 修正した内容はメモに保存され、画面を開き直しても残る
    func testEditIsSavedOnMemo() throws {
        let store = makeStore()
        let memo = try XCTUnwrap(store.inbox.first { $0.text == "美容院を予約する" })
        var edited = InboxClassifier.suggest(for: memo.text)
        edited.day = .saturday
        InboxViewModel(store: store, now: TestDates.friday).update(memo.id, with: edited)

        XCTAssertNotNil(store.inbox.first { $0.id == memo.id }?.edit)
        let reopened = InboxViewModel(store: store, now: TestDates.friday)
        let current = try XCTUnwrap(reopened.items.first { $0.id == memo.id })
        XCTAssertTrue(reopened.isEdited(current))
        XCTAssertEqual(reopened.suggestion(for: current).day, .saturday)

        // まとめて整理にも引き継ぐ
        let tidyUp = TidyUpViewModel(store: store, now: TestDates.friday)
        XCTAssertEqual(tidyUp.entries.first { $0.id == memo.id }?.suggestion.day, .saturday)
    }

    /// まとめて整理の「修正」もメモに保存する
    func testTidyUpEditIsSaved() throws {
        let store = makeStore()
        let tidyUp = TidyUpViewModel(store: store, now: TestDates.friday)
        let entry = try XCTUnwrap(tidyUp.entries.first)
        var edited = entry.suggestion
        edited.ownership = .shared
        tidyUp.update(entry.id, with: edited)
        tidyUp.skip(entry.id)
        XCTAssertEqual(store.inbox.first { $0.id == entry.id }?.edit?.ownership, .shared)
    }

    /// 以前の保存データ（修正内容が無い）もそのまま読める。修正内容は保存して読み戻せる
    func testInboxItemCompatibilityAndRoundTrip() throws {
        let json = """
        {"id":"7C0A6D2E-9F0B-4C1A-8E0D-2B1C3D4E5F61","text":"明日牛乳買う","createdAt":0}
        """
        let legacy = try JSONDecoder().decode(InboxItem.self, from: Data(json.utf8))
        XCTAssertNil(legacy.edit)

        var edit = InboxClassifier.suggest(for: "10:30 歯医者")
        edit.applyUserEdit()
        let memo = InboxItem(text: "10:30 歯医者", createdAt: TestDates.friday, edit: edit)
        let decoded = try JSONDecoder().decode(InboxItem.self, from: JSONEncoder().encode(memo))
        XCTAssertEqual(decoded.edit, edit)
        XCTAssertEqual(decoded.edit?.time, ClockTime(hour: 10, minute: 30))
    }
}
