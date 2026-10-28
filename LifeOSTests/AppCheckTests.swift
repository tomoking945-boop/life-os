import XCTest
@testable import LifeOS

// Firebase App Check の基礎（2026-10-20）のテスト
// 実際のネットワーク・Firebase には接続しない（起動の手順を偽物に差し替えて、順番を確かめる）。

/// 起動の手順の偽物（呼ばれた順番を記録する）
final class FakeFirebaseStartupSteps: FirebaseStartupSteps {
    var isAlreadyConfigured = false
    var hasFile = true
    var optionsAreValid = true
    var configureSucceeds = true
    private(set) var calls: [String] = []

    func hasConfigurationFile(in bundle: Bundle) -> Bool {
        calls.append("hasConfigurationFile")
        return hasFile
    }

    func loadValidOptions(from bundle: Bundle) -> Bool {
        calls.append("loadValidOptions")
        return optionsAreValid
    }

    func installAppCheckProviderFactory(_ kind: AppCheckProviderKind) {
        calls.append("installAppCheck(\(kind == .debug ? "debug" : "appAttest"))")
    }

    func configure() -> Bool {
        calls.append("configure")
        return configureSucceeds
    }
}

final class AppCheckBootstrapTests: XCTestCase {
    private func run(_ steps: FakeFirebaseStartupSteps, isDebugBuild: Bool = false, isRunningTests: Bool = false) -> FirebaseBootstrap.Result {
        FirebaseBootstrap.run(steps: steps, bundle: .main, isRunningTests: isRunningTests, isDebugBuild: isDebugBuild)
    }

    /// App Check の Provider Factory は、Firebase の設定（configure）より前に設定される
    func testProviderFactoryIsInstalledBeforeConfigure() {
        let steps = FakeFirebaseStartupSteps()
        XCTAssertEqual(run(steps), .configured)
        XCTAssertEqual(steps.calls, ["hasConfigurationFile", "loadValidOptions", "installAppCheck(appAttest)", "configure"])
        let install = steps.calls.firstIndex { $0.hasPrefix("installAppCheck") }
        let configure = steps.calls.firstIndex(of: "configure")
        XCTAssertNotNil(install)
        XCTAssertNotNil(configure)
        if let install, let configure {
            XCTAssertLessThan(install, configure)
        }
    }

    /// Debug ビルドは Debug Provider
    func testDebugBuildUsesDebugProvider() {
        XCTAssertEqual(AppCheckProviderPolicy.kind(isDebugBuild: true), .debug)
        let steps = FakeFirebaseStartupSteps()
        _ = run(steps, isDebugBuild: true)
        XCTAssertTrue(steps.calls.contains("installAppCheck(debug)"))
        XCTAssertFalse(steps.calls.contains("installAppCheck(appAttest)"))
    }

    /// Release ビルド（TestFlight・実機）は App Attest
    func testReleaseBuildUsesAppAttest() {
        XCTAssertEqual(AppCheckProviderPolicy.kind(isDebugBuild: false), .appAttest)
        let steps = FakeFirebaseStartupSteps()
        _ = run(steps, isDebugBuild: false)
        XCTAssertTrue(steps.calls.contains("installAppCheck(appAttest)"))
    }

    /// 設定ファイルが無い：App Check も Firebase も設定せず、アプリは止まらない
    func testMissingConfigurationFileDoesNotCrash() {
        let steps = FakeFirebaseStartupSteps()
        steps.hasFile = false
        XCTAssertEqual(run(steps), .missingConfiguration)
        XCTAssertEqual(steps.calls, ["hasConfigurationFile"])
    }

    /// 設定ファイルが使えない（別のアプリ用など）：設定しない
    func testInvalidConfigurationDoesNotConfigure() {
        let steps = FakeFirebaseStartupSteps()
        steps.optionsAreValid = false
        XCTAssertEqual(run(steps), .invalidConfiguration)
        XCTAssertFalse(steps.calls.contains("configure"))
        XCTAssertFalse(steps.calls.contains { $0.hasPrefix("installAppCheck") })
    }

    /// 設定に失敗しても止まらず「使えない」になる
    func testConfigureFailureIsReported() {
        let steps = FakeFirebaseStartupSteps()
        steps.configureSucceeds = false
        XCTAssertEqual(run(steps), .invalidConfiguration)
    }

    /// テスト中・設定済みのときは何もしない
    func testSkipsWhenRunningTestsOrAlreadyConfigured() {
        let testing = FakeFirebaseStartupSteps()
        XCTAssertEqual(run(testing, isRunningTests: true), .skippedForTests)
        XCTAssertTrue(testing.calls.isEmpty)

        let configured = FakeFirebaseStartupSteps()
        configured.isAlreadyConfigured = true
        XCTAssertEqual(run(configured), .configured)
        XCTAssertTrue(configured.calls.isEmpty, "二重に設定しない")
    }

    /// このテストを動かしているビルド（Debug）では Debug Provider が選ばれる
    func testCurrentBuildConfiguration() {
        #if DEBUG
        XCTAssertTrue(FirebaseBootstrap.isDebugBuild)
        XCTAssertEqual(AppCheckProviderPolicy.kind(isDebugBuild: FirebaseBootstrap.isDebugBuild), .debug)
        #else
        XCTAssertFalse(FirebaseBootstrap.isDebugBuild)
        #endif
        XCTAssertTrue(FirebaseBootstrap.isRunningTests)
    }

    /// Firebase に接続していなくても、今までの機能は使える
    func testLocalFeaturesWorkWithoutFirebase() {
        let auth = AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: FakeAppleSignIn())
        XCTAssertFalse(auth.isAvailable)
        let store = LifeStore()
        let before = store.items.count
        store.add([LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(store.items.count, before + 1)
    }
}

/// Firestore を使うのは、わが家の共有 ToDo・買い物の窓口（FirestoreSharedItemsBackend.swift）だけ（2026-10-28 Build 7。以前は「まったく使わない」）
final class NoFirestoreWritesTests: XCTestCase {
    func testAppSourceDoesNotUseFirestore() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let appSource = testFile.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LifeOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: appSource, includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        var swiftFiles = 0
        var offenders: [String] = []
        var backendText: String?
        var deviceRegistryText: String?
        let forbidden = ["import FirebaseFirestore", "Firestore.firestore(", ".setData(", ".addDocument(", ".updateData("]
        // 2026-10-28（Build 7）：Firestore を使ってよいのは、わが家の共有 ToDo・買い物の窓口のファイルだけ
        // 2026-10-28（Build 8）：共有の通知の端末の文書（自分の users/{uid}/devices）の窓口も
        let allowedFile = "FirestoreSharedItemsBackend.swift"
        let deviceRegistryFile = "FirestoreDeviceRegistry.swift"
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles += 1
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if url.lastPathComponent == allowedFile {
                backendText = text
                continue
            }
            if url.lastPathComponent == deviceRegistryFile {
                deviceRegistryText = text
                continue
            }
            for word in forbidden where text.contains(word) {
                offenders.append("\(url.lastPathComponent): \(word)")
            }
        }
        try XCTSkipIf(swiftFiles == 0, "アプリのソースを読めない環境のため、確認を省きます")
        XCTAssertEqual(offenders, [], "Firestore を使うのは FirestoreSharedItemsBackend.swift と FirestoreDeviceRegistry.swift だけ")

        // 端末の窓口が読み書きするのは、自分の users/{uid}/devices/{deviceID} だけ。決まった項目だけを書く
        let registry = try XCTUnwrap(deviceRegistryText, "FirestoreDeviceRegistry.swift が見つからない")
        XCTAssertEqual(Set(Self.matches(of: #"\.collection\("([^"]+)"\)"#, in: registry)), ["users", "devices"])
        XCTAssertTrue(registry.contains("collection(\"users\").document(uid).collection(\"devices\")"), "自分の UID の下だけ")
        XCTAssertTrue(registry.contains("Auth.auth().currentUser?.uid"), "UID はサインインの情報から読む（ほかの人を指定できない）")
        let fieldKeys = Set(Self.matches(of: #"^\s*"([A-Za-z]+)": "#, in: registry, options: [.anchorsMatchLines]))
        XCTAssertEqual(fieldKeys, ["fcmToken", "platform", "notificationsEnabled", "sharedUpdatesEnabled", "showsPreview", "updatedAt"], "端末の文書は決まった項目だけ")
        for word in ["print(", "NSLog", "os_log", "Logger(", "localizedDescription", "collectionGroup", ".addDocument(", "identifierForVendor", "advertisingIdentifier"] {
            XCTAssertFalse(registry.contains(word), "端末の窓口：\(word)")
        }

        // その窓口が読み書きするのは groups/{groupID}/items だけ（ほかの場所・一括の追加・別のコレクションは使わない）
        let backend = try XCTUnwrap(backendText, "FirestoreSharedItemsBackend.swift が見つからない")
        let collections = Self.matches(of: #"\.collection\("([^"]+)"\)"#, in: backend)
        XCTAssertEqual(Set(collections), ["groups", "items"], "使うコレクション")
        XCTAssertFalse(backend.contains(".addDocument("), "文書の ID は項目の UUID（自動の ID で二重に作らない）")
        XCTAssertFalse(backend.contains("collectionGroup"), "グループをまたいで探さない")
        XCTAssertFalse(backend.contains("WriteBatch") || backend.contains(".batch()"), "まとめて送らない（既存データの一括アップロードをしない）")
        XCTAssertTrue(backend.contains("document(id.uuidString)"), "文書の ID は項目の UUID")
        for word in ["print(", "NSLog", "os_log", "Logger(", "localizedDescription"] {
            XCTAssertFalse(backend.contains(word), "ログ・エラー文を出さない：\(word)")
        }
    }

    private static func matches(of pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Debug Token の実値をソースや設定に書かない（環境変数で渡す設定も使わない）
    func testNoDebugTokenInSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("LifeOS"), includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        var checked = 0
        for case let url as URL in enumerator where ["swift", "plist", "entitlements", "xcconfig"].contains(url.pathExtension) {
            checked += 1
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("FIRAAppCheckDebugToken"), url.lastPathComponent)
        }
        try XCTSkipIf(checked == 0, "アプリのソースを読めない環境のため、確認を省きます")

        // Scheme（GitHub に入る）の環境変数にも Debug Token を入れない
        let scheme = root.appendingPathComponent("LifeOS.xcodeproj/xcshareddata/xcschemes/LifeOS.xcscheme")
        if let text = try? String(contentsOf: scheme, encoding: .utf8) {
            XCTAssertFalse(text.contains("FIRAAppCheckDebugToken"), "Scheme に Debug Token を入れない")
        }
    }
}
