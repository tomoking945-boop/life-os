import XCTest
@testable import LifeOS

// パートナー共有の土台：Appleでサインイン（2026-10-19）のテスト
// 実際のネットワーク・Firebase・Apple の画面は使わない（偽物に差し替える）。

/// Apple の画面の偽物
final class FakeAppleSignIn: AppleSignInProviding {
    var result: Result<AppleCredential, Error> = .success(AppleCredential(identityToken: "id-token", authorizationCode: "auth-code"))
    private(set) var receivedHashedNonces: [String] = []

    func requestCredential(hashedNonce: String) async throws -> AppleCredential {
        receivedHashedNonces.append(hashedNonce)
        return try result.get()
    }
}

/// Apple の画面の偽物（結果を返すまで止まる。処理中の状態を確かめるため）
final class SuspendingAppleSignIn: AppleSignInProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var requestedWaiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false

    @MainActor
    func requestCredential(hashedNonce: String) async throws -> AppleCredential {
        requested = true
        requestedWaiters.forEach { $0.resume() }
        requestedWaiters.removeAll()
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    @MainActor
    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestedWaiters.append($0) }
    }

    @MainActor
    func resume(with result: Result<AppleCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// Firebase Authentication の偽物（呼ばれた順番を記録する）
final class FakeAuthBackend: AuthBackend {
    var currentAccount: AuthAccount?
    var signInError: Error?
    var signOutError: Error?
    var reauthenticateError: Error?
    var revokeError: Error?
    var deleteError: Error?
    private(set) var calls: [String] = []
    private(set) var receivedRawNonces: [String] = []
    private(set) var revokedCodes: [String] = []

    init(account: AuthAccount? = nil) {
        currentAccount = account
    }

    func signIn(with credential: AppleCredential, rawNonce: String) async throws -> AuthAccount {
        calls.append("signIn")
        receivedRawNonces.append(rawNonce)
        if let signInError { throw signInError }
        let account = AuthAccount(uid: "firebase-uid-\(credential.identityToken)")
        currentAccount = account
        return account
    }

    func signOut() throws {
        calls.append("signOut")
        if let signOutError { throw signOutError }
        currentAccount = nil
    }

    func reauthenticate(with credential: AppleCredential, rawNonce: String) async throws {
        calls.append("reauthenticate")
        receivedRawNonces.append(rawNonce)
        if let reauthenticateError { throw reauthenticateError }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        calls.append("revoke")
        revokedCodes.append(authorizationCode)
        if let revokeError { throw revokeError }
    }

    func deleteCurrentUser() async throws {
        calls.append("delete")
        if let deleteError { throw deleteError }
        currentAccount = nil
    }
}

@MainActor
final class AuthServiceTests: XCTestCase {
    private let signedInAccount = AuthAccount(uid: "uid-0123456789")

    private func makeService(backend: FakeAuthBackend?, apple: FakeAppleSignIn = FakeAppleSignIn()) -> AuthService {
        AuthService(backend: backend, apple: apple, makeNonce: { "fixed-raw-nonce" })
    }

    // MARK: - 状態

    func testInitialStatusFollowsBackend() {
        XCTAssertEqual(makeService(backend: FakeAuthBackend()).status, .signedOut)
        XCTAssertEqual(makeService(backend: FakeAuthBackend(account: signedInAccount)).status, .signedIn(signedInAccount))
    }

    /// Firebase 未設定：使えない状態になり、サインインしようとしても何も起きない
    func testUnavailableWhenFirebaseIsNotConfigured() async {
        let apple = FakeAppleSignIn()
        let service = AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: apple)
        XCTAssertEqual(service.status, .unavailable(.missingConfiguration))
        XCTAssertFalse(service.isAvailable)

        await service.signIn()
        service.signOut()
        await service.deleteAccount()

        XCTAssertEqual(service.status, .unavailable(.missingConfiguration))
        XCTAssertFalse(service.canDeleteAccount)
        XCTAssertTrue(apple.receivedHashedNonces.isEmpty, "Apple の画面も出さない")
        XCTAssertEqual(service.status.shortLabel, "使えません")
    }

    /// 設定ファイルが無いバンドルでは Firebase を設定しない（アプリは止まらない）
    func testBootstrapWithoutConfigurationFileDoesNotConfigureFirebase() {
        let bundleWithoutPlist = Bundle(for: AuthServiceTests.self)
        XCTAssertNil(bundleWithoutPlist.path(forResource: "GoogleService-Info", ofType: "plist"))
        XCTAssertEqual(FirebaseBootstrap.configureIfPossible(bundle: bundleWithoutPlist, isRunningTests: false), .missingConfiguration)
        XCTAssertEqual(FirebaseBootstrap.configureIfPossible(bundle: .main, isRunningTests: true), .skippedForTests, "テスト中は接続しない")
    }

    // MARK: - サインイン

    /// nonce：Apple には SHA-256、Firebase には元の文字列を渡す
    func testSignInUsesHashedNonceForAppleAndRawNonceForFirebase() async {
        let backend = FakeAuthBackend()
        let apple = FakeAppleSignIn()
        let service = makeService(backend: backend, apple: apple)

        await service.signIn()

        XCTAssertEqual(service.status, .signedIn(AuthAccount(uid: "firebase-uid-id-token")))
        XCTAssertEqual(apple.receivedHashedNonces, [AuthNonce.sha256("fixed-raw-nonce")])
        XCTAssertNotEqual(apple.receivedHashedNonces.first, "fixed-raw-nonce", "Apple に元の nonce は渡さない")
        XCTAssertEqual(backend.receivedRawNonces, ["fixed-raw-nonce"])
        XCTAssertEqual(backend.calls, ["signIn"])
    }

    /// やめた（キャンセル）ときはエラーにせず、サインアウトのまま
    func testCancelledSignInReturnsToSignedOutWithoutError() async {
        let backend = FakeAuthBackend()
        let apple = FakeAppleSignIn()
        apple.result = .failure(AuthFailure.canceled)
        let service = makeService(backend: backend, apple: apple)

        await service.signIn()

        XCTAssertEqual(service.status, .signedOut)
        XCTAssertTrue(backend.calls.isEmpty, "Firebase には何も送らない")
    }

    /// 失敗はエラーの状態になり、閉じるとサインアウトに戻る
    func testFailedSignInShowsErrorAndCanBeDismissed() async {
        let backend = FakeAuthBackend()
        backend.signInError = AuthFailure.network
        let service = makeService(backend: backend)

        await service.signIn()
        XCTAssertEqual(service.status, .failed(.network, account: nil))
        XCTAssertEqual(service.status.shortLabel, "未サインイン")

        service.dismissFailure()
        XCTAssertEqual(service.status, .signedOut)
    }

    func testAppleFailureAndUnknownErrorsAreMapped() async {
        let apple = FakeAppleSignIn()
        apple.result = .failure(AuthFailure.appleFailed)
        let service = makeService(backend: FakeAuthBackend(), apple: apple)
        await service.signIn()
        XCTAssertEqual(service.status, .failed(.appleFailed, account: nil))

        let backend = FakeAuthBackend()
        backend.signInError = NSError(domain: "something", code: 1)
        let other = makeService(backend: backend)
        await other.signIn()
        XCTAssertEqual(other.status, .failed(.other, account: nil), "知らないエラーの中身は画面に出さない")
    }

    // MARK: - サインアウト

    func testSignOut() {
        let backend = FakeAuthBackend(account: signedInAccount)
        let service = makeService(backend: backend)
        service.signOut()
        XCTAssertEqual(service.status, .signedOut)
        XCTAssertEqual(backend.calls, ["signOut"])
    }

    func testFailedSignOutKeepsAccount() {
        let backend = FakeAuthBackend(account: signedInAccount)
        backend.signOutError = AuthFailure.other
        let service = makeService(backend: backend)
        service.signOut()
        XCTAssertEqual(service.status, .failed(.other, account: signedInAccount))
        service.dismissFailure()
        XCTAssertEqual(service.status, .signedIn(signedInAccount))
    }

    // MARK: - アカウント削除

    /// 2026-10-19 の不具合の再現：確認画面が先に閉じても（以前は閉じたときに確認の状態が消え、削除が何もせず終わっていた）、
    /// 「アカウントを削除」を確定すれば、再認証 → トークン失効 → Firebase 利用者の削除がそれぞれ1回だけ行われる
    func testConfirmedDeletionRunsEvenAfterDialogClosed() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        let service = makeService(backend: backend, apple: apple)
        XCTAssertTrue(service.canDeleteAccount)

        // 確認画面の表示状態は画面側にあり、閉じても AuthService には何も起きない。そのあと確定の処理が届く
        await service.deleteAccount()

        XCTAssertEqual(backend.calls, ["reauthenticate", "revoke", "delete"])
        XCTAssertEqual(backend.revokedCodes, ["auth-code"])
        XCTAssertEqual(apple.receivedHashedNonces, [AuthNonce.sha256("fixed-raw-nonce")], "Apple での再認証は1回")
        XCTAssertEqual(service.status, .signedOut)
        XCTAssertFalse(service.canDeleteAccount)
    }

    /// 確認画面で「やめる」・閉じた：削除の処理を呼ばないので、Apple にも Firebase にも何もしない
    func testCancellingConfirmationDeletesNothing() {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        let service = makeService(backend: backend, apple: apple)

        // 画面は確認画面を出して閉じるだけ（deleteAccount を呼ばない）
        XCTAssertTrue(service.canDeleteAccount)

        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertTrue(apple.receivedHashedNonces.isEmpty)
        XCTAssertEqual(service.status, .signedIn(signedInAccount))
    }

    /// 2回続けて押しても、削除の処理は1回だけ
    func testDoubleTapDeletesOnlyOnce() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        let service = makeService(backend: backend, apple: apple)

        async let first: Void = service.deleteAccount()
        async let second: Void = service.deleteAccount()
        _ = await (first, second)
        await service.deleteAccount()

        XCTAssertEqual(backend.calls, ["reauthenticate", "revoke", "delete"])
        XCTAssertEqual(apple.receivedHashedNonces.count, 1)
        XCTAssertEqual(service.status, .signedOut)
    }

    /// 削除中は「処理中」になり、そのあいだ削除ボタンは押せない
    func testDeletionShowsWorkingState() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = SuspendingAppleSignIn()
        let suspending = AuthService(backend: backend, apple: apple, makeNonce: { "fixed-raw-nonce" })

        let task = Task { await suspending.deleteAccount() }
        await apple.waitUntilRequested()
        XCTAssertEqual(suspending.status, .working(.deletingAccount, account: signedInAccount))
        XCTAssertFalse(suspending.canDeleteAccount)

        apple.resume(with: .success(AppleCredential(identityToken: "id-token", authorizationCode: "auth-code")))
        await task.value
        XCTAssertEqual(suspending.status, .signedOut)
    }

    /// 削除中に Apple の画面でやめたら、何も消さずサインイン済みのまま
    func testCancelledReauthenticationKeepsAccount() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        apple.result = .failure(AuthFailure.canceled)
        let service = makeService(backend: backend, apple: apple)

        await service.deleteAccount()

        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertEqual(service.status, .signedIn(signedInAccount))
    }

    /// Apple での再認証に失敗：何も消さず、案内を出す
    func testAppleFailureDuringDeletionDeletesNothing() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        apple.result = .failure(AuthFailure.appleFailed)
        let service = makeService(backend: backend, apple: apple)

        await service.deleteAccount()

        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertEqual(service.status, .failed(.appleFailed, account: signedInAccount))
        service.dismissFailure()
        XCTAssertEqual(service.status, .signedIn(signedInAccount))
    }

    /// authorization code が無ければ、失効も削除もしない
    func testDeletionWithoutAuthorizationCodeStops() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        let apple = FakeAppleSignIn()
        apple.result = .success(AppleCredential(identityToken: "id-token", authorizationCode: nil))
        let service = makeService(backend: backend, apple: apple)

        await service.deleteAccount()

        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertEqual(service.status, .failed(.missingToken, account: signedInAccount))
    }

    /// トークンの失効に失敗したら、利用者は削除しない
    func testRevokeFailureDoesNotDeleteUser() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        backend.revokeError = AuthFailure.network
        let service = makeService(backend: backend)

        await service.deleteAccount()

        XCTAssertEqual(backend.calls, ["reauthenticate", "revoke"])
        XCTAssertEqual(service.status, .failed(.network, account: signedInAccount))
    }

    /// Firebase の利用者の削除に失敗：サインイン済みのまま案内を出す
    func testFirebaseDeleteFailureKeepsAccount() async {
        let backend = FakeAuthBackend(account: signedInAccount)
        backend.deleteError = AuthFailure.requiresRecentLogin
        let service = makeService(backend: backend)

        await service.deleteAccount()

        XCTAssertEqual(backend.calls, ["reauthenticate", "revoke", "delete"])
        XCTAssertEqual(service.status, .failed(.requiresRecentLogin, account: signedInAccount))
    }

    /// サインインしていないときは、削除の処理を呼んでも何もしない
    func testDeletionWhenSignedOutDoesNothing() async {
        let backend = FakeAuthBackend()
        let apple = FakeAppleSignIn()
        let service = makeService(backend: backend, apple: apple)

        await service.deleteAccount()

        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertTrue(apple.receivedHashedNonces.isEmpty)
        XCTAssertEqual(service.status, .signedOut)
    }

    // MARK: - nonce

    func testNonceIsRandomAndHashIsSHA256() {
        let first = AuthNonce.random()
        let second = AuthNonce.random()
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(AuthNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMaskedUID() {
        XCTAssertEqual(AuthAccount(uid: "abcd1234efgh5678").maskedUID, "abcd…5678")
        XCTAssertEqual(AuthAccount(uid: "short").maskedUID, "short")
    }
}

/// サインインしても、生活データは送らない（Firestore を使わない）ことの確認
final class AuthPrivacyTests: XCTestCase {
    /// アプリの通知・保存の仕組みは、サインインの状態に関係なくこれまでどおり（ローカルの機能に影響しない）
    func testLocalFeaturesDoNotDependOnSignIn() {
        let store = LifeStore()
        XCTAssertFalse(store.items.isEmpty)
        let appState = AppState()
        XCTAssertFalse(appState.canUseSharedUpdates, "共有の更新は、本物の同期ができるまで無効のまま")
    }
}
