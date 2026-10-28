import XCTest
@testable import LifeOS

// 共有の通知（2026-10-28 Build 8）のテスト。docs/SHARED_PUSH_NOTIFICATIONS.md
// 実際の APNs・Firebase・ネットワークは使わない（すべて偽物に差し替える）。

final class FakePushPreferenceStore: SharedPushPreferenceStore {
    var stored: SharedPushPreferences?
    private(set) var saveCount = 0

    func load() -> SharedPushPreferences? { stored }
    func save(_ preferences: SharedPushPreferences) {
        stored = preferences
        saveCount += 1
    }
}

final class FakePushPermission: PushPermissionProviding {
    var current: PushAuthorization = .notDetermined
    /// 許可画面で「許可」を押すか
    var grants = true
    private(set) var requestCount = 0
    private(set) var registerCount = 0

    func authorization() async -> PushAuthorization { current }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        current = grants ? .authorized : .denied
        return grants
    }

    @MainActor
    func registerForRemoteNotifications() {
        registerCount += 1
    }
}

final class FakePushTokens: PushTokenProviding {
    var onTokenRefresh: ((String) -> Void)?
    var token: String?
    private(set) var autoInit = false
    private(set) var apnsToken: Data?
    private(set) var deleteCount = 0

    func setAutoInit(_ enabled: Bool) { autoInit = enabled }
    func setAPNsToken(_ token: Data) { apnsToken = token }

    func currentToken() async throws -> String {
        guard let token else { throw SharedItemsFailure.other }
        return token
    }

    func deleteToken() async {
        deleteCount += 1
        token = nil
    }
}

final class FakeDeviceRegistry: PushDeviceRegistry {
    /// サーバーの端末の文書（端末 ID → 内容）
    private(set) var documents: [String: PushDeviceRecord] = [:]
    private(set) var saveCount = 0
    var failsSave = false
    var failsRemove = false
    /// 削除が返ってこない（通信できない）
    var hangsRemove = false

    func save(deviceID: String, record: PushDeviceRecord) async throws {
        saveCount += 1
        if failsSave { throw SharedItemsFailure.other }
        documents[deviceID] = record
    }

    func remove(deviceID: String) async throws {
        if hangsRemove {
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        if failsRemove { throw SharedItemsFailure.other }
        documents[deviceID] = nil
    }
}

/// テスト用のトークン（その場で作る。ソースにトークンを書かない）
private func randomPushToken() -> String {
    "test" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

final class SharedPushServiceTests: XCTestCase {
    private struct Parts {
        let service: SharedPushService
        let store: FakePushPreferenceStore
        let permission: FakePushPermission
        let tokens: FakePushTokens
        let registry: FakeDeviceRegistry
    }

    private func make(authorization: PushAuthorization = .notDetermined, token: String? = randomPushToken()) -> Parts {
        let store = FakePushPreferenceStore()
        let permission = FakePushPermission()
        permission.current = authorization
        let tokens = FakePushTokens()
        tokens.token = token
        let registry = FakeDeviceRegistry()
        let service = SharedPushService(preferenceStore: store, permission: permission, tokens: tokens, registry: registry)
        service.signOutTimeout = 0.2
        return Parts(service: service, store: store, permission: permission, tokens: tokens, registry: registry)
    }

    /// 初期値はオフ・項目名もオフ。作っただけでは許可を求めない・登録しない（起動時に勝手に求めない）
    @MainActor
    func testDefaultsAreOffAndNothingIsRequested() async {
        let parts = make()
        XCTAssertFalse(parts.service.preferences.receives)
        XCTAssertFalse(parts.service.preferences.showsTitle)
        XCTAssertEqual(parts.service.status, .off)
        XCTAssertFalse(parts.service.canChangeShowsTitle, "通知がオフなら項目名の設定は無効")
        // 起動したとき（サインイン済み・わが家に参加中）も、許可は求めない
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.refreshAuthorization()
        XCTAssertEqual(parts.permission.requestCount, 0)
        XCTAssertEqual(parts.permission.registerCount, 0)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertFalse(parts.tokens.autoInit, "オンにするまでトークンを作らない")
    }

    /// 端末の ID はランダム（UUID）。保存して、次に起動しても同じ
    func testDeviceIDIsRandomAndKept() {
        let store = FakePushPreferenceStore()
        let first = SharedPushService(preferenceStore: store, permission: nil, tokens: nil, registry: nil)
        let id = first.preferences.deviceID
        XCTAssertNotNil(UUID(uuidString: id))
        let second = SharedPushService(preferenceStore: store, permission: nil, tokens: nil, registry: nil)
        XCTAssertEqual(second.preferences.deviceID, id)
        XCTAssertNotEqual(SharedPushPreferences.makeNew().deviceID, SharedPushPreferences.makeNew().deviceID)
    }

    /// オンにしたときだけ許可を求め、許可されたら自分の端末の文書だけに保存する
    @MainActor
    func testTurningOnRequestsPermissionAndRegisters() async throws {
        let parts = make()
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.permission.requestCount, 1)
        XCTAssertEqual(parts.permission.registerCount, 1)
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertTrue(parts.service.preferences.receives)
        XCTAssertTrue(parts.store.stored?.receives == true, "設定を保存")
        let record = try XCTUnwrap(parts.registry.documents[parts.service.preferences.deviceID])
        XCTAssertEqual(record.token, parts.tokens.token)
        XCTAssertFalse(record.showsPreview, "項目名の表示は初期値オフ")
        XCTAssertEqual(parts.registry.documents.count, 1)
        XCTAssertTrue(parts.tokens.autoInit)
    }

    /// 許可画面で拒否：オンにならず、登録しない。「設定を開く」を出す状態
    @MainActor
    func testDeniedPermission() async {
        let parts = make()
        parts.permission.grants = false
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.service.status, .denied)
        XCTAssertEqual(parts.service.authorization, .denied)
        XCTAssertFalse(parts.service.preferences.receives)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertNotNil(parts.service.status.message)

        // すでに iOS の設定で拒否されている：許可画面は出さない（出せない）
        let blocked = make(authorization: .denied)
        await blocked.service.updateContext(isSignedIn: true, isJoined: true)
        await blocked.service.setReceives(true)
        XCTAssertEqual(blocked.permission.requestCount, 0)
        XCTAssertEqual(blocked.service.status, .denied)
    }

    /// すでに許可されている：許可画面を出さずに登録する
    @MainActor
    func testAlreadyAuthorized() async {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.permission.requestCount, 0)
        XCTAssertEqual(parts.service.status, .registered)
    }

    /// サインインしていない・わが家に参加していないときは登録できない（許可も求めない）
    @MainActor
    func testRequiresSignInAndHousehold() async {
        let parts = make()
        await parts.service.updateContext(isSignedIn: false, isJoined: false)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.service.status, .needsSignIn)
        await parts.service.updateContext(isSignedIn: true, isJoined: false)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.service.status, .needsHousehold)
        XCTAssertEqual(parts.permission.requestCount, 0)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertFalse(parts.service.preferences.receives)

        // Firebase に接続していない
        let offline = SharedPushService(preferenceStore: FakePushPreferenceStore(), permission: nil, tokens: nil, registry: nil)
        await offline.setReceives(true)
        XCTAssertEqual(offline.status, .unavailable)
    }

    /// 項目名の表示：オンのときだけ切り替えられ、端末の文書を上書きする
    @MainActor
    func testShowsTitleSetting() async throws {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setShowsTitle(true)
        XCTAssertFalse(parts.service.preferences.showsTitle, "受け取るがオフなら変えない")

        await parts.service.setReceives(true)
        XCTAssertTrue(parts.service.canChangeShowsTitle)
        await parts.service.setShowsTitle(true)
        XCTAssertTrue(try XCTUnwrap(parts.registry.documents[parts.service.preferences.deviceID]).showsPreview)
        XCTAssertEqual(parts.registry.documents.count, 1, "同じ端末の文書を上書きする")
        await parts.service.setShowsTitle(false)
        XCTAssertFalse(try XCTUnwrap(parts.registry.documents[parts.service.preferences.deviceID]).showsPreview)
    }

    /// トークンが新しくなったら、同じ端末の文書を上書きする。条件を満たさないときは書かない
    @MainActor
    func testTokenRefreshOverwrites() async throws {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        let newToken = randomPushToken()
        await parts.service.tokenDidRefresh(newToken)
        XCTAssertTrue(parts.registry.documents.isEmpty, "受け取るがオフなら書かない")

        await parts.service.setReceives(true)
        await parts.service.tokenDidRefresh(newToken)
        XCTAssertEqual(try XCTUnwrap(parts.registry.documents[parts.service.preferences.deviceID]).token, newToken)
        XCTAssertEqual(parts.registry.documents.count, 1)
    }

    /// APNs のトークンが届く前は待ち、届いたら登録する
    @MainActor
    func testWaitsForAPNsToken() async throws {
        let parts = make(authorization: .authorized, token: nil)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.service.status, .registering)
        XCTAssertTrue(parts.registry.documents.isEmpty)

        parts.tokens.token = randomPushToken()
        parts.service.apnsTokenDidArrive(Data([1, 2, 3]))
        try await waitUntil { parts.service.status == .registered }
        XCTAssertEqual(parts.tokens.apnsToken, Data([1, 2, 3]))
        XCTAssertEqual(parts.registry.documents.count, 1)
    }

    /// オフにしたら端末の文書を消し、トークンも無効にする
    @MainActor
    func testTurningOffRemovesDevice() async {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.registry.documents.count, 1)
        await parts.service.setReceives(false)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertEqual(parts.tokens.deleteCount, 1)
        XCTAssertFalse(parts.tokens.autoInit)
        XCTAssertEqual(parts.service.status, .off)
        XCTAssertFalse(parts.service.preferences.receives)
    }

    /// サインアウト：先に端末の文書を消す。消せなくても（通信できない）決まった時間で先へ進む
    @MainActor
    func testSignOutRemovesDeviceSafely() async {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        await parts.service.prepareForSignOut()
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertEqual(parts.service.status, .needsSignIn)

        let stuck = make(authorization: .authorized)
        await stuck.service.updateContext(isSignedIn: true, isJoined: true)
        await stuck.service.setReceives(true)
        stuck.registry.hangsRemove = true
        let started = Date()
        await stuck.service.prepareForSignOut()
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "通信できなくても、サインアウトを止めない")

        let failing = make(authorization: .authorized)
        await failing.service.updateContext(isSignedIn: true, isJoined: true)
        await failing.service.setReceives(true)
        failing.registry.failsRemove = true
        await failing.service.prepareForSignOut()
        XCTAssertEqual(failing.service.status, .needsSignIn, "消せなくてもサインアウトへ進む")
    }

    /// わが家を退出・削除したら端末の文書を消す。設定の「受け取る」は残し、また参加したら登録し直す
    @MainActor
    func testLeavingHouseholdUnregisters() async {
        let parts = make(authorization: .authorized)
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        await parts.service.updateContext(isSignedIn: true, isJoined: false)
        XCTAssertTrue(parts.registry.documents.isEmpty)
        XCTAssertEqual(parts.service.status, .needsHousehold)
        XCTAssertTrue(parts.service.preferences.receives)

        parts.tokens.token = randomPushToken()
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        XCTAssertEqual(parts.service.status, .registered)
        XCTAssertEqual(parts.registry.documents.count, 1)
    }

    /// 登録の通信に失敗：失敗を表示し、設定やほかの機能はそのまま
    @MainActor
    func testRegistrationFailure() async {
        let parts = make(authorization: .authorized)
        parts.registry.failsSave = true
        await parts.service.updateContext(isSignedIn: true, isJoined: true)
        await parts.service.setReceives(true)
        XCTAssertEqual(parts.service.status, .failed)
        XCTAssertNotNil(parts.service.status.message)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("待っても変わらない")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

final class SharedPushRouteTests: XCTestCase {
    /// 通知をタップ：ToDo は「やること」の今日、買い物は「買い物」を開く
    func testRoutes() {
        XCTAssertEqual(SharedPushRoute(userInfo: ["type": "taskAdded", "kind": "todo", "groupID": "g", "itemID": "i"]), .tasks(.today))
        XCTAssertEqual(SharedPushRoute(userInfo: ["type": "taskChanged", "kind": "shopping"]), .tasks(.shopping))
        XCTAssertEqual(SharedPushRoute(userInfo: ["type": "completionChanged", "kind": "todo"]), .tasks(.today))
    }

    /// 共有の通知でないもの（ローカル通知・形の違うもの）は、開く画面を決めない・クラッシュしない
    func testUnknownPayloadsAreIgnored() {
        XCTAssertNil(SharedPushRoute(userInfo: [:]))
        XCTAssertNil(SharedPushRoute(userInfo: ["type": "eventAdded", "kind": "event"]))
        XCTAssertNil(SharedPushRoute(userInfo: ["type": "taskAdded", "kind": "money"]))
        XCTAssertNil(SharedPushRoute(userInfo: ["type": 1, "kind": ["todo"]]))
        XCTAssertNil(SharedPushRoute(userInfo: ["type": "taskAdded"]))
        let router = SharedPushRouter()
        router.open(userInfo: ["aps": ["alert": "x"]])
        XCTAssertNil(router.takePending())
    }

    /// アプリを開いているとき：共有の通知だけバナーを出す（ローカル通知はこれまでどおり出さない）
    func testForegroundPresentation() {
        XCTAssertTrue(SharedPushRouter.showsInForeground(userInfo: ["type": "taskAdded", "kind": "shopping"]))
        XCTAssertFalse(SharedPushRouter.showsInForeground(userInfo: [:]))
    }

    /// タップの行き先は1回だけ受け取る。「やること」が切り替わる。項目は変えない
    func testTapOpensTasksOnceWithoutChangingItems() throws {
        let router = SharedPushRouter()
        router.open(userInfo: ["type": "taskAdded", "kind": "shopping", "itemID": UUID().uuidString])
        XCTAssertEqual(router.takePending(), .tasks(.shopping))
        XCTAssertNil(router.takePending())

        // 対象の項目が無い（削除済み・権限なし）ときも、画面を開くだけ
        let store = LifeStore.empty()
        let before = store.items
        let state = AppState()
        state.pendingTasksSegment = .shopping
        let viewModel = TasksViewModel(store: store, appState: state, now: TestDates.friday)
        XCTAssertEqual(viewModel.requestedSegment, .shopping)
        viewModel.completion = .completed
        viewModel.applyRequestedSegment()
        XCTAssertEqual(viewModel.segment, .shopping)
        XCTAssertEqual(viewModel.completion, .incomplete)
        XCTAssertNil(state.pendingTasksSegment, "1回だけ")
        XCTAssertEqual(store.items, before, "通知から項目を編集・完了・削除しない")
        XCTAssertTrue(viewModel.tasks.isEmpty)
    }
}

/// ソースの確認：起動時に許可を求めない・ログを出さない・決まった場所だけ
final class SharedPushSourceTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
            throw XCTSkip("\(path) を読めない環境のため、確認を省きます")
        }
        return text
    }

    /// 起動時（LifeOSApp・AppDelegate・MainTabView）に通知の許可を求めない
    func testNoPermissionRequestAtLaunch() throws {
        for path in ["LifeOS/App/LifeOSApp.swift", "LifeOS/App/AppDelegate.swift", "LifeOS/App/MainTabView.swift"] {
            let text = try read(path)
            XCTAssertFalse(text.contains("requestAuthorization"), path)
            XCTAssertFalse(text.contains("registerForRemoteNotifications()"), path)
            XCTAssertFalse(text.contains("setReceives("), path)
        }
        // 許可を求めるのは setReceives の中だけ
        let service = try read("LifeOS/Core/Notifications/SharedPushNotifications.swift")
        XCTAssertEqual(service.components(separatedBy: "permission.requestAuthorization()").count - 1, 1)
        // Firebase の設定は、これまでどおり LifeOSApp の init だけ（AppDelegate では設定しない）
        let delegate = try read("LifeOS/App/AppDelegate.swift")
        XCTAssertFalse(delegate.contains("FirebaseApp.configure"))
        XCTAssertFalse(delegate.contains("configureIfPossible"))
    }

    /// トークン・UID・項目名をログに出さない。広告の識別子・端末固有の番号を使わない
    func testNoLoggingOrDeviceIdentifiers() throws {
        let files = [
            "LifeOS/Core/Notifications/SharedPushNotifications.swift",
            "LifeOS/Core/Notifications/SystemPushPermission.swift",
            "LifeOS/Core/Notifications/FirebaseMessagingTokenProvider.swift",
            "LifeOS/Core/Notifications/FirestoreDeviceRegistry.swift",
            "LifeOS/App/AppDelegate.swift",
            "LifeOS/Features/Profile/HouseholdSettingsView.swift",
        ]
        for file in files {
            let text = try read(file)
            for finding in InviteLinkSourceScanner.findings(in: text) {
                XCTFail("\(file) \(finding.line)行目：\(finding.rule)")
            }
            for word in ["identifierForVendor", "advertisingIdentifier", "ASIdentifierManager", "localizedDescription", "FirebaseAnalytics", "Crashlytics"] {
                XCTAssertFalse(text.contains(word), "\(file)：\(word)")
            }
        }
    }

    /// Firebase の製品は Messaging だけを足した（Analytics・Crashlytics などは入れない）。テストのターゲットには入れない
    func testOnlyMessagingProductAdded() throws {
        let project = try read("LifeOS.xcodeproj/project.pbxproj")
        let products = Set(project.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("productName = Firebase") })
        XCTAssertEqual(products, [
            "productName = FirebaseCore;", "productName = FirebaseAuth;", "productName = FirebaseFirestore;",
            "productName = FirebaseAppCheck;", "productName = FirebaseFunctions;", "productName = FirebaseMessaging;",
        ])
        XCTAssertFalse(project.contains("FirebaseAnalytics"))
        XCTAssertFalse(project.contains("FirebaseCrashlytics"))
        // Push Notifications はアプリの entitlements だけ（テストのターゲットは entitlements を持たない：InviteLinkTests で確認）
        XCTAssertFalse(project.contains("UIBackgroundModes"), "裏での通知の処理は使わない（Background Modes は足さない）")
    }
}
