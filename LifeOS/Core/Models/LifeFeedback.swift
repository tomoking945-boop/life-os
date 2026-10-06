import Foundation

/// 操作のあとに短く出す一言と「元に戻す」（Calm Future）。
/// 今日画面・Inbox・まとめて整理で共通に使う。表示は DesignSystem の `lifeFeedbackBanner`。
struct LifeFeedback: Equatable {
    let id = UUID()
    let message: String
    /// nil なら「元に戻す」を出さない
    let undo: (() -> Void)?

    static func == (lhs: LifeFeedback, rhs: LifeFeedback) -> Bool {
        lhs.id == rhs.id
    }
}
