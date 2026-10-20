import Foundation
import Observation

/// 招待リンクを受け取ったあとの流れ（2026-10-21 招待リンクの土台。docs/FIREBASE_INVITE_LINK_FOUNDATION.md）
///
/// - 有効な招待リンク：確認画面を出す（同じリンクが続けて届いても、確認画面は1つだけ）
/// - 「あとで」・画面を閉じる：何も変えず、持っていた招待を捨てる
/// - 「招待を確認」：共有用アカウントの画面へ進み、次の段階で参加できるようになることを案内する。
///   参加の処理はまだ無いので、持っていた招待はここで捨てる
/// - 不正なリンク：一般的な案内（「この招待リンクは使用できません」）だけを出す。アプリのほかの機能には触れない
///
/// リンクを開いただけでは、招待への参加・Firestore への書き込み・サインイン・端末内のデータの変更をしない。
/// 招待トークンは、アプリを開いているあいだのメモリだけで持ち、保存・表示・ログ出力しない。
@Observable
final class InviteLinkCoordinator {
    /// 確認画面の中の段階
    enum Step: Equatable {
        /// 「わが家への招待を受け取りました」
        case prompt
        /// 共有用アカウントの画面（次の段階の案内つき）
        case account
    }

    /// 受け取ったリンクをどう扱ったか（テスト用）
    enum Outcome: Equatable {
        /// 確認画面を出した
        case presented
        /// 同じリンクがもう表示中・直前に受け取ったので、何もしなかった
        case duplicate
        /// 招待のリンクとして使えない
        case invalid
        /// https・http 以外（招待とは関係ない）なので何もしなかった
        case ignored
    }

    /// 同じリンクが続けて届いたとき（起動の仕方によって、同じリンクが2回届くことがある）に、2回目を無視する時間
    static let duplicateWindow: TimeInterval = 3

    /// いま確認している招待（メモリの中だけ）
    private(set) var pendingInvite: InviteLink?
    /// 確認画面を出しているか
    private(set) var isPresented = false
    private(set) var step: Step = .prompt
    /// 「この招待リンクは使用できません」を出しているか
    private(set) var isShowingInvalidNotice = false

    @ObservationIgnored private let now: () -> Date
    /// 直前に受け取った招待の印（トークンそのものではなく SHA-256。メモリの中だけ）
    @ObservationIgnored private var lastReceived: (fingerprint: String, at: Date)?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// リンクを受け取る（アプリが終了・バックグラウンド・起動中のどの状態から開かれても、ここに届く）
    /// - Parameter allowsNotice: 不正なリンクのときに案内を出してよいか（はじめての設定の途中などは出さない）
    @discardableResult
    func receive(_ url: URL, allowsNotice: Bool = true) -> Outcome {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return .ignored
        }
        guard let invite = InviteLink(url: url) else {
            // 確認画面を出しているときは、そちらを優先して案内を重ねない
            if allowsNotice && !isPresented {
                isShowingInvalidNotice = true
            }
            return .invalid
        }

        let time = now()
        if isPresented, pendingInvite == invite {
            return .duplicate
        }
        if let last = lastReceived, last.fingerprint == invite.fingerprint, time.timeIntervalSince(last.at) < Self.duplicateWindow {
            return .duplicate
        }

        lastReceived = (invite.fingerprint, time)
        pendingInvite = invite
        step = .prompt
        isPresented = true
        isShowingInvalidNotice = false
        return .presented
    }

    /// 「あとで」：何も変えず、招待を捨てる
    func later() {
        discard()
    }

    /// 確認画面を閉じた（下へ引いて閉じた・「閉じる」）：何も変えず、招待を捨てる
    func close() {
        discard()
    }

    /// 「招待を確認」：共有用アカウントの画面へ進む。参加の処理はまだ無いので、招待はここで捨てる（サインインも始めない）
    func confirm() {
        guard isPresented else { return }
        pendingInvite = nil
        step = .account
    }

    func dismissInvalidNotice() {
        isShowingInvalidNotice = false
    }

    private func discard() {
        pendingInvite = nil
        isPresented = false
        step = .prompt
    }
}
