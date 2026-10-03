import SwiftUI

/// 招待された側が最初に見る画面（Mock）：「わが家へようこそ」
struct WelcomeView: View {
    let item: LifeItem?
    let store: LifeStore
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @State private var isShowingStarter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                LifeHeroCard {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        Text("わが家へようこそ")
                            .font(LifeTypography.heroTitle)
                            .foregroundStyle(LifeColors.onHero)
                        Text("\(appState.profile.name)さんから共有されています")
                            .font(LifeTypography.editorialCopy)
                            .foregroundStyle(LifeColors.onHeroSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let preview = previewItem {
                    SharedItemPreview(item: preview)
                }

                LifeEditorialCard(eyebrow: "SHOPPING", title: "買い物", tint: LifeCategoryColors.sage) {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        ForEach(shoppingTitles, id: \.self) { title in
                            HStack(spacing: LifeSpacing.xs) {
                                LifeCategoryDot(color: LifeCategoryColors.sage)
                                Text(title)
                                    .font(LifeTypography.body)
                                    .foregroundStyle(LifeColors.text)
                            }
                            .frame(minHeight: LifeSpacing.minTapTarget - LifeSpacing.xs)
                        }
                    }
                }

                LifeButton("わが家を始める", systemImage: "house") {
                    isShowingStarter = true
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.lg)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingStarter) {
            SharedStarterView(store: store, onFinish: onFinish)
        }
    }

    /// 見せる予定：共有する項目、無ければ今日以降で最初の共有の予定
    private var previewItem: LifeItem? {
        if let given = item { return given }
        let today = LifeCalendar.startOfDay(LifeCalendar.now)
        return store.items
            .filter { $0.kind == .event && $0.ownership == .shared && !$0.isDropped && $0.displayDate >= today }
            .min { $0.displayDate < $1.displayDate }
    }

    /// 共有の買い物（無ければ Mock の例）
    private var shoppingTitles: [String] {
        let titles = store.items
            .filter { $0.kind == .shopping && $0.ownership == .shared && !$0.isCompleted && !$0.isDropped }
            .map(\.title)
        return titles.isEmpty ? ["牛乳", "卵"] : Array(titles.prefix(4))
    }
}

#Preview {
    NavigationStack {
        WelcomeView(item: nil, store: LifeStore()) {}
    }
    .environment(AppState())
}
