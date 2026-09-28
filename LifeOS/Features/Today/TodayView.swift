import SwiftUI

/// 今日画面の遷移先
enum TodayRoute: Hashable {
    case profile
}

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @Environment(AppState.self) private var appState

    init(store: LifeStore, appState: AppState) {
        _viewModel = State(initialValue: TodayViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                header
                LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                greeting

                if let next = viewModel.nextEvent {
                    nextCard(next)
                }
                if !viewModel.todayTasks.isEmpty {
                    todayCard
                }
                if !viewModel.partnerTasks.isEmpty {
                    sharedCard
                }
                if viewModel.hasNoSchedule {
                    LifeCard {
                        LifeEmptyState(systemImage: "leaf", title: "今日の予定はありません")
                    }
                }

                moneyCard

                // Free のときだけ表示。Premium では条件ごと外れるので余白も残らない。
                // TODO: 広告カードの表示位置は仕様未定。現状は重要操作と離すため画面の最後に配置。
                if viewModel.showsAd {
                    MockAdCard()
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
            .animation(.easeInOut(duration: 0.25), value: viewModel.scope)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .navigationDestination(for: TodayRoute.self) { route in
            switch route {
            case .profile:
                ProfileView(appState: appState)
            }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .center) {
            Text(viewModel.dateTitle)
                .font(LifeTypography.headline)
                .foregroundStyle(LifeColors.text)
                .accessibilityLabel(viewModel.spokenDateTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink(value: TodayRoute.profile) {
                LifeAvatar(name: appState.profile.name, image: appState.profileImage, size: .medium)
                    .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("プロフィール")
            .accessibilityHint("プロフィール画面を開きます")
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Text(viewModel.greeting)
                .font(LifeTypography.display)
                .foregroundStyle(LifeColors.primary)
            Text(viewModel.subtitle)
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - NEXT

    private func nextCard(_ item: LifeItem) -> some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("NEXT", spokenTitle: "次の予定")
                Text(viewModel.timeText(for: item))
                    .font(LifeTypography.timeLarge)
                    .foregroundStyle(LifeColors.primary)
                Text(item.title)
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.remainingText(for: item))
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - TODAY

    private var todayCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("TODAY", spokenTitle: "今日のやること")
                taskRows(viewModel.todayTasks)
            }
        }
    }

    // MARK: - SHARED

    private var sharedCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("SHARED", spokenTitle: "共有")
                HStack(spacing: LifeSpacing.xs) {
                    LifeAvatar(name: viewModel.partnerName, size: .small)
                    Text(viewModel.partnerName)
                        .font(LifeTypography.headline)
                        .foregroundStyle(LifeColors.text)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(viewModel.partnerName)の担当")
                .padding(.top, LifeSpacing.xs)
                taskRows(viewModel.partnerTasks)
            }
        }
    }

    private func taskRows(_ items: [LifeItem]) -> some View {
        ForEach(items) { item in
            LifeTaskRow(
                title: item.title,
                detail: viewModel.detailText(for: item),
                isCompleted: item.isCompleted
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggle(item)
                }
            }
        }
    }

    // MARK: - MONEY

    private var moneyCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("MONEY", spokenTitle: "お金")
                LifeMoneyRow(title: "今日", amount: viewModel.todaySpending)
                LifeDivider()
                LifeMoneyRow(title: "今月", amount: viewModel.monthSpending)
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        TodayView(store: store, appState: appState)
    }
    .environment(appState)
    .environment(store)
}
