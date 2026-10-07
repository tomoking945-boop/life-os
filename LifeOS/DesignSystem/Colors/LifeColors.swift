import SwiftUI

/// 生活OS のカラートークン。
/// 画面側では Color リテラルを直接書かず、必ず `LifeColors.xxx` を使う。
/// ここを変更すれば全画面の配色が一括で切り替わる。
///
/// テーマとダークモード（2026-10-08）：
/// 各色は「いまのテーマ（LifeThemeRuntime.theme）」と「ライト／ダーク」に合わせて、その場で決まる。
/// 色の値そのものは `LifePalette`（テーマごとのライト・ダーク）にある。Forest のライトはこれまでの色と同じ。
enum LifeColors {
    /// 画面の背景（Forest ライト：#F6F4EF）
    static let background = LifeThemeRuntime.color { $0.background }
    /// カードなどの面（ライト：#FFFFFF）
    static let surface = LifeThemeRuntime.color { $0.surface }
    /// 主要アクション・強調（Forest ライト：#223C34。ダークでは明るい色）
    static let primary = LifeThemeRuntime.color { $0.primary }
    /// 本文テキスト（Forest ライト：#222522）
    static let text = LifeThemeRuntime.color { $0.text }
    /// 補助テキスト（Forest ライト：#747871）
    static let secondaryText = LifeThemeRuntime.color { $0.secondaryText }
    /// アクセント（控えめなハイライト。Forest ライト：#AD8A65）
    static let accent = LifeThemeRuntime.color { $0.accent }
    /// 区切り線・枠線（Forest ライト：#E6E1D8）
    static let divider = LifeThemeRuntime.color { $0.divider }

    // MARK: - 派生色（上記トークンの透過度だけを変えたもの。新しい色相は追加しない）

    /// primary の上に載せる文字色（ライトでは白、ダークでは暗い面の色）
    static let onPrimary = surface
    /// 選択状態などの淡い面
    static let primarySubtle = primary.opacity(0.08)
    /// アクセントの淡い面（バッジ背景など）
    static let accentSubtle = accent.opacity(0.16)
    /// カード影（ダークでは黒）
    static let shadow = LifeThemeRuntime.color { $0.shadow }
    /// 浮いているボタンの影（ダークでは黒）
    static let floatingShadow = LifeThemeRuntime.color { $0.floatingShadow }

    // MARK: - Editorial Living（v2）

    /// ヒーローの濃い面（Deep Forest を少し明るくした色。強いグラデーションにはしない）
    static let heroDeep = primary
    static let heroSoft = LifeThemeRuntime.color { $0.heroSoft }
    /// ヒーロー上の文字（Warm Ivory。ダークでは暗い色）
    static let onHero = background
    /// ヒーロー上の補助文字
    static let onHeroSecondary = background.opacity(0.78)
    /// ヒーローの装飾（抽象的な植物の形）
    static let heroOrnament = accent.opacity(0.22)
    /// 紙の質感を思わせる、少し濃いアイボリー（ダークでは背景より少し明るい面）
    static let paper = LifeThemeRuntime.color { $0.paper }

    // 決定（2026-10-08）：ダークモードを追加。表示設定の「端末に合わせる／ライト／ダーク」で選ぶ（LifeOSApp で反映）。
}
