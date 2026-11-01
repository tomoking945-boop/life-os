import Foundation
import Observation

// わが家で共有する ToDo・買い物（2026-10-28。Build 7 第2段階）。docs/SHARED_TODO_SHOPPING_FOUNDATION.md
//
// - 端末の個人データは、これまでどおり端末の中（life-store.json）だけ。形も変えない
// - 共有するのは、利用者が「わが家で共有」を選んだ ToDo・買い物と、カレンダーの「予定を追加」で選んだ予定（Build 14）だけ。
//   保存先は Firestore の groups/{groupID}/items/{itemID}（予定も同じ場所。別の仕組みは作らない）
// - 既存のデータを一括で送らない。AI・自動の分類が「共有」を選ぶこともない
// - 文書の ID は端末の項目の UUID（同じ操作をくり返しても1件のまま。共有への変換でも二重にならない）
// - 送る項目は決まった項目だけ（SharedItemPayload）。UID はアプリの画面・ログに出さない（作成者・更新者は Firebase の窓口が付ける）

/// 保存先（作るとき・編集するときに選ぶ）。初期値は必ず「自分だけ」
enum SaveDestination: String, CaseIterable, Identifiable, Hashable {
    /// 端末の中だけ（これまでどおり）
    case personal
    /// わが家で共有（Firestore）
    case household

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "自分だけ"
        case .household: return "わが家で共有"
        }
    }

    /// 初期値（必ず「自分だけ」）
    static let initial: SaveDestination = .personal
}

/// わが家で共有できる項目の種類（Build 7：ToDo・買い物。2026-11-01 Build 14：カレンダーから作る予定も）
enum HouseholdItemPolicy {
    static let kinds: Set<LifeItemKind> = [.event, .todo, .shopping]

    /// 共有の保存先へ送れる項目か（予定・ToDo・買い物で、名前が空でない）
    static func canShare(_ item: LifeItem) -> Bool {
        kinds.contains(item.kind) && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 送る形（Firestore に依存しない。テストで送る項目を確かめる）

/// Firestore に書く値（Firestore の型に頼らずに表す）
enum SharedItemValue: Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case date(Date)
    case null
    /// サーバーの時刻（FieldValue.serverTimestamp()）
    case serverTimestamp
    /// サインインしている本人の UID（Firebase の窓口が入れる。アプリの画面・ログには出さない）
    case currentUser
}

/// groups/{groupID}/items/{itemID} に書く内容・読む内容
enum SharedItemPayload {
    /// 保存の形の版
    static let schemaVersion = 1
    /// 名前の長さの上限（Security Rules の title と同じ 200）
    static let maxTitleLength = 200

    /// 作るときに送る項目（決まった項目だけ）。共有できない項目なら nil
    /// 送るもの：schemaVersion・kind・title・date・hasTime・isCompleted・assigneeUID（いまは常に null）・
    /// deferredTo・droppedAt（あれば）・createdBy・updatedBy・createdAt・updatedAt
    /// 送らないもの：柔らかい時間・暮らしメモリーとのつながり・担当（自分／パートナー）・端末の中の持ち主の区別
    static func createFields(for item: LifeItem) -> [String: SharedItemValue]? {
        guard HouseholdItemPolicy.canShare(item) else { return nil }
        var fields: [String: SharedItemValue] = [
            "schemaVersion": .int(schemaVersion),
            "kind": .string(item.kind.rawValue),
            "title": .string(title(item.title)),
            "date": .date(item.date),
            "hasTime": .bool(item.hasTime),
            "isCompleted": .bool(item.isCompleted),
            "assigneeUID": .null,
            "createdBy": .currentUser,
            "updatedBy": .currentUser,
            "createdAt": .serverTimestamp,
            "updatedAt": .serverTimestamp,
        ]
        if let deferredTo = item.deferredTo { fields["deferredTo"] = .date(deferredTo) }
        if let droppedAt = item.droppedAt { fields["droppedAt"] = .date(droppedAt) }
        return fields
    }

    /// 変えるときに送る項目（種類・作成者・作成日時・担当・schemaVersion は送らない＝変えない）
    static func updateFields(for item: LifeItem) -> [String: SharedItemValue]? {
        guard HouseholdItemPolicy.canShare(item) else { return nil }
        return [
            "title": .string(title(item.title)),
            "date": .date(item.date),
            "hasTime": .bool(item.hasTime),
            "isCompleted": .bool(item.isCompleted),
            "deferredTo": item.deferredTo.map { SharedItemValue.date($0) } ?? SharedItemValue.null,
            "droppedAt": item.droppedAt.map { SharedItemValue.date($0) } ?? SharedItemValue.null,
            "updatedBy": .currentUser,
            "updatedAt": .serverTimestamp,
        ]
    }

    /// 名前（前後の空白を除き、上限まで）
    static func title(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.count > maxTitleLength else { return trimmed }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: trimmed.unicodeScalars.prefix(maxTitleLength))
        return String(scalars)
    }

    /// 受け取った文書を、端末の画面に出す項目にする（日時は Date にしてから渡す）。
    /// ToDo・買い物以外・形が違うものは nil（表示しない）。持ち主は「共有」、担当は無し
    static func item(documentID: String, data: [String: Any]) -> LifeItem? {
        guard let id = UUID(uuidString: documentID),
              let kindText = data["kind"] as? String,
              let kind = LifeItemKind(rawValue: kindText),
              HouseholdItemPolicy.kinds.contains(kind),
              let title = data["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let date = data["date"] as? Date else {
            return nil
        }
        return LifeItem(
            id: id,
            title: title,
            kind: kind,
            ownership: .shared,
            date: date,
            hasTime: (data["hasTime"] as? Bool) ?? false,
            assignee: nil,
            isCompleted: (data["isCompleted"] as? Bool) ?? false,
            deferredTo: data["deferredTo"] as? Date,
            droppedAt: data["droppedAt"] as? Date
        )
    }
}

/// 受け取った共有項目1件
struct SharedItemSnapshot: Equatable {
    let item: LifeItem
    /// サーバーで保存が確かめられたか（まだ送信待ちの自分の変更なら false）
    let isConfirmed: Bool
}

/// 共有項目の読み書きがうまくいかなかった理由（画面にはここの文言だけを出す）
enum SharedItemsFailure: Error, Equatable {
    /// 権限が無い（わが家のメンバーでない・その種類がオフ など）
    case permissionDenied
    /// サインインしていない（サインインの情報を更新できない場合も含む）
    case notSignedIn
    /// 通信できない・サーバーが使えない（2026-10-28 Build 9）
    case unavailable
    /// そのほか
    case other

    var message: String {
        switch self {
        case .permissionDenied: return "わが家で共有できませんでした。わが家の設定（共有する種類）を確認してください。"
        case .notSignedIn: return "Appleでサインインしてください。"
        case .unavailable: return "通信できないため、共有の保存ができませんでした。電波のよい場所で、もう一度お試しください。"
        case .other: return "共有の保存がうまくいきませんでした。時間をおいて、もう一度お試しください。"
        }
    }

    /// 理由の短い説明（画面のお知らせ・診断に出す。エラーの中身・UID は出さない）
    var reason: String {
        switch self {
        case .permissionDenied: return "権限がありません"
        case .notSignedIn: return "サインインの確認ができません"
        case .unavailable: return "通信できません"
        case .other: return "原因が分かりません"
        }
    }

    /// 共有の保存が断られ、自分だけに残したときのお知らせ（2026-10-28 Build 9）
    var fallbackNotice: String {
        "共有できなかったため、自分だけに保存しました（\(reason)）。"
    }
}

/// 共有の状態の確認の結果（わが家の設定の「共有の状態を確かめる」。2026-10-28 Build 9）。
/// 実機で共有の保存が断られたとき、どこで止まっているかを、UID・トークンを出さずに確かめるためのもの
struct SharedSyncCheck: Equatable {
    enum Step: Equatable {
        case ok
        /// 失敗（Firestore・Authentication の決まった番号。中身の文は出さない）
        case failed(code: Int)
        /// 見つからない（メンバー文書が無い など）
        case missing
        case notChecked
    }

    var isSignedIn: Bool
    /// Firebase Authentication の ID トークンを新しくできるか（App Check のトークンとは別のもの。
    /// ID トークンが無い・期限切れ・更新できないときは、Firestore で未認証や権限エラーになることがある）
    var tokenRefresh: Step
    /// わが家の文書を読めるか（メンバーなら読める）
    var groupRead: Step
    /// 自分のメンバー文書があるか
    var memberDocument: Step
    /// 共有項目を読めるか
    var itemsRead: Step
    /// わが家の設定でオンの種類（サーバーの値。ToDo・買い物のうち）
    var serverKinds: [String]

    static let notAvailable = SharedSyncCheck(isSignedIn: false, tokenRefresh: .notChecked, groupRead: .notChecked, memberDocument: .notChecked, itemsRead: .notChecked, serverKinds: [])

    /// 画面に出す行（例：「サインインの更新：OK」）
    var lines: [String] {
        func text(_ step: Step) -> String {
            switch step {
            case .ok: return "OK"
            case .failed(let code): return "失敗（コード \(code)）"
            case .missing: return "見つかりません"
            case .notChecked: return "未確認"
            }
        }
        let kinds = serverKinds.compactMap { SharedSpaceKind(rawValue: $0)?.title }
        return [
            "サインイン：\(isSignedIn ? "OK" : "していません")",
            "サインインの更新：\(text(tokenRefresh))",
            "わが家の読み取り：\(text(groupRead))",
            "メンバーの登録：\(text(memberDocument))",
            "共有項目の読み取り：\(text(itemsRead))",
            "サーバーの共有する種類：\(kinds.isEmpty ? "なし" : kinds.joined(separator: "・"))",
        ]
    }
}

// MARK: - 窓口（テストでは偽物に差し替える）

/// 共有項目の保存先（Firestore）。オフラインのときは Firestore が端末にためて、つながったら送る
protocol SharedItemsBackend: AnyObject {
    /// groups/{groupID}/items を見張る。変わるたびに一覧で呼ぶ（自分の送信待ちの変更も含む）
    func listen(groupID: String, onChange: @escaping ([SharedItemSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// 作る（文書の ID は項目の UUID）。completion はサーバーが受け付けた・断ったとき（オフラインのあいだは呼ばれない）
    func create(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    func update(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    func delete(groupID: String, id: UUID, completion: @escaping (SharedItemsFailure?) -> Void)
    /// 共有の状態を確かめる（読み取りだけ。書き込みはしない。2026-10-28 Build 9）
    func diagnose(groupID: String) async -> SharedSyncCheck
}

extension SharedItemsBackend {
    func diagnose(groupID: String) async -> SharedSyncCheck { .notAvailable }
}

/// 予定を「わが家で共有」にできない理由（画面に日本語で出す。2026-11-01 Build 14）
enum EventSharingBlock: Equatable {
    /// 一人で使う設定
    case soloMode
    /// Firebase に接続していない
    case notConnected
    /// サインインしていない
    case notSignedIn
    /// わが家に参加していない
    case notJoined
    /// わが家の設定で「予定」がオフ
    case eventOff

    var message: String {
        switch self {
        case .soloMode: return "一人で使う設定のため、自分だけに保存します。"
        case .notConnected: return "共有の準備ができていないため、自分だけに保存します。"
        case .notSignedIn: return "Appleでサインインして、わが家に参加すると共有できます。"
        case .notJoined: return "わが家に参加すると共有できます。"
        case .eventOff: return "わが家の設定で「予定」がオフのため、共有できません。"
        }
    }
}

/// 予定の編集の保存の結果（Build 16。保存先の変更を含む）
enum EventSaveOutcome: Equatable {
    /// 保存先は変えず、内容を保存した
    case saved
    /// 自分だけ → わが家で共有：同じ UUID で Firestore への作成を始めた（確かめられるまで端末の予定は消さない）
    case sharingStarted
    /// わが家で共有 → 自分だけ：端末へ保存し、共有の予定の削除を始めた
    case madePersonal
    /// 保存先を変えられなかった（理由）。共有の予定・端末の予定は消していない
    case failed(String)

    static let notSavedMessage = "予定が見つからないため、保存できませんでした。"
    static let notJoinedMessage = "わが家に参加していないため、自分だけの予定に変更できませんでした。共有のまま残しています。"
    static let deviceSaveFailedMessage = "この iPhone に保存できなかったため、共有のまま残しました。"
    static let conversionInProgressMessage = "前に「自分だけ」へ変更した予定の片付けがまだ終わっていません。しばらくしてから、もう一度お試しください。"
}

/// LifeStore から共有項目の保存を頼む先
protocol HouseholdItemSyncing: AnyObject {
    /// すでにある共有項目を消せるか（わが家に参加していれば。種類の設定は見ない。Build 16）
    var canDeleteHouseholdItems: Bool { get }
    /// 共有の予定を「自分だけ」に変えるため、共有項目を1回消す。結果は LifeStore へ返す（Build 16）
    func deleteHouseholdItemForPersonalConversion(_ id: LifeItem.ID)
    /// 予定を新しく「わが家で共有」にできない理由（できるなら nil。Build 14）
    var eventSharingBlock: EventSharingBlock? { get }
    /// その種類で「わが家で共有」を選べるか（わが家に参加していて、設定でオン）
    func allowsSharing(_ kind: LifeItemKind) -> Bool
    /// 作る。convertingLocal は「端末の個人項目を共有に変える」とき（保存が確かめられてから端末の項目を片付ける）
    func createHouseholdItem(_ item: LifeItem, convertingLocal: Bool)
    func updateHouseholdItem(_ item: LifeItem)
    func deleteHouseholdItem(_ id: LifeItem.ID)
}

// MARK: - わが家の共有項目をまとめる

/// わが家の共有項目の見張り・保存（画面はこのクラスと LifeStore だけを使う。Firestore は直接使わない）
@Observable
final class SharedItemsService: HouseholdItemSyncing {
    enum Status: Equatable {
        /// わが家に参加していない・Firebase に接続していない
        case off
        case connecting
        case live
        case failed(SharedItemsFailure)
    }

    private(set) var status: Status = .off
    /// 共有の操作がうまくいかなかったときの一言（画面で閉じる。MainTabView が上に出す。2026-10-28 Build 9）
    private(set) var notice: String?
    /// いちばん最近の失敗の理由（わが家の設定に出す）
    private(set) var lastFailure: SharedItemsFailure?
    /// 共有の状態の確認の結果（わが家の設定の「共有の状態を確かめる」）
    private(set) var diagnosis: SharedSyncCheck?
    /// わが家の設定でオンの種類（ToDo・買い物のうち）
    private(set) var enabledKinds: Set<LifeItemKind> = []
    /// 見張っているわが家（文書の ID。画面・ログには出さない）
    @ObservationIgnored private(set) var groupID: String?

    @ObservationIgnored private let backend: SharedItemsBackend?
    @ObservationIgnored private weak var store: LifeStore?
    @ObservationIgnored private var observation: RepositoryObservation?
    /// 確認用の回数（2026-10-28 Build 10）：見張りを始めた回数。見張りは常に最大1つ（activeListenerCount）
    @ObservationIgnored private(set) var listenStartCount = 0
    /// いま動いている見張りの数（0 か 1）
    var activeListenerCount: Int { observation == nil ? 0 : 1 }
    /// 見張りの中の「わが家に参加しているか」（画面の更新のため、見える値として持つ）
    private(set) var isJoined = false
    /// サインインしているか（予定を共有できない理由の表示に使う。Build 14。見張りには使わない）
    private(set) var isSignedIn = true

    init(backend: SharedItemsBackend?) {
        self.backend = backend
    }

    var isAvailable: Bool { backend != nil }

    /// 端末の項目の置き場とつなぐ（起動時に1回）
    func attach(_ store: LifeStore) {
        guard self.store !== store else { return }
        self.store = store
        store.householdSync = self
    }

    /// わが家の情報が変わったとき（参加・退出・削除・サインアウト・設定の変更）
    func apply(household: HouseholdSummary?) {
        // 同じ値なら書き込まない（書くたびに、読んでいる画面が描き直されるため。2026-10-28 Build 10）
        let kinds = (household?.sharedKinds ?? []).filter(\.isSyncSupported)
        let newKinds = Set(kinds.compactMap { LifeItemKind(rawValue: $0.rawValue) })
        if enabledKinds != newKinds { enabledKinds = newKinds }
        let newGroupID = backend == nil ? nil : household?.groupID
        if isJoined != (newGroupID != nil) { isJoined = newGroupID != nil }
        // 同じわが家なら、見張りを作り直さない（何度呼ばれても見張りは1つ）
        guard newGroupID != groupID else { return }

        // わが家が変わった・抜けた：前の見張りをやめ、共有項目の表示だけを消す（端末の個人データは消さない）
        observation?.cancel()
        observation = nil
        groupID = newGroupID
        store?.clearHouseholdItems()
        guard let backend, let newGroupID else {
            status = .off
            return
        }
        status = .connecting
        listenStartCount += 1
        observation = backend.listen(groupID: newGroupID, onChange: { [weak self] snapshots in
            guard let self, self.groupID == newGroupID else { return }
            if self.status != .live { self.status = .live }
            self.store?.applyHouseholdSnapshot(snapshots)
        }, onError: { [weak self] failure in
            guard let self, self.groupID == newGroupID else { return }
            self.status = .failed(failure)
            self.lastFailure = failure
            // 読めなくなった（退出した・わが家が消えた）：共有項目の表示を消す。端末の個人データは消さない
            if failure == .permissionDenied {
                self.store?.clearHouseholdItems()
            }
        })
    }

    func dismissNotice() {
        notice = nil
    }

    /// サインインの状態（MainTabView から。理由の表示だけに使う）
    func updateSignIn(_ isSignedIn: Bool) {
        if self.isSignedIn != isSignedIn { self.isSignedIn = isSignedIn }
    }

    /// 予定を新しく「わが家で共有」にできない理由（できるなら nil）
    var eventSharingBlock: EventSharingBlock? {
        if backend == nil { return .notConnected }
        if !isSignedIn { return .notSignedIn }
        if !isJoined || groupID == nil { return .notJoined }
        if !enabledKinds.contains(.event) { return .eventOff }
        return nil
    }

    /// 共有の状態を確かめる（読み取りだけ）
    @MainActor
    func runDiagnosis() async {
        guard let backend, let groupID else {
            diagnosis = .notAvailable
            return
        }
        diagnosis = await backend.diagnose(groupID: groupID)
    }

    // MARK: HouseholdItemSyncing

    func allowsSharing(_ kind: LifeItemKind) -> Bool {
        isJoined && groupID != nil && enabledKinds.contains(kind)
    }

    func createHouseholdItem(_ item: LifeItem, convertingLocal: Bool) {
        guard let backend, let groupID, let fields = SharedItemPayload.createFields(for: item) else {
            store?.householdCreateFailed(item, convertingLocal: convertingLocal)
            lastFailure = .other
            notice = SharedItemsFailure.other.fallbackNotice
            return
        }
        backend.create(groupID: groupID, id: item.id, fields: fields) { [weak self] failure in
            guard let self else { return }
            if let failure {
                // 断られた：新しく作った項目は「自分だけ」として端末に残す（消さない）。変換なら端末の項目がそのまま残る。
                // 画面の上に「共有できなかったため、自分だけに保存しました」を出す（2026-10-28 Build 9。以前は出していなかった）
                self.store?.householdCreateFailed(item, convertingLocal: convertingLocal)
                self.lastFailure = failure
                self.notice = failure.fallbackNotice
            } else {
                // サーバーに保存できた：送信待ちの印を外す。変換なら端末の個人項目を片付ける（ここまでは消さない）
                self.store?.finishHouseholdCreate(item.id)
                if convertingLocal {
                    self.store?.finishHouseholdConversion(item.id)
                }
            }
        }
    }

    func updateHouseholdItem(_ item: LifeItem) {
        guard let backend, let groupID, let fields = SharedItemPayload.updateFields(for: item) else { return }
        backend.update(groupID: groupID, id: item.id, fields: fields) { [weak self] failure in
            guard let failure else { return }
            self?.lastFailure = failure
            self?.notice = "共有の変更を保存できませんでした（\(failure.reason)）。"
        }
    }

    var canDeleteHouseholdItems: Bool {
        backend != nil && isJoined && groupID != nil
    }

    /// 共有の予定を「自分だけ」に変える（Build 16）：端末へ保存したあとで呼ばれる。
    /// 消せたら LifeStore の印を外す。消せなかったら理由を出す（端末の自分だけの予定は残る。次の起動で1回だけ、もう一度消す）
    func deleteHouseholdItemForPersonalConversion(_ id: LifeItem.ID) {
        guard let backend, let groupID else {
            lastFailure = .other
            notice = Self.personalConversionNotice(SharedItemsFailure.other)
            return
        }
        backend.delete(groupID: groupID, id: id) { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.lastFailure = failure
                self.notice = Self.personalConversionNotice(failure)
            } else {
                self.store?.finishPersonalConversion(id)
            }
        }
    }

    static func personalConversionNotice(_ failure: SharedItemsFailure) -> String {
        "自分だけの予定に変更しました。パートナーのカレンダーからは、まだ消せていません（\(failure.reason)）。次に開いたときに、もう一度消します。"
    }

    func deleteHouseholdItem(_ id: LifeItem.ID) {
        guard let backend, let groupID else { return }
        backend.delete(groupID: groupID, id: id) { [weak self] failure in
            guard let failure else { return }
            self?.lastFailure = failure
            self?.notice = "共有の削除を保存できませんでした（\(failure.reason)）。"
        }
    }
}

extension SharedItemsService {
    /// アプリ全体で使う1つ（起動時の Firebase の設定の結果に合わせて作る）
    static let live: SharedItemsService = {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        if FirebaseBootstrap.result == .configured {
            return SharedItemsService(backend: FirestoreSharedItemsBackend())
        }
        #endif
        return SharedItemsService(backend: nil)
    }()
}
