import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// 端末の中の Firestore の送信待ちの山を1回だけ片付ける（2026-10-31 Build 10。docs/BUILD_10_PERFORMANCE_AND_TODO_CONSISTENCY.md の原因5）
//
// Instruments（48秒）で分かったこと：
// - 端末の中の Firestore（LevelDB）に、Build 8〜9 の通知の登録のくり返しで出た「端末の文書の保存」が
//   約48万件、送信待ちのまま残っていた（SetMutation・ServerTimestampTransform が 482,973件ずつ）
// - 起動のたびに Firestore がそれを順番に送り直し、サーバーの返事が1件届くたびに
//   LocalStore::AcknowledgeBatch → LocalDocumentsView::RecalculateAndSaveOverlays →
//   LevelDbMutationQueue::AllMutationBatchesAffecting… で、同じ文書の送信待ちを全部読み直していた（約1.3GB）
// - アプリ側の保存（FirestoreDeviceRegistry.save）は、この記録の中では1回だけ。新しい嵐は起きていない
// - 送信待ちは出した順番にしか送られないため、この山のあとの共有の ToDo・買い物の書き込みも届かなくなる
//
// Firestore には「送信待ちの一部だけを消す」方法が無いため、端末の中の Firestore の保存（キャッシュ）を1回だけ消す。
// サーバーのデータ・ルール・Functions は変えない（消すのはこの端末の中の控えだけ。必要なものはサーバーから読み直す）。
// 消す前に、まだサーバーに届いていない共有の ToDo・買い物の「新規作成」を読み出して、「自分だけ」の項目として端末に残す（消さない）。

/// 端末の中に残っていた共有項目1件（キャッシュから読んだもの）
struct CachedSharedItem: Equatable {
    /// 読めた項目（形が合わなければ nil）
    let item: LifeItem?
    /// この端末の変更が、まだサーバーに届いていないか
    let hasPendingWrites: Bool
    /// サーバーで付いた作成日時があるか（無ければ、一度もサーバーに届いていない新規作成）
    let hasServerCreatedAt: Bool
}

/// 片付けるか・何を残すかの決まり（Firebase を使わない。テストで確かめる）
enum FirestoreCacheRepairPolicy {
    /// 片付けの版（同じ版は二度と行わない）
    static let currentVersion = 1
    static let defaultsKey = "firestoreLocalCacheRepairVersion"

    static func needsRepair(storedVersion: Int) -> Bool {
        storedVersion < currentVersion
    }

    /// 一度もサーバーに届いていない新規作成だけを残す（サーバーにある項目への変更は、サーバーの内容に戻る）
    static func unsentCreates(_ cached: [CachedSharedItem]) -> [LifeItem] {
        cached
            .filter { $0.hasPendingWrites && !$0.hasServerCreatedAt }
            .compactMap(\.item)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

/// 片付けの手順（本物は Firestore、テストでは偽物）。どれも決まった時間で返る
protocol FirestoreCacheRepairSteps: AnyObject {
    /// 送り直しを止める（サーバーの返事による読み直しを始めさせない）
    func disableNetwork() async -> Bool
    /// 端末の中の共有項目を読む（サーバーには聞かない）。読めなければ nil
    func readCachedSharedItems() async -> [CachedSharedItem]?
    /// 送り直しを戻す（片付けをやめたとき）
    func enableNetwork() async -> Bool
    /// Firestore を止める（このあと Firestore.firestore() は新しく作られる）
    func terminate() async -> Bool
    /// 端末の中の Firestore の保存を消す
    func clearPersistence() async -> Bool
}

/// Firestore を使い始めてよいか（片付けが終わるまで、共有項目・通知の端末の文書は Firestore に触れない）
/// 待っている処理は、開いたときに1回ずつ動かす。テスト・Firebase なしでは最初から開いている
final class FirestoreAccessGate: @unchecked Sendable {
    static let shared = FirestoreAccessGate()

    private let lock = NSLock()
    private var opened = true
    private var waiting: [() -> Void] = []

    var isOpen: Bool { lock.withLock { opened } }
    var waitingCount: Int { lock.withLock { waiting.count } }

    func close() {
        lock.withLock { opened = false }
    }

    /// 開ける。待っていた処理を、頼まれた順に1回ずつ動かす
    func openGate() {
        let pending: [() -> Void] = lock.withLock {
            guard !opened else { return [] }
            opened = true
            let list = waiting
            waiting = []
            return list
        }
        pending.forEach { $0() }
    }

    /// 開いていればすぐ、閉じていれば開いたときに動かす
    func whenOpen(_ body: @escaping () -> Void) {
        let runNow: Bool = lock.withLock {
            if opened { return true }
            waiting.append(body)
            return false
        }
        if runNow { body() }
    }

    func waitUntilOpen() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            whenOpen { continuation.resume() }
        }
    }
}

/// 片付けの流れ
enum FirestoreLocalCacheRepair {
    enum Outcome: Equatable {
        /// もう片付けてある
        case notNeeded
        /// 片付けた（自分だけに残した件数）
        case repaired(rescued: Int)
        /// 送り直しを止められなかった（何も消していない。次の起動でもう一度）
        case skippedPrepareFailed
        /// 端末の中の共有項目を読めなかった（何も消していない。次の起動でもう一度）
        case skippedReadFailed
        /// 消せなかった（残した項目はそのまま。次の起動でもう一度）
        case clearFailed
    }

    /// 起動時に呼ぶ：必要なら、すぐに Firestore を使えない状態にしてから、片付けを始める
    @MainActor
    static func start(
        steps: @autoclosure () -> FirestoreCacheRepairSteps,
        defaults: UserDefaults = .standard,
        gate: FirestoreAccessGate = .shared,
        onRescued: @escaping ([LifeItem]) -> Void
    ) {
        guard FirestoreCacheRepairPolicy.needsRepair(storedVersion: defaults.integer(forKey: FirestoreCacheRepairPolicy.defaultsKey)) else { return }
        // ここで閉じる（画面が Firestore を使い始めるより前）
        gate.close()
        let liveSteps = steps()
        Task { @MainActor in
            _ = await run(steps: liveSteps, defaults: defaults, gate: gate, onRescued: onRescued)
        }
    }

    /// 片付けの本体。どの結果でも、最後に必ず Firestore を使える状態に戻す
    @MainActor
    @discardableResult
    static func run(
        steps: FirestoreCacheRepairSteps,
        defaults: UserDefaults,
        gate: FirestoreAccessGate,
        onRescued: ([LifeItem]) -> Void
    ) async -> Outcome {
        guard FirestoreCacheRepairPolicy.needsRepair(storedVersion: defaults.integer(forKey: FirestoreCacheRepairPolicy.defaultsKey)) else {
            gate.openGate()
            return .notNeeded
        }
        gate.close()
        defer { gate.openGate() }

        guard await steps.disableNetwork() else {
            _ = await steps.enableNetwork()
            return .skippedPrepareFailed
        }
        guard let cached = await steps.readCachedSharedItems() else {
            // 残すものを確かめられないときは消さない
            _ = await steps.enableNetwork()
            return .skippedReadFailed
        }
        // 消す前に、まだ届いていない新規作成を「自分だけ」として端末に保存する
        let rescued = FirestoreCacheRepairPolicy.unsentCreates(cached)
        if !rescued.isEmpty { onRescued(rescued) }

        guard await steps.terminate() else {
            _ = await steps.enableNetwork()
            return .clearFailed
        }
        guard await steps.clearPersistence() else {
            // 止めたあとの Firestore.firestore() は新しく作られ、送り直しも元どおりになる
            return .clearFailed
        }
        defaults.set(FirestoreCacheRepairPolicy.currentVersion, forKey: FirestoreCacheRepairPolicy.defaultsKey)
        return .repaired(rescued: rescued.count)
    }
}

#if canImport(FirebaseFirestore)
/// 本物の片付けの手順（Firestore の公開の機能だけを使う。サーバーには書き込まない）
final class LiveFirestoreCacheRepairSteps: FirestoreCacheRepairSteps {
    /// 1つの手順を待つ時間（端末の中だけの処理。通信はしない）
    private let timeout: TimeInterval = 15
    private var firestore: Firestore?

    private var db: Firestore {
        if let firestore { return firestore }
        let created = Firestore.firestore()
        firestore = created
        return created
    }

    func disableNetwork() async -> Bool {
        let db = self.db
        return await SharedPushService.run(timeout: timeout) { try await db.disableNetwork() }
    }

    func readCachedSharedItems() async -> [CachedSharedItem]? {
        let db = self.db
        let box = RepairResultBox()
        let finished = await SharedPushService.run(timeout: timeout) {
            // サーバーには聞かず、端末の中だけを読む（groups/{groupID}/items）
            let snapshot = try await db.collectionGroup("items").getDocuments(source: .cache)
            box.items = snapshot.documents.map { document in
                let raw = document.data()
                return CachedSharedItem(
                    item: SharedItemPayload.item(documentID: document.documentID, data: Self.plain(raw)),
                    hasPendingWrites: document.metadata.hasPendingWrites,
                    hasServerCreatedAt: raw["createdAt"] is Timestamp
                )
            }
        }
        return finished ? box.items : nil
    }

    func enableNetwork() async -> Bool {
        let db = self.db
        return await SharedPushService.run(timeout: timeout) { try await db.enableNetwork() }
    }

    func terminate() async -> Bool {
        let db = self.db
        return await SharedPushService.run(timeout: timeout) { try await db.terminate() }
    }

    func clearPersistence() async -> Bool {
        let db = self.db
        return await SharedPushService.run(timeout: timeout) { try await db.clearPersistence() }
    }

    private static func plain(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in data {
            if let timestamp = value as? Timestamp {
                result[key] = timestamp.dateValue()
            } else {
                result[key] = value
            }
        }
        return result
    }
}

private final class RepairResultBox: @unchecked Sendable {
    var items: [CachedSharedItem]?
}
#endif
