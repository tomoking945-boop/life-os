import XCTest
@testable import LifeOS

// パートナー共有・通知（2026-10-11）第1段階のテスト：Firebase を使わない部分
// - 個人項目は送らない（アップロードの対象外）
// - Firestore に保存する形への変換（担当の uid・送らない項目）
// - 既存の共有データの移行の対象
// - 招待リンク・通知タップの読み取り
// - Repository の監視・非同期の窓口（後方互換）
// - 「共有の更新」スイッチは本物の参加まで使えない

final class SharedSyncPolicyTests: XCTestCase {
    private func item(_ kind: LifeItemKind, _ ownership: Ownership) -> LifeItem {
        LifeItem(title: "項目", kind: kind, ownership: ownership, date: TestDates.friday)
    }

    func testPersonalItemsAreNeverSyncable() {
        for kind in LifeItemKind.allCases {
            XCTAssertFalse(SharedSyncPolicy.isSyncable(item(kind, .personal)), "\(kind) の個人項目")
            XCTAssertNil(SharedItemRecord(item: item(kind, .personal), myUID: "alice", partnerUID: "bob"))
        }
    }

    func testOnlySharedEventTodoChoreShoppingAreSyncable() {
        XCTAssertEqual(SharedSyncPolicy.syncableKinds, [.event, .todo, .chore, .shopping])
        XCTAssertTrue(SharedSyncPolicy.isSyncable(item(.event, .shared)))
        XCTAssertTrue(SharedSyncPolicy.isSyncable(item(.shopping, .shared)))
        XCTAssertFalse(SharedSyncPolicy.isSyncable(item(.payment, .shared)))
        XCTAssertFalse(SharedSyncPolicy.isSyncable(item(.habit, .shared)))
    }

    /// Mock の1日分のうち、送ってよいのは共有の項目だけ
    func testMockDayUploadsOnlySharedItems() {
        let store = makeStore()
        let syncable = SharedSyncPolicy.syncableItems(store.items)
        XCTAssertEqual(Set(syncable.map(\.title)), ["外食", "牛乳を買う", "クリーニング受取"])
        XCTAssertTrue(syncable.allSatisfy { $0.ownership == .shared })
    }
}

final class SharedItemRecordTests: XCTestCase {
    func testRecordMapsAssigneeAndKeepsPersonalDetailsOnDevice() throws {
        let shared = LifeItem(
            title: "牛乳を買う", kind: .shopping, ownership: .shared, date: TestDates.friday,
            assignee: .partner, softTime: .onTheWayHome, memoryID: UUID()
        )
        let record = try XCTUnwrap(SharedItemRecord(item: shared, myUID: "alice", partnerUID: "bob"))
        XCTAssertEqual(record.kind, "shopping")
        XCTAssertEqual(record.assigneeUID, "bob")
        XCTAssertEqual(record.createdBy, "alice")
        XCTAssertEqual(record.updatedBy, "alice")

        // 送る内容に、柔らかい時間・暮らしメモリー・持ち主の区別は入らない
        let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        for key in ["softTime", "memoryID", "ownership", "onTheWayHome"] {
            XCTAssertFalse(json.contains(key), key)
        }

        XCTAssertEqual(SharedItemRecord(item: LifeItem(title: "a", kind: .todo, ownership: .shared, date: TestDates.friday, assignee: .me),
                                        myUID: "alice", partnerUID: "bob")?.assigneeUID, "alice")
        XCTAssertNil(SharedItemRecord(item: LifeItem(title: "a", kind: .todo, ownership: .shared, date: TestDates.friday, assignee: .either),
                                      myUID: "alice", partnerUID: "bob")?.assigneeUID)
    }

    /// 受け取った項目は、相手の端末では担当の見え方が入れ替わる
    func testReceivedRecordBecomesSharedItemWithSameID() throws {
        let original = LifeItem(title: "歯医者", kind: .event, ownership: .shared,
                                date: TestDates.make(2026, 10, 2, 10, 30), hasTime: true, assignee: .me)
        let record = try XCTUnwrap(SharedItemRecord(item: original, myUID: "alice", partnerUID: "bob"))

        let onBob = try XCTUnwrap(record.makeItem(id: original.id, myUID: "bob"))
        XCTAssertEqual(onBob.id, original.id, "ID は同じ UUID")
        XCTAssertEqual(onBob.ownership, .shared)
        XCTAssertEqual(onBob.assignee, .partner)
        XCTAssertTrue(onBob.hasTime)
        XCTAssertEqual(onBob.date, original.date)

        let onAlice = try XCTUnwrap(record.makeItem(id: original.id, myUID: "alice"))
        XCTAssertEqual(onAlice.assignee, .me)

        var unknown = record
        unknown.kind = "payment"
        XCTAssertNil(unknown.makeItem(id: original.id, myUID: "bob"), "共有できない種類は受け取らない")
    }
}

final class SharedMigrationPlanTests: XCTestCase {
    func testPlanUploadsOnlySharedItemsAndKeepsIDs() {
        let store = makeStore()
        let plan = SharedMigrationPlan.make(items: store.items, isAlreadyMigrated: false)
        XCTAssertEqual(Set(plan.itemsToUpload.map(\.title)), ["外食", "牛乳を買う", "クリーニング受取"])
        XCTAssertEqual(Set(plan.itemsToUpload.map(\.id)), Set(store.items.filter { $0.ownership == .shared }.map(\.id)))
        XCTAssertEqual(plan.personalCount, store.items.filter { $0.ownership == .personal }.count)
        XCTAssertEqual(plan.skippedSharedCount, 0)
    }

    func testAlreadyMigratedOrUploadedItemsAreNotUploadedAgain() throws {
        let store = makeStore()
        XCTAssertTrue(SharedMigrationPlan.make(items: store.items, isAlreadyMigrated: true).isEmpty)

        let milk = try XCTUnwrap(store.items.first { $0.title == "牛乳を買う" })
        let plan = SharedMigrationPlan.make(items: store.items, isAlreadyMigrated: false, uploadedIDs: [milk.id])
        XCTAssertFalse(plan.itemsToUpload.contains { $0.id == milk.id })
        XCTAssertEqual(plan.skippedSharedCount, 1)
    }

    func testDroppedPaymentAndHabitSharedItemsAreSkipped() {
        let items = [
            LifeItem(title: "家賃", kind: .payment, ownership: .shared, date: TestDates.friday),
            LifeItem(title: "水", kind: .habit, ownership: .shared, date: TestDates.friday),
            LifeItem(title: "粗大ゴミ", kind: .chore, ownership: .shared, date: TestDates.friday, droppedAt: TestDates.friday),
            LifeItem(title: "旅行", kind: .event, ownership: .shared, date: TestDates.friday)
        ]
        let plan = SharedMigrationPlan.make(items: items, isAlreadyMigrated: false)
        XCTAssertEqual(plan.itemsToUpload.map(\.title), ["旅行"])
        XCTAssertEqual(plan.skippedSharedCount, 3)
    }
}

final class SharedLinkTests: XCTestCase {
    // 招待リンクのテストは InviteLinkTests.swift（2026-10-21 招待リンクの土台で、ドメインまで確かめるように変更）

    func testNotificationRoute() throws {
        let itemID = UUID()
        let route = try XCTUnwrap(SharedItemRoute(userInfo: ["groupID": "group-a", "itemID": itemID.uuidString, "type": "eventAdded"]))
        XCTAssertEqual(route.groupID, "group-a")
        XCTAssertEqual(route.itemID, itemID)
        XCTAssertEqual(route.type, "eventAdded")

        XCTAssertNil(SharedItemRoute(userInfo: ["groupID": "group-a"]))
        XCTAssertNil(SharedItemRoute(userInfo: ["groupID": "group/../a", "itemID": itemID.uuidString]))
        XCTAssertNil(SharedItemRoute(userInfo: ["groupID": "group-a", "itemID": "not-a-uuid"]))
    }
}

final class RepositoryObservationTests: XCTestCase {
    func testObserveItemsReceivesChangesUntilCancelled() {
        let store = makeStore()
        var received: [[LifeItem]] = []
        let observation = store.observeItems { received.append($0) }
        XCTAssertEqual(received.count, 1, "登録した直後に1回")

        store.add([LifeItem(title: "書類を出す", kind: .todo, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.last?.last?.title, "書類を出す")

        observation.cancel()
        store.add([LifeItem(title: "郵便", kind: .todo, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(received.count, 2, "解除したあとは呼ばれない")
    }

    /// 既存の窓口はそのまま。非同期の窓口は、端末内では同じ処理を呼ぶ
    func testAsyncWritesWorkThroughRepository() async throws {
        let store = makeStore()
        let repository: any LifeItemRepository = store
        let item = LifeItem(title: "母へ電話", kind: .todo, ownership: .personal, date: TestDates.friday)
        try await repository.addAsync([item])
        XCTAssertTrue(store.items.contains { $0.id == item.id })
        try await repository.toggleCompletionAsync(of: item.id)
        XCTAssertEqual(store.items.first { $0.id == item.id }?.isCompleted, true)
        try await repository.rescheduleAsync(item.id, to: TestDates.saturday)
        XCTAssertEqual(store.items.first { $0.id == item.id }?.deferredTo, TestDates.saturday)
    }
}

final class SharedUpdatesSettingTests: XCTestCase {
    /// 本物のメンバー参加が確認できるまで「共有の更新」は使えない（Mock の参加済みでは使えない）
    func testSharedUpdatesNeedVerifiedMembers() {
        let state = AppState()
        state.partnerJoined = true
        XCTAssertFalse(state.canUseSharedUpdates)
        state.verifiedSharedMemberCount = 2
        XCTAssertTrue(state.canUseSharedUpdates)
    }
}
