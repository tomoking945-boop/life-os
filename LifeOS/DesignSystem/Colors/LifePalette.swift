import SwiftUI
import UIKit

/// 1つのテーマの、ライトまたはダークの基本色（テーマとダークモード：2026-10-08）。
/// 画面は `LifeColors.xxx` を使い、ここを直接使わない。
struct LifePalette {
    /// 画面の背景
    let background: UIColor
    /// カードなどの面
    let surface: UIColor
    /// 主要アクション・強調（ダークでは明るい色。上に載せる文字は surface）
    let primary: UIColor
    /// 本文テキスト
    let text: UIColor
    /// 補助テキスト
    let secondaryText: UIColor
    /// アクセント（Brass など）
    let accent: UIColor
    /// 区切り線・枠線
    let divider: UIColor
    /// 紙の質感の面（背景面の切り替え）
    let paper: UIColor
    /// ヒーローのグラデーションのもう一方の色
    let heroSoft: UIColor
    /// 影の色
    let shadow: UIColor
    /// 浮いているボタンの影
    let floatingShadow: UIColor
}

extension UIColor {
    /// 0xRRGGBB 形式の16進数から UIColor を作る
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// いま使っているテーマ。色はここを見て、ライト／ダークに合わせてその場で決まる。
/// AppState の「選んだテーマ」（Free では Forest）を、アプリの一番外側で反映する（LifeOSApp）。
enum LifeThemeRuntime {
    /// 現在のテーマ（Free のときは Forest）
    static var theme: LifeTheme = .forest

    /// テーマとライト／ダークから基本色を選ぶ
    static func palette(for traits: UITraitCollection, theme: LifeTheme = LifeThemeRuntime.theme) -> LifePalette {
        traits.userInterfaceStyle == .dark ? theme.darkPalette : theme.lightPalette
    }

    /// ライト／ダークと現在のテーマに合わせて変わる UIColor
    static func uiColor(_ pick: @escaping (LifePalette) -> UIColor) -> UIColor {
        UIColor { traits in pick(palette(for: traits)) }
    }

    /// ライト／ダークと現在のテーマに合わせて変わる Color
    static func color(_ pick: @escaping (LifePalette) -> UIColor) -> Color {
        Color(uiColor: uiColor(pick))
    }

    /// 決まったテーマの色（Premium のテーマのプレビュー用。ライト／ダークには合わせる）
    static func color(of theme: LifeTheme, _ pick: @escaping (LifePalette) -> UIColor) -> Color {
        Color(uiColor: UIColor { traits in pick(palette(for: traits, theme: theme)) })
    }
}

/// ライト／ダークの選び方（表示設定）
enum LifeAppearanceMode: String, CaseIterable, Identifiable, Hashable, Codable {
    /// 端末の設定に合わせる
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "端末に合わせる"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }

    /// SwiftUI に渡す値（nil は端末に合わせる）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 各テーマの基本色

extension LifeTheme {
    /// ライトの基本色。Forest はこれまでの Editorial Living の色そのまま。
    var lightPalette: LifePalette {
        switch self {
        case .forest:
            return .light(background: 0xF6F4EF, primary: 0x223C34, text: 0x222522, secondaryText: 0x747871,
                          accent: 0xAD8A65, divider: 0xE6E1D8, paper: 0xEFEBE3, heroSoft: 0x2F4D43)
        case .hotel:
            return .light(background: 0xF4F1EC, primary: 0x3A3230, text: 0x252220, secondaryText: 0x6D6660,
                          accent: 0xB39169, divider: 0xE5DED5, paper: 0xECE6DE, heroSoft: 0x4A403C)
        case .sage:
            return .light(background: 0xF2F4EF, primary: 0x55684F, text: 0x232622, secondaryText: 0x6C7266,
                          accent: 0xA39A74, divider: 0xE0E4DA, paper: 0xE8ECE3, heroSoft: 0x667A60)
        case .midnight:
            return .light(background: 0xF1F2F3, primary: 0x34404A, text: 0x20252A, secondaryText: 0x656C73,
                          accent: 0xB59B6E, divider: 0xDFE2E5, paper: 0xE7EAED, heroSoft: 0x46535E)
        case .terracotta:
            return .light(background: 0xF7F1EB, primary: 0x8A4F3C, text: 0x2A2220, secondaryText: 0x786D67,
                          accent: 0xC49A6C, divider: 0xE9DFD6, paper: 0xEFE6DD, heroSoft: 0x9C6250)
        }
    }

    /// ダークの基本色。夜の Deep Forest・Midnight をもとに、テーマごとに少しだけ色みを変える。
    /// 主要色は明るくし、その上の文字（onPrimary）は暗い面の色にする。
    var darkPalette: LifePalette {
        switch self {
        case .forest:
            return .dark(background: 0x121815, surface: 0x1B2320, primary: 0xB9D3C5, text: 0xECE8E0,
                         secondaryText: 0xA2A79F, accent: 0xC9A57E, divider: 0x2C3631, paper: 0x171E1B, heroSoft: 0xA7C4B4)
        case .hotel:
            return .dark(background: 0x161312, surface: 0x211C1A, primary: 0xE2D2C2, text: 0xEEE7E0,
                         secondaryText: 0xA89F98, accent: 0xC9A57E, divider: 0x352E2B, paper: 0x1B1716, heroSoft: 0xD2C0AE)
        case .sage:
            return .dark(background: 0x131712, surface: 0x1C211B, primary: 0xC3D3BD, text: 0xE9ECE4,
                         secondaryText: 0xA0A699, accent: 0xBDB38C, divider: 0x2F362D, paper: 0x181C17, heroSoft: 0xB0C3A9)
        case .midnight:
            return .dark(background: 0x121519, surface: 0x1B2026, primary: 0xC4D0DC, text: 0xECE6DA,
                         secondaryText: 0xA1A6AD, accent: 0xC9AE80, divider: 0x2D333B, paper: 0x171B20, heroSoft: 0xB1BFCD)
        case .terracotta:
            return .dark(background: 0x171210, surface: 0x221B18, primary: 0xE6C3B2, text: 0xF0E7DF,
                         secondaryText: 0xAA9E96, accent: 0xD2A877, divider: 0x382D29, paper: 0x1C1614, heroSoft: 0xD9B19E)
        }
    }
}

private extension LifePalette {
    /// ライト：面は白、影は文字色をごく薄く
    static func light(
        background: UInt32, primary: UInt32, text: UInt32, secondaryText: UInt32,
        accent: UInt32, divider: UInt32, paper: UInt32, heroSoft: UInt32
    ) -> LifePalette {
        LifePalette(
            background: UIColor(hex: background),
            surface: UIColor(hex: 0xFFFFFF),
            primary: UIColor(hex: primary),
            text: UIColor(hex: text),
            secondaryText: UIColor(hex: secondaryText),
            accent: UIColor(hex: accent),
            divider: UIColor(hex: divider),
            paper: UIColor(hex: paper),
            heroSoft: UIColor(hex: heroSoft),
            shadow: UIColor(hex: text, alpha: 0.05),
            floatingShadow: UIColor(hex: text, alpha: 0.12)
        )
    }

    /// ダーク：影は黒（明るい影で光って見えないように）
    static func dark(
        background: UInt32, surface: UInt32, primary: UInt32, text: UInt32, secondaryText: UInt32,
        accent: UInt32, divider: UInt32, paper: UInt32, heroSoft: UInt32
    ) -> LifePalette {
        LifePalette(
            background: UIColor(hex: background),
            surface: UIColor(hex: surface),
            primary: UIColor(hex: primary),
            text: UIColor(hex: text),
            secondaryText: UIColor(hex: secondaryText),
            accent: UIColor(hex: accent),
            divider: UIColor(hex: divider),
            paper: UIColor(hex: paper),
            heroSoft: UIColor(hex: heroSoft),
            shadow: UIColor(hex: 0x000000, alpha: 0.30),
            floatingShadow: UIColor(hex: 0x000000, alpha: 0.45)
        )
    }
}
