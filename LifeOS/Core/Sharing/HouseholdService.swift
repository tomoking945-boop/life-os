import Foundation
import Observation

/// わが家の作成・招待・参加をまとめる（画面はこのクラスだけを使う。Firebase SDK は直接使わない）
/// docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md
///
/// - わが家の情報は、サーバー（getMyHousehold など）から受け取る。UID は受け取らない・出さない
/// - 作った招待のリンクは、アプリを開いているあいだのメモリだけで持つ（保存しない・画面に文字として出さない）
/// - 参加は、利用者が「参加する」を押したときだけ。サインインしていなければ何もしない
/// - Firebase に接続できないときは何もしない（アプリのほかの機能はそのまま使える）
/// - 生活データ（予定・ToDo・家計簿・保証書など）は送らない
@Observable
final class HouseholdService {
    /// わが家の状態
    enum State: Equatable {
        /// Firebase に接続していない
        case unavailable
        /// サインインしていない
        case signedOut
        /// まだ読み込んでいない
        case idle
        case loading
        /// わが家に参加していない
        case none
        case loaded(HouseholdSummary)
        case failed(HouseholdFailure)

        var summary: HouseholdSummary? {
            if case .loaded(let summary) = self { return summary }
            return nil
        }
    }

    /// 招待の確認（参加の前の内容表示）の状態
    enum PreviewState: Equatable {
        case idle
        case loading
        case loaded(InvitePreview)
        case failed(HouseholdFailure)
        case joining
        case joined
    }

    /// 処理中の内容（画面に「処理中」を出す）
    enum Operation: Equatable {
        case creating
        case creatingInvite
        case revokingInvite

        var message: String {
            switch self {
            case .creating: return "わが家を作っています…"
            case .creatingInvite: return "招待を作っています…"
            case .revokingInvite: return "招待を取り消しています…"
            }
        }
    }

    private(set) var state: State
    private(set) var preview: PreviewState = .idle
    /// 処理中の操作（作成・招待・取り消し）
    private(set) var operation: Operation?
    /// 作成・招待・取り消しがうまくいかなかったとき
    private(set) var actionFailure: HouseholdFailure?
    /// 作った招待（メモリの中だけ。保存しない）
    private(set) var activeInvite: CreatedInvite?
    /// 「わが家に参加しました」などのお知らせ
    private(set) var notice: String?

    @ObservationIgnored private let backend: HouseholdBackend?
    @ObservationIgnored private let isSignedIn: () -> Bool

    /// - Parameters:
    ///   - backend: サーバーの窓口。nil なら Firebase に接続していない
    ///   - isSignedIn: いまサインインしているか（AuthService から）
    init(backend: HouseholdBackend?, isSignedIn: @escaping () -> Bool) {
        self.backend = backend
        self.isSignedIn = isSignedIn
        state = backend == nil ? .unavailable : .idle
    }

    var isAvailable: Bool { backend != nil }
    var isWorking: Bool { operation != nil || state == .loading || preview == .joining }

    // MARK: - わが家の情報

    /// わが家の情報を読み直す（画面を開いたとき・サインインしたとき）
    @MainActor
    func refresh() async {
        guard let backend else {
            state = .unavailable
            return
        }
        guard isSignedIn() else {
            state = .signedOut
            activeInvite = nil
            return
        }
        guard state != .loading else { return }
        state = .loading
        do {
            apply(try await backend.fetchMyHousehold())
        } catch {
            state = .failed(Self.failure(from: error))
        }
    }

    /// わが家を作る（名前・共有する種類）。作れたら true
    @MainActor
    func create(name: String, kinds: Set<SharedSpaceKind>) async -> Bool {
        guard let backend else {
            actionFailure = .notConnected
            return false
        }
        guard isSignedIn() else {
            actionFailure = .notSignedIn
            return false
        }
        guard HouseholdRules.canCreate(name: name, kinds: kinds) else {
            actionFailure = .invalidInput
            return false
        }
        guard operation == nil else { return false }
        operation = .creating
        actionFailure = nil
        defer { operation = nil }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            apply(try await backend.createHousehold(name: trimmed, kinds: SharedSpaceKind.ordered(kinds)))
            return true
        } catch {
            actionFailure = Self.failure(from: error)
            return false
        }
    }

    // MARK: - 招待（オーナーだけ）

    /// 招待を作る（前の招待は使えなくなる）。リンクはメモリの中だけで持つ
    @MainActor
    func createInvite() async {
        guard let backend, isSignedIn(), operation == nil else { return }
        operation = .creatingInvite
        actionFailure = nil
        defer { operation = nil }
        do {
            let invite = try await backend.createInvite()
            activeInvite = invite
            apply(try await backend.fetchMyHousehold())
        } catch {
            actionFailure = Self.failure(from: error)
        }
    }

    /// 未使用の招待を取り消す
    @MainActor
    func revokeInvite() async {
        guard let backend, isSignedIn(), operation == nil else { return }
        operation = .revokingInvite
        actionFailure = nil
        defer { operation = nil }
        do {
            try await backend.revokeInvite()
            activeInvite = nil
            apply(try await backend.fetchMyHousehold())
        } catch {
            actionFailure = Self.failure(from: error)
        }
    }

    // MARK: - 招待で参加する

    /// 招待の内容を読む（参加はしない）。サインインしていなければ何もしない
    @MainActor
    func loadPreview(for invite: InviteLink) async {
        guard let backend else {
            preview = .failed(.notConnected)
            return
        }
        guard isSignedIn() else {
            preview = .idle
            return
        }
        guard preview != .loading, preview != .joining else { return }
        preview = .loading
        do {
            preview = .loaded(try await backend.fetchInvitePreview(token: invite.token))
        } catch {
            preview = .failed(Self.failure(from: error))
        }
    }

    /// 「参加する」を押したとき。参加できたら true（2回押しても、サーバーへは1回だけ送る）
    @MainActor
    func join(_ invite: InviteLink) async -> Bool {
        guard let backend else {
            preview = .failed(.notConnected)
            return false
        }
        guard isSignedIn() else {
            preview = .idle
            return false
        }
        guard case .loaded = preview else { return false }
        preview = .joining
        do {
            apply(try await backend.acceptInvite(token: invite.token))
            preview = .joined
            notice = "わが家に参加しました"
            return true
        } catch {
            preview = .failed(Self.failure(from: error))
            return false
        }
    }

    /// 招待の確認をやめる・閉じる
    func resetPreview() {
        preview = .idle
    }

    func dismissNotice() {
        notice = nil
    }

    func dismissActionFailure() {
        actionFailure = nil
    }

    // MARK: - 内部

    private func apply(_ summary: HouseholdSummary?) {
        guard let summary else {
            state = .none
            activeInvite = nil
            return
        }
        state = .loaded(summary)
        // サーバーに有効な招待が無い（使われた・取り消された・期限切れ）、または別の招待になったら、メモリのリンクも捨てる
        if let invite = activeInvite {
            let serverExpiry = summary.activeInviteExpiresAt
            if !summary.isOwner || summary.isFull || serverExpiry == nil
                || abs(serverExpiry!.timeIntervalSince(invite.expiresAt)) > 1 {
                activeInvite = nil
            }
        }
    }

    private static func failure(from error: Error) -> HouseholdFailure {
        (error as? HouseholdFailure) ?? .other
    }
}

extension HouseholdService {
    /// アプリ全体で使う1つ（起動時の Firebase の設定の結果に合わせて作る）
    static let live: HouseholdService = {
        #if canImport(FirebaseFunctions)
        if FirebaseBootstrap.result == .configured {
            return HouseholdService(backend: FirebaseHouseholdBackend(), isSignedIn: { AuthService.live.account != nil })
        }
        #endif
        return HouseholdService(backend: nil, isSignedIn: { AuthService.live.account != nil })
    }()
}
