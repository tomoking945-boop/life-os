import XCTest
@testable import LifeOS

// Build 10（2026-10-28）：使っているうちに重くなる・「今日の流れ」と「やること」が食い違う不具合の再発防止。
// docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md
// 実際の Firestore・APNs・ネットワークは使わない（偽物で、見張り・書き込み・登録の回数を数える）。

private func household(_ groupID: String = "group-a", kinds: [SharedSpaceKind] = [.todo, .shopping]) -> HouseholdSummary {
    HouseholdSummary(name: "わが家", sharedKinds: kinds, isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)], groupID: groupID)
}

private func makeSync() -> (FakeSharedServer, FakeSharedItemsBackend, SharedItemsService, LifeStore) {
    let server = FakeSharedServer()
    let backend = FakeSharedItemsBackend(server: server, uid: "alice")
    let service = SharedItemsService(backend: backend)
    let store = LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
    service.attach(store)
    return (server, backend, service, store)
}

private func todo(_ title: String, on date: Date = TestDates.friday, ownership: Ownership = .personal) -> LifeItem {
    LifeItem(title: title, kind: .todo, ownership: ownership, date: LifeCalendar.startOfDay(date), assignee: .me)
}

final class SharedListenerLifecycleTests: XCTestCase {
    /// 1・14：同じわが家で同期の開始を100回呼んでも（画面の表示・タブの切り替え・わが家の読み直しのたびに呼ばれても）見張りは1つ
    func testSameGroupStartsOneListener() {
        let (_, backend, service, _) = makeSync()
        for _ in 0..<100 {
            service.apply(household: household())
        }
        XCTAssertEqual(backend.listenStartCount, 1)
        XCTAssertEqual(backend.activeListenerCount, 1)
        XCTAssertEqual(service.listenStartCount, 1)
        XCTAssertEqual(service.activeListenerCount, 1)
        // 共有する種類だけが変わっても、見張りは作り直さない
        service.apply(household: household(kinds: [.todo]))
        XCTAssertEqual(backend.listenStartCount, 1)
    }

    /// 2：わが家が変わったら、前の見張りを外してから新しい見張りを始める
    func testGroupChangeRemovesOldListener() {
        let (_, backend, service, _) = makeSync()
        service.apply(household: household("group-a"))
        service.apply(household: household("group-b"))
        XCTAssertEqual(backend.listenStartCount, 2)
        XCTAssertEqual(backend.removedListenerCount, 1)
        XCTAssertEqual(backend.activeListenerCount, 1)
        XCTAssertEqual(backend.listenedGroupIDs, ["group-a", "group-b"])
    }

    /// 3：サインアウト・退出・わが家の削除（どれも「わが家が無い」）で見張りが0になる。何度呼んでも負にならない
    func testLeavingStopsListener() {
        let (_, backend, service, store) = makeSync()
        service.apply(household: household())
        store.add([todo("共有")], destination: .household)
        for _ in 0..<5 {
            service.apply(household: nil)
        }
        XCTAssertEqual(backend.activeListenerCount, 0)
        XCTAssertEqual(service.activeListenerCount, 0)
        XCTAssertEqual(backend.removedListenerCount, 1)
        XCTAssertTrue(store.householdItems.isEmpty, "共有の表示だけを消す")
        // また参加したら1つだけ
        service.apply(household: household())
        XCTAssertEqual(backend.activeListenerCount, 1)
    }

    /// 見張りは長く生きるサービス（SharedItemsService）だけが持つ。画面（View）は持たない
    func testOnlyServiceOwnsListener() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("LifeOS"), includingPropertiesForKeys: nil) else {
            throw XCTSkip("ソースを読めない環境のため、確認を省きます")
        }
        var checked = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            checked += 1
            let name = url.lastPathComponent
            if name != "FirestoreSharedItemsBackend.swift" {
                XCTAssertFalse(text.contains("addSnapshotListener"), name)
            }
            if name != "HouseholdItems.swift" {
                XCTAssertFalse(text.contains("backend.listen("), name)
            }
            // わが家の同期を始めるのは MainTabView の applyHousehold だけ
            if name != "MainTabView.swift" && name != "HouseholdItems.swift" {
                XCTAssertFalse(text.contains("sharedItems.apply(household:"), name)
                XCTAssertFalse(text.contains("push.updateContext("), name)
            }
        }
        try XCTSkipIf(checked == 0, "ソースを読めない環境のため、確認を省きます")
    }
}

final class SharedSnapshotStabilityTests: XCTestCase {
    /// 4・5：同じ一覧を1000回受け取っても、項目数・送信待ちの数が増えず、一覧の入れ替え（画面の描き直し）もしない
    func testRepeatedSnapshotsDoNotGrowOrRedraw() {
        let (server, backend, service, store) = makeSync()
        service.apply(household: household())
        store.add([todo("書類を出す"), LifeItem(title: "洗剤を買う", kind: .shopping, ownership: .personal, date: TestDates.friday)], destination: .household)
        XCTAssertEqual(server.count, 2)
        XCTAssertEqual(store.householdItems.count, 2)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 0)
        let updates = store.householdUpdateCount
        let writes = backend.totalCalls

        for _ in 0..<1000 {
            backend.emitCurrent()
        }
        XCTAssertEqual(store.householdItems.count, 2)
        XCTAssertEqual(store.visibleItems.count, 2)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 0)
        XCTAssertEqual(store.householdUpdateCount, updates, "同じ一覧では入れ替えない")
        // 6：受け取っただけでは、Firestore へ書き込まない
        XCTAssertEqual(backend.totalCalls, writes)
        XCTAssertEqual(backend.listenStartCount, 1)
    }

    /// 6：受け取りだけでは書き込みが起きない（相手の追加・変更を受け取っても、送り返さない）
    func testReceivingNeverWritesBack() {
        let server = FakeSharedServer()
        let alice = FakeSharedItemsBackend(server: server, uid: "alice")
        let bob = FakeSharedItemsBackend(server: server, uid: "bob")
        let aliceService = SharedItemsService(backend: alice)
        let bobService = SharedItemsService(backend: bob)
        let aliceStore = LifeStore.empty()
        let bobStore = LifeStore.empty()
        aliceService.attach(aliceStore)
        bobService.attach(bobStore)
        aliceService.apply(household: household())
        bobService.apply(household: household())

        aliceStore.add([todo("書類を出す")], destination: .household)
        let id = aliceStore.householdItems[0].id
        aliceStore.rename(id, to: "書類を出す（市役所）")
        aliceStore.toggleCompletion(of: id, at: TestDates.friday)
        XCTAssertEqual(bobStore.householdItems.first?.isCompleted, true)
        XCTAssertEqual(bob.totalCalls, 0, "受け取った側は何も書かない")
        XCTAssertEqual(alice.sentCreates.count, 1)
        XCTAssertEqual(alice.sentUpdates.count, 2, "利用者の操作の分だけ")
    }

    /// 7：送信待ちの項目は、空・古い一覧が何度届いても消えず、増えもしない
    func testPendingSurvivesEmptyAndStaleSnapshots() {
        let (_, backend, service, store) = makeSync()
        service.apply(household: household())
        backend.isOnline = false
        store.add([todo("書類を出す")], destination: .household)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 1)
        for _ in 0..<100 {
            backend.emitEmptySnapshot()
            backend.emitCurrent()
        }
        XCTAssertEqual(store.householdItems.count, 1)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 1)
        XCTAssertEqual(store.visibleItems.count, 1)
    }

    /// 8：保存に成功したら、送信待ちから1回だけ除かれる（あとから同じ一覧が届いても戻らない・増えない）
    func testSuccessClearsPendingOnce() {
        let (server, backend, service, store) = makeSync()
        service.apply(household: household())
        backend.isOnline = false
        store.add([todo("書類を出す")], destination: .household)
        backend.goOnline()
        XCTAssertEqual(server.count, 1)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 0)
        store.finishHouseholdCreate(store.householdItems[0].id)
        backend.goOnline()
        XCTAssertEqual(store.pendingHouseholdCreateCount, 0)
        XCTAssertEqual(store.householdItems.count, 1)
        XCTAssertEqual(backend.sentCreates.count, 1, "送り直さない")
    }

    /// 9：保存が断られたら、同じ ID の「自分だけ」の項目が1件だけ残る（共有版は残らない）。何度一覧が届いても同じ
    func testFailureLeavesExactlyOnePersonalCopy() throws {
        let (server, backend, service, store) = makeSync()
        server.memberUIDs = ["owner-only"]
        service.apply(household: household())
        store.add([todo("書類を出す")], destination: .household)
        let kept = try XCTUnwrap(store.items.first)
        for _ in 0..<100 {
            backend.emitEmptySnapshot()
            backend.emitCurrent()
        }
        XCTAssertEqual(store.items.filter { $0.id == kept.id }.count, 1)
        XCTAssertFalse(store.isHouseholdItem(kept.id))
        XCTAssertEqual(store.visibleItems.filter { $0.id == kept.id }.count, 1)
        XCTAssertEqual(store.pendingHouseholdCreateCount, 0)
        XCTAssertNotNil(service.notice)
    }
}

/// 10〜12：「今日の流れ」と「やること」は同じ正本（LifeStore.visibleItems）から絞り、未完了の ToDo が食い違わない
final class TodayTasksConsistencyTests: XCTestCase {
    private let friday = TestDates.friday

    private func makeStore() -> (LifeStore, FakeSharedItemsBackend, SharedItemsService) {
        let (_, backend, service, store) = makeSync()
        service.apply(household: household())
        let thursday = TestDates.daysAgo(1, from: friday)
        store.add([
            todo("今日の個人ToDo"),
            todo("昨日の残り", on: thursday),
            todo("以前の端末の共有", ownership: .shared),
            LifeItem(title: "完了した今日のToDo", kind: .todo, ownership: .personal, date: LifeCalendar.startOfDay(friday), isCompleted: true),
            LifeItem(title: "明日にあとで", kind: .todo, ownership: .personal, date: LifeCalendar.startOfDay(friday), deferredTo: TestDates.saturday),
            LifeItem(title: "もうやらない", kind: .todo, ownership: .personal, date: LifeCalendar.startOfDay(friday), droppedAt: friday),
        ])
        store.add([todo("今日の共有ToDo")], destination: .household)
        // 送信待ち（オフライン）の共有 ToDo
        backend.isOnline = false
        store.add([todo("送信待ちの共有ToDo")], destination: .household)
        return (store, backend, service)
    }

    private func todayOpenTodoIDs(_ store: LifeStore, scope: ScopeFilter) -> Set<UUID> {
        let state = AppState()
        state.usageStyle = .shared
        state.scope = scope
        let today = TodayViewModel(store: store, appState: state, now: friday)
        let shown = today.focusItems + today.restItems + today.leftovers
        return Set(shown.filter { $0.kind == .todo && !$0.isCompleted }.map(\.id))
    }

    private func tasks(_ store: LifeStore, scope: ScopeFilter, segment: TaskSegment = .today, completion: CompletionFilter = .incomplete) -> [LifeItem] {
        let state = AppState()
        state.usageStyle = .shared
        state.scope = scope
        let viewModel = TasksViewModel(store: store, appState: state, now: friday)
        viewModel.segment = segment
        viewModel.completion = completion
        return viewModel.tasks
    }

    /// 10：今日に出る未完了の ToDo は、やることの「今日」（すべて）にも必ず出る（昨日の残り・共有・送信待ちも）
    func testTodayOpenTodosAppearInTasks() {
        let (store, _, _) = makeStore()
        let todayIDs = todayOpenTodoIDs(store, scope: .all)
        let taskIDs = Set(tasks(store, scope: .all).map(\.id))
        XCTAssertFalse(todayIDs.isEmpty)
        XCTAssertTrue(todayIDs.isSubset(of: taskIDs), "今日にあって、やることに無い ToDo がある")
        let titles = Set(tasks(store, scope: .all).map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["今日の個人ToDo", "昨日の残り", "今日の共有ToDo", "送信待ちの共有ToDo"]))
        // 同じ ID を2回出さない
        let all = tasks(store, scope: .all)
        XCTAssertEqual(all.count, Set(all.map(\.id)).count)
    }

    /// 11：「自分」には個人の ToDo、「共有」には共有の ToDo。両画面で同じ
    func testScopesMatchBetweenScreens() {
        let (store, _, _) = makeStore()
        for scope in ScopeFilter.allCases {
            XCTAssertTrue(todayOpenTodoIDs(store, scope: scope).isSubset(of: Set(tasks(store, scope: scope).map(\.id))), scope.title)
        }
        let mine = Set(tasks(store, scope: .mine).map(\.title))
        XCTAssertTrue(mine.contains("今日の個人ToDo"))
        XCTAssertFalse(mine.contains("今日の共有ToDo"))
        let shared = Set(tasks(store, scope: .shared).map(\.title))
        XCTAssertTrue(shared.isSuperset(of: ["今日の共有ToDo", "送信待ちの共有ToDo"]))
        XCTAssertFalse(shared.contains("今日の個人ToDo"))
    }

    /// 12：完了・あとで・もうやらないの決まりが両画面で矛盾しない
    func testCompletionPostponeAndDropRules() {
        let (store, _, _) = makeStore()
        let todayIDs = todayOpenTodoIDs(store, scope: .all)
        let titleOf = Dictionary(uniqueKeysWithValues: store.visibleItems.map { ($0.id, $0.title) })
        let todayTitles = Set(todayIDs.compactMap { titleOf[$0] })
        // もうやらない：どちらにも出ない
        XCTAssertFalse(todayTitles.contains("もうやらない"))
        XCTAssertFalse(tasks(store, scope: .all).contains { $0.title == "もうやらない" })
        XCTAssertFalse(tasks(store, scope: .all, completion: .completed).contains { $0.title == "もうやらない" })
        // あとで（明日）：今日には出ず、やることの「今後」に出る
        XCTAssertFalse(todayTitles.contains("明日にあとで"))
        XCTAssertFalse(tasks(store, scope: .all).contains { $0.title == "明日にあとで" })
        XCTAssertTrue(tasks(store, scope: .all, segment: .upcoming).contains { $0.title == "明日にあとで" })
        // 完了（今日）：やることの「今日・完了」に出る。未完了には出ない
        XCTAssertTrue(tasks(store, scope: .all, completion: .completed).contains { $0.title == "完了した今日のToDo" })
        XCTAssertFalse(tasks(store, scope: .all).contains { $0.title == "完了した今日のToDo" })
    }

    /// 日付が変わったあと：やることの「今日」も新しい日付になる（以前は作ったときの日付のままで、今日画面とずれた）
    func testTasksTodayFollowsDateChange() {
        let store = LifeStore.empty()
        store.add([todo("土曜のToDo", on: TestDates.saturday)])
        let viewModel = TasksViewModel(store: store, appState: AppState(), now: friday)
        XCTAssertTrue(viewModel.tasks.isEmpty)
        viewModel.refreshNow(TestDates.saturday)
        XCTAssertEqual(viewModel.tasks.map(\.title), ["土曜のToDo"])
    }
}

/// 13：通知の設定の画面を何度開いても（許可の読み直し・わが家の読み直し）、登録・同期が増えない。登録のくり返しも起きない
final class PushRegistrationStabilityTests: XCTestCase {
    @MainActor
    func testRegistrationDoesNotLoopOrMultiply() async throws {
        let store = FakePushPreferenceStore()
        let permission = FakePushPermission()
        permission.current = .authorized
        let tokens = FakePushTokens()
        tokens.token = nil
        tokens.tokenAfterAPNs = "tokenafterapns"
        let registry = FakeDeviceRegistry()
        registry.saveDelayNanoseconds = 50_000_000
        let service = SharedPushService(preferenceStore: store, permission: permission, tokens: tokens, registry: registry)
        // 本物の iOS と同じく、APNs への登録を頼むと、すぐに APNs のトークンが届く
        permission.onRegister = { [weak service] in service?.apnsTokenDidArrive(Data([1, 2, 3])) }

        await service.updateContext(isSignedIn: true, isJoined: true)
        await service.setReceives(true)
        try await settle()
        XCTAssertEqual(service.status, .registered)

        // 画面を開く・アプリに戻る・わが家を読み直す、を100回
        for _ in 0..<100 {
            await service.refreshAuthorization()
            await service.updateContext(isSignedIn: true, isJoined: true)
        }
        try await settle()
        XCTAssertEqual(permission.registerCount, 1, "APNs への登録は1回だけ")
        XCTAssertEqual(service.apnsRequestCount, 1)
        XCTAssertEqual(registry.saveCount, 1, "端末の文書の保存は1回だけ")
        XCTAssertEqual(service.deviceSaveCount, 1)
        XCTAssertLessThanOrEqual(service.registrationStartCount, 2, "トークン待ちのあとの1回まで")
        XCTAssertEqual(registry.documents.count, 1)

        // 同じトークンが何度届いても書き直さない
        for _ in 0..<50 {
            await service.tokenDidRefresh("tokenafterapns")
        }
        XCTAssertEqual(registry.saveCount, 1)
    }

    /// 保存に失敗しても、自動でくり返さない（次にアプリに戻ったときに1回だけ試す）
    @MainActor
    func testFailedSaveDoesNotRetryInLoop() async throws {
        let permission = FakePushPermission()
        permission.current = .authorized
        let tokens = FakePushTokens()
        tokens.tokenAfterAPNs = "tokenafterapns"
        let registry = FakeDeviceRegistry()
        registry.failsSave = true
        let service = SharedPushService(preferenceStore: FakePushPreferenceStore(), permission: permission, tokens: tokens, registry: registry)
        permission.onRegister = { [weak service] in service?.apnsTokenDidArrive(Data([9])) }
        await service.updateContext(isSignedIn: true, isJoined: true)
        await service.setReceives(true)
        try await settle()
        XCTAssertEqual(service.status, .failed)
        let saves = registry.saveCount
        XCTAssertLessThanOrEqual(saves, 1)
        try await settle()
        XCTAssertEqual(registry.saveCount, saves, "失敗のあと、勝手にくり返さない")
        XCTAssertEqual(permission.registerCount, 1)
        // アプリに戻った：1回だけ試す
        await service.updateContext(isSignedIn: true, isJoined: true)
        XCTAssertEqual(registry.saveCount, saves + 1)
        XCTAssertEqual(permission.registerCount, 1, "APNs への登録は頼み直さない")
    }

    /// 通知の登録の処理から、共有項目の同期（見張り）を始めない
    func testPushDoesNotTouchSharedSync() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: root.appendingPathComponent("LifeOS/Core/Notifications/SharedPushNotifications.swift"), encoding: .utf8) else {
            throw XCTSkip("ソースを読めない環境のため、確認を省きます")
        }
        for word in ["SharedItemsService", "apply(household:", "listen(", "LifeStore"] {
            XCTAssertFalse(text.contains(word), word)
        }
        // APNs への登録を頼むのは register() の中の1か所だけ
        XCTAssertEqual(text.components(separatedBy: "permission.registerForRemoteNotifications()").count - 1, 1)
    }

    private func settle() async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
