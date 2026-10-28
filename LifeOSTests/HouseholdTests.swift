import XCTest
@testable import LifeOS

// わが家の作成・招待・参加（2026-10-22）のテスト。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md
// ネットワーク・実際の Firebase・実際の Apple の認証は使わない（偽物に差し替える）。
// テストで使う招待トークンは、その場で作る乱数（ソースに招待トークンを書かない）。

/// テスト用の招待トークン（32バイトの乱数を base64url にした 43 文字）
private func randomInviteToken() -> String {
    let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func randomInvite() -> (InviteLink, String) {
    let token = randomInviteToken()
    let url = URL(string: "https://\(InviteLink.host)\(InviteLink.path)?token=\(token)")!
    return (InviteLink(url: url)!, token)
}

private let ownerOnly = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)])
private let ownerAndPartner = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: true, members: [
    HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false),
])
private let partnerView = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: false, members: [
    HouseholdMember(role: .owner, isSelf: false), HouseholdMember(role: .member, isSelf: true),
])

/// サーバーの偽物（呼ばれた順番を記録する）
final class FakeHouseholdBackend: HouseholdBackend {
    var household: HouseholdSummary?
    var error: Error?
    var acceptError: Error?
    var previewResult: Result<InvitePreview, Error> = .success(InvitePreview(groupName: "池上家", sharedKinds: [.todo, .shopping, .money], expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
    var createdInvite: CreatedInvite?
    private(set) var calls: [String] = []
    private(set) var receivedTokens: [String] = []
    private(set) var createdWith: (name: String, kinds: [SharedSpaceKind])?

    func fetchMyHousehold() async throws -> HouseholdSummary? {
        calls.append("fetch")
        if let error { throw error }
        return household
    }

    func createHousehold(name: String, kinds: [SharedSpaceKind]) async throws -> HouseholdSummary {
        calls.append("create")
        if let error { throw error }
        createdWith = (name, kinds)
        let summary = HouseholdSummary(name: name, sharedKinds: kinds, isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)])
        household = summary
        return summary
    }

    func createInvite() async throws -> CreatedInvite {
        calls.append("createInvite")
        if let error { throw error }
        let invite = createdInvite ?? CreatedInvite(url: URL(string: "https://\(InviteLink.host)\(InviteLink.path)?token=\(randomInviteToken())")!, expiresAt: Date(timeIntervalSince1970: 1_800_086_400))!
        household = HouseholdSummary(name: "わが家", sharedKinds: [.todo], isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)], activeInviteExpiresAt: invite.expiresAt)
        return invite
    }

    func revokeInvite() async throws {
        calls.append("revokeInvite")
        if let error { throw error }
        household = ownerOnly
    }

    func fetchInvitePreview(token: String) async throws -> InvitePreview {
        calls.append("preview")
        receivedTokens.append(token)
        return try previewResult.get()
    }

    func acceptInvite(token: String) async throws -> HouseholdSummary {
        calls.append("accept")
        receivedTokens.append(token)
        if let acceptError { throw acceptError }
        household = partnerView
        return partnerView
    }
}

/// サインインしているかを切り替えられる
private final class SignInFlag {
    var isSignedIn: Bool
    init(_ isSignedIn: Bool) { self.isSignedIn = isSignedIn }
}

final class SharedSpaceKindTests: XCTestCase {
    /// 7種類・英語の固定の値・画面の名前・はじめの選択
    func testKindsAndTitles() {
        XCTAssertEqual(SharedSpaceKind.allCases.map(\.rawValue), ["event", "todo", "chore", "shopping", "money", "warranty", "list"])
        XCTAssertEqual(SharedSpaceKind.allCases.map(\.title), ["予定", "ToDo", "家事", "買い物", "家計簿", "保証書", "リスト・メモ"])
        XCTAssertEqual(SharedSpaceKind.defaultSelection, [.todo, .shopping])
        XCTAssertEqual(SharedSpaceKind.ordered([.shopping, .event, .todo]), [.event, .todo, .shopping])
        XCTAssertEqual(SharedSpaceKind.titles([.todo, .shopping]), "ToDo・買い物")
        // 共有項目（items）で使う4種類は、端末の予定・やることの種類と同じ値
        for kind in SharedSyncPolicy.syncableKinds {
            XCTAssertNotNil(SharedSpaceKind(rawValue: kind.rawValue), kind.rawValue)
        }
    }

    /// サーバーの決まった値（household.js）と同じ
    func testKindsMatchServer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let source = try? String(contentsOf: root.appendingPathComponent("firebase/functions/src/household.js"), encoding: .utf8) else {
            throw XCTSkip("サーバーのソースを読めない環境のため、確認を省きます")
        }
        let expected = "const SHARED_SPACE_KINDS = Object.freeze([" + SharedSpaceKind.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]);"
        XCTAssertTrue(source.contains(expected), expected)
        XCTAssertTrue(source.contains("const DEFAULT_SHARED_SPACE_KINDS = Object.freeze(['todo', 'shopping']);"))
        XCTAssertTrue(source.contains("const MAX_MEMBERS = 2;"))
        XCTAssertEqual(HouseholdRules.maxMembers, 2)
    }

    /// 作れる入力：名前（空・51文字以上・改行は不可）と、種類1つ以上
    func testCanCreate() {
        XCTAssertTrue(HouseholdRules.canCreate(name: "わが家", kinds: [.todo]))
        XCTAssertTrue(HouseholdRules.canCreate(name: " わが家 ", kinds: Set(SharedSpaceKind.allCases)))
        XCTAssertFalse(HouseholdRules.canCreate(name: "わが家", kinds: []))
        XCTAssertFalse(HouseholdRules.canCreate(name: "   ", kinds: [.todo]))
        XCTAssertFalse(HouseholdRules.canCreate(name: String(repeating: "あ", count: 51), kinds: [.todo]))
        XCTAssertTrue(HouseholdRules.canCreate(name: String(repeating: "あ", count: 50), kinds: [.todo]))
        XCTAssertFalse(HouseholdRules.canCreate(name: "わが\t家", kinds: [.todo]))
    }
}

final class HouseholdPayloadTests: XCTestCase {
    /// サーバーの返事を読む（知らない種類は無視・UID は無い）
    func testParseSummary() throws {
        let payload: [String: Any] = [
            "name": "池上家",
            "sharedKinds": ["shopping", "todo", "unknown"],
            "isOwner": true,
            "members": [["role": "owner", "isSelf": true, "joinedAt": 1000], ["role": "member", "isSelf": false, "joinedAt": 2000]],
            "maxMembers": 2,
            "activeInvite": ["expiresAt": NSNumber(value: 1_800_000_000_000)],
        ]
        let summary = try XCTUnwrap(HouseholdSummary(payload: payload))
        XCTAssertEqual(summary.name, "池上家")
        XCTAssertEqual(summary.sharedKinds, [.todo, .shopping])
        XCTAssertTrue(summary.isFull)
        XCTAssertEqual(summary.members.map(\.label), ["あなた（オーナー）", "パートナー"])
        XCTAssertEqual(summary.activeInviteExpiresAt, Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertNil(HouseholdSummary(payload: nil))
        XCTAssertNil(HouseholdSummary(payload: ["name": "x", "isOwner": true, "members": []]))
        XCTAssertNil(HouseholdSummary(payload: ["name": "x", "isOwner": true, "members": [["role": "admin", "isSelf": true]]]))
        XCTAssertEqual(HouseholdSummary(payload: ["name": "x", "isOwner": false, "members": [["role": "member", "isSelf": true]]])?.activeInviteExpiresAt, nil)
    }

    func testParsePreviewAndInvite() throws {
        let preview = try XCTUnwrap(InvitePreview(payload: ["groupName": "池上家", "sharedKinds": ["money", "todo"], "expiresAt": 1_800_000_000_000]))
        XCTAssertEqual(preview.groupName, "池上家")
        XCTAssertEqual(preview.sharedKinds, [.todo, .money])
        XCTAssertNil(InvitePreview(payload: ["groupName": "x"]))

        let token = randomInviteToken()
        let invite = try XCTUnwrap(CreatedInvite(payload: ["url": "https://\(InviteLink.host)/invite?token=\(token)", "expiresAt": 1_800_000_000_000]))
        XCTAssertEqual(invite.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        // 招待リンクの形でなければ受け取らない（別ドメインなど）
        XCTAssertNil(CreatedInvite(payload: ["url": "https://evil.example/invite?token=\(token)", "expiresAt": 1]))
        XCTAssertNil(CreatedInvite(payload: ["url": "https://\(InviteLink.host)/invite?token=short", "expiresAt": 1]))
        // 文字にしても、デバッグで中身を見ても、トークンが出ない
        XCTAssertFalse(String(describing: invite).contains(token))
        XCTAssertFalse(String(reflecting: invite).contains(token))
        var dumped = ""
        dump(invite, to: &dumped)
        XCTAssertFalse(dumped.contains(token))
    }

    /// サーバーの理由 → 画面の文言（通信・期限切れ・使用済み／取消済み・満員・別のわが家・自分の招待・未接続を区別する）
    func testFailureReasonsAndMessages() {
        XCTAssertEqual(HouseholdFailure(reason: "expired"), .expired)
        XCTAssertEqual(HouseholdFailure(reason: "already-used"), .inviteUnavailable)
        XCTAssertEqual(HouseholdFailure(reason: "revoked"), .inviteUnavailable)
        XCTAssertEqual(HouseholdFailure(reason: "not-found"), .inviteUnavailable)
        XCTAssertEqual(HouseholdFailure(reason: "household-full"), .full)
        XCTAssertEqual(HouseholdFailure(reason: "already-in-household"), .alreadyInHousehold)
        XCTAssertEqual(HouseholdFailure(reason: "already-member"), .alreadyMember)
        XCTAssertEqual(HouseholdFailure(reason: "own-invite"), .ownInvite)
        XCTAssertEqual(HouseholdFailure(reason: "not-owner"), .notOwner)
        XCTAssertEqual(HouseholdFailure(reason: "no-household"), .noHousehold)
        XCTAssertEqual(HouseholdFailure(reason: "invalid-kinds"), .invalidInput)
        XCTAssertEqual(HouseholdFailure(reason: "internal"), .other)
        XCTAssertEqual(HouseholdFailure(reason: nil), .other)

        let distinct: [HouseholdFailure] = [.network, .expired, .inviteUnavailable, .full, .alreadyInHousehold, .ownInvite, .notConnected]
        XCTAssertEqual(Set(distinct.map(\.message)).count, distinct.count, "それぞれ違う文言")
        let all: [HouseholdFailure] = distinct + [.notSignedIn, .alreadyMember, .notOwner, .noHousehold, .invalidInput, .other]
        for failure in all {
            XCTAssertFalse(failure.message.isEmpty)
            for word in ["UID", "uid", "token", "トークン", "Firebase", "error", "Error"] {
                XCTAssertFalse(failure.message.contains(word), "\(failure)：\(word)")
            }
        }
    }
}

final class HouseholdServiceTests: XCTestCase {
    private func makeService(backend: FakeHouseholdBackend? = FakeHouseholdBackend(), signedIn: Bool = true) -> (HouseholdService, FakeHouseholdBackend?, SignInFlag) {
        let flag = SignInFlag(signedIn)
        return (HouseholdService(backend: backend, isSignedIn: { flag.isSignedIn }), backend, flag)
    }

    /// Firebase 未接続：何もせず「使えない」。ほかの機能は使える
    @MainActor
    func testUnavailableWithoutFirebase() async {
        let (service, _, _) = makeService(backend: nil)
        XCTAssertEqual(service.state, .unavailable)
        await service.refresh()
        XCTAssertEqual(service.state, .unavailable)
        let created = await service.create(name: "わが家", kinds: [.todo])
        XCTAssertFalse(created)
        XCTAssertEqual(service.actionFailure, .notConnected)
        let (invite, _) = randomInvite()
        await service.loadPreview(for: invite)
        XCTAssertEqual(service.preview, .failed(.notConnected))

        let store = makeStore()
        let before = store.items.count
        store.add([LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(store.items.count, before + 1)
    }

    /// サインアウト中：サーバーを呼ばない
    @MainActor
    func testSignedOutDoesNotCallServer() async {
        let (service, backend, _) = makeService(signedIn: false)
        await service.refresh()
        XCTAssertEqual(service.state, .signedOut)
        let created = await service.create(name: "わが家", kinds: [.todo])
        XCTAssertFalse(created)
        XCTAssertEqual(service.actionFailure, .notSignedIn)
        await service.createInvite()
        XCTAssertEqual(backend?.calls, [])
    }

    /// わが家が無い・ある
    @MainActor
    func testRefresh() async {
        let (service, backend, _) = makeService()
        await service.refresh()
        XCTAssertEqual(service.state, .none)
        backend?.household = ownerAndPartner
        await service.refresh()
        XCTAssertEqual(service.state, .loaded(ownerAndPartner))
    }

    /// 通信できないときは「通信できない」。アプリのほかの機能は使える
    @MainActor
    func testNetworkFailureKeepsAppWorking() async {
        let (service, backend, _) = makeService()
        backend?.error = HouseholdFailure.network
        await service.refresh()
        XCTAssertEqual(service.state, .failed(.network))
        let store = makeStore()
        XCTAssertFalse(store.items.isEmpty)
    }

    /// 作成：名前と種類を確かめてから送る。空の種類は送らない
    @MainActor
    func testCreate() async {
        let (service, backend, _) = makeService()
        var created = await service.create(name: "わが家", kinds: [])
        XCTAssertFalse(created)
        XCTAssertEqual(service.actionFailure, .invalidInput)
        XCTAssertEqual(backend?.calls, [], "空の種類はサーバーへ送らない")

        created = await service.create(name: "  池上家  ", kinds: [.shopping, .todo])
        XCTAssertTrue(created)
        XCTAssertEqual(backend?.createdWith?.name, "池上家")
        XCTAssertEqual(backend?.createdWith?.kinds, [.todo, .shopping])
        XCTAssertEqual(service.state.summary?.name, "池上家")
        XCTAssertNil(service.actionFailure)
        XCTAssertNil(service.operation)
    }

    /// 作成：別のわが家に参加中など、サーバーの理由をそのまま伝える
    @MainActor
    func testCreateFailure() async {
        let (service, backend, _) = makeService()
        backend?.error = HouseholdFailure.alreadyInHousehold
        let created = await service.create(name: "わが家", kinds: [.todo])
        XCTAssertFalse(created)
        XCTAssertEqual(service.actionFailure, .alreadyInHousehold)
        service.dismissActionFailure()
        XCTAssertNil(service.actionFailure)
    }

    /// 招待：リンクはメモリの中だけ。取り消すと消える。サーバーに有効な招待が無くなったら、メモリからも消える
    @MainActor
    func testInviteLifecycle() async {
        let (service, backend, _) = makeService()
        backend?.household = ownerOnly
        await service.refresh()
        await service.createInvite()
        XCTAssertNotNil(service.activeInvite)
        XCTAssertEqual(service.state.summary?.activeInviteExpiresAt, service.activeInvite?.expiresAt)

        await service.revokeInvite()
        XCTAssertNil(service.activeInvite)
        XCTAssertEqual(backend?.calls.suffix(2), ["revokeInvite", "fetch"])

        await service.createInvite()
        XCTAssertNotNil(service.activeInvite)
        // パートナーが参加した（サーバーに有効な招待が無い）
        backend?.household = ownerAndPartner
        await service.refresh()
        XCTAssertNil(service.activeInvite)
    }

    /// 招待：オーナーでなければサーバーが断る（理由を伝える）
    @MainActor
    func testInviteNotOwner() async {
        let (service, backend, _) = makeService()
        backend?.error = HouseholdFailure.notOwner
        await service.createInvite()
        XCTAssertEqual(service.actionFailure, .notOwner)
        XCTAssertNil(service.activeInvite)
    }

    /// Preview では参加しない。「参加する」で参加し、トークンはサーバーへ送るだけ
    @MainActor
    func testPreviewDoesNotJoinAndJoinOnce() async {
        let (service, backend, _) = makeService()
        let (invite, token) = randomInvite()
        await service.loadPreview(for: invite)
        guard case .loaded(let preview) = service.preview else { return XCTFail("Preview を読めていない") }
        XCTAssertEqual(preview.groupName, "池上家")
        XCTAssertEqual(backend?.calls, ["preview"], "Preview だけでは参加しない")

        let joined = await service.join(invite)
        XCTAssertTrue(joined)
        XCTAssertEqual(service.preview, .joined)
        XCTAssertEqual(service.notice, "わが家に参加しました")
        XCTAssertEqual(service.state, .loaded(partnerView))
        XCTAssertEqual(backend?.receivedTokens, [token, token])

        // もう一度押しても、サーバーへは送らない（Preview を読み直していないため）
        let again = await service.join(invite)
        XCTAssertFalse(again)
        XCTAssertEqual(backend?.calls.filter { $0 == "accept" }.count, 1)
    }

    /// 参加できない理由（期限切れ・満員・自分の招待など）を伝え、参加しない
    @MainActor
    func testJoinFailures() async {
        for failure in [HouseholdFailure.expired, .inviteUnavailable, .full, .alreadyInHousehold, .ownInvite] {
            let (service, backend, _) = makeService()
            backend?.previewResult = .failure(failure)
            let (invite, _) = randomInvite()
            await service.loadPreview(for: invite)
            XCTAssertEqual(service.preview, .failed(failure))
            let joined = await service.join(invite)
            XCTAssertFalse(joined, "\(failure)")
            XCTAssertEqual(backend?.calls.contains("accept"), false)
        }

        let (service, backend, _) = makeService()
        backend?.acceptError = HouseholdFailure.full
        let (invite, _) = randomInvite()
        await service.loadPreview(for: invite)
        let joined = await service.join(invite)
        XCTAssertFalse(joined)
        XCTAssertEqual(service.preview, .failed(.full))
        XCTAssertNil(service.notice)
    }

    /// サインアウト中に受け取った招待：サインインのキャンセルでは参加しない。サインインしてから Preview を読み直す
    @MainActor
    func testSignInCancelDoesNotJoin() async {
        let flag = SignInFlag(false)
        let backend = FakeHouseholdBackend()
        let service = HouseholdService(backend: backend, isSignedIn: { flag.isSignedIn })
        let apple = FakeAppleSignIn()
        apple.result = .failure(AuthFailure.canceled)
        let auth = AuthService(backend: FakeAuthBackend(), apple: apple)
        let coordinator = InviteLinkCoordinator()
        let (invite, _) = randomInvite()
        coordinator.receive(URL(string: "https://\(InviteLink.host)\(InviteLink.path)?token=\(invite.token)")!)
        coordinator.confirm()
        XCTAssertEqual(coordinator.step, .join)

        // サインインしていない：Preview も参加もしない
        await service.loadPreview(for: invite)
        XCTAssertEqual(service.preview, .idle)
        let joinedWhileSignedOut = await service.join(invite)
        XCTAssertFalse(joinedWhileSignedOut)

        // サインインをやめた：参加しない（招待はメモリの中に残る）
        await auth.signIn()
        XCTAssertEqual(auth.status, .signedOut)
        XCTAssertEqual(backend.calls, [])
        XCTAssertNotNil(coordinator.pendingInvite)

        // サインインできたら、もう一度 Preview（まだ参加しない）
        flag.isSignedIn = true
        await service.loadPreview(for: invite)
        XCTAssertEqual(backend.calls, ["preview"])
        guard case .loaded = service.preview else { return XCTFail("Preview を読めていない") }

        // 参加できたら、招待をメモリから捨てる
        let joined = await service.join(invite)
        XCTAssertTrue(joined)
        coordinator.completeJoin()
        XCTAssertNil(coordinator.pendingInvite)
        XCTAssertEqual(coordinator.step, .joined)
    }

    /// サインアウトしたら、メモリの招待リンクも捨てる
    @MainActor
    func testSignOutClearsInvite() async {
        let (service, backend, flag) = makeService()
        backend?.household = ownerOnly
        await service.refresh()
        await service.createInvite()
        XCTAssertNotNil(service.activeInvite)
        flag.isSignedIn = false
        await service.refresh()
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(service.activeInvite)
    }
}

/// ソースの確認：UID・トークンを画面・ログ・保存に出さない（シミュレーターでテストするとき、Mac のファイルを読める）
final class HouseholdSourceTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
            throw XCTSkip("\(path) を読めない環境のため、確認を省きます")
        }
        return text
    }

    func testNoLoggingOrStorageOfTokensAndUIDs() throws {
        let files = [
            "LifeOS/Core/Sharing/HouseholdModels.swift",
            "LifeOS/Core/Sharing/HouseholdService.swift",
            "LifeOS/Core/Sharing/FirebaseHouseholdBackend.swift",
            "LifeOS/Features/Profile/HouseholdSection.swift",
            "LifeOS/Features/Profile/PartnerAccountView.swift",
            "LifeOS/Features/Sharing/InviteLinkSheet.swift",
            "LifeOS/Features/Sharing/InviteLinkEntryView.swift",
        ]
        for file in files {
            let text = try read(file)
            for word in ["print(", "NSLog", "os_log", "Logger(", "UserDefaults", "@AppStorage", "@SceneStorage", "Analytics", "localizedDescription"] {
                XCTAssertFalse(text.contains(word), "\(file)：\(word)")
            }
        }
        // 画面には UID を出さない（アカウントの番号の表示もやめた）
        for file in ["LifeOS/Features/Profile/HouseholdSection.swift", "LifeOS/Features/Profile/PartnerAccountView.swift", "LifeOS/Features/Sharing/InviteLinkSheet.swift"] {
            let text = try read(file)
            XCTAssertFalse(text.contains("maskedUID"), file)
            XCTAssertFalse(text.contains("\\(account.uid"), file)
            XCTAssertFalse(text.contains(".url)"), "\(file)：招待のリンクを文字として出さない")
        }
        // 「招待リンクを入力」はクリップボードを自動で読まない（利用者が自分で貼り付ける。2026-10-28）
        let entry = try read("LifeOS/Features/Sharing/InviteLinkEntryView.swift")
        for word in ["UIPasteboard", "PasteButton", "pasteboard", "onPasteCommand"] {
            XCTAssertFalse(entry.contains(word), word)
        }
        XCTAssertTrue(entry.contains(".privacySensitive()"), "入力欄は、アプリの切り替え画面などで隠す")
        // アプリは Firestore を使わない（わが家の情報は Cloud Functions から受け取る）
        for file in files {
            XCTAssertFalse(try read(file).contains("import FirebaseFirestore"), file)
        }
    }

    /// Cloud Functions の地域・名前がサーバーと同じ
    func testFunctionNamesMatchServer() throws {
        let backend = try read("LifeOS/Core/Sharing/FirebaseHouseholdBackend.swift")
        let server = try read("firebase/functions/index.js")
        for name in ["getMyHousehold", "createHousehold", "createInvite", "revokeInvite", "getInvitePreview", "acceptInvite"] {
            XCTAssertTrue(backend.contains("\"\(name)\""), name)
            XCTAssertTrue(server.contains("exports.\(name) = onCall({ enforceAppCheck: true }"), name)
        }
        // 地域（asia-northeast1）もサーバーと同じ
        XCTAssertTrue(backend.contains("static let region = \"asia-northeast1\""))
        XCTAssertTrue(server.contains("const REGION = 'asia-northeast1';"))
    }
}
