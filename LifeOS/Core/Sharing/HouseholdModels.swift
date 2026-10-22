import Foundation

// わが家の作成・招待・参加（2026-10-22）。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md
//
// 画面は Firebase SDK を直接使わない。ここで決めた型と窓口（HouseholdBackend）だけを使う。
// サーバー（Cloud Functions）は UID を返さない。アプリも UID・招待トークンを画面・ログに出さない。
// 予定・ToDo・家計簿・保証書などの生活データは、まだ送らない。

/// 共有する種類（保存する値は英語の固定の値。サーバーの firebase/functions/src/household.js の SHARED_SPACE_KINDS と同じ。テストで一致を確かめる）
///
/// わが家を作るときに「これからこの種類の共有の場所を使う」と決めるだけ。いま端末にあるデータを送る意味ではない。
enum SharedSpaceKind: String, CaseIterable, Identifiable, Hashable {
    case event
    case todo
    case chore
    case shopping
    case money
    case warranty
    case list

    var id: String { rawValue }

    /// 画面に出す名前（ここだけで決める）
    var title: String {
        switch self {
        case .event: return "予定"
        case .todo: return "ToDo"
        case .chore: return "家事"
        case .shopping: return "買い物"
        case .money: return "家計簿"
        case .warranty: return "保証書"
        case .list: return "リスト・メモ"
        }
    }

    /// はじめに選んでおく種類
    static let defaultSelection: Set<SharedSpaceKind> = [.todo, .shopping]

    /// 決まった並び（画面・送る値の並び）にそろえる
    static func ordered(_ kinds: Set<SharedSpaceKind>) -> [SharedSpaceKind] {
        allCases.filter { kinds.contains($0) }
    }

    /// 画面に出す一覧（例：ToDo・買い物）
    static func titles(_ kinds: [SharedSpaceKind]) -> String {
        kinds.map(\.title).joined(separator: "・")
    }

    /// サーバーから届いた値を読む（知らない値は無視する）
    static func parse(_ values: Any?) -> [SharedSpaceKind] {
        guard let values = values as? [Any] else { return [] }
        let kinds = Set(values.compactMap { ($0 as? String).flatMap(SharedSpaceKind.init(rawValue:)) })
        return ordered(kinds)
    }
}

/// わが家の決まりごと（サーバーと同じ）
enum HouseholdRules {
    /// わが家の名前の初期値
    static let defaultName = "わが家"
    /// 名前の長さの上限（サーバー・Security Rules と同じ）
    static let maxNameLength = 50
    /// 人数の上限（オーナー＋パートナー）
    static let maxMembers = 2

    /// 作れる入力か（名前が空でなく50文字以内・改行なし、種類が1つ以上）
    static func canCreate(name: String, kinds: Set<SharedSpaceKind>) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= maxNameLength
            && !trimmed.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            && !kinds.isEmpty
    }
}

/// わが家のメンバー（UID は持たない。自分かどうかと役割だけ）
struct HouseholdMember: Equatable {
    enum Role: String, Equatable {
        case owner
        case member
    }

    let role: Role
    let isSelf: Bool

    /// 画面に出す名前（例：あなた（オーナー）、パートナー）
    var label: String {
        switch (isSelf, role) {
        case (true, .owner): return "あなた（オーナー）"
        case (true, .member): return "あなた（パートナー）"
        case (false, .owner): return "オーナー"
        case (false, .member): return "パートナー"
        }
    }
}

/// わが家の情報（サーバーの getMyHousehold などが返す内容）
struct HouseholdSummary: Equatable {
    let name: String
    let sharedKinds: [SharedSpaceKind]
    let isOwner: Bool
    let members: [HouseholdMember]
    let maxMembers: Int
    /// 有効な招待の期限（オーナーにだけ届く。招待のリンクそのものは届かない）
    let activeInviteExpiresAt: Date?

    /// 満員か（2人そろっている）
    var isFull: Bool { members.count >= maxMembers }

    /// サーバーから届いた内容を読む。形が違えば nil
    init?(payload: Any?) {
        guard let dictionary = payload as? [String: Any],
              let name = dictionary["name"] as? String,
              let isOwner = dictionary["isOwner"] as? Bool,
              let rawMembers = dictionary["members"] as? [[String: Any]] else {
            return nil
        }
        let members = rawMembers.compactMap { raw -> HouseholdMember? in
            guard let roleText = raw["role"] as? String,
                  let role = HouseholdMember.Role(rawValue: roleText),
                  let isSelf = raw["isSelf"] as? Bool else { return nil }
            return HouseholdMember(role: role, isSelf: isSelf)
        }
        guard members.count == rawMembers.count, !members.isEmpty else { return nil }
        self.name = name
        self.sharedKinds = SharedSpaceKind.parse(dictionary["sharedKinds"])
        self.isOwner = isOwner
        self.members = members
        self.maxMembers = (dictionary["maxMembers"] as? Int) ?? HouseholdRules.maxMembers
        let invite = dictionary["activeInvite"] as? [String: Any]
        self.activeInviteExpiresAt = HouseholdPayload.date(invite?["expiresAt"])
    }

    init(name: String, sharedKinds: [SharedSpaceKind], isOwner: Bool, members: [HouseholdMember], maxMembers: Int = HouseholdRules.maxMembers, activeInviteExpiresAt: Date? = nil) {
        self.name = name
        self.sharedKinds = sharedKinds
        self.isOwner = isOwner
        self.members = members
        self.maxMembers = maxMembers
        self.activeInviteExpiresAt = activeInviteExpiresAt
    }
}

/// 参加の前に見せる招待の内容（グループ名・共有する種類・期限だけ）
struct InvitePreview: Equatable {
    let groupName: String
    let sharedKinds: [SharedSpaceKind]
    let expiresAt: Date

    init?(payload: Any?) {
        guard let dictionary = payload as? [String: Any],
              let groupName = dictionary["groupName"] as? String,
              let expiresAt = HouseholdPayload.date(dictionary["expiresAt"]) else {
            return nil
        }
        self.groupName = groupName
        self.sharedKinds = SharedSpaceKind.parse(dictionary["sharedKinds"])
        self.expiresAt = expiresAt
    }

    init(groupName: String, sharedKinds: [SharedSpaceKind], expiresAt: Date) {
        self.groupName = groupName
        self.sharedKinds = sharedKinds
        self.expiresAt = expiresAt
    }
}

/// 作った招待（リンクと期限）。リンクにはトークンが入るので、画面に文字として出さず、共有シートで送るだけ。
/// アプリを開いているあいだのメモリだけで持ち、保存しない
struct CreatedInvite: Equatable {
    let url: URL
    let expiresAt: Date

    /// サーバーから届いた内容を読む。招待リンクとして正しい形（InviteLink）でなければ nil
    init?(payload: Any?) {
        guard let dictionary = payload as? [String: Any],
              let text = dictionary["url"] as? String,
              let url = URL(string: text),
              InviteLink(url: url) != nil,
              let expiresAt = HouseholdPayload.date(dictionary["expiresAt"]) else {
            return nil
        }
        self.url = url
        self.expiresAt = expiresAt
    }

    init?(url: URL, expiresAt: Date) {
        guard InviteLink(url: url) != nil else { return nil }
        self.url = url
        self.expiresAt = expiresAt
    }
}

/// 文字にしたとき・デバッグで中身を見たときも、リンク（トークン）を出さない
extension CreatedInvite: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "CreatedInvite(リンクは表示しません)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }
}

/// サーバーから届いた値を読む小さな道具
enum HouseholdPayload {
    /// ミリ秒の数値を日時に
    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if let number = value as? Int {
            return Date(timeIntervalSince1970: Double(number) / 1000)
        }
        return nil
    }
}

/// わが家の操作がうまくいかなかった理由（画面にはここの文言だけを出す。内部のエラー・UID・トークンは出さない）
enum HouseholdFailure: Error, Equatable {
    /// 通信できない
    case network
    /// Firebase に接続していない・共有の機能を使えない
    case notConnected
    /// サインインしていない
    case notSignedIn
    /// 招待の期限切れ
    case expired
    /// 招待が使用済み・取り消し済み・見つからない
    case inviteUnavailable
    /// わが家が満員
    case full
    /// 別のわが家に参加している
    case alreadyInHousehold
    /// すでにこのわが家のメンバー
    case alreadyMember
    /// 自分で作った招待
    case ownInvite
    /// オーナーではない
    case notOwner
    /// わが家に参加していない
    case noHousehold
    /// 入力が正しくない
    case invalidInput
    /// そのほか
    case other

    /// サーバーの理由（details.reason）から
    init(reason: String?) {
        switch reason {
        case "expired": self = .expired
        case "already-used", "revoked", "not-found", "invalid-token": self = .inviteUnavailable
        case "household-full": self = .full
        case "already-in-household": self = .alreadyInHousehold
        case "already-member": self = .alreadyMember
        case "own-invite": self = .ownInvite
        case "not-owner": self = .notOwner
        case "no-household": self = .noHousehold
        case "invalid-kinds", "invalid-name": self = .invalidInput
        default: self = .other
        }
    }

    var message: String {
        switch self {
        case .network: return "通信できませんでした。電波のよい場所で、もう一度お試しください。"
        case .notConnected: return "いまは共有の機能に接続できません。くらしOSのほかの機能は、これまでどおり使えます。"
        case .notSignedIn: return "Appleでサインインしてください。"
        case .expired: return "この招待は期限（24時間）が切れています。もう一度招待してもらってください。"
        case .inviteUnavailable: return "この招待は使用済みか、取り消されています。もう一度招待してもらってください。"
        case .full: return "このわが家は満員です（2人まで）。"
        case .alreadyInHousehold: return "すでに別のわが家に参加しています。参加できるわが家は1つだけです。"
        case .alreadyMember: return "すでにこのわが家に参加しています。"
        case .ownInvite: return "自分で作った招待には参加できません。パートナーに送ってください。"
        case .notOwner: return "招待を作ったり取り消したりできるのは、オーナーだけです。"
        case .noHousehold: return "まだわが家に参加していません。"
        case .invalidInput: return "名前と共有する種類を確認してください（種類は1つ以上選びます）。"
        case .other: return "うまくいきませんでした。時間をおいて、もう一度お試しください。"
        }
    }
}

// MARK: - 窓口（テストでは偽物に差し替える）

/// わが家のサーバー（Cloud Functions）の窓口
protocol HouseholdBackend: AnyObject {
    /// 自分のわが家（参加していなければ nil）
    func fetchMyHousehold() async throws -> HouseholdSummary?
    /// わが家を作る（名前・共有する種類）
    func createHousehold(name: String, kinds: [SharedSpaceKind]) async throws -> HouseholdSummary
    /// 招待を作る（前の未使用の招待は使えなくなる）
    func createInvite() async throws -> CreatedInvite
    /// 未使用の招待を取り消す
    func revokeInvite() async throws
    /// 参加の前に招待の内容を見る（参加はしない）
    func fetchInvitePreview(token: String) async throws -> InvitePreview
    /// 招待で参加する
    func acceptInvite(token: String) async throws -> HouseholdSummary
}
