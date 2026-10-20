import Foundation
#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
import FirebaseAppCheck
import FirebaseCore
#endif

// 起動時の Firebase の設定（2026-10-19 Authentication、2026-10-20 App Check を追加）
// docs/FIREBASE_APPLE_AUTH_FOUNDATION.md・docs/FIREBASE_APP_CHECK_FOUNDATION.md
//
// 順番：
//   1. すでに設定済みなら何もしない
//   2. テスト中は設定しない（テストでネットワークを使わないため）
//   3. 設定ファイル（GoogleService-Info.plist）が無い・壊れている・別のアプリ用なら設定しない（アプリは普通に起動する）
//   4. App Check の Provider Factory を設定する（FirebaseApp.configure より必ず前）
//   5. FirebaseApp.configure（Authentication はこのあと、使うときに初めて動く）
//
// どの順番でも、失敗してアプリ全体が止まることはない。生活データは送らない（Firestore は使わない）。

/// App Check でどの仕組みを使うか
enum AppCheckProviderKind: Equatable {
    /// Debug ビルド：Debug Provider（Xcode のログに出るトークンを、利用者が Firebase Console に登録して使う）
    case debug
    /// Release ビルド（TestFlight・App Store・実機の Release）：App Attest
    case appAttest
}

/// Debug と Release で、App Check の仕組みを選ぶ
enum AppCheckProviderPolicy {
    /// 最低対応 iOS が 17 のため、App Attest の仕組み（iOS 14 以降）は常に使える。
    /// App Attest を使えない環境（シミュレーターなど）では、トークンが取れないだけでアプリは止まらない。
    /// DeviceCheck は Firebase Console に登録していないため、代わりには使わない
    static func kind(isDebugBuild: Bool) -> AppCheckProviderKind {
        isDebugBuild ? .debug : .appAttest
    }
}

/// 起動時の手順（テストでは偽物に差し替えて、順番を確かめる）
protocol FirebaseStartupSteps: AnyObject {
    var isAlreadyConfigured: Bool { get }
    func hasConfigurationFile(in bundle: Bundle) -> Bool
    /// 設定ファイルを読み、このアプリ用か確かめる。使えなければ false
    func loadValidOptions(from bundle: Bundle) -> Bool
    /// App Check の Provider Factory を設定する（configure より前に呼ぶ）
    func installAppCheckProviderFactory(_ kind: AppCheckProviderKind)
    /// FirebaseApp.configure。設定できたら true
    func configure() -> Bool
}

enum FirebaseBootstrap {
    enum Result: Equatable {
        case notStarted
        case configured
        case missingConfiguration
        case invalidConfiguration
        case skippedForTests
    }

    /// 起動時の結果（AuthService.live が使う）
    private(set) static var result: Result = .notStarted

    /// このビルドが Debug か
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 起動の手順を決まった順番で進める（Firebase の型を使わないので、テストで確かめられる）
    static func run(steps: FirebaseStartupSteps, bundle: Bundle, isRunningTests: Bool, isDebugBuild: Bool) -> Result {
        if steps.isAlreadyConfigured { return .configured }
        if isRunningTests { return .skippedForTests }
        guard steps.hasConfigurationFile(in: bundle) else { return .missingConfiguration }
        guard steps.loadValidOptions(from: bundle) else { return .invalidConfiguration }
        // App Check は、Firebase の設定（configure）より前に設定する
        steps.installAppCheckProviderFactory(AppCheckProviderPolicy.kind(isDebugBuild: isDebugBuild))
        return steps.configure() ? .configured : .invalidConfiguration
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
extension FirebaseBootstrap {
    /// アプリの起動時に呼ぶ
    @discardableResult
    static func configureIfPossible(
        bundle: Bundle = .main,
        isRunningTests: Bool = FirebaseBootstrap.isRunningTests,
        isDebugBuild: Bool = FirebaseBootstrap.isDebugBuild
    ) -> Result {
        let outcome = run(steps: LiveFirebaseStartupSteps(), bundle: bundle, isRunningTests: isRunningTests, isDebugBuild: isDebugBuild)
        result = outcome
        return outcome
    }
}

/// 本物の起動の手順
final class LiveFirebaseStartupSteps: FirebaseStartupSteps {
    private var options: FirebaseOptions?

    var isAlreadyConfigured: Bool { FirebaseApp.app() != nil }

    func hasConfigurationFile(in bundle: Bundle) -> Bool {
        bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    func loadValidOptions(from bundle: Bundle) -> Bool {
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let loaded = FirebaseOptions(contentsOfFile: path),
              loaded.bundleID == bundle.bundleIdentifier else {
            return false
        }
        options = loaded
        return true
    }

    func installAppCheckProviderFactory(_ kind: AppCheckProviderKind) {
        AppCheck.setAppCheckProviderFactory(KurashiAppCheckProviderFactory(kind: kind))
    }

    func configure() -> Bool {
        guard let options else { return false }
        FirebaseApp.configure(options: options)
        return FirebaseApp.app() != nil
    }
}

/// App Check の仕組みを作る（Debug：Debug Provider、Release：App Attest）
/// Debug Provider のトークンはコードにも設定ファイルにも書かない（Xcode のログに出たものを、利用者が Firebase Console に登録する）
final class KurashiAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    let kind: AppCheckProviderKind

    init(kind: AppCheckProviderKind) {
        self.kind = kind
        super.init()
    }

    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        switch kind {
        case .debug:
            return AppCheckDebugProvider(app: app)
        case .appAttest:
            return AppAttestProvider(app: app)
        }
    }
}
#endif
