import Foundation
import Observation

// 共有の通知（プッシュ通知。2026-10-28 Build 8）。docs/SHARED_PUSH_NOTIFICATIONS.md
//
// - パートナーが「わが家で共有」の ToDo・買い物を追加・変更したとき、Cloud Function（onSharedItemWritten）が送る
// - 受け取るかどうかは、利用者が「わが家の設定」で決める（初期値はオフ）。通知の許可は、オンにしたときだけ求める（起動時には求めない）
// - 登録するのは、サインインしていて、わが家に参加しているときだけ。保存先は自分の users/{uid}/devices/{deviceID} だけ
// - 端末の ID は、アプリを入れるたびに作るランダムな ID（広告の識別子・端末固有の番号は使わない）
// - トークン・UID・項目名はログに出さない（ここでは何もログに出さない）

/// 共有の通知の設定（端末の中だけに保存する。項目名の表示の設定は、端末の文書にも入れる）
struct SharedPushPreferences: Codable, Equatable {
    /// 共有の通知を受け取る（初期値オフ）
    var receives: Bool
    /// 通知に項目名を表示する（初期値オフ）
    var showsTitle: Bool
    /// この端末（このインストール）を見分けるランダムな ID
    var deviceID: String

    static func makeNew() -> SharedPushPreferences {
        SharedPushPreferences(receives: false, showsTitle: false, deviceID: UUID().uuidString)
    }
}

/// 設定の保存先（テストでは偽物に差し替える）
protocol SharedPushPreferenceStore: AnyObject {
    func load() -> SharedPushPreferences?
    func save(_ preferences: SharedPushPreferences)
}

/// 端末の中のファイルに保存する（life-store.json とは別のファイル。外部へは送らない）
final class LocalSharedPushPreferenceStore: SharedPushPreferenceStore {
    static let fileName = "shared-push.json"

    func load() -> SharedPushPreferences? {
        LocalStorage.load(SharedPushPreferences.self, from: Self.fileName)
    }

    func save(_ preferences: SharedPushPreferences) {
        LocalStorage.save(preferences, to: Self.fileName)
    }
}

/// iPhone の通知の許可
enum PushAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
}

/// 通知の許可・APNs への登録（テストでは偽物）
protocol PushPermissionProviding: AnyObject {
    func authorization() async -> PushAuthorization
    /// 許可を求める（iOS の許可画面を出す）。許可されたら true
    func requestAuthorization() async -> Bool
    @MainActor func registerForRemoteNotifications()
}

/// 通知用のトークン（Firebase Cloud Messaging。テストでは偽物）
protocol PushTokenProviding: AnyObject {
    /// トークンを自動で作るか（オンにするまで作らない）
    func setAutoInit(_ enabled: Bool)
    /// APNs から届いたトークンを渡す
    func setAPNsToken(_ token: Data)
    /// いまの通知用のトークン（APNs のトークンが届く前は失敗する）
    func currentToken() async throws -> String
    /// トークンを無効にする（オフにしたとき・サインアウトのとき）
    func deleteToken() async
    /// トークンが新しくなったとき
    var onTokenRefresh: ((String) -> Void)? { get set }
}

/// 端末の文書に書く内容（通知に必要な最小限）
struct PushDeviceRecord: Equatable {
    let token: String
    let showsPreview: Bool
}

/// 自分の users/{uid}/devices/{deviceID}（Firestore。テストでは偽物）
protocol PushDeviceRegistry: AnyObject {
    func save(deviceID: String, record: PushDeviceRecord) async throws
    func remove(deviceID: String) async throws
}

/// 通知をタップしたときに開く画面
enum SharedPushRoute: Equatable {
    case tasks(TaskSegment)

    /// サーバーが送る種類（Functions の NotificationType と同じ）
    static let knownTypes: Set<String> = ["taskAdded", "taskChanged", "completionChanged"]

    /// 通知の中の情報から開く画面を決める。共有の通知でなければ nil（ローカル通知など）
    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, Self.knownTypes.contains(type),
              let kind = userInfo["kind"] as? String else { return nil }
        switch kind {
        case "todo": self = .tasks(.today)
        case "shopping": self = .tasks(.shopping)
        default: return nil
        }
    }
}

/// 通知をタップしたときの行き先を、画面へ渡す（アプリを開いたあとで画面が受け取る）。
/// 項目を勝手に編集・完了・削除しない。項目が消えていても、画面を開くだけ
@Observable
final class SharedPushRouter {
    static let shared = SharedPushRouter()

    private(set) var pending: SharedPushRoute?

    /// 通知がタップされた（共有の通知でなければ何もしない）
    func open(userInfo: [AnyHashable: Any]) {
        guard let route = SharedPushRoute(userInfo: userInfo) else { return }
        pending = route
    }

    /// 画面が受け取る（1回だけ）
    func takePending() -> SharedPushRoute? {
        defer { pending = nil }
        return pending
    }

    /// アプリを開いているときに届いた通知を、バナーで出すか（共有の通知だけ。ローカル通知はこれまでどおり出さない）
    static func showsInForeground(userInfo: [AnyHashable: Any]) -> Bool {
        SharedPushRoute(userInfo: userInfo) != nil
    }
}

/// 共有の通知の受け取り・端末の登録をまとめる（画面はこのクラスだけを使う）
@Observable
final class SharedPushService {
    enum Status: Equatable {
        /// 受け取らない
        case off
        /// Firebase に接続していない
        case unavailable
        /// サインインしていない
        case needsSignIn
        /// わが家に参加していない
        case needsHousehold
        /// iPhone の設定で通知が許可されていない
        case denied
        case registering
        case registered
        /// 登録できなかった（通信できない など）
        case failed

        var message: String? {
            switch self {
            case .off, .registered: return nil
            case .unavailable: return "いまは共有の通知を使えません。"
            case .needsSignIn: return "Appleでサインインすると使えます。"
            case .needsHousehold: return "わが家に参加すると使えます。"
            case .denied: return "iPhone の設定で、くらしOSの通知がオフになっています。設定アプリで通知を許可してください。"
            case .registering: return "通知を受け取る準備をしています…"
            case .failed: return "通知の登録ができませんでした。電波のよい場所で、もう一度お試しください。"
            }
        }
    }

    private(set) var preferences: SharedPushPreferences
    private(set) var authorization: PushAuthorization = .notDetermined
    private(set) var status: Status = .off

    @ObservationIgnored private let preferenceStore: SharedPushPreferenceStore
    @ObservationIgnored private let permission: PushPermissionProviding?
    @ObservationIgnored private let tokens: PushTokenProviding?
    @ObservationIgnored private let registry: PushDeviceRegistry?
    @ObservationIgnored private var isSignedIn = false
    @ObservationIgnored private var isJoined = false
    /// 端末の文書を書いたか（消すときの目安。書いていなくても消すのは安全）
    @ObservationIgnored private(set) var hasRegistration = false
    /// サインアウトのときに、端末の文書を消すのを待つ時間（秒）。これを過ぎてもサインアウトは続ける
    @ObservationIgnored var signOutTimeout: TimeInterval = 3

    // MARK: 登録の重複を防ぐ印（2026-10-28 Build 10。docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md）
    // Build 8・9 では、登録の中で APNs への登録を毎回頼み、その返事（apnsTokenDidArrive）からまた登録を始めていたため、
    // 登録 → APNs → 登録 … が止まらず、Firestore への端末の書き込みと APNs の登録が増え続けることがあった

    /// 登録の処理が動いているか（同時に2つ動かさない）
    @ObservationIgnored private var isRegistrationInFlight = false
    /// この起動で APNs への登録を頼んだか（1回の起動で1回だけ頼む）
    @ObservationIgnored private var hasRequestedAPNs = false
    /// 通知用のトークンが APNs のトークン待ちで取れなかったか（APNs のトークンが届いたときだけ、もう一度試す）
    @ObservationIgnored private var isWaitingForAPNsToken = false
    /// 最後に保存した端末の文書の内容（同じ内容なら、もう一度書かない）
    @ObservationIgnored private var lastSavedRecord: PushDeviceRecord?
    /// 確認用の回数（テストで、増え続けないことを確かめる。数だけで、トークン・UID は持たない）
    @ObservationIgnored private(set) var registrationStartCount = 0
    @ObservationIgnored private(set) var apnsRequestCount = 0
    @ObservationIgnored private(set) var deviceSaveCount = 0

    /// - Parameters: permission・tokens・registry が無ければ、Firebase に接続していない
    init(
        preferenceStore: SharedPushPreferenceStore,
        permission: PushPermissionProviding?,
        tokens: PushTokenProviding?,
        registry: PushDeviceRegistry?
    ) {
        self.preferenceStore = preferenceStore
        self.permission = permission
        self.tokens = tokens
        self.registry = registry
        if let saved = preferenceStore.load() {
            preferences = saved
        } else {
            let created = SharedPushPreferences.makeNew()
            preferences = created
            preferenceStore.save(created)
        }
        if permission == nil || tokens == nil || registry == nil {
            status = .unavailable
        }
        self.tokens?.onTokenRefresh = { [weak self] token in
            Task { @MainActor in await self?.tokenDidRefresh(token) }
        }
    }

    var isAvailable: Bool { permission != nil && tokens != nil && registry != nil }

    /// 「通知に項目名を表示する」を切り替えられるか（受け取るがオンのときだけ）
    var canChangeShowsTitle: Bool { preferences.receives }

    // MARK: - 画面から

    /// iPhone の通知の許可を読み直す（許可画面は出さない）
    @MainActor
    func refreshAuthorization() async {
        guard let permission else { return }
        let current = await permission.authorization()
        // 同じなら書き込まない（画面を開くたびに描き直さない。2026-10-28 Build 10）
        if authorization != current { authorization = current }
        if preferences.receives, authorization == .denied {
            status = .denied
        }
    }

    /// 「共有の通知を受け取る」を切り替える。オンにしたときだけ、未確認なら iOS の許可画面を出す
    @MainActor
    func setReceives(_ isOn: Bool) async {
        guard isOn else {
            preferences.receives = false
            preferenceStore.save(preferences)
            await unregister(deleteToken: true)
            status = isAvailable ? .off : .unavailable
            return
        }
        guard let permission, isAvailable else {
            status = .unavailable
            return
        }
        guard isSignedIn else {
            status = .needsSignIn
            return
        }
        guard isJoined else {
            status = .needsHousehold
            return
        }
        var current = await permission.authorization()
        if current == .notDetermined {
            current = await permission.requestAuthorization() ? .authorized : .denied
        }
        authorization = current
        guard current == .authorized else {
            status = .denied
            return
        }
        preferences.receives = true
        preferenceStore.save(preferences)
        await register()
    }

    /// 「通知に項目名を表示する」を切り替える（受け取るがオンのときだけ）
    @MainActor
    func setShowsTitle(_ isOn: Bool) async {
        guard preferences.receives else { return }
        preferences.showsTitle = isOn
        preferenceStore.save(preferences)
        // すでに保存したトークンで、項目名の表示だけを書き直す（APNs・トークンの取り直しはしない）
        if let token = lastSavedRecord?.token {
            await saveDevice(token: token)
        } else if hasRegistration || status == .registered {
            await register()
        }
    }

    // MARK: - アプリの状態から

    /// サインイン・わが家の状態が変わったとき（起動時・参加・退出・削除・サインアウト）
    @MainActor
    func updateContext(isSignedIn: Bool, isJoined: Bool) async {
        self.isSignedIn = isSignedIn
        self.isJoined = isJoined
        guard isAvailable else {
            status = .unavailable
            return
        }
        guard isSignedIn, isJoined else {
            // 参加していない・サインアウトした：端末の文書を消す（設定の「受け取る」は残す。また参加したら登録し直す）
            if hasRegistration { await unregister(deleteToken: true) }
            status = preferences.receives ? (isSignedIn ? .needsHousehold : .needsSignIn) : .off
            return
        }
        guard preferences.receives else {
            status = .off
            return
        }
        await refreshAuthorization()
        guard authorization == .authorized else {
            status = authorization == .denied ? .denied : .off
            return
        }
        // 登録済み・登録中なら何もしない（画面を開くたび・アプリに戻るたびに登録し直さない）
        if status != .registered && !isRegistrationInFlight {
            await register()
        }
    }

    /// サインアウトの前に：端末の文書を消す（決まった時間だけ待つ。消せなくてもサインアウトは続ける）
    @MainActor
    func prepareForSignOut() async {
        guard let registry else { return }
        let deviceID = preferences.deviceID
        _ = await Self.run(timeout: signOutTimeout) {
            try await registry.remove(deviceID: deviceID)
        }
        hasRegistration = false
        lastSavedRecord = nil
        isWaitingForAPNsToken = false
        if let tokens {
            tokens.setAutoInit(false)
            _ = await Self.run(timeout: signOutTimeout) { await tokens.deleteToken() }
        }
        isSignedIn = false
        status = preferences.receives ? .needsSignIn : .off
    }

    // MARK: - APNs・Firebase Messaging から

    /// APNs のトークンが届いた（AppDelegate から）。
    /// トークンを Firebase Messaging へ渡すだけ。登録の続きは、APNs のトークン待ちで止まっていたときだけ1回行う
    /// （ここから APNs への登録を頼み直さない。Build 8・9 の「登録 → APNs → 登録 …」の繰り返しを止める）
    func apnsTokenDidArrive(_ token: Data) {
        tokens?.setAPNsToken(token)
        Task { @MainActor in
            guard self.isWaitingForAPNsToken, self.isEligible, !self.isRegistrationInFlight else { return }
            await self.register()
        }
    }

    /// APNs への登録に失敗した（シミュレーターなど）
    func apnsRegistrationFailed() {
        Task { @MainActor in
            if self.status == .registering { self.status = .failed }
        }
    }

    /// 通知用のトークンが新しくなった：受け取る設定で、条件を満たすときだけ上書きする
    @MainActor
    func tokenDidRefresh(_ token: String) async {
        guard isEligible, !token.isEmpty else { return }
        await saveDevice(token: token)
    }

    // MARK: - 内部

    private var isEligible: Bool {
        isAvailable && isSignedIn && isJoined && preferences.receives && authorization == .authorized
    }

    /// 登録（同時に1つだけ）。APNs への登録はこの起動で1回だけ頼み、トークンが取れたら端末の文書を保存する
    @MainActor
    private func register() async {
        guard let permission, let tokens, isSignedIn, isJoined, preferences.receives, !isRegistrationInFlight else { return }
        isRegistrationInFlight = true
        defer { isRegistrationInFlight = false }
        registrationStartCount += 1
        if status != .registered { status = .registering }
        tokens.setAutoInit(true)
        if !hasRequestedAPNs {
            hasRequestedAPNs = true
            apnsRequestCount += 1
            permission.registerForRemoteNotifications()
        }
        let token: String
        do {
            token = try await tokens.currentToken()
        } catch {
            // APNs のトークンがまだ届いていない：届いたとき（apnsTokenDidArrive）に1回だけもう一度試す
            isWaitingForAPNsToken = true
            return
        }
        isWaitingForAPNsToken = false
        await saveDevice(token: token)
    }

    /// 端末の文書を保存する（同じ内容なら書かない。失敗しても自動で繰り返さない。次にアプリに戻ったときに1回だけ試す）
    @MainActor
    private func saveDevice(token: String) async {
        guard let registry else { return }
        let record = PushDeviceRecord(token: token, showsPreview: preferences.showsTitle)
        if hasRegistration, record == lastSavedRecord {
            if status != .registered { status = .registered }
            return
        }
        deviceSaveCount += 1
        do {
            try await registry.save(deviceID: preferences.deviceID, record: record)
            lastSavedRecord = record
            hasRegistration = true
            status = .registered
        } catch {
            status = .failed
        }
    }

    @MainActor
    private func unregister(deleteToken: Bool) async {
        if let registry {
            let deviceID = preferences.deviceID
            _ = await Self.run(timeout: signOutTimeout) {
                try await registry.remove(deviceID: deviceID)
            }
        }
        hasRegistration = false
        lastSavedRecord = nil
        isWaitingForAPNsToken = false
        if let tokens {
            tokens.setAutoInit(false)
            if deleteToken {
                _ = await Self.run(timeout: signOutTimeout) { await tokens.deleteToken() }
            }
        }
    }

    /// 決まった時間だけ待つ（通信できないときに、画面やサインアウトを止めないため）。終わったら true
    static func run(timeout: TimeInterval, _ operation: @escaping () async throws -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = OnceGate()
            Task {
                let succeeded: Bool
                do {
                    try await operation()
                    succeeded = true
                } catch {
                    succeeded = false
                }
                if gate.claim() { continuation.resume(returning: succeeded) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                if gate.claim() { continuation.resume(returning: false) }
            }
        }
    }
}

/// 1回だけ通す（待ち合わせの結果を2回返さないため）
private final class OnceGate {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}

extension SharedPushService {
    /// アプリ全体で使う1つ（起動時の Firebase の設定の結果に合わせて作る）
    static let live: SharedPushService = {
        #if canImport(FirebaseMessaging) && canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        if FirebaseBootstrap.result == .configured {
            return SharedPushService(
                preferenceStore: LocalSharedPushPreferenceStore(),
                permission: SystemPushPermission(),
                tokens: FirebaseMessagingTokenProvider(),
                registry: FirestoreDeviceRegistry()
            )
        }
        #endif
        return SharedPushService(preferenceStore: LocalSharedPushPreferenceStore(), permission: nil, tokens: nil, registry: nil)
    }()
}
