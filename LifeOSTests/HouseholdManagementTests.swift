import XCTest
@testable import LifeOS

// わが家の設定・削除・退出と、古い「生活グループ」画面の整理（2026-10-28。Build 7 第1段階）のテスト。
// docs/SHARED_TODO_SHOPPING_FOUNDATION.md
// ネットワーク・実際の Firebase は使わない（HouseholdTests.swift の FakeHouseholdBackend に差し替える）。

private let soleOwner = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: true, members: [HouseholdMember(role: .owner, isSelf: true)], groupID: "group-a")
private let ownerWithPartner = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: true, members: [
    HouseholdMember(role: .owner, isSelf: true), HouseholdMember(role: .member, isSelf: false),
], groupID: "group-a")
private let partner = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping], isOwner: false, members: [
    HouseholdMember(role: .owner, isSelf: false), HouseholdMember(role: .member, isSelf: true),
], groupID: "group-a")

/// テスト用の招待トークン（その場で作る乱数）
private func freshInvite() -> InviteLink {
    let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
    let token = Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return InviteLink(url: URL(string: "https://\(InviteLink.host)\(InviteLink.path)?token=\(token)")!)!
}

final class HouseholdSettingsModelTests: XCTestCase {
    /// いま同期できるのは ToDo・買い物だけ。ほかは「今後対応」
    func testSyncSupportedKinds() {
        XCTAssertEqual(SharedSpaceKind.syncSupported, [.todo, .shopping])
        XCTAssertEqual(SharedSpaceKind.comingSoon, [.event, .chore, .money, .warranty, .list])
        XCTAssertTrue(SharedSpaceKind.todo.isSyncSupported)
        XCTAssertFalse(SharedSpaceKind.money.isSyncSupported)
    }

    /// サーバー（household.js）の SYNC_SUPPORTED_KINDS と同じ
    func testSyncSupportedMatchesServer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let source = try? String(contentsOf: root.appendingPathComponent("firebase/functions/src/household.js"), encoding: .utf8) else {
            throw XCTSkip("サーバーのソースを読めない環境のため、確認を省きます")
        }
        let expected = "const SYNC_SUPPORTED_KINDS = Object.freeze([" + SharedSpaceKind.syncSupported.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]);"
        XCTAssertTrue(source.contains(expected), expected)
    }

    /// groupID を読む（人の情報ではない。無ければ nil）
    func testSummaryGroupID() throws {
        let payload: [String: Any] = ["groupID": "abc", "name": "わが家", "isOwner": true, "members": [["role": "owner", "isSelf": true]]]
        XCTAssertEqual(try XCTUnwrap(HouseholdSummary(payload: payload)).groupID, "abc")
        var withoutID = payload
        withoutID["groupID"] = NSNull()
        XCTAssertNil(try XCTUnwrap(HouseholdSummary(payload: withoutID)).groupID)
        withoutID["groupID"] = ""
        XCTAssertNil(try XCTUnwrap(HouseholdSummary(payload: withoutID)).groupID)
    }

    /// 削除できるのは1人のオーナーだけ。退出できるのはパートナーだけ
    func testDeleteAndLeavePermissions() {
        XCTAssertTrue(soleOwner.canDelete)
        XCTAssertFalse(soleOwner.canLeave)
        XCTAssertFalse(ownerWithPartner.canDelete, "2人いるときは削除できない")
        XCTAssertFalse(ownerWithPartner.canLeave, "オーナーは退出できない")
        XCTAssertFalse(partner.canDelete)
        XCTAssertTrue(partner.canLeave)
    }

    /// 種類のオン・オフ：「今後対応」の種類は残す。1つも残らない変更は不可
    func testKindsAfterSettingKeepComingSoon() {
        let mixed = HouseholdSummary(name: "わが家", sharedKinds: [.event, .todo, .shopping, .money], isOwner: false, members: partner.members)
        XCTAssertEqual(mixed.sharedKinds(afterSettingSyncKinds: [.todo]), [.event, .todo, .money])
        XCTAssertEqual(mixed.sharedKinds(afterSettingSyncKinds: []), [.event, .money], "予定・家計簿は消さない")
        XCTAssertEqual(mixed.comingSoonKinds, [.event, .money])
        // 「今後対応」の種類は、ここから足せない
        XCTAssertEqual(mixed.sharedKinds(afterSettingSyncKinds: [.todo, .warranty]), [.event, .todo, .money])
        XCTAssertNil(soleOwner.sharedKinds(afterSettingSyncKinds: []), "1つも残らない")
        XCTAssertEqual(soleOwner.sharedKinds(afterSettingSyncKinds: [.shopping]), [.shopping])
    }

    /// 「わが家で共有」を選べるのは、同期できる種類で、設定でオンのものだけ
    func testAllowsSharing() {
        let todoOnly = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .event], isOwner: true, members: soleOwner.members)
        XCTAssertTrue(todoOnly.allowsSharing(.todo))
        XCTAssertFalse(todoOnly.allowsSharing(.shopping), "オフの種類")
        XCTAssertFalse(todoOnly.allowsSharing(.event), "今後対応の種類")
    }

    /// 削除・退出の理由と文言（UID・トークンなどを出さない）
    func testNewFailureReasons() {
        XCTAssertEqual(HouseholdFailure(reason: "household-not-empty"), .householdNotEmpty)
        XCTAssertEqual(HouseholdFailure(reason: "owner-cannot-leave"), .ownerCannotLeave)
        XCTAssertEqual(HouseholdFailure(reason: "invalid-update"), .invalidInput)
        for failure in [HouseholdFailure.householdNotEmpty, .ownerCannotLeave] {
            XCTAssertFalse(failure.message.isEmpty)
            for word in ["UID", "uid", "token", "Firebase", "error"] {
                XCTAssertFalse(failure.message.contains(word), word)
            }
        }
    }
}

final class HouseholdManagementServiceTests: XCTestCase {
    private func makeService(_ household: HouseholdSummary?) -> (HouseholdService, FakeHouseholdBackend) {
        let backend = FakeHouseholdBackend()
        backend.household = household
        return (HouseholdService(backend: backend, isSignedIn: { true }), backend)
    }

    /// 名前の変更（オーナー・パートナーのどちらでも。空白は送らない）
    @MainActor
    func testRename() async {
        for summary in [soleOwner, partner] {
            let (service, backend) = makeService(summary)
            await service.refresh()
            let renamed = await service.rename(to: "  さくら家 ")
            XCTAssertTrue(renamed)
            XCTAssertEqual(backend.updatedWith.last?.name, "さくら家")
            XCTAssertEqual(backend.updatedWith.count, 1)
            XCTAssertNil(backend.updatedWith.last?.syncKinds, "種類は変えない")
            XCTAssertEqual(service.state.summary?.name, "さくら家")

            let blank = await service.rename(to: "   ")
            XCTAssertFalse(blank)
            XCTAssertEqual(service.actionFailure, .invalidInput)
            XCTAssertEqual(backend.updatedWith.count, 1, "空の名前は送らない")
        }
    }

    /// 種類の変更：送るのは ToDo・買い物のうちオンのものだけ。「今後対応」の種類は残る（テスト10の画面側）
    @MainActor
    func testSetSyncKindsKeepsComingSoon() async {
        let mixed = HouseholdSummary(name: "わが家", sharedKinds: [.todo, .shopping, .money], isOwner: false, members: partner.members)
        let (service, backend) = makeService(mixed)
        await service.refresh()
        let changed = await service.setSyncKinds([.shopping, .money])
        XCTAssertTrue(changed)
        XCTAssertEqual(backend.updatedWith.last?.syncKinds, [.shopping], "今後対応の種類は送らない")
        XCTAssertEqual(service.state.summary?.sharedKinds, [.shopping, .money])
    }

    /// テスト11：1人のオーナーは削除できる。削除のあとは「わが家なし」（サインインはそのまま）
    @MainActor
    func testSoleOwnerCanDelete() async {
        let (service, backend) = makeService(soleOwner)
        await service.refresh()
        let deleted = await service.deleteHousehold()
        XCTAssertTrue(deleted)
        XCTAssertEqual(backend.calls.last, "delete")
        XCTAssertEqual(service.state, .none)
        XCTAssertNil(service.activeInvite)
        XCTAssertEqual(service.notice, "わが家を削除しました")
        // もう一度作れる
        let created = await service.create(name: "わが家", kinds: [.todo])
        XCTAssertTrue(created)
    }

    /// テスト12：2人いるオーナーは削除できない（サーバーへも送らない。サーバーも断る）
    @MainActor
    func testOwnerWithPartnerCannotDelete() async {
        let (service, backend) = makeService(ownerWithPartner)
        await service.refresh()
        let deleted = await service.deleteHousehold()
        XCTAssertFalse(deleted)
        XCTAssertEqual(service.actionFailure, .householdNotEmpty)
        XCTAssertFalse(backend.calls.contains("delete"))
        XCTAssertEqual(service.state, .loaded(ownerWithPartner), "わが家はそのまま")

        // 画面が古くても、サーバーが断った理由をそのまま伝える
        let (stale, staleBackend) = makeService(soleOwner)
        await stale.refresh()
        staleBackend.error = HouseholdFailure.householdNotEmpty
        let staleDeleted = await stale.deleteHousehold()
        XCTAssertFalse(staleDeleted)
        XCTAssertEqual(stale.actionFailure, .householdNotEmpty)
        XCTAssertEqual(stale.state, .loaded(soleOwner))
    }

    /// パートナーは削除できない
    @MainActor
    func testPartnerCannotDelete() async {
        let (service, backend) = makeService(partner)
        await service.refresh()
        let deleted = await service.deleteHousehold()
        XCTAssertFalse(deleted)
        XCTAssertEqual(service.actionFailure, .notOwner)
        XCTAssertFalse(backend.calls.contains("delete"))
    }

    /// テスト13：パートナーは退出でき、そのあと別の招待で参加できる
    @MainActor
    func testPartnerCanLeaveAndJoinAnotherInvite() async {
        let (service, backend) = makeService(partner)
        await service.refresh()
        let left = await service.leaveHousehold()
        XCTAssertTrue(left)
        XCTAssertEqual(backend.calls.last, "leave")
        XCTAssertEqual(service.state, .none)
        XCTAssertEqual(service.notice, "わが家から退出しました")

        let invite = freshInvite()
        await service.loadPreview(for: invite)
        guard case .loaded = service.preview else { return XCTFail("招待の内容を読めていない") }
        let joined = await service.join(invite)
        XCTAssertTrue(joined)
        XCTAssertNotNil(service.state.summary)
    }

    /// テスト14：オーナーは退出できない（サーバーへも送らない）
    @MainActor
    func testOwnerCannotLeave() async {
        for summary in [soleOwner, ownerWithPartner] {
            let (service, backend) = makeService(summary)
            await service.refresh()
            let left = await service.leaveHousehold()
            XCTAssertFalse(left)
            XCTAssertEqual(service.actionFailure, .ownerCannotLeave)
            XCTAssertFalse(backend.calls.contains("leave"))
            XCTAssertEqual(service.state, .loaded(summary))
        }
    }

    /// 通信できないとき：わが家の表示はそのまま（勝手に「わが家なし」にしない）
    @MainActor
    func testNetworkFailureKeepsHousehold() async {
        let (service, backend) = makeService(partner)
        await service.refresh()
        backend.error = HouseholdFailure.network
        let left = await service.leaveHousehold()
        XCTAssertFalse(left)
        XCTAssertEqual(service.actionFailure, .network)
        XCTAssertEqual(service.state, .loaded(partner))
        let renamed = await service.rename(to: "さくら家")
        XCTAssertFalse(renamed)
        XCTAssertEqual(service.state, .loaded(partner))
    }

    /// サインインしていない・Firebase が無いときは、サーバーへ送らない
    @MainActor
    func testSignedOutOrUnavailable() async {
        let backend = FakeHouseholdBackend()
        backend.household = soleOwner
        let signedOut = HouseholdService(backend: backend, isSignedIn: { false })
        let deleted = await signedOut.deleteHousehold()
        XCTAssertFalse(deleted)
        XCTAssertTrue(backend.calls.isEmpty)
        let unavailable = HouseholdService(backend: nil, isSignedIn: { true })
        let left = await unavailable.leaveHousehold()
        XCTAssertFalse(left)
        XCTAssertEqual(unavailable.actionFailure, .notConnected)
    }
}

/// 「今日」の招待のカード：端末の中の Mock の値ではなく、Firebase のわが家の人数で決める
final class HouseholdInviteCardTests: XCTestCase {
    func testInviteCardFollowsHousehold() {
        let state = AppState()
        state.usageStyle = .shared
        let viewModel = TodayViewModel(store: LifeStore.empty(), appState: state, now: TestDates.friday)

        state.partnerJoined = false
        state.householdMemberCount = nil
        XCTAssertFalse(viewModel.showsInviteCard, "わが家が無い・読めないときは出さない（Mock の値は使わない）")
        state.householdMemberCount = 1
        XCTAssertTrue(viewModel.showsInviteCard, "わが家が自分1人のとき")
        state.householdMemberCount = 2
        XCTAssertFalse(viewModel.showsInviteCard)
        state.usageStyle = .solo
        state.householdMemberCount = 1
        XCTAssertFalse(viewModel.showsInviteCard, "一人モードでは出さない")
        // 通知の「共有の更新」は、わが家の人数では有効にしない（端末の登録がまだ無いため）
        state.householdMemberCount = 2
        XCTAssertFalse(state.canUseSharedUpdates)
    }
}

/// ソースの確認：古い「生活グループ」の画面・招待が残っていない（テスト15）
final class LegacyGroupRemovalTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func appSources() throws -> [(String, String)] {
        let appRoot = root.appendingPathComponent("LifeOS")
        guard let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                result.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text))
            }
        }
        if result.isEmpty { throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます") }
        return result
    }

    private func read(_ path: String) throws -> String {
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
            throw XCTSkip("\(path) を読めない環境のため、確認を省きます")
        }
        return text
    }

    /// 古い画面（端末の中だけの生活グループ・共有メンバー・Mock の招待）が無い
    func testLegacyScreensRemoved() throws {
        let sources = try appSources()
        for (path, text) in sources {
            for word in ["GroupSettingsView", "MembersView", "SharingFlowView", "WelcomeView", "SharedStarterView", "applySharedStarter", "\"メンバーを招待\""] {
                XCTAssertFalse(text.contains(word), "\(path)：\(word)")
            }
            // Mock の招待文（InviteMessage）は画面で使わない（定義のファイルだけ）
            if !path.hasSuffix("InviteMessage.swift") {
                XCTAssertFalse(text.contains("InviteMessage."), "\(path)：InviteMessage")
            }
            // Mock の「参加済み」は画面の判断に使わない（AppState の保存のためだけに残す）
            if !path.hasSuffix("AppState.swift") {
                XCTAssertFalse(text.contains("partnerJoined"), "\(path)：partnerJoined")
            }
            // 端末の中で印を付けるだけの「共有」は画面から呼ばない
            XCTAssertFalse(text.contains("store.share("), "\(path)：store.share")
        }
    }

    /// 端末の中の古いグループ名を、Firebase へ送らない
    func testLocalGroupNameIsNeverSent() throws {
        for path in [
            "LifeOS/Core/Sharing/HouseholdModels.swift",
            "LifeOS/Core/Sharing/HouseholdService.swift",
            "LifeOS/Core/Sharing/FirebaseHouseholdBackend.swift",
            "LifeOS/Features/Profile/HouseholdSection.swift",
            "LifeOS/Features/Profile/HouseholdSettingsView.swift",
            "LifeOS/Features/Profile/PartnerAccountView.swift",
        ] {
            let text = try read(path)
            XCTAssertFalse(text.contains("profile.groupName"), path)
            if path.contains("/Core/") {
                XCTAssertFalse(text.contains("AppState"), "\(path)：端末の設定を読まない")
            }
        }
        // 新しく使い始める人にも、端末の中だけのグループ名を聞かない
        let onboarding = OnboardingViewModel(appState: AppState(), store: LifeStore.empty(), now: TestDates.friday)
        XCTAssertFalse(onboarding.asksGroupName)
    }

    /// プロフィール・「今日」のどこから開いても、同じ「共有用アカウント・わが家」へ
    func testSingleEntryPoint() throws {
        let profile = try read("LifeOS/Features/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("PartnerAccountView(auth: auth)"))
        XCTAssertFalse(profile.contains("生活グループ"))
        XCTAssertFalse(profile.contains("共有メンバー"))
        let today = try read("LifeOS/Features/Today/TodayView.swift")
        XCTAssertTrue(today.contains("PartnerAccountView(auth: AuthService.live"))
        let section = try read("LifeOS/Features/Profile/HouseholdSection.swift")
        XCTAssertTrue(section.contains("HouseholdSettingsView(household: household)"))
    }

    /// テスト16：管理の Functions（設定・削除・退出）も App Check 必須。アプリはその名前で呼ぶ
    func testManagementFunctionsRequireAppCheck() throws {
        let backend = try read("LifeOS/Core/Sharing/FirebaseHouseholdBackend.swift")
        let server = try read("firebase/functions/index.js")
        for name in ["updateHousehold", "deleteHousehold", "leaveHousehold"] {
            XCTAssertTrue(backend.contains("\"\(name)\""), name)
            XCTAssertTrue(server.contains("exports.\(name) = onCall({ enforceAppCheck: true }"), name)
        }
    }

    /// 設定画面も UID・トークン・ログを出さない
    func testSettingsViewHasNoSecrets() throws {
        let text = try read("LifeOS/Features/Profile/HouseholdSettingsView.swift")
        for finding in InviteLinkSourceScanner.findings(in: text, ignoring: []) {
            XCTFail("HouseholdSettingsView \(finding.line)行目：\(finding.rule)")
        }
        XCTAssertFalse(text.contains("groupID"), "わが家の ID を画面に出さない")
        XCTAssertFalse(text.contains("localizedDescription"))
    }
}
