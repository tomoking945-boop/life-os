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
    /// テーマのプレビューの大きさ
    static let themePreviewWidth: CGFloat = 132
    static let themePreviewHeight: CGFloat = 168

    // MARK: - Calm Future

    /// Living Timeline の線の列の幅
    static let timelineRail: CGFloat = 16
    /// Living Timeline の点（通常）
    static let timelineDot: CGFloat = 7
    /// Living Timeline の「いま」の点のまわりの輪
    static let timelineRing: CGFloat = 15
    /// Living Timeline の点を置く高さ（見出しの1行分）
    static let timelineMarkerHeight: CGFloat = 22
    /// Living Timeline の線の太さ
    static let timelineLine: CGFloat = 1
    /// Living Timeline の項目の左のずらし（番号の幅）
    static let timelineNumeralWidth: CGFloat = 22
    /// 暮らしメモリーの横スクロールのカード幅
    static let insightCardWidth: CGFloat = 248
    /// カード上辺の細い光の長さ
    static let insightAccentLength: CGFloat = 28
    /// 背景の弱い光の半径
    static let ambientGlowRadius: CGFloat = 420
    /// お金の予算の細い線の太さ
    static let budgetLine: CGFloat = 2
    /// なんでも追加の小さな Orb の直径
    static let orbSize: CGFloat = 30
}
