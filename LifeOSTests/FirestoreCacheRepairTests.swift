import XCTest
@testable import LifeOS

// 端末の中の Firestore の送信待ちの山を1回だけ片付ける（2026-10-31 Build 10。原因5）のテスト。
// docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md
// 本物の Firestore・ネットワークは使わない（手順はすべて偽物）。

/// 偽物の片付けの手順（呼ばれた順番を記録する）
final class FakeCacheRepairSteps: FirestoreCacheRepairSteps {
    var log: [String] = []
    var cached: [CachedSharedItem]? = []
    var disableSucceeds = true
    var terminateSucceeds = true
    var clearSucceeds = true

    func disableNetwork() async -> Bool { log.append("disableNetwork"); return disableSucceeds }
    func readCachedSharedItems() async -> [CachedSharedItem]? { log.append("read"); return cached }
    func enableNetwork() async -> Bool { log.append("enableNetwork"); return true }
    func terminate() async -> Bool { log.append("terminate"); return terminateSucceeds }
    func clearPersistence() async -> Bool { log.append("clear"); return clearSucceeds }
}

final class FirestoreCacheRepairTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FirestoreCacheRepairTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func sharedItem(_ title: String, kind: LifeItemKind = .todo) -> LifeItem {
        LifeItem(title: title, kind: kind, ownership: .shared, date: LifeCalendar.startOfDay(TestDates.friday))
    }

    /// 送信待ちの新規作成・サーバーにある項目への変更・確かめ済み・形が合わないもの
    private func sampleCache() -> (unsent: LifeItem, cache: [CachedSharedItem]) {
        let unsent = sharedItem("まだ届いていない新しいToDo")
        let cache = [
            CachedSharedItem(item: unsent, hasPendingWrites: true, hasServerCreatedAt: false),
            CachedSharedItem(item: sharedItem("サーバーにある項目への変更"), hasPendingWrites: true, hasServerCreatedAt: true),
            CachedSharedItem(item: sharedItem("確かめ済み"), hasPendingWrites: false, hasServerCreatedAt: true),
            CachedSharedItem(item: nil, hasPendingWrites: true, hasServerCreatedAt: false),
        ]
        return (unsent, cache)
    }

    /// 決まった順番で1回だけ片付け、消す前に「まだ届いていない新規作成」だけを残す。2回目は何もしない
    @MainActor
    func testRepairRunsOnceInOrderAndKeepsUnsentCreates() async {
        let steps = FakeCacheRepairSteps()
        let sample = sampleCache()
        steps.cached = sample.cache
        let gate = FirestoreAccessGate()
        var rescued: [LifeItem] = []

        let outcome = await FirestoreLocalCacheRepair.run(steps: steps, defaults: defaults, gate: gate) { items in
            steps.log.append("rescued")
            rescued = items
        }
        XCTAssertEqual(outcome, .repaired(rescued: 1))
        XCTAssertEqual(steps.log, ["disableNetwork", "read", "rescued", "terminate", "clear"], "残す → 止める → 消す の順番")
        XCTAssertEqual(rescued.map(\.id), [sample.unsent.id], "一度もサーバーに届いていない新規作成だけ")
        XCTAssertEqual(defaults.integer(forKey: FirestoreCacheRepairPolicy.defaultsKey), FirestoreCacheRepairPolicy.currentVersion)
        XCTAssertTrue(gate.isOpen, "終わったら Firestore を使える")

        // 次の起動：もう片付けない
        let second = FakeCacheRepairSteps()
        let again = await FirestoreLocalCacheRepair.run(steps: second, defaults: defaults, gate: gate) { _ in XCTFail("2回目は残す処理もしない") }
        XCTAssertEqual(again, .notNeeded)
        XCTAssertTrue(second.log.isEmpty)
        XCTAssertTrue(gate.isOpen)
    }

    /// 端末の中を読めないときは、何も消さない（次の起動でもう一度）
    @MainActor
    func testReadFailureDoesNotClear() async {
        let steps = FakeCacheRepairSteps()
        steps.cached = nil
        let gate = FirestoreAccessGate()
        let outcome = await FirestoreLocalCacheRepair.run(steps: steps, defaults: defaults, gate: gate) { _ in XCTFail("読めないときは残す処理もしない") }
        XCTAssertEqual(outcome, .skippedReadFailed)
        XCTAssertEqual(steps.log, ["disableNetwork", "read", "enableNetwork"])
        XCTAssertFalse(steps.log.contains("clear"))
        XCTAssertTrue(FirestoreCacheRepairPolicy.needsRepair(storedVersion: defaults.integer(forKey: FirestoreCacheRepairPolicy.defaultsKey)), "次の起動でもう一度")
        XCTAssertTrue(gate.isOpen)
    }

    /// 送り直しを止められないときも、何も消さない
    @MainActor
    func testPrepareFailureDoesNotClear() async {
        let steps = FakeCacheRepairSteps()
        steps.disableSucceeds = false
        let gate = FirestoreAccessGate()
        let outcome = await FirestoreLocalCacheRepair.run(steps: steps, defaults: defaults, gate: gate) { _ in XCTFail("止められないときは残す処理もしない") }
        XCTAssertEqual(outcome, .skippedPrepareFailed)
        XCTAssertFalse(steps.log.contains("read"))
        XCTAssertFalse(steps.log.contains("clear"))
        XCTAssertTrue(gate.isOpen)
    }

    /// 消せなかったら次の起動でもう一度。残した項目は2つにならない
    @MainActor
    func testClearFailureRetriesWithoutDuplicates() async {
        let store = LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
        let sample = sampleCache()
        let gate = FirestoreAccessGate()

        let first = FakeCacheRepairSteps()
        first.cached = sample.cache
        first.clearSucceeds = false
        let outcome = await FirestoreLocalCacheRepair.run(steps: first, defaults: defaults, gate: gate) { _ = store.recoverUnsentHouseholdItems($0) }
        XCTAssertEqual(outcome, .clearFailed)
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(store.items.count, 1, "消す前に残してある")

        let second = FakeCacheRepairSteps()
        second.cached = sample.cache
        let retried = await FirestoreLocalCacheRepair.run(steps: second, defaults: defaults, gate: gate) { _ = store.recoverUnsentHouseholdItems($0) }
        XCTAssertEqual(retried, .repaired(rescued: 1))
        XCTAssertEqual(store.items.count, 1, "同じ ID の項目を2つ作らない")
    }

    /// 残した項目は「自分だけ」の ToDo・買い物になり、共有の一覧には入らない
    @MainActor
    func testRescuedItemsBecomePersonal() {
        let store = LifeStore(items: [], expenses: [], lists: [], inbox: [], memories: [], frequentPurchases: [], habits: [])
        let todo = sharedItem("送れていなかったToDo")
        let shopping = sharedItem("送れていなかった買い物", kind: .shopping)
        XCTAssertEqual(store.recoverUnsentHouseholdItems([todo, shopping]), 2)
        XCTAssertEqual(Set(store.items.map(\.id)), [todo.id, shopping.id])
        XCTAssertTrue(store.items.allSatisfy { $0.ownership == .personal })
        XCTAssertTrue(store.householdItems.isEmpty)
        XCTAssertEqual(store.recoverUnsentHouseholdItems([todo]), 0, "2回目は足さない")
        XCTAssertEqual(store.items.count, 2)
    }

    /// 片付けが終わるまで、共有項目・通知の端末の文書の処理は待つ。終わったら頼まれた順に1回ずつ動く
    func testGateHoldsFirestoreWorkUntilOpen() async {
        let gate = FirestoreAccessGate()
        XCTAssertTrue(gate.isOpen, "最初は開いている（テスト・Firebase なし）")
        var ran: [Int] = []
        gate.whenOpen { ran.append(0) }
        XCTAssertEqual(ran, [0])

        gate.close()
        gate.whenOpen { ran.append(1) }
        gate.whenOpen { ran.append(2) }
        XCTAssertEqual(ran, [0], "閉じているあいだは動かさない")
        XCTAssertEqual(gate.waitingCount, 2)

        gate.openGate()
        XCTAssertEqual(ran, [0, 1, 2])
        XCTAssertEqual(gate.waitingCount, 0)
        gate.openGate()
        XCTAssertEqual(ran, [0, 1, 2], "2回開いても2回は動かさない")
        await gate.waitUntilOpen()
    }

    /// 起動時：片付けが要るなら、画面が Firestore を使い始める前に閉じる。終われば開く
    @MainActor
    func testStartClosesGateImmediately() async throws {
        let gate = FirestoreAccessGate()
        let steps = FakeCacheRepairSteps()
        FirestoreLocalCacheRepair.start(steps: steps, defaults: defaults, gate: gate) { _ in }
        XCTAssertFalse(gate.isOpen, "呼んだその場で閉じる")
        await gate.waitUntilOpen()
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(steps.log, ["disableNetwork", "read", "terminate", "clear"])

        // もう片付けてあれば閉じない
        let later = FirestoreAccessGate()
        FirestoreLocalCacheRepair.start(steps: FakeCacheRepairSteps(), defaults: defaults, gate: later) { _ in }
        XCTAssertTrue(later.isOpen)
    }

    /// 片付けはサーバーに書き込まない（読むのは端末の中だけ）。Firestore を使う2か所は片付けを待つ
    func testRepairSourceDoesNotWriteAndAccessIsGated() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                throw XCTSkip("ソースを読めない環境のため、確認を省きます")
            }
            return text
        }
        let repair = try source("LifeOS/Core/Sharing/FirestoreLocalCacheRepair.swift")
        for word in ["setData(", "updateData(", ".delete(", "addDocument(", "batch()", "runTransaction("] {
            XCTAssertFalse(repair.contains(word), word)
        }
        XCTAssertTrue(repair.contains("getDocuments(source: .cache)"), "端末の中だけを読む")
        let backend = try source("LifeOS/Core/Sharing/FirestoreSharedItemsBackend.swift")
        XCTAssertEqual(backend.components(separatedBy: "FirestoreAccessGate.shared").count - 1, 5, "見張り・作成・変更・削除・確認")
        let registry = try source("LifeOS/Core/Notifications/FirestoreDeviceRegistry.swift")
        XCTAssertEqual(registry.components(separatedBy: "FirestoreAccessGate.shared.waitUntilOpen()").count - 1, 2, "保存・削除")
        let app = try source("LifeOS/App/LifeOSApp.swift")
        XCTAssertTrue(app.contains("FirestoreLocalCacheRepair.start"))
    }
}

/// 保存中は、画面の表示・アプリに戻る（updateContext）が何回来ても、登録やトークンの取り直しを始めない（2026-10-31）
final class PushContextWhileSavingTests: XCTestCase {
    @MainActor
    func testContextChangesWhileSavingDoNotRestartRegistration() async throws {
        let permission = FakePushPermission()
        permission.current = .authorized
        let tokens = FakePushTokens()
        tokens.token = "test" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let registry = PausableDeviceRegistry()
        let service = SharedPushService(preferenceStore: FakePushPreferenceStore(), permission: permission, tokens: tokens, registry: registry)
        service.signOutTimeout = 0.2
        await service.updateContext(isSignedIn: true, isJoined: true)

        // 1回目の登録は失敗（状態は「失敗」）
        let first = Task { @MainActor in await service.setReceives(true) }
        try await waitUntil { registry.waitingCount == 1 }
        registry.finishNext(succeeds: false)
        await first.value
        XCTAssertEqual(service.status, .failed)

        // 新しいトークンが届き、その保存が返ってこない
        let newToken = "test" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let refresh = Task { @MainActor in await service.tokenDidRefresh(newToken) }
        try await waitUntil { registry.waitingCount == 1 }
        let registrations = service.registrationStartCount
        let tokenRequests = tokens.tokenRequestCount

        // 画面の表示・アプリに戻る、を100回
        for _ in 0..<100 {
            await service.refreshAuthorization()
            await service.updateContext(isSignedIn: true, isJoined: true)
        }
        XCTAssertEqual(service.registrationStartCount, registrations, "保存中は登録を始め直さない")
        XCTAssertEqual(tokens.tokenRequestCount, tokenRequests, "保存中はトークンを取り直さない")
        XCTAssertEqual(registry.startedCount, 2)
        XCTAssertEqual(registry.maxConcurrentCount, 1)
        registry.finishNext()
        await refresh.value
        try await settle()
        XCTAssertEqual(service.status, .registered)
        XCTAssertEqual(registry.startedCount, 2)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("待っても変わらない")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    private func settle() async throws {
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
