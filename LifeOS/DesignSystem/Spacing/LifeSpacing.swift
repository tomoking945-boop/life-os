import SwiftUI

/// 余白のトークン。大きめの余白を基本とする。
enum LifeSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// 画面左右の余白
    static let screenHorizontal: CGFloat = 24
    /// 画面上下の余白
    static let screenVertical: CGFloat = 24
    /// セクション同士の間隔
    static let sectionGap: CGFloat = 28
    /// カード内側の余白
    static let cardPadding: CGFloat = 24
    /// 行と行の間隔
    static let rowGap: CGFloat = 12

    /// タップ領域の最小サイズ（Apple HIG 44pt）
    static let minTapTarget: CGFloat = 44
    /// ボタンの高さ
    static let buttonHeight: CGFloat = 52
    /// カレンダーの日付セルの丸の直径
    static let calendarDayDiameter: CGFloat = 38
    /// カレンダーの予定ドットの直径
    static let calendarDotDiameter: CGFloat = 5
    /// 区切り線の太さ
    static let hairline: CGFloat = 0.5
    /// カテゴリー色のドットの直径
    static let categoryDot: CGFloat = 8
    /// カテゴリー色の細い線の幅
    static let categoryBar: CGFloat = 3
    /// ヒーローカードの最低の高さ
    static let heroMinHeight: CGFloat = 180
}
