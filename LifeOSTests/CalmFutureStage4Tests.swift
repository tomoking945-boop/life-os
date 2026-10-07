import XCTest
@testable import LifeOS

// Calm Future 第4段階のテスト：見た目の統一で追加した表示用の値（機能は変えていない）
// 日時は 2026/10/2（金）9:10 に固定（TestDates.friday）

final class CalendarPresentationTests: XCTestCase {
    /// その日の項目の種類をカテゴリー色の点で（種類の並び順で最大3つ）
    func testMarkerKindsFollowKindOrder() {
        let viewModel = CalendarViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.markerKinds(on: TestDates.friday), [.event, .todo, .chore])
        XCTAssertEqual(viewModel.markerKinds(on: TestDates.daysAgo(1, from: TestDates.friday)), [.todo])
        XCTAssertEqual(viewModel.markerKinds(on: TestDates.october25), [])
    }

    /// 「共有」に切り替えると、共有の項目の種類だけ
    func testMarkerKindsFollowScope() {
        let state = AppState()
        state.scope = .shared
        let viewModel = CalendarViewModel(store: makeStore(), appState: state, now: TestDates.friday)
        XCTAssertEqual(viewModel.markerKinds(on: TestDates.friday), [.event, .chore, .shopping])
    }

    func testSelectedDayHeadline() {
        let viewModel = CalendarViewModel(store: makeStore(), appState: AppState(), now: TestDates.friday)
        XCTAssertEqual(viewModel.selectedDateHeadline, "10月2日（金）")
        XCTAssertEqual(viewModel.selectedDateEyebrow, "TODAY")
        viewModel.select(TestDates.saturday)
        XCTAssertEqual(viewModel.selectedDateHeadline, "10月3日（土）")
        XCTAssertEqual(viewModel.selectedDateEyebrow, "SELECTED DAY")
    }
}

final class ListsPresentationTests: XCTestCase {
    /// リストの行に、中身を少しだけ見せる
    func testPreviewShowsFirstTwoItems() throws {
        let store = makeStore()
        let viewModel = ListsViewModel(store: store)
        let places = try XCTUnwrap(store.lists.first { $0.title == "行きたい場所" })
        XCTAssertEqual(viewModel.previewText(for: places), "箱根の温泉・近所の新しいカフェ")

        store.addList(title: "読みたい本")
        let empty = try XCTUnwrap(store.lists.first { $0.title == "読みたい本" })
        XCTAssertNil(viewModel.previewText(for: empty))
    }
}
