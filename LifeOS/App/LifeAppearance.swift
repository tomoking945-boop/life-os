import SwiftUI
import UIKit

/// タブバー・ナビゲーションバーの見た目を DesignSystem に合わせる
enum LifeAppearance {
    static func configure() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(LifeColors.background)
        tabBar.shadowColor = UIColor(LifeColors.divider)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navigationBar = UINavigationBarAppearance()
        navigationBar.configureWithOpaqueBackground()
        navigationBar.backgroundColor = UIColor(LifeColors.background)
        navigationBar.shadowColor = .clear
        navigationBar.titleTextAttributes = [.foregroundColor: UIColor(LifeColors.text)]
        navigationBar.largeTitleTextAttributes = [.foregroundColor: UIColor(LifeColors.text)]
        UINavigationBar.appearance().standardAppearance = navigationBar
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBar
        UINavigationBar.appearance().compactAppearance = navigationBar
    }
}
