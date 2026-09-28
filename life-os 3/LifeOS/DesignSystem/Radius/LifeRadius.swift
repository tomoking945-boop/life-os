import SwiftUI

/// 角丸のトークン。カードは大きめの角丸を基本とする。
enum LifeRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 18
    static let large: CGFloat = 26

    /// カード
    static let card: CGFloat = large
    /// 入力欄
    static let field: CGFloat = medium
    /// Bottom Sheet
    static let sheet: CGFloat = 32
}
