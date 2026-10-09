import XCTest
@testable import LifeOS

// はじめての設定（2026-10-09）のテスト（docs/ONBOARDING_SPEC.md「自動テスト」の1〜16）
// 保存を使うテストは、実際の利用者データと衝突しないよう、テストごとの一時フォルダに保存する。

final class OnboardingTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOSTests-\(UUID().uuidString)", isDirectory: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDown() {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    // MARK: - 補助

    /// 新しく使い始める人と同じ状態（保存データ無し）から、AppState と LifeStore を読み込む
    private func makeNewUser() -> (AppState, LifeStore) {
        let state = AppState.persistent()
        let store = LifeStore.persistent(startEmptyIfNoSavedData: !state.hasCompletedOnboarding)
        return (state, store)
    }

    private func writeFile(_ name: String, _ json: String) throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: temporaryDirectory.appendingPathComponent(name))
    }

    /// 名前のステップまで進める
    private func advanceToName(_ viewModel: OnboardingViewModel, usage: UsageStyle) {
        viewModel.next()
        viewModel.selectUsage(usage)
        viewModel.next()
    }

    // MARK: - 1. 新しく使い始める人

    func testNewUserHasNotCompletedOnboarding() {
        let (state, store) = makeNewUser()
        XCTAssertFalse(state.hasCompletedOnboarding)
        XCTAssertNil(state.onboardingProgress)
        XCTAssertEqual(state.profile.name, "", "見本の名前を入れない")
        XCTAssertEqual(state.profile.members.count, 1, "見本の「妻」を入れない")
        XCTAssertFalse(state.partnerJoined, "実際の同期は無いので、参加済みにしない")
        // 見本（Mock）データは入らない
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.expenses.isEmpty)
        XCTAssertTrue(store.inbox.isEmpty)
        XCTAssertTrue(store.memories.isEmpty)
        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertTrue(store.frequentPurchases.isEmpty)
        XCTAssertEqual(store.budget.spent, 0)
    }

    // MARK: - 2. 以前のバージョンの設定（完了状態が無い）

    func testLegacySettingsAreTreatedAsCompleted() throws {
        try writeFile("app-settings.json", """
        {"plan":"free",
         "profile":{"name":"池上","groupName":"わが家",
                    "members":[{"id":"7C0A6D2E-9F0B-4C1A-8E0D-2B1C3D4E5F70","name":"池上","isCurrentUser":true}]},
         "notificationSettings":{"todaySchedule":true,"taskReminder":true,"sharedUpdates":false},
         "usageStyle":"solo","partnerJoined":true}
        """)
        let state = AppState.persistent()
        XCTAssertTrue(state.hasCompletedOnboarding)
        XCTAssertEqual(state.profile.name, "池上")
        XCTAssertEqual(state.usageStyle, .solo)
    }

    /// 設定のファイルが無くても、データの保存があれば以前から使っている人
    func testSavedStoreWithoutSettingsIsExistingUser() {
        _ = LifeStore.persistent(startEmptyIfNoSavedData: false)
        XCTAssertTrue(AppState.persistent().hasCompletedOnboarding)
    }

    // MARK: - 3・4. 使い方

    func testSoloSelectionIsSaved() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "池上"
        XCTAssertTrue(viewModel.complete())
        XCTAssertEqual(state.usageStyle, .solo)
        XCTAssertEqual(state.effectiveScope, .all, "一人モードでは共有のフィルターを使わない")
        XCTAssertEqual(AppState.persistent().usageStyle, .solo, "保存されている")
    }

    func testSharedSelectionIsSaved() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .shared)
        XCTAssertTrue(viewModel.asksGroupName)
        viewModel.name = "池上"
        viewModel.groupName = "池上家"
        XCTAssertTrue(viewModel.complete())
        XCTAssertEqual(state.usageStyle, .shared)
        XCTAssertTrue(state.usageStyle.showsScopeFilter)
        XCTAssertEqual(AppState.persistent().usageStyle, .shared)
    }

    // MARK: - 5〜8. 名前・生活グループ名

    func testBlankNameCannotComplete() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "   　"
        XCTAssertFalse(viewModel.canGoNext)
        viewModel.next()
        XCTAssertEqual(viewModel.step, .name, "空白だけでは次へ進めない")
        XCTAssertFalse(viewModel.complete())
        XCTAssertFalse(state.hasCompletedOnboarding)
    }

    func testNameIsTrimmedAndMemberUpdated() throws {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "  池上 "
        viewModel.next()
        XCTAssertTrue(viewModel.complete())
        XCTAssertEqual(state.profile.name, "池上")
        let me = try XCTUnwrap(state.profile.members.first { $0.isCurrentUser })
        XCTAssertEqual(me.name, "池上")
    }

    func testGroupNameIsSavedOnlyForShared() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .shared)
        viewModel.name = "池上"
        viewModel.groupName = " 池上家 "
        XCTAssertTrue(viewModel.complete())
        XCTAssertEqual(state.profile.groupName, "池上家")
        XCTAssertEqual(AppState.persistent().profile.groupName, "池上家")

        // 一人モードでは生活グループ名を聞かず、変えない
        let solo = AppState()
        solo.hasCompletedOnboarding = false
        let soloModel = OnboardingViewModel(appState: solo, store: LifeStore.empty(), now: TestDates.friday)
        advanceToName(soloModel, usage: .solo)
        XCTAssertFalse(soloModel.asksGroupName)
        soloModel.name = "池上"
        soloModel.groupName = "使わない名前"
        XCTAssertTrue(soloModel.complete())
        XCTAssertEqual(solo.profile.groupName, MockData.profile.groupName)
    }

    // MARK: - 9〜12. 最初の習慣

    func testOnlySelectedHabitsAreAddedWithLightSetting() throws {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "池上"
        viewModel.next()
        XCTAssertEqual(viewModel.step, .habits)
        XCTAssertEqual(viewModel.starters.map(\.title), ["水を飲む", "薬を飲む", "ストレッチ", "散歩する", "日記を書く"])

        let starters = Dictionary(uniqueKeysWithValues: viewModel.starters.map { ($0.title, $0) })
        viewModel.toggle(try XCTUnwrap(starters["ストレッチ"]))
        viewModel.toggle(try XCTUnwrap(starters["水を飲む"]))
        viewModel.toggle(try XCTUnwrap(starters["薬を飲む"]))
        viewModel.toggle(try XCTUnwrap(starters["薬を飲む"]))   // 選び直し
        XCTAssertEqual(viewModel.primaryTitle, "生活OSをはじめる")
        viewModel.primaryAction()

        XCTAssertTrue(state.hasCompletedOnboarding)
        XCTAssertEqual(store.habits.map(\.title), ["水を飲む", "ストレッチ"])
        XCTAssertTrue(store.habits.allSatisfy { $0.repeatRule == .daily })
        XCTAssertTrue(store.habits.allSatisfy { $0.isActive(on: TestDates.friday) }, "今日から始まる")
        XCTAssertFalse(store.habits.first?.isActive(on: TestDates.daysAgo(1, from: TestDates.friday)) ?? true)

        // 今日画面に選んだ習慣だけが出る
        let today = TodayViewModel(store: store, appState: state, now: TestDates.friday)
        XCTAssertEqual(today.visibleHabits.map(\.title), ["水を飲む", "ストレッチ"])
    }

    func testLightHabitSettingsFollowSpec() {
        let light = Dictionary(uniqueKeysWithValues: OnboardingStarter.all.map { ($0.title, $0.isLight) })
        XCTAssertEqual(light, ["水を飲む": true, "薬を飲む": false, "ストレッチ": true, "散歩する": true, "日記を書く": false])
    }

    func testSameHabitsDoNotDuplicate() throws {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "池上"
        viewModel.next()
        let water = try XCTUnwrap(viewModel.starters.first { $0.title == "水を飲む" })
        viewModel.toggle(water)
        XCTAssertTrue(viewModel.complete())
        XCTAssertFalse(viewModel.complete(), "二度目は何もしない（連打しても重複しない）")
        XCTAssertEqual(store.habits.filter { $0.title == "水を飲む" }.count, 1)

        // はじめての設定を再表示して、同じ習慣を選んでも重複しない（データは消えない）
        let doneDays = store.habits.first?.doneDays
        state.restartOnboarding()
        XCTAssertFalse(state.hasCompletedOnboarding)
        let again = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        XCTAssertEqual(again.step, .welcome)
        XCTAssertEqual(again.name, "池上", "今の名前が入っている")
        XCTAssertEqual(again.usageStyle, .solo)
        again.next(); again.next(); again.next()
        again.toggle(water)
        XCTAssertTrue(again.complete())
        XCTAssertEqual(store.habits.filter { $0.title == "水を飲む" }.count, 1)
        XCTAssertEqual(store.habits.first?.doneDays, doneDays)
    }

    func testCompletesWithoutChoosingHabits() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .shared)
        viewModel.name = "池上"
        viewModel.next()
        XCTAssertTrue(viewModel.canGoNext, "何も選ばなくても完了できる")
        XCTAssertTrue(viewModel.complete())
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertEqual(state.selectedTab, .today)
        let today = TodayViewModel(store: store, appState: state, now: TestDates.friday)
        XCTAssertTrue(today.hasNoSchedule, "空の今日画面")
        XCTAssertFalse(today.hasHabits)
    }

    // MARK: - 13・14. 途中経過

    func testProgressIsRemovedAfterCompletion() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .solo)
        viewModel.name = "池上"
        XCTAssertNotNil(state.onboardingProgress)
        XCTAssertTrue(viewModel.complete())
        XCTAssertNil(state.onboardingProgress)

        let reloaded = AppState.persistent()
        XCTAssertTrue(reloaded.hasCompletedOnboarding, "再起動しても初回設定は出ない")
        XCTAssertNil(reloaded.onboardingProgress)
    }

    func testProgressIsRestoredAfterRestart() {
        let (state, store) = makeNewUser()
        let viewModel = OnboardingViewModel(appState: state, store: store, now: TestDates.friday)
        advanceToName(viewModel, usage: .shared)
        viewModel.name = "池上"
        viewModel.groupName = "池上家"

        // アプリを終了して再起動した想定
        let reloaded = AppState.persistent()
        XCTAssertFalse(reloaded.hasCompletedOnboarding)
        let resumed = OnboardingViewModel(appState: reloaded, store: LifeStore.persistent(startEmptyIfNoSavedData: true), now: TestDates.friday)
        XCTAssertEqual(resumed.step, .name)
        XCTAssertEqual(resumed.usageStyle, .shared)
        XCTAssertEqual(resumed.name, "池上")
        XCTAssertEqual(resumed.groupName, "池上家")

        resumed.back()
        XCTAssertEqual(resumed.step, .usage, "前のステップに戻れる")
    }

    func testProgressRoundTrips() throws {
        let progress = OnboardingProgress(step: 3, usageStyle: .solo, name: "池上", groupName: "", selectedStarterIDs: ["water", "diary"])
        let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(decoded, progress)
    }

    // MARK: - 15. 以前から使っている人のデータ

    func testExistingSavedDataIsLoadedAsIs() {
        // 以前のバージョンで保存されたデータ（ここでは Mock）を作る
        let saved = LifeStore.persistent(startEmptyIfNoSavedData: false)
        saved.addToInbox("書類を出す", now: TestDates.friday)
        let itemCount = saved.items.count

        // 初回設定が未完了でも、保存があればそのまま読み込む（空にしない）
        let loaded = LifeStore.persistent(startEmptyIfNoSavedData: true)
        XCTAssertEqual(loaded.items.count, itemCount)
        XCTAssertTrue(loaded.inbox.contains { $0.text == "書類を出す" })
        XCTAssertFalse(loaded.habits.isEmpty)
    }

    // MARK: - 16. プレビュー用の Mock データ

    func testPreviewMockDataIsKept() {
        let preview = LifeStore()
        XCTAssertFalse(preview.items.isEmpty)
        XCTAssertFalse(preview.habits.isEmpty)
        XCTAssertFalse(preview.memories.isEmpty)
        XCTAssertTrue(AppState().hasCompletedOnboarding, "プレビューはこれまでどおり今日画面から")
        XCTAssertEqual(AppState().profile, MockData.profile)
    }

    /// 空のデータでも、今日の余力の家事の候補は使える（本人の記録ではないため残す）
    func testEmptyStoreKeepsChoreChoices() {
        let empty = LifeStore.empty()
        XCTAssertFalse(empty.choreTemplates.isEmpty)
        XCTAssertTrue(empty.items.isEmpty)
    }
}
