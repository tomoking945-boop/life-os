import SwiftUI

/// 生活OS のカラートークン。
/// 画面側では Color リテラルを直接書かず、必ず `LifeColors.xxx` を使う。
/// ここを変更すれば全画面の配色が一括で切り替わる。
enum LifeColors {
    /// #F6F4EF 画面の背景
    static let background = Color(hex: 0xF6F4EF)
    /// #FFFFFF カードなどの面
    static let surface = Color(hex: 0xFFFFFF)
    /// #223C34 主要アクション・強調
    static let primary = Color(hex: 0x223C34)
    /// #222522 本文テキスト
    static let text = Color(hex: 0x222522)
    /// #747871 補助テキスト
    static let secondaryText = Color(hex: 0x747871)
    /// #AD8A65 アクセント（控えめなハイライト）
    static let accent = Color(hex: 0xAD8A65)
    /// #E6E1D8 区切り線・枠線
    static let divider = Color(hex: 0xE6E1D8)

    // MARK: - 派生色（上記トークンの透過度だけを変えたもの。新しい色相は追加しない）

    /// primary の上に載せる文字色
    static let onPrimary = surface
    /// 選択状態などの淡い面
    static let primarySubtle = primary.opacity(0.08)
    /// アクセントの淡い面（バッジ背景など）
    static let accentSubtle = accent.opacity(0.16)
    /// カード影
    static let shadow = text.opacity(0.05)
    /// 浮いているボタンの影
    static let floatingShadow = text.opacity(0.12)

    // TODO: ダークモードの配色は仕様未定。現状はライトモード固定（LifeOSApp で指定）。
}
