import XCTest
@testable import LifeOS

// 招待リンクの土台（2026-10-21）のテスト。docs/FIREBASE_INVITE_LINK_FOUNDATION.md
// ネットワーク・実際の Firebase・実際の Apple の認証は使わない。
// テストで使うトークンは、その場で作る乱数（ソースに招待トークンを書かない）。

/// テスト用の招待トークン（32バイトの乱数を base64url にした 43 文字。サーバーと同じ形）
private func makeToken() -> String {
    let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func inviteURL(_ token: String) -> URL {
    URL(string: "https://kurashi-os-production.web.app/invite?token=\(token)")!
}

private func parse(_ text: String) -> InviteLink? {
    guard let url = URL(string: text) else { return nil }
    return InviteLink(url: url)
}

final class InviteLinkParsingTests: XCTestCase {
    /// 1：正しいリンクだけを受け付ける
    func testAcceptsCorrectURL() throws {
        let token = makeToken()
        XCTAssertEqual(token.count, 43)
        let link = try XCTUnwrap(InviteLink(url: inviteURL(token)))
        XCTAssertEqual(link.token, token)
        XCTAssertEqual(link.fingerprint.count, 64, "SHA-256")
        XCTAssertNotEqual(link.fingerprint, token)
        // ホスト名・https の大文字・小文字は区別しない（DNS と同じ）
        XCTAssertNotNil(parse("https://KURASHI-OS-PRODUCTION.WEB.APP/invite?token=\(token)"))
        XCTAssertNotNil(parse("HTTPS://kurashi-os-production.web.app/invite?token=\(token)"))
    }

    /// 2：http は不可
    func testRejectsHTTP() {
        let token = makeToken()
        XCTAssertNil(parse("http://kurashi-os-production.web.app/invite?token=\(token)"))
        XCTAssertNil(parse("ftp://kurashi-os-production.web.app/invite?token=\(token)"))
        XCTAssertNil(parse("kurashi-os-production.web.app/invite?token=\(token)"), "scheme が無い")
    }

    /// 3：別ドメイン・似た偽ドメインは不可
    func testRejectsOtherAndLookalikeDomains() {
        let token = makeToken()
        let hosts = [
            "kurashi-os-production.firebaseapp.com",          // 同じ Hosting の別ドメイン（招待には使わない）
            "lifeos-example.web.app",
            "kurashi-os-production.web.app.evil.example",
            "evil-kurashi-os-production.web.app",
            "sub.kurashi-os-production.web.app",
            "kurashi-os-producti0n.web.app",
            "kurashi-os-production.web.ap",
            "kurashi-os-production.web.app.",                 // 末尾の点
            "xn--kurashi-os-production-.web.app",
        ]
        for host in hosts {
            XCTAssertNil(parse("https://\(host)/invite?token=\(token)"), host)
        }
        // ユーザー名・パスワード・ポート番号付き、ホストの書き換え
        XCTAssertNil(parse("https://kurashi-os-production.web.app@evil.example/invite?token=\(token)"))
        XCTAssertNil(parse("https://user@kurashi-os-production.web.app/invite?token=\(token)"))
        XCTAssertNil(parse("https://user:pass@kurashi-os-production.web.app/invite?token=\(token)"))
        XCTAssertNil(parse("https://kurashi-os-production.web.app:443/invite?token=\(token)"))
        XCTAssertNil(parse("https://kurashi-os-production.web.app:8443/invite?token=\(token)"))
        XCTAssertNil(parse("https://kurashi%2Dos-production.web.app/invite?token=\(token)"))
    }

    /// 4：別のパスは不可
    func testRejectsOtherPaths() {
        let token = makeToken()
        let paths = ["/invite/", "/Invite", "/INVITE", "/invites", "/invite/x", "/x/invite", "/", "", "//invite", "/invite%2F", "/%69nvite", "/invite.html", "/invite/index.html"]
        for path in paths {
            XCTAssertNil(parse("https://kurashi-os-production.web.app\(path)?token=\(token)"), path)
        }
    }

    /// 5：トークンなし・空・重複・ほかの項目は不可
    func testRejectsMissingEmptyDuplicateToken() {
        let token = makeToken()
        let other = makeToken()
        let base = "https://kurashi-os-production.web.app/invite"
        for query in [
            "", "?", "?token", "?token=", "?Token=\(token)", "?tok=\(token)",
            "?token=\(token)&token=\(token)", "?token=\(token)&token=\(other)",
            "?token=\(token)&", "?&token=\(token)", "?token=\(token)&from=mail", "?from=mail&token=\(token)",
        ] {
            XCTAssertNil(parse(base + query), query)
        }
        XCTAssertNil(parse(base + "?token=\(token)#x"), "# 以降があるリンク")
    }

    /// 6：不正な文字・長すぎるトークン・長すぎるリンクは不可
    func testRejectsInvalidCharactersAndLength() {
        let token = makeToken()
        let base = "https://kurashi-os-production.web.app/invite?token="
        let prefix42 = String(token.prefix(42))
        for value in [
            prefix42 + "+", prefix42 + "/", prefix42 + "=", prefix42 + ".", prefix42 + "~",
            prefix42 + "%41", String(token.prefix(40)) + "%2B", prefix42 + "%20",
            String(token.prefix(41)) + "あ",
        ] {
            XCTAssertNil(parse(base + value), value)
        }
        XCTAssertNil(parse(base + prefix42), "42文字")
        XCTAssertNil(parse(base + token + "A"), "44文字")
        XCTAssertNil(parse(base + String(repeating: "A", count: 1000)), "長すぎる")
        XCTAssertFalse(InviteLink.isValidToken(""))
        XCTAssertFalse(InviteLink.isValidToken(String(repeating: "あ", count: 43)))
        XCTAssertTrue(InviteLink.isValidToken(token))
    }

    /// 10（一部）：文字にしても、デバッグで中身を見ても、トークンが出ない
    func testDescriptionDoesNotRevealToken() throws {
        let token = makeToken()
        let link = try XCTUnwrap(InviteLink(url: inviteURL(token)))
        XCTAssertFalse(String(describing: link).contains(token))
        XCTAssertFalse(String(reflecting: link).contains(token))
        XCTAssertFalse("\(link)".contains(token))
        var dumped = ""
        dump(link, to: &dumped)
        XCTAssertFalse(dumped.contains(token))
        XCTAssertFalse(dumped.contains(link.fingerprint))
    }
}

final class InviteLinkCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> InviteLinkCoordinator {
        InviteLinkCoordinator()
    }

    /// 有効なリンクで確認画面を出す（参加の処理は無い）
    func testValidLinkPresentsPrompt() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        XCTAssertEqual(coordinator.receive(inviteURL(token)), .presented)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .prompt)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
        XCTAssertFalse(coordinator.isShowingInvalidNotice)
    }

    /// 7：表示中に同じリンクが届いても、2枚目を出さない（onOpenURL と onContinueUserActivity の両方から届いたときなど）
    func testSameLinkWhilePresentedIsNotShownTwice() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        let url = inviteURL(token)
        XCTAssertEqual(coordinator.receive(url), .presented)
        XCTAssertEqual(coordinator.receive(url), .duplicate)
        XCTAssertEqual(coordinator.receive(url), .duplicate)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .prompt)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
        XCTAssertEqual(coordinator.rememberedInviteCount, 1)
    }

    /// 「あとで」・閉じるのあと、同じ起動中に同じリンクが届いても出さない
    func testSameLinkAfterLaterOrCloseIsNotShownAgain() {
        let coordinator = makeCoordinator()
        let url = inviteURL(makeToken())
        XCTAssertEqual(coordinator.receive(url), .presented)
        coordinator.later()
        XCTAssertEqual(coordinator.receive(url), .duplicate)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.pendingInvite)

        let other = inviteURL(makeToken())
        XCTAssertEqual(coordinator.receive(other), .presented)
        coordinator.close()
        XCTAssertEqual(coordinator.receive(other), .duplicate)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.pendingInvite)
    }

    /// 「招待を確認」で共有用アカウントへ進んだあとも、同じリンクは出さない（画面もそのまま）
    func testSameLinkAfterConfirmIsNotShownAgain() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        let url = inviteURL(token)
        coordinator.receive(url)
        coordinator.confirm()
        XCTAssertEqual(coordinator.receive(url), .duplicate)
        // 2026-10-22：「招待を確認」は参加の確認へ進む（招待はメモリの中で持ったまま）
        XCTAssertEqual(coordinator.step, .join)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
        coordinator.close()
        XCTAssertEqual(coordinator.receive(url), .duplicate)
        XCTAssertFalse(coordinator.isPresented)
    }

    /// 別の正しい招待リンクは出せる
    func testDifferentValidLinkIsShown() {
        let coordinator = makeCoordinator()
        coordinator.receive(inviteURL(makeToken()))
        coordinator.later()
        let second = makeToken()
        XCTAssertEqual(coordinator.receive(inviteURL(second)), .presented)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.pendingInvite?.token, second)
        XCTAssertEqual(coordinator.rememberedInviteCount, 2)
    }

    /// アプリを起動し直す（新しく作る）と、覚えている招待は空。同じリンクをまた受け取れる
    func testNewCoordinatorStartsWithEmptyHistory() {
        let url = inviteURL(makeToken())
        let first = InviteLinkCoordinator()
        first.receive(url)
        first.later()
        XCTAssertEqual(first.receive(url), .duplicate)

        let relaunched = InviteLinkCoordinator()
        XCTAssertEqual(relaunched.rememberedInviteCount, 0)
        XCTAssertEqual(relaunched.receive(url), .presented)
    }

    /// 不正なリンクは覚えない（そのあと正しいリンクは出せる）
    func testInvalidLinkIsNotRemembered() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        XCTAssertEqual(coordinator.receive(URL(string: "https://kurashi-os-production.web.app/invite?token=\(token)&x=1")!), .invalid)
        XCTAssertEqual(coordinator.receive(URL(string: "http://kurashi-os-production.web.app/invite?token=\(token)")!), .invalid)
        XCTAssertEqual(coordinator.receive(URL(fileURLWithPath: "/tmp/a.pdf")), .ignored)
        XCTAssertEqual(coordinator.rememberedInviteCount, 0)
        coordinator.dismissInvalidNotice()
        XCTAssertEqual(coordinator.receive(inviteURL(token)), .presented)
        XCTAssertEqual(coordinator.rememberedInviteCount, 1)
    }

    /// 覚えているのは元に戻せない印だけ（「あとで」のあと、トークンはどこにも残らない）
    func testRememberedHistoryDoesNotContainToken() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        coordinator.receive(inviteURL(token))
        coordinator.later()
        var dumped = ""
        dump(coordinator, to: &dumped)
        XCTAssertFalse(dumped.contains(token))
        XCTAssertNil(coordinator.pendingInvite)
    }

    /// 別の招待リンクが届いたら、新しいほうに置き換える（確認画面は1つ）
    func testDifferentLinkReplacesPending() {
        let coordinator = makeCoordinator()
        let first = makeToken()
        let second = makeToken()
        coordinator.receive(inviteURL(first))
        coordinator.confirm()
        // 「招待を確認」で進んだ画面の上に、別の招待が届いたら、新しいほうの確認画面にする
        XCTAssertEqual(coordinator.receive(inviteURL(second)), .presented)
        XCTAssertEqual(coordinator.pendingInvite?.token, second)
        XCTAssertEqual(coordinator.step, .prompt)
    }

    /// 8：「あとで」・閉じるでトークンを捨てる
    func testLaterAndCloseDiscardToken() {
        let coordinator = makeCoordinator()
        coordinator.receive(inviteURL(makeToken()))
        coordinator.later()
        XCTAssertNil(coordinator.pendingInvite)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .prompt)

        coordinator.receive(inviteURL(makeToken()))
        coordinator.close()
        XCTAssertNil(coordinator.pendingInvite)
        XCTAssertFalse(coordinator.isPresented)
        // 何度呼んでも壊れない
        coordinator.close()
        coordinator.later()
        XCTAssertFalse(coordinator.isPresented)
    }

    /// 「招待を確認」：共有用アカウントの画面へ進む。参加の処理は無いので、トークンは捨てる
    /// 「招待を確認」：参加の確認へ進む（招待はメモリの中で持ったまま）。参加できたら捨てる。閉じても捨てる（2026-10-22）
    func testConfirmMovesToJoinAndCompleteJoinDiscardsToken() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        coordinator.receive(inviteURL(token))
        coordinator.confirm()
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .join)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
        coordinator.completeJoin()
        XCTAssertEqual(coordinator.step, .joined)
        XCTAssertNil(coordinator.pendingInvite)
        coordinator.close()
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertEqual(coordinator.step, .prompt)

        // 参加の確認で「やめる」（閉じる）：招待を捨てる
        coordinator.receive(inviteURL(makeToken()))
        coordinator.confirm()
        coordinator.close()
        XCTAssertNil(coordinator.pendingInvite)
        XCTAssertFalse(coordinator.isPresented)
        // 確認画面が出ていないときは何もしない
        coordinator.confirm()
        XCTAssertFalse(coordinator.isPresented)
    }

    /// 「招待を確認」でもサインインを始めない（AuthService の状態は変わらない）
    func testConfirmDoesNotStartSignIn() {
        let coordinator = makeCoordinator()
        let auth = AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: FakeAppleSignIn())
        let before = auth.status
        coordinator.receive(inviteURL(makeToken()))
        coordinator.confirm()
        XCTAssertEqual(auth.status, before)
    }

    /// 9：不正なリンクでも、アプリのほかの機能はそのまま使える
    func testInvalidLinkShowsGenericNoticeOnly() {
        let coordinator = makeCoordinator()
        let store = makeStore()
        let appState = AppState()
        let itemsBefore = store.items.count

        XCTAssertEqual(coordinator.receive(URL(string: "https://kurashi-os-production.web.app/invite?token=short")!), .invalid)
        XCTAssertTrue(coordinator.isShowingInvalidNotice)
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.pendingInvite)
        coordinator.dismissInvalidNotice()
        XCTAssertFalse(coordinator.isShowingInvalidNotice)

        // はじめての設定の途中などでは、案内も出さない
        XCTAssertEqual(coordinator.receive(URL(string: "https://evil.example/invite")!, allowsNotice: false), .invalid)
        XCTAssertFalse(coordinator.isShowingInvalidNotice)

        // https・http 以外は招待と関係ないので、何もしない
        XCTAssertEqual(coordinator.receive(URL(fileURLWithPath: "/tmp/a.pdf")), .ignored)
        XCTAssertFalse(coordinator.isShowingInvalidNotice)

        // 予定・ToDo などはこれまでどおり使える
        store.add([LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .personal, date: TestDates.friday)])
        XCTAssertEqual(store.items.count, itemsBefore + 1)
        XCTAssertEqual(appState.selectedTab, .today)
    }

    /// 確認画面を出しているときに不正なリンクが届いても、確認画面はそのまま（案内を重ねない）
    func testInvalidLinkWhilePresentingKeepsPrompt() {
        let coordinator = makeCoordinator()
        let token = makeToken()
        coordinator.receive(inviteURL(token))
        XCTAssertEqual(coordinator.receive(URL(string: "https://kurashi-os-production.web.app/other")!), .invalid)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertFalse(coordinator.isShowingInvalidNotice)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
    }
}

/// 10〜12：ソース・設定の確認（シミュレーターでテストするとき、Mac のファイルを読める）
final class InviteLinkConfigurationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) を読めない環境のため、確認を省きます")
        }
        return text
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let url = root.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("\(relativePath) を読めない環境のため、確認を省きます")
        }
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// 11：Associated Domains は招待のドメインだけ（ワイルドカードなし）
    func testAssociatedDomainsContainOnlyInviteDomain() throws {
        let entitlements = try plist("LifeOS.entitlements")
        let domains = try XCTUnwrap(entitlements["com.apple.developer.associated-domains"] as? [String])
        XCTAssertEqual(domains, ["applinks:\(InviteLink.host)"])
        XCTAssertFalse(domains.contains { $0.contains("*") })
    }

    /// 12：App Attest と Sign in with Apple が残っている
    func testExistingEntitlementsRemain() throws {
        let entitlements = try plist("LifeOS.entitlements")
        XCTAssertEqual(entitlements["com.apple.developer.applesignin"] as? [String], ["Default"])
        XCTAssertEqual(entitlements["com.apple.developer.devicecheck.appattest-environment"] as? String, "production")
        XCTAssertEqual(Set(entitlements.keys), [
            "com.apple.developer.applesignin",
            "com.apple.developer.devicecheck.appattest-environment",
            "com.apple.developer.associated-domains",
        ])
    }

    /// Debug・Release とも同じ entitlements と Info.plist を使う。テストのターゲットには付けない
    /// （2026-10-28：設定のブロックごとに読んで確かめる。前は行の一部の文字で探していたため、
    /// `GENERATE_INFOPLIST_FILE = YES;` を `INFOPLIST_FILE =` と取り違えていた）
    func testDebugAndReleaseUseSameEntitlements() throws {
        let project = try read("LifeOS.xcodeproj/project.pbxproj")
        let configurations = InviteLinkProjectSettings.buildConfigurations(in: project)
        XCTAssertEqual(configurations.count, 6, "プロジェクト・アプリ・テストの Debug と Release")

        let app = configurations.filter { $0.settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.tomoking945boop.lifeos" }
        let tests = configurations.filter { $0.settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.tomoking945boop.lifeos.tests" }
        let projectLevel = configurations.filter { $0.settings["PRODUCT_BUNDLE_IDENTIFIER"] == nil }
        XCTAssertEqual(Set(app.map(\.name)), ["Debug", "Release"])
        XCTAssertEqual(Set(tests.map(\.name)), ["Debug", "Release"])
        XCTAssertEqual(Set(projectLevel.map(\.name)), ["Debug", "Release"])

        // アプリ：Debug・Release とも同じ entitlements・Info.plist（URL Scheme）
        for configuration in app {
            let settings = configuration.settings
            XCTAssertEqual(settings["CODE_SIGN_ENTITLEMENTS"], "LifeOS.entitlements", configuration.name)
            XCTAssertEqual(settings["INFOPLIST_FILE"], "LifeOS-Info.plist", configuration.name)
            XCTAssertEqual(settings["GENERATE_INFOPLIST_FILE"], "YES", configuration.name)
            XCTAssertEqual(settings["INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"], "NO", configuration.name)
        }
        // テスト・プロジェクト全体：entitlements も Info.plist の URL Scheme も付けない
        for configuration in tests + projectLevel {
            XCTAssertNil(configuration.settings["CODE_SIGN_ENTITLEMENTS"], configuration.name)
            XCTAssertNil(configuration.settings["INFOPLIST_FILE"], configuration.name)
        }
        // Build・Version は、アプリとテストの Debug・Release の4か所で同じ
        let builds = Set((app + tests).compactMap { $0.settings["CURRENT_PROJECT_VERSION"] })
        let versions = Set((app + tests).compactMap { $0.settings["MARKETING_VERSION"] })
        XCTAssertEqual(builds.count, 1, "Build 番号がそろっていない：\(builds.sorted())")
        XCTAssertEqual(versions, ["1.0"])
        XCTAssertEqual((app + tests).compactMap { $0.settings["CURRENT_PROJECT_VERSION"] }.count, 4)

        // ファイル全体でも、行の頭が一致するものだけを数える（ほかの設定の名前の一部とは取り違えない）
        let lines = project.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(lines.filter { $0.hasPrefix("CODE_SIGN_ENTITLEMENTS = ") }, Array(repeating: "CODE_SIGN_ENTITLEMENTS = LifeOS.entitlements;", count: 2))
        XCTAssertEqual(lines.filter { $0.hasPrefix("INFOPLIST_FILE = ") }, Array(repeating: "INFOPLIST_FILE = \"LifeOS-Info.plist\";", count: 2))
        XCTAssertFalse(project.contains("CFBundleURLTypes"), "URL Scheme はプロジェクトの設定ではなく LifeOS-Info.plist に書く")
    }

    /// 設定の読み取りそのものが正しいか（取り違えないことを、小さな例で確かめる）
    func testProjectSettingsParserDoesNotConfuseSimilarNames() {
        let sample = """
        \t\tA /* Debug */ = {
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {
        \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
        \t\t\t\tINFOPLIST_FILE = "LifeOS-Info.plist";
        \t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
        \t\t\t\t\t"$(inherited)",
        \t\t\t\t);
        \t\t\t};
        \t\t\tname = Debug;
        \t\t};
        \t\tB /* Release */ = {
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {
        \t\t\t\tGENERATE_INFOPLIST_FILE = YES;
        \t\t\t};
        \t\t\tname = Release;
        \t\t};
        """
        let configurations = InviteLinkProjectSettings.buildConfigurations(in: sample)
        XCTAssertEqual(configurations.map(\.name), ["Debug", "Release"])
        guard configurations.count == 2 else { return XCTFail("設定を2つ読めていない") }
        XCTAssertEqual(configurations[0].settings["INFOPLIST_FILE"], "LifeOS-Info.plist")
        XCTAssertEqual(configurations[0].settings["GENERATE_INFOPLIST_FILE"], "YES")
        XCTAssertNil(configurations[1].settings["INFOPLIST_FILE"], "GENERATE_INFOPLIST_FILE を INFOPLIST_FILE と取り違えない")
    }

    /// くらしOS専用の URL Scheme：Bundle ID と同じ名前が1つだけ（2026-10-28）
    func testAppURLSchemeIsRegisteredOnce() throws {
        let info = try plist("LifeOS-Info.plist")
        let types = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(types[0]["CFBundleURLSchemes"] as? [String], [InviteLink.appScheme])
        XCTAssertEqual(InviteLink.appScheme, "com.tomoking945boop.lifeos", "Bundle ID と同じ名前（ほかのアプリと重なりにくい）")
        XCTAssertEqual(Set(info.keys), ["CFBundleURLTypes"], "ほかの設定は Xcode が作る（GENERATE_INFOPLIST_FILE）")
        // 案内ページのボタンも同じ名前を使う
        let page = try read("firebase/hosting/invite/invite.js")
        XCTAssertTrue(page.contains("var APP_SCHEME = '\(InviteLink.appScheme)';"))
    }

    /// ドメインが、サーバーが作る招待リンク・AASA・Firebase の設定と一致する
    func testDomainMatchesServerAndAASA() throws {
        // サーバー（index.js）：https://<プロジェクト ID>.web.app/invite?token=…
        let functions = try read("firebase/functions/index.js")
        XCTAssertTrue(functions.contains("return `https://${projectID}.web.app`;"))
        let invites = try read("firebase/functions/src/invites.js")
        XCTAssertTrue(invites.contains("return `${base}/invite?token=${encodeURIComponent(token)}`;"))
        XCTAssertTrue(invites.contains("const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;"))
        // プロジェクト ID
        let google = try plist("LifeOS/GoogleService-Info.plist")
        let projectID = try XCTUnwrap(google["PROJECT_ID"] as? String)
        XCTAssertEqual("\(projectID).web.app", InviteLink.host)
        // AASA：Team ID・Bundle ID・パス
        let aasaText = try read("firebase/hosting/.well-known/apple-app-site-association")
        let aasa = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(aasaText.utf8)) as? [String: Any])
        let details = try XCTUnwrap((aasa["applinks"] as? [String: Any])?["details"] as? [[String: Any]])
        XCTAssertEqual(details.count, 1)
        XCTAssertEqual(details[0]["appIDs"] as? [String], ["A8D9YY866R.com.tomoking945boop.lifeos"])
        let components = try XCTUnwrap(details[0]["components"] as? [[String: Any]])
        XCTAssertEqual(components.first?["/"] as? String, InviteLink.path)
        XCTAssertEqual((components.first?["?"] as? [String: String])?["token"], "?*")
    }

    /// 10：ソース・設定に招待トークンを書かない。招待の処理はログ・保存をしない
    func testNoHardcodedTokensOrLogging() throws {
        let appSource = root.appendingPathComponent("LifeOS")
        guard let enumerator = FileManager.default.enumerator(at: appSource, includingPropertiesForKeys: nil) else {
            throw XCTSkip("アプリのソースを読めない環境のため、確認を省きます")
        }
        let quotedToken = try NSRegularExpression(pattern: "\"[A-Za-z0-9_-]{43}\"")
        let tokenInURL = try NSRegularExpression(pattern: "token=[A-Za-z0-9_-]{8,}")
        var checked = 0
        for case let url as URL in enumerator where ["swift", "plist", "entitlements", "xcconfig", "json"].contains(url.pathExtension) {
            checked += 1
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertEqual(quotedToken.numberOfMatches(in: text, range: range), 0, url.lastPathComponent)
            XCTAssertEqual(tokenInURL.numberOfMatches(in: text, range: range), 0, url.lastPathComponent)
        }
        try XCTSkipIf(checked == 0, "アプリのソースを読めない環境のため、確認を省きます")

        // ログ・保存・トークンの表示：言葉の一部ではなく、言葉そのものとして探す
        // （2026-10-28：前は「print(」を文字で探していたため、`fingerprint(of:)` の一部を取り違えていた）
        for file in [
            "LifeOS/Core/Sharing/SharedLinks.swift",
            "LifeOS/Core/Sharing/InviteLinkCoordinator.swift",
            "LifeOS/Features/Sharing/InviteLinkSheet.swift",
            "LifeOS/Features/Sharing/InviteLinkEntryView.swift",
        ] {
            let text = try read(file)
            for finding in InviteLinkSourceScanner.findings(in: text) {
                XCTFail("\(file) \(finding.line)行目：\(finding.rule)")
            }
        }
        let hosting = try read("firebase/hosting/invite/index.html")
        XCTAssertEqual(tokenInURL.numberOfMatches(in: hosting, range: NSRange(hosting.startIndex..., in: hosting)), 0)
    }
}

/// くらしOS専用の URL Scheme と「招待リンクを入力」（2026-10-28。docs/INVITE_OPEN_BUTTON_FIX.md）
final class InviteLinkAppSchemeTests: XCTestCase {
    private func schemeURL(_ token: String) -> URL {
        URL(string: "com.tomoking945boop.lifeos://invite?token=\(token)")!
    }

    /// 2：正しい URL Scheme は、Universal Link と同じように受け付ける
    func testAcceptsAppScheme() throws {
        let token = makeToken()
        let link = try XCTUnwrap(InviteLink(url: schemeURL(token)))
        XCTAssertEqual(link.token, token)
        XCTAssertEqual(link, InviteLink(url: inviteURL(token)), "同じトークンなら同じ招待")
        XCTAssertNotNil(parse("COM.TOMOKING945BOOP.LIFEOS://invite?token=\(token)"), "スキームの大文字・小文字は区別しない")
    }

    /// 3〜5：URL Scheme でも確かめ方は省かない（トークンなし・形・場所・別のスキーム・別ホスト）
    func testRejectsInvalidAppSchemeURLs() {
        let token = makeToken()
        let other = makeToken()
        let base = "com.tomoking945boop.lifeos://"
        for text in [
            base + "invite", base + "invite?", base + "invite?token=", base + "invite?token",
            base + "invite?token=\(token.prefix(42))", base + "invite?token=\(token)A",
            base + "invite?token=\(token.prefix(42))+", base + "invite?token=\(token.prefix(40))%41",
            base + "invite?token=\(token)&token=\(other)", base + "invite?token=\(token)&x=1",
            base + "invite?token=\(token)#x", base + "invite/?token=\(token)", base + "invite/x?token=\(token)",
            base + "join?token=\(token)", base + "?token=\(token)", base + "user@invite?token=\(token)",
            base + "invite:80?token=\(token)",
            "kurashios://invite?token=\(token)", "com.tomoking945boop.lifeos.evil://invite?token=\(token)",
            "lifeos://invite?token=\(token)", "https://evil.example/invite?token=\(token)",
            "http://kurashi-os-production.web.app/invite?token=\(token)",
        ] {
            XCTAssertNil(parse(text), text)
        }
    }

    /// 9：貼り付けた文字も同じ判定（前後の空白・改行は除く。途中の空白・URL でない文字は不可）
    func testPastedTextUsesSameValidation() throws {
        let token = makeToken()
        XCTAssertEqual(InviteLink(text: "  https://kurashi-os-production.web.app/invite?token=\(token)\n")?.token, token)
        XCTAssertEqual(InviteLink(text: "com.tomoking945boop.lifeos://invite?token=\(token)")?.token, token)
        for text in ["", "   ", token, "token=\(token)", "招待 https://kurashi-os-production.web.app/invite?token=\(token)",
                     "https://kurashi-os-production.web.app/invite?token=\(token) ありがとう",
                     "https://kurashi-os-production.web.app/invite?token=short",
                     "https://evil.example/invite?token=\(token)", String(repeating: "a", count: 300)] {
            XCTAssertNil(InviteLink(text: text), text)
        }
    }
}

final class InviteLinkReceivingRoutesTests: XCTestCase {
    private func schemeURL(_ token: String) -> URL {
        URL(string: "com.tomoking945boop.lifeos://invite?token=\(token)")!
    }

    /// 1・2：Universal Link でも URL Scheme でも、同じ確認画面へ進む
    func testBothRoutesPresentSamePrompt() {
        let byLink = InviteLinkCoordinator()
        let token = makeToken()
        XCTAssertEqual(byLink.receive(inviteURL(token)), .presented)
        XCTAssertEqual(byLink.step, .prompt)

        let byScheme = InviteLinkCoordinator()
        XCTAssertEqual(byScheme.receive(schemeURL(token)), .presented)
        XCTAssertEqual(byScheme.step, .prompt)
        XCTAssertEqual(byScheme.pendingInvite, byLink.pendingInvite)
    }

    /// 7：同じ招待は、Universal Link と URL Scheme の両方から届いても1回だけ
    func testSameInviteFromBothRoutesIsNotShownTwice() {
        let coordinator = InviteLinkCoordinator()
        let token = makeToken()
        XCTAssertEqual(coordinator.receive(inviteURL(token)), .presented)
        XCTAssertEqual(coordinator.receive(schemeURL(token)), .duplicate)
        coordinator.later()
        XCTAssertEqual(coordinator.receive(schemeURL(token)), .duplicate)
        XCTAssertEqual(coordinator.rememberedInviteCount, 1)
    }

    /// 8：不正な URL Scheme は「使用できません」の案内だけ。覚えない
    func testInvalidAppSchemeIsNotRemembered() {
        let coordinator = InviteLinkCoordinator()
        XCTAssertEqual(coordinator.receive(URL(string: "com.tomoking945boop.lifeos://invite?token=short")!), .invalid)
        XCTAssertTrue(coordinator.isShowingInvalidNotice)
        XCTAssertEqual(coordinator.rememberedInviteCount, 0)
        XCTAssertNil(coordinator.pendingInvite)
        // 関係のないスキームは何もしない
        XCTAssertEqual(coordinator.receive(URL(string: "mailto:a@example.com")!), .ignored)
    }

    /// 6：リンクを受け取っただけでは、サインイン・Preview・参加のどれも呼ばない
    @MainActor
    func testReceivingDoesNotStartSignInOrJoin() async {
        let backend = FakeHouseholdBackend()
        let apple = FakeAppleSignIn()
        let authBackend = FakeAuthBackend()
        let auth = AuthService(backend: authBackend, apple: apple)
        let household = HouseholdService(backend: backend, isSignedIn: { auth.account != nil })
        let coordinator = InviteLinkCoordinator()
        let token = makeToken()

        coordinator.receive(inviteURL(token))
        coordinator.receive(schemeURL(makeToken()))
        _ = coordinator.submitManualEntry("https://kurashi-os-production.web.app/invite?token=\(makeToken())")
        coordinator.confirm()

        XCTAssertEqual(apple.receivedHashedNonces, [], "Apple のサインイン画面は出ない")
        XCTAssertEqual(authBackend.calls, [], "Firebase へのサインインもしない")
        XCTAssertEqual(auth.status, .signedOut)
        XCTAssertEqual(backend.calls, [], "Preview・参加・Firestore への書き込みはしない")
        XCTAssertEqual(household.preview, .idle)
    }

    /// 9：「招待リンクを入力」も同じ判定。不正なら案内の画面を出さずに入力欄で知らせる。覚えない
    func testManualEntry() {
        let coordinator = InviteLinkCoordinator()
        XCTAssertEqual(coordinator.submitManualEntry("https://kurashi-os-production.web.app/invite?token=short"), .invalid)
        XCTAssertEqual(coordinator.submitManualEntry("よろしく"), .invalid)
        XCTAssertFalse(coordinator.isShowingInvalidNotice, "入力欄の下で知らせるので、全体の案内は出さない")
        XCTAssertEqual(coordinator.rememberedInviteCount, 0)
        XCTAssertFalse(coordinator.isPresented)

        let token = makeToken()
        XCTAssertEqual(coordinator.submitManualEntry("  com.tomoking945boop.lifeos://invite?token=\(token)  "), .presented)
        XCTAssertEqual(coordinator.pendingInvite?.token, token)
        XCTAssertEqual(coordinator.step, .prompt)
        XCTAssertEqual(coordinator.submitManualEntry("https://kurashi-os-production.web.app/invite?token=\(token)"), .alreadyShowing, "表示中の同じ招待は重ねない")
        XCTAssertEqual(coordinator.receive(inviteURL(token)), .duplicate)
    }

    /// 自分で入力したときは、前に「あとで」で閉じた同じ招待でも、もう一度確認画面を出す
    func testManualEntryCanReopenDismissedInvite() {
        let coordinator = InviteLinkCoordinator()
        let token = makeToken()
        coordinator.receive(inviteURL(token))
        coordinator.later()
        XCTAssertEqual(coordinator.receive(inviteURL(token)), .duplicate, "リンクから届いたものは重ねない")
        XCTAssertEqual(coordinator.submitManualEntry("https://kurashi-os-production.web.app/invite?token=\(token)"), .presented)
        XCTAssertTrue(coordinator.isPresented)
    }

    /// 10：トークンは保存しない（「あとで」のあと、メモリの中にも残らない）
    func testTokenIsNotKeptAfterLater() {
        let coordinator = InviteLinkCoordinator()
        let token = makeToken()
        _ = coordinator.submitManualEntry("com.tomoking945boop.lifeos://invite?token=\(token)")
        coordinator.later()
        var dumped = ""
        dump(coordinator, to: &dumped)
        XCTAssertFalse(dumped.contains(token))
        XCTAssertNil(coordinator.pendingInvite)
    }
}

/// project.pbxproj のビルド設定（XCBuildConfiguration）を、ブロックごとに読む（テスト用）
enum InviteLinkProjectSettings {
    struct BuildConfiguration {
        let name: String
        let settings: [String: String]
    }

    static func buildConfigurations(in project: String) -> [BuildConfiguration] {
        project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst().compactMap { block -> BuildConfiguration? in
            guard let open = block.range(of: "buildSettings = {"),
                  let close = block.range(of: "\n\t\t\t};", range: open.upperBound..<block.endIndex) else {
                return nil
            }
            var settings: [String: String] = [:]
            for line in block[open.upperBound..<close.lowerBound].components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasSuffix(";"), let separator = trimmed.range(of: " = ") else { continue }
                let key = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let value = String(trimmed[separator.upperBound...].dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                settings[key] = value
            }
            let nameLine = block[close.upperBound...].components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("name = ") && $0.hasSuffix(";") }
            guard let nameLine else { return nil }
            let name = String(nameLine.dropFirst("name = ".count).dropLast())
            return BuildConfiguration(name: name, settings: settings)
        }
    }
}

/// 招待の処理のソースに、ログ・保存・トークンの表示が無いかを、言葉そのものとして探す（テスト用）
enum InviteLinkSourceScanner {
    struct Finding: Equatable {
        let line: Int
        let rule: String
    }

    /// 探す言葉（前後が別の言葉の一部でないものだけ。例：`fingerprint(` は `print(` ではない）
    static let rules: [(name: String, pattern: String)] = [
        ("print(", #"(?<![A-Za-z0-9_])print\("#),
        ("debugPrint(", #"(?<![A-Za-z0-9_])debugPrint\("#),
        ("dump(", #"(?<![A-Za-z0-9_.])dump\("#),
        ("NSLog", #"(?<![A-Za-z0-9_])NSLog(?![A-Za-z0-9_])"#),
        ("os_log", #"(?<![A-Za-z0-9_])os_log(?![A-Za-z0-9_])"#),
        ("Logger(", #"(?<![A-Za-z0-9_])Logger\("#),
        ("OSLog", #"(?<![A-Za-z0-9_])OSLog(?![A-Za-z0-9_])"#),
        ("UserDefaults", #"(?<![A-Za-z0-9_])UserDefaults(?![A-Za-z0-9_])"#),
        ("@AppStorage", #"@AppStorage(?![A-Za-z0-9_])"#),
        ("@SceneStorage", #"@SceneStorage(?![A-Za-z0-9_])"#),
        ("Analytics", #"(?<![A-Za-z0-9_])Analytics(?![A-Za-z0-9_])"#),
        ("Crashlytics", #"(?<![A-Za-z0-9_])Crashlytics(?![A-Za-z0-9_])"#),
        ("UIPasteboard", #"(?<![A-Za-z0-9_])UIPasteboard(?![A-Za-z0-9_])"#),
        // 決まりの名前は「\(url」という文字そのもの（文字列の補間ではない）なので、raw string で書く（2026-10-28 修正）
        (#"URL の文字への埋め込み \(url"#, #"\\\(url"#),
        (tokenArgumentRule, #"\.token\)"#),
    ]

    /// トークンを関数に渡すところ（サーバーへ送る決まった2か所以外にあってはいけない）
    static let tokenArgumentRule = "トークンを関数に渡す（.token)）"

    /// - Parameter ignoring: 調べない決まり（名前）。理由のある場所で、別の確かめ方をするときだけ使う
    static func findings(in text: String, ignoring: Set<String> = []) -> [Finding] {
        var result: [Finding] = []
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for rule in rules where !ignoring.contains(rule.name) {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else {
                    result.append(Finding(line: index + 1, rule: "探し方が壊れている：\(rule.name)"))
                    continue
                }
                if regex.firstMatch(in: line, range: range) != nil {
                    result.append(Finding(line: index + 1, rule: rule.name))
                }
            }
        }
        return result
    }
}

/// 探し方そのものが正しいか（見落とさない・取り違えない）
final class InviteLinkSourceScannerTests: XCTestCase {
    func testFindsRealLoggingAndStorage() {
        let samples = [
            "print(token)", "    print(\"x\")", "debugPrint(link)", "dump(invite)", "NSLog(\"%@\", x)", "os_log(.info, \"x\")",
            "let logger = Logger(subsystem: \"a\", category: \"b\")", "import OSLog", "UserDefaults.standard.set(x, forKey: \"k\")",
            "@AppStorage(\"k\") var k = \"\"", "@SceneStorage(\"k\") var k = \"\"", "Analytics.logEvent(\"x\")",
            "Crashlytics.crashlytics().log(x)", "UIPasteboard.general.string", "Text(\"\\(url)\")", "show(invite.token)",
        ]
        for sample in samples {
            XCTAssertFalse(InviteLinkSourceScanner.findings(in: sample).isEmpty, "見落とし：\(sample)")
        }
    }

    func testDoesNotConfuseSafeWords() {
        let samples = [
            "private func fingerprint(of invite: InviteLink) -> Data {",
            "guard receivedFingerprints.insert(fingerprint(of: invite)).inserted else {",
            "static let appScheme = \"com.tomoking945boop.lifeos\"",
            "items[0].name == \"token\",",
            "Data(invite.token.utf8)",
            "/// 形：com.tomoking945boop.lifeos://invite?token=<43文字>",
            "let blueprint = 1",
        ]
        for sample in samples {
            XCTAssertEqual(InviteLinkSourceScanner.findings(in: sample), [], "取り違え：\(sample)")
        }
    }

    func testReportsLineNumber() {
        let text = "let a = 1\nlet b = 2\nprint(a)\n"
        XCTAssertEqual(InviteLinkSourceScanner.findings(in: text), [InviteLinkSourceScanner.Finding(line: 3, rule: "print(")])
    }
}
