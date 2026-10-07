import SwiftUI
import UIKit
import XCTest
@testable import LifeOS

// テーマとダークモード（2026-10-08）のテスト：基本色 / 読みやすさ（コントラスト）/ 選び方と保存の規則

private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
private let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

/// 相対輝度（WCAG）
private func luminance(_ color: UIColor) -> Double {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    func channel(_ value: CGFloat) -> Double {
        let c = Double(value)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
}

/// コントラスト比
private func contrast(_ lhs: UIColor, _ rhs: UIColor) -> Double {
    let a = luminance(lhs), b = luminance(rhs)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

private func hex(_ color: UIColor) -> UInt32 {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (UInt32((red * 255).rounded()) << 16) | (UInt32((green * 255).rounded()) << 8) | UInt32((blue * 255).rounded())
}

final class ThemePaletteTests: XCTestCase {
    override func tearDown() {
        LifeThemeRuntime.theme = .forest
        super.tearDown()
    }

    /// Forest のライトは、これまでの色そのまま
    func testForestLightKeepsExistingColors() {
        let palette = LifeTheme.forest.lightPalette
        XCTAssertEqual(hex(palette.background), 0xF6F4EF)
        XCTAssertEqual(hex(palette.surface), 0xFFFFFF)
        XCTAssertEqual(hex(palette.primary), 0x223C34)
        XCTAssertEqual(hex(palette.text), 0x222522)
        XCTAssertEqual(hex(palette.secondaryText), 0x747871)
        XCTAssertEqual(hex(palette.accent), 0xAD8A65)
        XCTAssertEqual(hex(palette.divider), 0xE6E1D8)
        XCTAssertEqual(hex(palette.paper), 0xEFEBE3)
        XCTAssertEqual(hex(palette.heroSoft), 0x2F4D43)
    }

    /// 色はテーマとライト／ダークに合わせて、その場で決まる
    func testDynamicColorFollowsThemeAndAppearance() {
        let background = LifeThemeRuntime.uiColor { $0.background }
        LifeThemeRuntime.theme = .forest
        XCTAssertEqual(hex(background.resolvedColor(with: lightTraits)), 0xF6F4EF)
        XCTAssertEqual(hex(background.resolvedColor(with: darkTraits)), hex(LifeTheme.forest.darkPalette.background))

        LifeThemeRuntime.theme = .hotel
        XCTAssertEqual(hex(background.resolvedColor(with: lightTraits)), hex(LifeTheme.hotel.lightPalette.background))
        XCTAssertEqual(hex(background.resolvedColor(with: darkTraits)), hex(LifeTheme.hotel.darkPalette.background))
    }

    /// どのテーマのライト・ダークでも、文字が読みやすい
    func testAllPalettesAreReadable() {
        for theme in LifeTheme.allCases {
            for (name, palette) in [("ライト", theme.lightPalette), ("ダーク", theme.darkPalette)] {
                let label = "\(theme.name) \(name)"
                XCTAssertGreaterThanOrEqual(contrast(palette.text, palette.background), 7, label)
                XCTAssertGreaterThanOrEqual(contrast(palette.text, palette.surface), 7, label)
                XCTAssertGreaterThanOrEqual(contrast(palette.secondaryText, palette.background), 4, label)
                // ボタンの文字（onPrimary = surface）と主要色
                XCTAssertGreaterThanOrEqual(contrast(palette.surface, palette.primary), 4.5, label)
                // リンクなど、背景の上の主要色の文字
                XCTAssertGreaterThanOrEqual(contrast(palette.primary, palette.background), 4.5, label)
            }
        }
    }

    func testDarkPalettesAreDark() {
        for theme in LifeTheme.allCases {
            XCTAssertLessThan(luminance(theme.darkPalette.background), 0.05, theme.name)
            XCTAssertGreaterThan(luminance(theme.lightPalette.background), 0.8, theme.name)
        }
    }
}

final class ThemeSettingTests: XCTestCase {
    func testAppearanceModeMapping() {
        XCTAssertNil(LifeAppearanceMode.system.colorScheme)
        XCTAssertEqual(LifeAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(LifeAppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(LifeAppearanceMode.allCases.map(\.label), ["端末に合わせる", "ライト", "ダーク"])
        XCTAssertEqual(AppState().appearanceMode, .system)
    }

    /// テーマは Premium の機能。Free では Forest、選んだテーマは覚えておく
    func testThemeIsPremiumOnly() {
        let state = AppState()
        state.plan = .free
        state.selectTheme(.hotel)
        XCTAssertEqual(state.selectedTheme, .forest, "Free では選べない")
        XCTAssertEqual(state.effectiveTheme, .forest)

        state.plan = .premium
        state.selectTheme(.hotel)
        XCTAssertEqual(state.effectiveTheme, .hotel)

        state.plan = .free
        XCTAssertEqual(state.effectiveTheme, .forest)
        XCTAssertEqual(state.selectedTheme, .hotel, "Premium に戻せば同じテーマ")
    }

    func testPremiumScreenApplyTheme() {
        let state = AppState()
        let viewModel = PremiumViewModel(appState: state)
        XCTAssertEqual(viewModel.previewTheme, .forest)
        viewModel.previewTheme = .sage
        XCTAssertFalse(viewModel.canApplyTheme, "Free では反映しない")
        XCTAssertTrue(viewModel.themeNote.contains("Free"))

        state.plan = .premium
        XCTAssertTrue(viewModel.canApplyTheme)
        XCTAssertEqual(viewModel.applyThemeTitle, "Sage を使う")
        viewModel.applyTheme()
        XCTAssertEqual(state.effectiveTheme, .sage)
        XCTAssertFalse(viewModel.canApplyTheme)
        XCTAssertEqual(viewModel.applyThemeTitle, "Sage を使用中")
    }

    func testThemeRoundTrips() throws {
        let data = try JSONEncoder().encode([LifeTheme.midnight])
        XCTAssertEqual(try JSONDecoder().decode([LifeTheme].self, from: data), [.midnight])
        let mode = try JSONDecoder().decode([LifeAppearanceMode].self, from: JSONEncoder().encode([LifeAppearanceMode.dark]))
        XCTAssertEqual(mode, [.dark])
    }
}
