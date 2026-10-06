import SwiftUI

/// 生活OS のタイポグラフィ。
/// すべて TextStyle ベースなので Dynamic Type に追従する。
enum LifeTypography {
    /// 画面タイトル・キャッチコピー（明朝系で落ち着いた印象に）
    static let display = Font.system(.largeTitle, design: .serif)
    /// 大見出し
    static let title = Font.system(.title2, design: .serif)
    /// 中見出し
    static let headline = Font.system(.headline)
    /// 本文
    static let body = Font.system(.body)
    /// 本文（強調）
    static let bodyEmphasis = Font.system(.body).weight(.semibold)
    /// 補助テキスト
    static let callout = Font.system(.callout)
    /// 注釈
    static let footnote = Font.system(.footnote)
    /// 小さな補足
    static let caption = Font.system(.caption)
    /// セクションラベル（NEXT / TODAY など）
    static let label = Font.system(.caption).weight(.semibold)
    /// ボタン
    static let button = Font.system(.body).weight(.semibold)
    /// 金額（桁揃え）
    static let amount = Font.system(.body).weight(.medium).monospacedDigit()
    /// 大きな金額
    static let amountLarge = Font.system(.title, design: .serif).monospacedDigit()
    /// NEXT カードの時刻
    static let timeLarge = Font.system(.largeTitle, design: .serif).monospacedDigit()
    /// カレンダーの日付
    static let calendarDay = Font.system(.callout).monospacedDigit()

    // MARK: - Editorial Living（v2）
    // 本文は読みやすいサンセリフ、日付・大見出し・挨拶・キャッチコピーはセリフ体（.serif）。
    // 外部フォントは使わない。

    /// ヒーローの挨拶（Good morning.）
    static let heroTitle = Font.system(.largeTitle, design: .serif).weight(.regular)
    /// 日付（Saturday, October 3）
    static let editorialDate = Font.system(.title3, design: .serif)
    /// セクションの大見出し（今日これだけ）
    static let editorialTitle = Font.system(.title, design: .serif)
    /// カードの見出し（暮らしメモリー・今日の余力など）
    static let editorialHeadline = Font.system(.title3, design: .serif)
    /// 番号（01 / 02 / 03）
    static let numeral = Font.system(.callout, design: .serif).monospacedDigit()
    /// キャッチコピー（今日も、無理なく。）
    static let editorialCopy = Font.system(.body, design: .serif)
    /// テーマのプレビューの小さな挨拶
    static let themePreviewTitle = Font.system(.caption, design: .serif).italic()

    /// セクションラベルの字間
    static let labelTracking: CGFloat = 1.6

    // MARK: - Calm Future

    /// Ambient Header の一言（10:30の歯医者まで1時間20分）
    static let ambientMessage = Font.system(.title2, design: .serif)
    /// Living Timeline の時刻（10:30）
    static let timelineTime = Font.system(.title3, design: .serif).monospacedDigit()
    /// 大きな数字（今日の支出など）
    static let bigNumeral = Font.system(.largeTitle, design: .serif).monospacedDigit()
    /// 注釈（強調）。「元に戻す」など
    static let footnoteEmphasis = Font.system(.footnote).weight(.semibold)
}
