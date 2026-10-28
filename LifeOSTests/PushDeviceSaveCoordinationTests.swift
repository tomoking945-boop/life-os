import XCTest
@testable import LifeOS

// 端末の文書の保存は「常に最大1件」（2026-10-29 Build 10 の追加の修正）のテスト。
// docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md
// Instruments で、通知用の端末の文書の保存（SetMutation・ServerTimestampTransform）が約48万件残っていた。
// 前の偽物は保存がすぐ終わるので、保存の途中に次の呼び出しが入る状態を作れなかった。
// ここでは、保存を好きなところで止めておける偽物を使う。実際の APNs・Firebase・ネットワークは使わない。

/// 保存を止めておける偽物の端末の登録先。`finishNext` を呼ぶまで、保存は返ってこない
/// Firestore と同じく、同じ端末からの書き込みは出した順番どおりに反映する（保存のあとに出した削除が勝つ）
final class PausableDeviceRegistry: PushDeviceRegistry {
    private struct Waiting {
        let deviceID: String
        let record: PushDeviceRecord
        let order: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// サーバーの端末の文書（端末 ID → 内容）
    @MainActor private(set) var documents: [String: PushDeviceRecord] = [:]
    /// 始まった保存の内容（確認用）
    @MainActor private(set) var startedRecords: [PushDeviceRecord] = []
    @MainActor var startedCount: Int { startedRecords.count }
    /// 同時に動いている保存の数と、その最大
    @MainActor private(set) var concurrentCount = 0
    @MainActor private(set) var maxConcurrentCount = 0
    @MainActor private(set) var removeCount = 0
    /// 止まっている保存
    @MainActor private var waiting: [Waiting] = []
    @MainActor var waitingCount: Int { waiting.count }
    /// 書き込みの順番と、端末ごとの最後の削除の順番
    @MainActor private var order = 0
    @MainActor private var lastRemoveOrder: [String: Int] = [:]

    func save(deviceID: String, record: PushDeviceRecord) async throws {
        let succeeds: Bool = await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.begin(deviceID: deviceID, record: record, continuation: continuation)
            }
        }
        if !succeeds { throw SharedItemsFailure.other }
    }

    func remove(deviceID: String) async throws {
        await MainActor.run {
            self.order += 1
            self.lastRemoveOrder[deviceID] = self.order
            self.removeCount += 1
            self.documents[deviceID] = nil
        }
    }

    @MainActor
    private func begin(deviceID: String, record: PushDeviceRecord, continuation: CheckedContinuation<Bool, Never>) {
        order += 1
        startedRecords.append(record)
        concurrentCount += 1
        maxConcurrentCount = max(maxConcurrentCount, concurrentCount)
        waiting.append(Waiting(deviceID: deviceID, record: record, order: order, continuation: continuation))
    }

    /// いちばん古い止まっている保存を終わらせる（成功なら、あとから削除されていなければ文書に書く）
    @MainActor
    func finishNext(succeeds: Bool = true) {
        guard !waiting.isEmpty else { return }
        let item = waiting.removeFirst()
        concurrentCount -= 1
        if succeeds, item.order > (lastRemoveOrder[item.deviceID] ?? 0) {
            documents[item.deviceID] = item.record
        }
        item.continuation.resume(returning: succeeds)
    }
}

/// テスト用のトークン（その場で作る。ソースにトークンを書かない）
private func makeSaveTestToken() -> String {
    "test" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

final class PushDeviceSaveCoordinationTests: XCTestCase {
    private struct Parts {
        let service: SharedPushService
        let permission: FakePushPermission
        let tokens: FakePushTokens
        let registry: PausableDeviceRegistry
        let firstToken: String
    }

    /// 許可済み・サインイン済み・わが家に参加中。トークンはすでに取れる
    @MainActor
    private func make(token: String? = makeSaveTestToken()) async -> Parts {
        let permission = FakePushPermission()
        permission.current = .authorized
        let tokens = FakePushTokens()
        tokens.token = token
        let registry = PausableDeviceRegistry()
        let service = SharedPushService(preferenceStore: FakePushPreferenceStore(), permission: permission, tokens: tokens, registry: registry)
        service.signOutTimeout = 0.2
        await service.updateContext(isSignedIn: true, isJoined: true)
        return Parts(service: service, permission: permission, tokens: tokens, registry: registry, firstToken: token ?? "")
    }

    /// 「受け取る」をオンにして、最初の保存が始まって止まったところまで進める
    @MainActor
    private func startFirstSave(_ parts: Parts) async throws -> Task<Void, Never> {
        let service = parts.service
        let task = Task { @MainActor in await service.setReceives(true) }
        try await waitUntil { parts.registry.waitingCount == 1 }
        XCTAssertEqual(parts.registry.startedCount, 1)
        return task
    }

    // MARK: 1

    /// 最初の保存を終わらせずに、同じトークンで1000回届いても、始まる保存は1件だけ
    @MainActor
    func testSameTokenWhileSavingStartsOnlyOneSave() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(parts.firstToken)
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "保存中に同じ内容が来ても、新しい保存を始めない")
        XCTAssertEqual(parts.service.deviceSaveCount, 1)
        XCTAssertEqual(parts.service.pendingSaveCount, 0, "同じ内容は保留もしない")

        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "終わったあとにも、追加で保存しない")
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.registry.documents[parts.service.preferences.deviceID]?.token, parts.firstToken)
    }

    // MARK: 2

    /// トークンの更新・画面の表示・アプリに戻る・項目名の設定・APNs が入り混じっても、同時に動く保存は最大1件
    @MainActor
    func testConcurrentSavesNeverExceedOne() async throws {
        let parts = await make()
        let service = parts.service
        let first = try await startFirstSave(parts)
        var tasks: [Task<Void, Never>] = []
        var finishes = 0
        for round in 0..<5 {
            for index in 0..<100 {
                let token = makeSaveTestToken()
                tasks.append(Task { @MainActor in
                    switch index % 5 {
                    case 0: await service.updateContext(isSignedIn: true, isJoined: true)
                    case 1: await service.refreshAuthorization()
                    case 2: service.apnsTokenDidArrive(Data([UInt8(index)]))
                    case 3: await service.setShowsTitle(round % 2 == 0)
                    default: await service.tokenDidRefresh(token)
                    }
                })
            }
            // 保存を待っている呼び出しもあるので、ここでは待たずに様子を見る
            try await settle()
            XCTAssertLessThanOrEqual(parts.registry.waitingCount, 1, "止まっている保存はいつも1件まで")
            XCTAssertLessThanOrEqual(parts.service.pendingSaveCount, 1)
            if parts.registry.waitingCount > 0 {
                parts.registry.finishNext()
                finishes += 1
            }
            try await settle()
        }
        // 残りを1件ずつ終わらせる
        for _ in 0..<20 where parts.registry.waitingCount > 0 {
            parts.registry.finishNext()
            finishes += 1
            try await settle()
        }
        for task in tasks { await task.value }
        await first.value
        XCTAssertEqual(parts.registry.waitingCount, 0)
        XCTAssertEqual(parts.registry.maxConcurrentCount, 1, "サーバーに同時に出した保存は最大1件")
        XCTAssertEqual(parts.service.maxConcurrentSaveCount, 1)
        XCTAssertEqual(parts.registry.startedCount, finishes, "始めた保存は、1件ずつ終わらせた数と同じ")
        XCTAssertLessThanOrEqual(parts.registry.startedCount, 10, "500回の呼び出しでも、保存は1回ごとに多くても1件")
    }

    // MARK: 3

    /// 保存中に違うトークンが1000回来ても、保存は最初と最後の2回だけ
    @MainActor
    func testManyDifferentTokensSaveFirstAndLastOnly() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        var last = ""
        for _ in 0..<1000 {
            last = makeSaveTestToken()
            await parts.service.tokenDidRefresh(last)
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "保存中は新しい保存を始めない")
        XCTAssertEqual(parts.service.pendingSaveCount, 1, "最新の1件だけを保留")

        parts.registry.finishNext()
        try await waitUntil { parts.registry.waitingCount == 1 }
        XCTAssertEqual(parts.registry.startedCount, 2)
        XCTAssertEqual(parts.registry.startedRecords.last?.token, last, "2回目は最後に届いたトークン")
        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 2, "最初と最後の2回だけ")
        XCTAssertEqual(parts.registry.documents[parts.service.preferences.deviceID]?.token, last)
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.service.pendingSaveCount, 0)
    }

    // MARK: 4

    /// 保存済みと同じ内容なら、そのあと1000回来ても追加の保存は0回
    @MainActor
    func testSavedRecordIsNotRewritten() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        parts.registry.finishNext()
        await first.value
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.registry.startedCount, 1)

        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(parts.firstToken)
            await parts.service.updateContext(isSignedIn: true, isJoined: true)
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "追加の保存は0回")
        XCTAssertEqual(parts.registry.waitingCount, 0)
    }

    // MARK: 5

    /// 保存中に通知をオフにすると、保存が終わっても「登録済み」に戻らず、端末の文書も残らない
    @MainActor
    func testTurningOffDuringSaveDoesNotRegister() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        let generation = parts.service.contextGeneration
        await parts.service.tokenDidRefresh(makeSaveTestToken())
        XCTAssertEqual(parts.service.pendingSaveCount, 1)

        await parts.service.setReceives(false)
        XCTAssertGreaterThan(parts.service.contextGeneration, generation, "世代が進む")
        XCTAssertEqual(parts.service.pendingSaveCount, 0, "保留していた保存は捨てる")

        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.status, .off, "古い保存が終わっても登録済みに戻らない")
        XCTAssertFalse(parts.service.hasRegistration)
        XCTAssertTrue(parts.registry.documents.isEmpty, "端末の文書を復活させない")
        XCTAssertEqual(parts.registry.startedCount, 1, "保留していた分も保存しない")

        // オフのあいだは、トークンが届いても保存しない
        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(makeSaveTestToken())
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1)
    }

    /// 保存中にわが家から退出（わが家の削除も同じ）すると、結果を使わず、端末の文書も残らない
    @MainActor
    func testLeavingHouseholdDuringSaveDiscardsIt() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        await parts.service.tokenDidRefresh(makeSaveTestToken())

        await parts.service.updateContext(isSignedIn: true, isJoined: false)
        XCTAssertEqual(parts.service.pendingSaveCount, 0)

        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.status, .needsHousehold)
        XCTAssertFalse(parts.service.hasRegistration)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertEqual(parts.registry.startedCount, 1)
    }

    // MARK: 6

    /// 保存中にサインアウトすると、古い保存の結果は使わない
    @MainActor
    func testSignOutDuringSaveIgnoresStaleResult() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        await parts.service.tokenDidRefresh(makeSaveTestToken())

        await parts.service.prepareForSignOut()
        await parts.service.updateContext(isSignedIn: false, isJoined: false)
        XCTAssertEqual(parts.service.pendingSaveCount, 0)

        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.status, .needsSignIn, "サインアウトのあと、登録済みに戻らない")
        XCTAssertFalse(parts.service.hasRegistration)
        XCTAssertTrue(parts.registry.documents.isEmpty, "端末の文書を復活させない")
        XCTAssertEqual(parts.registry.startedCount, 1)
        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(makeSaveTestToken())
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "サインアウトのあとは保存しない")
    }

    /// サインアウトしてすぐにサインインし直した：古い保存が後から終わっても、新しい登録を消さず、同時にも保存しない
    @MainActor
    func testStaleSaveAfterSignInAgainKeepsNewRegistration() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        await parts.service.prepareForSignOut()

        // サインインし直す（新しいトークン）。古い保存はまだ終わっていない
        let newToken = makeSaveTestToken()
        parts.tokens.token = newToken
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "古い保存が終わるまで、新しい保存を同時に始めない")
        XCTAssertNotEqual(parts.service.status, .registered)

        // 古い保存が終わる：結果は使わず、新しい世代の保存を1回だけ行う
        parts.registry.finishNext()
        try await waitUntil { parts.registry.waitingCount == 1 }
        XCTAssertEqual(parts.registry.startedCount, 2)
        XCTAssertEqual(parts.registry.startedRecords.last?.token, newToken)
        XCTAssertNotEqual(parts.service.status, .registered, "古い保存では登録済みにしない")
        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.registry.documents[parts.service.preferences.deviceID]?.token, newToken, "新しい登録は消さない")
        XCTAssertEqual(parts.registry.maxConcurrentCount, 1)
        XCTAssertEqual(parts.registry.startedCount, 2)
    }

    // MARK: 7

    /// 保存に失敗したあと、トークンの更新が大量に来ても、自動のやり直しの嵐にならない
    @MainActor
    func testFailureDoesNotCauseRetryStorm() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        // 保存中に、同じトークン・違うトークンが大量に届く
        for index in 0..<1000 {
            await parts.service.tokenDidRefresh(index % 2 == 0 ? parts.firstToken : makeSaveTestToken())
        }
        parts.registry.finishNext(succeeds: false)
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.status, .failed)
        XCTAssertEqual(parts.registry.startedCount, 1, "失敗したら、保留していた分も保存しない")
        XCTAssertEqual(parts.service.pendingSaveCount, 0)

        // 失敗した内容と同じトークンが何回届いても、自動ではやり直さない
        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(parts.firstToken)
        }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "自動のやり直しをしない")
        XCTAssertEqual(parts.registry.waitingCount, 0)

        // アプリに戻った：1回だけ試す
        let retry = Task { @MainActor in await parts.service.updateContext(isSignedIn: true, isJoined: true) }
        try await waitUntil { parts.registry.waitingCount == 1 }
        XCTAssertEqual(parts.registry.startedCount, 2)
        parts.registry.finishNext(succeeds: false)
        await retry.value
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 2, "1回だけ")
        XCTAssertEqual(parts.permission.registerCount, 1, "APNs への登録は頼み直さない")
    }

    // MARK: 8

    /// APNs のトークンが届いたのと、通知用のトークンの更新が同時に来ても、保存は最大1件
    @MainActor
    func testAPNsCallbackAndTokenRefreshTogetherSaveOnce() async throws {
        let parts = await make(token: nil)
        let token = makeSaveTestToken()
        parts.tokens.tokenAfterAPNs = token
        // APNs のトークンを待つ状態にする
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.registry.startedCount, 0)
        XCTAssertEqual(parts.service.status, .registering)

        let service = parts.service
        service.apnsTokenDidArrive(Data([1, 2, 3]))
        var tasks: [Task<Void, Never>] = []
        for index in 0..<1000 {
            tasks.append(Task { @MainActor in
                if index % 100 == 0 { service.apnsTokenDidArrive(Data([4, 5, 6])) }
                await service.tokenDidRefresh(token)
            })
        }
        try await waitUntil { parts.registry.waitingCount == 1 }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1, "保存は1件だけ")
        XCTAssertEqual(parts.registry.maxConcurrentCount, 1)

        parts.registry.finishNext()
        for task in tasks { await task.value }
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1)
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.permission.registerCount, 1)
    }

    // MARK: 9

    /// 保存中に「項目名を表示する」を切り替え、トークンの更新も来た：最後の設定を、多くても1回だけ追加で保存する
    @MainActor
    func testShowsTitleChangeDuringSaveSavesFinalSettingOnce() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        await parts.service.setShowsTitle(true)
        for _ in 0..<100 {
            await parts.service.tokenDidRefresh(parts.firstToken)
        }
        await parts.service.setShowsTitle(false)
        await parts.service.setShowsTitle(true)
        XCTAssertEqual(parts.registry.startedCount, 1, "保存中は新しい保存を始めない")
        XCTAssertEqual(parts.service.pendingSaveCount, 1)

        parts.registry.finishNext()
        try await waitUntil { parts.registry.waitingCount == 1 }
        XCTAssertEqual(parts.registry.startedRecords.last?.showsPreview, true, "最後の設定")
        XCTAssertEqual(parts.registry.startedRecords.last?.token, parts.firstToken)
        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 2, "追加の保存は1回だけ")
        XCTAssertEqual(parts.registry.documents[parts.service.preferences.deviceID]?.showsPreview, true)
        XCTAssertEqual(parts.service.status, .registered)
    }

    /// 保存中に設定を切り替えて、すぐに元に戻した：保存中の内容と同じなので、追加の保存はしない
    @MainActor
    func testShowsTitleToggledBackDuringSaveAddsNoSave() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        await parts.service.setShowsTitle(true)
        await parts.service.setShowsTitle(false)
        XCTAssertEqual(parts.service.pendingSaveCount, 0)
        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.registry.startedCount, 1)
        XCTAssertEqual(parts.registry.documents[parts.service.preferences.deviceID]?.showsPreview, false)
    }

    // MARK: 10

    /// 保留は配列に積まない（いつも0か1件）
    @MainActor
    func testPendingIsSingleSlot() async throws {
        let parts = await make()
        let first = try await startFirstSave(parts)
        for _ in 0..<1000 {
            await parts.service.tokenDidRefresh(makeSaveTestToken())
            XCTAssertLessThanOrEqual(parts.service.pendingSaveCount, 1)
        }
        await parts.service.setShowsTitle(true)
        XCTAssertLessThanOrEqual(parts.service.pendingSaveCount, 1)
        parts.registry.finishNext()
        try await waitUntil { parts.registry.waitingCount == 1 }
        parts.registry.finishNext()
        await first.value
        try await settle()
        XCTAssertEqual(parts.service.pendingSaveCount, 0)
        XCTAssertEqual(parts.registry.startedCount, 2)
    }

    /// ソースでも、保留が1件の入れ物で、保存の頼みを配列に積んでいないことを確かめる
    func testSourceKeepsSingleSlotWithoutQueue() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: root.appendingPathComponent("LifeOS/Core/Notifications/SharedPushNotifications.swift"), encoding: .utf8) else {
            throw XCTSkip("ソースを読めない環境")
        }
        XCTAssertTrue(text.contains("private var pendingRecord: PushDeviceRecord?"), "保留は1件だけの入れ物")
        XCTAssertTrue(text.contains("private var inFlightRecord: PushDeviceRecord?"))
        XCTAssertFalse(text.contains("[PushDeviceRecord]"), "保存の頼みを配列に積まない")
        XCTAssertFalse(text.contains("Array<PushDeviceRecord>"))
        // registry.save を呼ぶのは1か所だけ（すべての保存が1つの入口を通る）
        XCTAssertEqual(text.components(separatedBy: "registry.save(").count - 1, 1)
    }

    // MARK: - 補助

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
