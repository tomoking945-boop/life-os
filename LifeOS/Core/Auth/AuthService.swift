import Foundation
import Observation

/// パートナー共有用のサインインをまとめる（画面はこのクラスだけを使う。Firebase SDK は直接使わない）
///
/// - サインイン：nonce を作る → Apple に SHA-256 を渡して画面を出す → ID トークンと元の nonce で Firebase にサインイン
/// - サインアウト：Firebase からサインアウト
/// - アカウント削除：（画面で確認したあと）Apple でもう一度確かめる → Firebase で再認証 → authorization code で Apple のトークンを失効 → Firebase の利用者を削除
///   確認画面の表示状態はここでは持たない（画面側の @State）。2026-10-19 修正：確認画面が閉じる処理とボタンの処理の順番によって、削除が何もせず終わっていた
/// - やめた（キャンセル）ときは、元の状態に戻す（エラーにしない）
/// - Firebase に接続できないときは、何もしない（アプリのほかの機能はそのまま使える）
/// - 生活データは送らない。Firestore にも書き込まない
@Observable
final class AuthService {
    private(set) var status: AuthStatus

    @ObservationIgnored private let backend: AuthBackend?
    @ObservationIgnored private let apple: AppleSignInProviding
    @ObservationIgnored private let makeNonce: () -> String

    /// - Parameters:
    ///   - backend: Firebase の窓口。nil なら Firebase に接続していない
    ///   - unavailableReason: 接続していない理由
    ///   - apple: 「Appleでサインイン」の画面
    ///   - makeNonce: 使い捨ての文字列を作る（テストでは固定にできる）
    init(
        backend: AuthBackend?,
        unavailableReason: AuthUnavailableReason = .missingConfiguration,
        apple: AppleSignInProviding,
        makeNonce: @escaping () -> String = { AuthNonce.random() }
    ) {
        self.backend = backend
        self.apple = apple
        self.makeNonce = makeNonce
        if let backend {
            status = backend.currentAccount.map(AuthStatus.signedIn) ?? .signedOut
        } else {
            status = .unavailable(unavailableReason)
        }
    }

    var isAvailable: Bool { backend != nil }
    var account: AuthAccount? { status.account }

    /// Firebase に記録されている今の状態を読み直す（画面を開いたとき）
    func refresh() {
        guard let backend, !status.isWorking else { return }
        status = backend.currentAccount.map(AuthStatus.signedIn) ?? .signedOut
    }

    /// エラーの表示を閉じる
    func dismissFailure() {
        guard case .failed(_, let account) = status else { return }
        status = account.map(AuthStatus.signedIn) ?? .signedOut
    }

    // MARK: - サインイン

    @MainActor
    func signIn() async {
        guard let backend, !status.isWorking, account == nil else { return }
        status = .working(.signingIn, account: nil)
        let rawNonce = makeNonce()
        do {
            let credential = try await apple.requestCredential(hashedNonce: AuthNonce.sha256(rawNonce))
            let signedIn = try await backend.signIn(with: credential, rawNonce: rawNonce)
            status = .signedIn(signedIn)
        } catch let failure as AuthFailure where failure == .canceled {
            status = .signedOut
        } catch {
            status = .failed(Self.failure(from: error), account: nil)
        }
    }

    // MARK: - サインアウト

    @MainActor
    func signOut() {
        guard let backend, let current = account, !status.isWorking else { return }
        status = .working(.signingOut, account: current)
        do {
            try backend.signOut()
            status = .signedOut
        } catch {
            status = .failed(Self.failure(from: error), account: backend.currentAccount)
        }
    }

    // MARK: - アカウント削除

    /// アカウントを削除できる状態か（サインイン済みで、処理中でない）。削除ボタンの表示・押せるかに使う
    var canDeleteAccount: Bool {
        guard backend != nil, case .signedIn = status else { return false }
        return true
    }

    /// アカウントを削除する（画面の確認で「アカウントを削除」を選んだときだけ呼ぶ）：
    /// Apple で再認証 → トークン失効 → Firebase の利用者を削除（それぞれ1回）
    ///
    /// - 実行のときに、サインイン済み・処理中でないことを改めて確かめる
    /// - 最初の await の前に「処理中」にするので、2回押しても2回目は何もしない
    @MainActor
    func deleteAccount() async {
        guard let backend, case .signedIn(let current) = status else { return }
        status = .working(.deletingAccount, account: current)
        let rawNonce = makeNonce()
        do {
            let credential = try await apple.requestCredential(hashedNonce: AuthNonce.sha256(rawNonce))
            guard let code = credential.authorizationCode, !code.isEmpty else {
                throw AuthFailure.missingToken
            }
            try await backend.reauthenticate(with: credential, rawNonce: rawNonce)
            try await backend.revokeAppleToken(authorizationCode: code)
            try await backend.deleteCurrentUser()
            status = .signedOut
        } catch let failure as AuthFailure where failure == .canceled {
            status = backend.currentAccount.map(AuthStatus.signedIn) ?? .signedOut
        } catch {
            let remaining = backend.currentAccount
            status = .failed(Self.failure(from: error), account: remaining)
        }
    }

    private static func failure(from error: Error) -> AuthFailure {
        (error as? AuthFailure) ?? .other
    }
}

extension AuthService {
    /// アプリ全体で使う1つ（起動時の Firebase の設定の結果に合わせて作る）
    static let live: AuthService = {
        #if canImport(FirebaseAuth)
        switch FirebaseBootstrap.result {
        case .configured:
            return AuthService(backend: FirebaseAuthBackend(), apple: AppleSignInCoordinator())
        case .missingConfiguration:
            return AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: AppleSignInCoordinator())
        case .invalidConfiguration:
            return AuthService(backend: nil, unavailableReason: .invalidConfiguration, apple: AppleSignInCoordinator())
        case .notStarted, .skippedForTests:
            return AuthService(backend: nil, unavailableReason: .notStarted, apple: AppleSignInCoordinator())
        }
        #else
        return AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: AppleSignInCoordinator())
        #endif
    }()
}
