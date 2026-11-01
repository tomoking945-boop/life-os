import ImageIO
import XCTest
@testable import LifeOS

// Build 12（2026-11-01）：新しいアプリアイコン・カレンダーで選んだ日から予定を追加・なんでも追加で1週間より先の予定。
// docs/BUILD_12_CALENDAR_EVENT_AND_ICON.md

private func emptyStore() -> LifeStore {
    LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
}

private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    TestDates.make(year, month, day, hour, minute)
}

/// 2026年11月1日（日）9:00
private let november1 = day(2026, 11, 1, 9, 0)

// MARK: - アプリアイコン

final class Build12AppIconTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 新しいアイコンは 1024×1024・透明部分なし（アルファの無い画像）。Contents.json がその画像を指している
    func testAppIconIs1024OpaqueAndReferenced() throws {
        let iconSet = root.appendingPathComponent("LifeOS/Assets.xcassets/AppIcon.appiconset")
        guard let contents = try? Data(contentsOf: iconSet.appendingPathComponent("Contents.json")) else {
            throw XCTSkip("ソースを読めない環境のため、確認を省きます")
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: contents) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?["filename"] as? String, "kurashi-os-app-icon-house-check-v3.png")
        XCTAssertEqual(images.first?["size"] as? String, "1024x1024")
        XCTAssertEqual(images.first?["idiom"] as? String, "universal")

        let url = iconSet.appendingPathComponent("kurashi-os-app-icon-house-check-v3.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 1024)
        XCTAssertTrue([CGImageAlphaInfo.none, CGImageAlphaInfo.noneSkipLast, CGImageAlphaInfo.noneSkipFirst].contains(image.alphaInfo), "透明部分（アルファ）が無いこと")

        // 以前のアイコン（v2）は消さずに docs に残している
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/app-icon/kurashi-os-app-icon-v2.png").path))
        // アイコンの設定は、アプリの Debug・Release とも AppIcon のまま
        let project = try String(contentsOf: root.appendingPathComponent("LifeOS.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertEqual(project.components(separatedBy: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;").count - 1, 2)
    }
}

// MARK: - カレンダーで選んだ日から予定を追加

final class CalendarAddEventTests: XCTestCase {
    private func makeCalendar(_ store: LifeStore, appState: AppState = AppState()) -> CalendarViewModel {
        CalendarViewModel(store: store, appState: appState, now: november1)
    }

    /// 選んだ日が初期値。終日で保存すると、自分の予定として選んだ日の一覧にすぐ出る
    func testAddAllDayEventFromSelectedDay() throws {
        let store = emptyStore()
        let calendar = makeCalendar(store)
        calendar.select(day(2026, 11, 20))
        calendar.startAddingEvent()
        var draft = try XCTUnwrap(calendar.eventDraft)
        XCTAssertTrue(LifeCalendar.isSameDay(draft.date, day(2026, 11, 20)), "選んだ日が初期値")
        XCTAssertTrue(draft.isAllDay)
        draft.title = "  美容院  "

        XCTAssertTrue(calendar.saveEvent(draft))
        XCTAssertNil(calendar.eventDraft, "保存したらシートを閉じる")
        let item = try XCTUnwrap(calendar.selectedItems.first)
        XCTAssertEqual(calendar.selectedItems.count, 1)
        XCTAssertEqual(item.title, "美容院")
        XCTAssertEqual(item.kind, .event)
        XCTAssertEqual(item.ownership, .personal, "予定の共有はまだしない（自分だけ）")
        XCTAssertFalse(item.hasTime)
        XCTAssertEqual(item.date, day(2026, 11, 20))
        XCTAssertNil(calendar.timeText(for: item), "終日")
        XCTAssertTrue(store.householdItems.isEmpty)
    }

    /// 時刻を指定した予定
    func testAddTimedEvent() throws {
        let store = emptyStore()
        let calendar = makeCalendar(store)
        calendar.select(day(2026, 11, 3))
        calendar.startAddingEvent()
        var draft = try XCTUnwrap(calendar.eventDraft)
        draft.title = "歯医者"
        draft.isAllDay = false
        draft.time = day(2000, 1, 1, 19, 30)

        XCTAssertTrue(calendar.saveEvent(draft))
        let item = try XCTUnwrap(store.items(on: day(2026, 11, 3), scope: .all).first)
        XCTAssertTrue(item.hasTime)
        XCTAssertEqual(item.date, day(2026, 11, 3, 19, 30), "日付は選んだ日、時刻だけを使う")
        XCTAssertEqual(calendar.timeText(for: item), "19:30")
    }

    /// タイトルが空なら保存しない
    func testEmptyTitleIsNotSaved() throws {
        let store = emptyStore()
        let calendar = makeCalendar(store)
        calendar.startAddingEvent()
        var draft = try XCTUnwrap(calendar.eventDraft)
        for title in ["", "   ", "\n"] {
            draft.title = title
            XCTAssertFalse(draft.canSave)
            XCTAssertNil(draft.makeItem())
            XCTAssertFalse(calendar.saveEvent(draft))
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNotNil(calendar.eventDraft, "保存できないときはシートを閉じない")
        calendar.cancelAddingEvent()
        XCTAssertNil(calendar.eventDraft)
    }

    /// 翌月・翌年・うるう日・月末：選んだ日のまま保存し、その日・その月を表示する
    func testFarAndEdgeDates() throws {
        let store = emptyStore()
        let calendar = makeCalendar(store)
        let dates = [
            day(2026, 12, 15),  // 翌月
            day(2027, 11, 1),   // 翌年
            day(2028, 2, 29),   // うるう日
            day(2026, 11, 30),  // 月末（30日）
            day(2027, 1, 31),   // 月末（31日）
            day(2027, 2, 28),   // 2月の月末（うるう年でない）
        ]
        for date in dates {
            calendar.startAddingEvent()
            var draft = try XCTUnwrap(calendar.eventDraft)
            draft.title = "予定"
            draft.date = date
            XCTAssertTrue(calendar.saveEvent(draft))
            XCTAssertTrue(LifeCalendar.isSameDay(calendar.selectedDate, date))
            XCTAssertEqual(calendar.displayedMonth, LifeCalendar.startOfMonth(date), "その月を表示する")
            XCTAssertEqual(calendar.selectedItems.map(\.date), [date])
        }
        XCTAssertEqual(store.items.count, dates.count)
    }

    /// 「共有」だけを表示していても、追加した自分の予定がすぐ見えるように「すべて」に戻す
    func testSharedScopeShowsNewPersonalEvent() throws {
        let store = emptyStore()
        let appState = AppState()
        appState.usageStyle = .shared
        appState.scope = .shared
        let calendar = makeCalendar(store, appState: appState)
        calendar.startAddingEvent()
        var draft = try XCTUnwrap(calendar.eventDraft)
        draft.title = "役所"
        XCTAssertTrue(calendar.saveEvent(draft))
        XCTAssertEqual(appState.scope, .all)
        XCTAssertEqual(calendar.selectedItems.map(\.title), ["役所"])
    }

    /// 保存した予定は「今日」と「カレンダー」で同じ日付に出る
    func testSavedEventAppearsOnSameDayInTodayAndCalendar() throws {
        let store = emptyStore()
        let appState = AppState()
        let calendar = makeCalendar(store, appState: appState)
        calendar.startAddingEvent()
        var draft = try XCTUnwrap(calendar.eventDraft)
        draft.title = "家族の食事会"
        draft.date = day(2026, 12, 24)
        draft.isAllDay = false
        draft.time = day(2026, 1, 1, 18, 0)
        XCTAssertTrue(calendar.saveEvent(draft))

        let today = TodayViewModel(store: store, appState: appState, now: day(2026, 12, 24, 8, 0))
        XCTAssertEqual((today.focusItems + today.restItems).map(\.title), ["家族の食事会"])
        let otherDay = TodayViewModel(store: store, appState: appState, now: day(2026, 12, 23, 8, 0))
        XCTAssertTrue((otherDay.focusItems + otherDay.restItems).isEmpty, "前の日には出ない")

        let freshCalendar = makeCalendar(store, appState: appState)
        freshCalendar.select(day(2026, 12, 24))
        XCTAssertEqual(freshCalendar.selectedItems.map(\.title), ["家族の食事会"])
        XCTAssertEqual(freshCalendar.selectedItems.first?.date, day(2026, 12, 24, 18, 0))
    }
}

// MARK: - 日付の読み取り

final class DateReaderTests: XCTestCase {
    private func read(_ text: String, now: Date = november1) -> DateReader.Match? {
        DateReader.read(text, now: now)
    }

    func testReadsRequestedExamples() throws {
        let christmas = try XCTUnwrap(read("12月25日 19時 美容院"))
        XCTAssertEqual(christmas.date, day(2026, 12, 25))
        XCTAssertEqual(christmas.remainingText, "19時 美容院")
        XCTAssertEqual(christmas.clue, "12月25日")

        let hospital = try XCTUnwrap(read("2027年3月10日 10時 病院"))
        XCTAssertEqual(hospital.date, day(2027, 3, 10))
        XCTAssertEqual(hospital.remainingText, "10時 病院")

        let dentist = try XCTUnwrap(read("来月15日 歯医者"))
        XCTAssertEqual(dentist.date, day(2026, 12, 15))
        XCTAssertEqual(dentist.remainingText, "歯医者")

        XCTAssertEqual(read("１２月２５日に美容院")?.date, day(2026, 12, 25), "全角の数字・「に」も読む")
        XCTAssertNil(read("歯医者 10:30"), "日付が無ければ読まない")
    }

    /// 年が無いとき：今年のその日が過ぎていれば次の年。今日は過ぎていない
    func testYearOmittedRollsOverToNextYear() {
        let december26 = day(2026, 12, 26, 9, 0)
        XCTAssertEqual(read("12月25日 美容院", now: december26)?.date, day(2027, 12, 25))
        XCTAssertEqual(read("1月5日 美容院", now: december26)?.date, day(2027, 1, 5))
        XCTAssertEqual(read("12月26日 美容院", now: december26)?.date, day(2026, 12, 26), "今日は今年")
        XCTAssertEqual(read("11月1日 美容院")?.date, day(2026, 11, 1))
        XCTAssertEqual(read("10月31日 美容院")?.date, day(2027, 10, 31), "昨日は次の年")
        XCTAssertEqual(read("来月15日 歯医者", now: december26)?.date, day(2027, 1, 15), "12月の来月は翌年の1月")
    }

    /// うるう日・月末。存在しない日付は日付を決めず、確かめてもらう
    func testLeapDaysMonthEndsAndInvalidDates() throws {
        XCTAssertEqual(read("2月29日 歯医者", now: day(2027, 11, 1))?.date, day(2028, 2, 29), "次のうるう年")
        XCTAssertEqual(read("2028年2月29日 歯医者")?.date, day(2028, 2, 29))
        XCTAssertEqual(read("1月31日 歯医者")?.date, day(2027, 1, 31))
        XCTAssertEqual(read("来月31日 歯医者")?.date, day(2026, 12, 31))

        for text in ["2月29日 歯医者", "2027年2月29日 歯医者", "4月31日 歯医者", "2月30日 歯医者", "13月5日 歯医者", "12月0日 歯医者"] {
            let match = try XCTUnwrap(read(text), text)
            XCTAssertNil(match.date, "\(text) は存在しない日付（別の日にずらさない）")
            XCTAssertTrue(match.needsConfirmation, text)
            XCTAssertNotNil(match.problem, text)
        }
        let october15 = day(2026, 10, 15, 9, 0)
        XCTAssertNil(read("来月31日 歯医者", now: october15)?.date, "11月は30日まで")
    }
}

// MARK: - なんでも追加で1週間より先の予定

final class QuickAddFutureDateTests: XCTestCase {
    private func viewModel(_ store: LifeStore, now: Date = november1) -> QuickAddViewModel {
        QuickAddViewModel(store: store, now: now)
    }

    /// 例の3つ：予定として、その日（時刻があれば時刻つき）に「自分」で追加する
    func testRequestedExamplesAreAddedAsEvents() throws {
        let cases: [(String, String, Date, Bool)] = [
            ("12月25日 19時 美容院", "美容院", day(2026, 12, 25, 19, 0), true),
            ("2027年3月10日 10時 病院", "病院", day(2027, 3, 10, 10, 0), true),
            ("来月15日 歯医者", "歯医者", day(2026, 12, 15), false),
        ]
        for (text, title, date, hasTime) in cases {
            let store = emptyStore()
            let quickAdd = viewModel(store)
            quickAdd.inputText = text
            XCTAssertEqual(quickAdd.understanding?.headline, "予定", text)
            XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared), text)
            let item = try XCTUnwrap(store.items.first, text)
            XCTAssertEqual(store.items.count, 1, text)
            XCTAssertEqual(item.title, title, text)
            XCTAssertEqual(item.kind, .event, text)
            XCTAssertEqual(item.date, date, text)
            XCTAssertEqual(item.hasTime, hasTime, text)
            XCTAssertEqual(item.ownership, .personal, "自動で共有を選ばない：\(text)")
        }
    }

    /// 8日後・3か月後・翌年（アプリ独自の「1週間先まで」の上限は無い）
    func testEightDaysThreeMonthsAndNextYear() throws {
        let cases: [(String, Date)] = [
            ("11月9日 美容院", day(2026, 11, 9)),
            ("2月1日 歯医者", day(2027, 2, 1)),
            ("2027年11月1日 健診", day(2027, 11, 1)),
        ]
        for (text, date) in cases {
            let store = emptyStore()
            let quickAdd = viewModel(store)
            quickAdd.inputText = text
            XCTAssertTrue(quickAdd.addAsSuggested(usageStyle: .shared), text)
            XCTAssertEqual(store.items.first?.date, date, text)
            XCTAssertEqual(store.items.first?.kind, .event, text)
        }
    }

    /// 存在しない日付は黙って保存しない。確認画面で日付を選ぶと追加できる
    func testInvalidDateIsConfirmedBeforeSaving() throws {
        let store = emptyStore()
        let quickAdd = viewModel(store)
        quickAdd.inputText = "2月30日 歯医者"
        XCTAssertTrue(quickAdd.understandingTiming?.hasPrefix("日付を確認") == true)

        XCTAssertFalse(quickAdd.addAsSuggested(usageStyle: .shared), "そのまま保存しない")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(quickAdd.isShowingResults, "確認画面を開く")
        let candidate = try XCTUnwrap(quickAdd.candidates.first)
        XCTAssertNotNil(candidate.dateNote)
        XCTAssertTrue(quickAdd.canChooseDate(candidate))
        XCTAssertFalse(quickAdd.canAdd, "日付を選ぶまで追加できない")

        quickAdd.setDate(day(2027, 3, 1), for: candidate.id)
        XCTAssertTrue(quickAdd.canAdd)
        quickAdd.addSelected()
        XCTAssertEqual(store.items.map(\.date), [day(2027, 3, 1)])
        XCTAssertEqual(store.items.first?.title, "歯医者")
    }

    /// 「種類を決めて追加」の予定も日付を読む。存在しない日付なら保存せず知らせる
    func testQuickAddEventTypeReadsDates() {
        let store = emptyStore()
        let quickAdd = viewModel(store)
        quickAdd.inputText = "12月25日 19時 美容院"
        XCTAssertTrue(quickAdd.quickAdd(.event))
        XCTAssertEqual(store.items.first?.date, day(2026, 12, 25, 19, 0))
        XCTAssertEqual(store.items.first?.title, "美容院")

        quickAdd.inputText = "4月31日 美容院"
        XCTAssertFalse(quickAdd.quickAdd(.event))
        XCTAssertTrue(quickAdd.isShowingDateNotice)
        XCTAssertEqual(store.items.count, 1, "保存しない")
        XCTAssertEqual(quickAdd.inputText, "4月31日 美容院", "入力は消さない（直せるように）")

        quickAdd.inputText = "19時 美容院"
        XCTAssertTrue(quickAdd.quickAdd(.event))
        XCTAssertEqual(store.items.last?.date, day(2026, 11, 1, 19, 0), "日付が無ければ今日（これまでどおり）")
    }

    /// 「詳しく整える」の日付：遠い先（2030年）も選べ、時刻はそのまま
    func testRefineDatePickerHasNoUpperLimit() throws {
        let store = emptyStore()
        let quickAdd = viewModel(store)
        quickAdd.inputText = "歯医者 10:30"
        quickAdd.refine(usageStyle: .shared)
        let candidate = try XCTUnwrap(quickAdd.candidates.first)
        XCTAssertEqual(candidate.item.kind, .event)
        XCTAssertTrue(quickAdd.canChooseDate(candidate))

        quickAdd.setDate(day(2030, 6, 15), for: candidate.id)
        XCTAssertEqual(quickAdd.candidates.first?.item.date, day(2030, 6, 15, 10, 30))
        XCTAssertEqual(quickAdd.detailText(for: try XCTUnwrap(quickAdd.candidates.first?.item)), "予定・2030/6/15（土）")
        XCTAssertEqual(quickAdd.destination, .personal, "保存先の初期値は自分")
        quickAdd.addSelected()
        XCTAssertEqual(store.items.map(\.date), [day(2030, 6, 15, 10, 30)])
        XCTAssertEqual(store.items.first?.ownership, .personal)
    }

    /// ToDo・買い物・支出・家事の分類は、日付を読むようになっても変わらない。自動で共有を選ばない
    func testExistingCategoriesAreUnchanged() {
        for text in ["牛乳とティッシュ", "ランチ 1200", "書類を出す", "明日 掃除", "土曜に母へ電話", "歯医者 10:30", "妻と旅行相談", "1000歩 歩く"] {
            XCTAssertEqual(LifeInterpreter.understand(text, now: november1), LifeInterpreter.understand(text), text)
        }
        XCTAssertTrue(LifeInterpreter.understand("12月25日 プレゼントを買う", now: november1)?.headline.hasPrefix("買い物") == true)
        XCTAssertEqual(LifeInterpreter.understand("12月25日 ゴミ出し", now: november1)?.headline, "家事")
        XCTAssertEqual(InboxClassifier.suggest(for: "12月25日 妻と美容院", now: november1).ownership, .personal)
    }

    /// おまかせ Inbox は日付を読まない（これまでどおり）。前の保存データ（日付の項目なし）も読める
    func testInboxUnchangedAndOldSuggestionsDecode() throws {
        XCTAssertNil(InboxClassifier.suggest(for: "12月25日 美容院").specificDate)

        let old = #"{"title":"歯医者","kind":"event","ownership":"personal","day":"tomorrow","clues":[],"isEditedByUser":false,"isSoftTimeChosen":false}"#
        let decoded = try JSONDecoder().decode(InboxSuggestion.self, from: Data(old.utf8))
        XCTAssertNil(decoded.specificDate)
        XCTAssertNil(decoded.dateProblem)
        XCTAssertEqual(decoded.makeItem(today: november1).date, day(2026, 11, 2))

        var suggestion = InboxClassifier.suggest(for: "12月25日 19時 美容院", now: november1)
        suggestion.applyUserEdit()
        let roundTrip = try JSONDecoder().decode(InboxSuggestion.self, from: JSONEncoder().encode(suggestion))
        XCTAssertEqual(roundTrip, suggestion)
        XCTAssertEqual(roundTrip.makeItem(today: november1).date, day(2026, 12, 25, 19, 0))
    }
}
