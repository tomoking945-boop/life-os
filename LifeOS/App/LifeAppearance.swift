import SwiftUI
import UIKit

/// タブバー・ナビゲーションバーの見た目を DesignSystem に合わせる。
/// Calm Future 第4段階：
/// - タブバーは Ivory のすりガラス寄り（下の内容がごく薄く透ける）。選択は Deep Forest、それ以外は補助テキストの色
/// - ナビゲーションバーの見出しはセリフ体。上端では背景を透明にして、時間帯の背景とつなげる
/// - 「透明度を下げる」がオンのときは、システムがすりガラスを不透明な面に置き換える
/// テーマとダークモード（2026-10-08）：色はテーマとライト／ダークに合わせてその場で決まる（LifeThemeRuntime）。
/// すりガラスもライト／ダークに合わせる。
enum LifeAppearance {
    /// タブバーに重ねる Ivory の濃さ
    static let tabBarTintOpacity: CGFloat = 0.78

    static func configure() {
        configureTabBar()
        configureNavigationBar()
    }

    private static func configureTabBar() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        tabBar.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabBar.backgroundColor = tintedBackground
        tabBar.shadowColor = LifeThemeRuntime.uiColor { $0.divider }

        let selected = LifeThemeRuntime.uiColor { $0.primary }
        let normal = LifeThemeRuntime.uiColor { $0.secondaryText }
        for layout in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance, tabBar.compactInlineLayoutAppearance] {
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
            layout.normal.iconColor = normal
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
        }

        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    private static func configureNavigationBar() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: LifeThemeRuntime.uiColor { $0.text },
            .font: serifFont(.headline)
        ]
        let largeTitleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: LifeThemeRuntime.uiColor { $0.text },
            .font: serifFont(.largeTitle)
        ]

        // スクロールしたとき：Ivory のすりガラス
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        standard.backgroundColor = tintedBackground
        standard.shadowColor = LifeThemeRuntime.uiColor { $0.divider }
        standard.titleTextAttributes = titleAttributes
        standard.largeTitleTextAttributes = largeTitleAttributes

        // 上端にいるとき：透明（時間帯の背景とつなげる）
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = titleAttributes
        edge.largeTitleTextAttributes = largeTitleAttributes

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().compactAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().tintColor = LifeThemeRuntime.uiColor { $0.primary }
    }

    /// すりガラスに重ねる背景色（テーマとライト／ダークに合わせる）
    private static var tintedBackground: UIColor {
        LifeThemeRuntime.uiColor { $0.background.withAlphaComponent(tabBarTintOpacity) }
    }

    /// 起動したときの文字の大きさ（Dynamic Type）に合わせたセリフ体
    /// TODO: 起動中に文字の大きさを変えたときは、次の起動から反映される（UIKit の見た目の設定は起動時に一度だけ行うため）。
    private static func serifFont(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        // size 0 は「descriptor の大きさのまま」（preferredFont で文字の大きさの設定はすでに反映済み）
        return UIFont(descriptor: descriptor, size: 0)
    }
}
