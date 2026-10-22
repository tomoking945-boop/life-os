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

    /// Debug・Release とも同じ entitlements を使う。独自の URL スキームは追加しない
    func testDebugAndReleaseUseSameEntitlements() throws {
        let project = try read("LifeOS.xcodeproj/project.pbxproj")
        let lines = project.components(separatedBy: .newlines).filter { $0.contains("CODE_SIGN_ENTITLEMENTS") }
        XCTAssertEqual(lines.count, 2, "アプリの Debug と Release")
        XCTAssertTrue(lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces) == "CODE_SIGN_ENTITLEMENTS = LifeOS.entitlements;" })
        XCTAssertFalse(project.contains("CFBundleURLTypes"), "独自の URL スキームは使わない")
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

        for file in ["LifeOS/Core/Sharing/SharedLinks.swift", "LifeOS/Core/Sharing/InviteLinkCoordinator.swift", "LifeOS/Features/Sharing/InviteLinkSheet.swift"] {
            let text = try read(file)
            for word in ["print(", "NSLog", "os_log", "Logger(", "UserDefaults", "@AppStorage", "@SceneStorage", "Analytics", "\\(url", ".token)"] {
                XCTAssertFalse(text.contains(word), "\(file)：\(word)")
            }
        }
        let hosting = try read("firebase/hosting/invite/index.html")
        XCTAssertEqual(tokenInURL.numberOfMatches(in: hosting, range: NSRange(hosting.startIndex..., in: hosting)), 0)
    }
}
