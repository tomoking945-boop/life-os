import CryptoKit
import Foundation
import Observation

/// 招待リンクを受け取ったあとの流れ（2026-10-21 招待リンクの土台。docs/FIREBASE_INVITE_LINK_FOUNDATION.md）
///
/// - 有効な招待リンク：確認画面を出す。同じリンクは、アプリを開いているあいだ1回だけ
///   （表示中・「あとで」のあと・「招待を確認」のあとに同じリンクが届いても出さない。アプリを起動し直すと、また受け取れる）
/// - 「あとで」・画面を閉じる：何も変えず、持っていた招待を捨てる
/// - 「招待を確認」：参加の確認（招待の内容の Preview・サインインの案内）へ進む。招待はメモリの中で持ったまま
///   （2026-10-22 わが家の参加。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
/// - 参加できた：招待を捨て、メンバーの画面へ進む
/// - 不正なリンク：一般的な案内（「この招待リンクは使用できません」）だけを出す。アプリのほかの機能には触れない
///
/// リンクを開いただけでは、招待への参加・Firestore への書き込み・サインイン・端末内のデータの変更をしない。
/// 参加は、利用者が確認画面で「参加する」を押したときだけ（HouseholdService.join）。
/// 招待トークンは、アプリを開いているあいだのメモリだけで持ち、保存・表示・ログ出力しない。
@Observable
final class InviteLinkCoordinator {
    /// 確認画面の中の段階
    enum Step: Equatable {
        /// 「わが家への招待を受け取りました」
        case prompt
        /// 参加の確認（サインインの案内・招待の内容・「参加する」「やめる」）
        case join
        /// 参加できた（メンバーの画面）
        case joined
    }

    /// 受け取ったリンクをどう扱ったか（テスト用）
    enum Outcome: Equatable {
        /// 確認画面を出した
        case presented
        /// 同じリンクを、このアプリの起動中にもう受け取っているので、何もしなかった
        case duplicate
        /// 招待のリンクとして使えない
        case invalid
        /// https・http 以外（招待とは関係ない）なので何もしなかった
        case ignored
    }

    /// いま確認している招待（メモリの中だけ）
    private(set) var pendingInvite: InviteLink?
    /// 確認画面を出しているか
    private(set) var isPresented = false
    private(set) var step: Step = .prompt
    /// 「この招待リンクは使用できません」を出しているか
    private(set) var isShowingInvalidNotice = false

    /// このアプリの起動中に受け取った招待の印（重複を見分けるためだけ）。
    /// トークンそのものではなく、起動ごとに作る秘密の鍵で計算した HMAC-SHA256（元のトークンには戻せない）。
    /// メモリの中だけで持ち、保存しない。アプリを起動し直す（新しく作る）と空になる
    @ObservationIgnored private var receivedFingerprints: Set<Data> = []
    /// 印を計算する鍵（起動ごとに作る乱数。保存しない）
    @ObservationIgnored private let fingerprintKey = SymmetricKey(size: .bits256)

    /// 覚えている招待の数（テスト用。中身は出さない）
    var rememberedInviteCount: Int { receivedFingerprints.count }

    init() {}

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

        // 同じリンクは、起動中に1回だけ（表示中・「あとで」・「招待を確認」のあとも出さない）
        let fingerprint = Data(HMAC<SHA256>.authenticationCode(for: Data(invite.token.utf8), using: fingerprintKey))
        guard receivedFingerprints.insert(fingerprint).inserted else {
            return .duplicate
        }

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

    /// 「招待を確認」：参加の確認へ進む（招待はメモリの中で持ったまま。サインイン・参加は自動では始めない）
    func confirm() {
        guard isPresented, pendingInvite != nil else { return }
        step = .join
    }

    /// 参加できた：招待を捨て、メンバーの画面へ進む
    func completeJoin() {
        guard isPresented else { return }
        pendingInvite = nil
        step = .joined
    }

    /// 確認画面を閉じたあとに、まだ持っている招待があれば、もう一度参加の確認を出す（共有用アカウントの「招待内容を確認」）
    func reopen() {
        guard !isPresented, pendingInvite != nil else { return }
        step = .join
        isPresented = true
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
