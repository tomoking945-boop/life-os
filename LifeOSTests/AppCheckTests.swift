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

/// Firestore に書き込む処理が無いこと（ソースの中を調べる。シミュレーターでテストするとき Mac のファイルを読める）
final class NoFirestoreWritesTests: XCTestCase {
    func testAppSourceDoesNotUseFirestore() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let appSource = testFile.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LifeOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: appSource, includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        var swiftFiles = 0
        var offenders: [String] = []
        let forbidden = ["import FirebaseFirestore", "Firestore.firestore(", ".setData(", ".addDocument(", ".updateData("]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles += 1
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            for word in forbidden where text.contains(word) {
                offenders.append("\(url.lastPathComponent): \(word)")
            }
        }
        try XCTSkipIf(swiftFiles == 0, "アプリのソースを読めない環境のため、確認を省きます")
        XCTAssertEqual(offenders, [], "Firestore に書き込む処理は、まだ追加しない")
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
