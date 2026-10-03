import SwiftUI

/// 今日画面の遷移先
enum TodayRoute: Hashable {
    case profile
    case inbox
    case memories
}

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store: LifeStore

    private let leftoverActionColumns = [
        GridItem(.flexible(), spacing: LifeSpacing.xs),
        GridItem(.flexible(), spacing: LifeSpacing.xs)
    ]

    init(store: LifeStore, appState: AppState) {
        self.store = store
        _viewModel = State(initialValue: TodayViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                header
                LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                greeting

                if let message = viewModel.feedbackMessage {
                    feedbackBanner(message)
                }

                if !viewModel.focusItems.isEmpty {
                    focusCard
                }
                if !viewModel.leftovers.isEmpty {
                    leftoverCard
                }
                if let next = viewModel.nextEvent {
                    nextCard(next)
                }
                if viewModel.hasNoSchedule {
                    LifeCard {
                        LifeEmptyState(systemImage: "leaf", title: "今日の予定はありません")
                    }
                }
                if !viewModel.visibleMemories.isEmpty {
                    memoryCard
                }

                autopilotCard

                if !viewModel.habits.isEmpty {
                    habitCard
                }
                if viewModel.inboxCount > 0 {
                    inboxCard
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.scope)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .navigationDestination(for: TodayRoute.self) { route in
            switch route {
            case .profile:
                ProfileView(appState: appState)
            case .inbox:
                InboxView(store: store)
            case .memories:
                LifeMemoryView(store: store)
            }
        }
        .postponeSheet(item: $viewModel.postponingItem) { item, option in
            animate { viewModel.postpone(item, to: option) }
        }
        .task(id: viewModel.feedbackMessage) {
            // 一言は数秒で消す
            guard viewModel.feedbackMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            animate { viewModel.feedbackMessage = nil }
        }
    }

    /// Reduce Motion のときはアニメーションしない
    private func animate(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { changes() }
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

    private func feedbackBanner(_ message: String) -> some View {
        HStack(spacing: LifeSpacing.xs) {
            Image(systemName: "checkmark")
                .accessibilityHidden(true)
            Text(message)
        }
        .font(LifeTypography.footnote)
        .foregroundStyle(LifeColors.text)
        .padding(.horizontal, LifeSpacing.md)
        .padding(.vertical, LifeSpacing.xs)
        .background(Capsule().fill(LifeColors.primarySubtle))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - 今日これだけ

    private var focusCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("TODAY", spokenTitle: "今日これだけ")
                Text("今日これだけ")
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
                    .padding(.bottom, LifeSpacing.xxs)

                taskRows(viewModel.focusItems)

                if viewModel.isFocusCompleted {
                    Text(viewModel.focusCompletedMessage)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.primary)
                        .padding(.top, LifeSpacing.xxs)
                        .transition(.opacity)
                }

                if !viewModel.restItems.isEmpty {
                    LifeDivider()
                        .padding(.vertical, LifeSpacing.xs)
                    Button {
                        animate { viewModel.isShowingRest.toggle() }
                    } label: {
                        HStack {
                            Text(viewModel.restToggleTitle)
                                .font(LifeTypography.callout)
                            Spacer()
                            Image(systemName: viewModel.isShowingRest ? "chevron.up" : "chevron.down")
                                .font(LifeTypography.footnote)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(viewModel.isShowingRest ? "残りのやることを閉じます" : "残りのやることを表示します")

                    if viewModel.isShowingRest {
                        taskRows(viewModel.restItems)
                    }
                }
            }
        }
    }

    private func taskRows(_ items: [LifeItem]) -> some View {
        ForEach(items) { item in
            LifeTaskRow(
                title: item.title,
                detail: viewModel.detailText(for: item),
                isCompleted: item.isCompleted,
                onLater: { viewModel.startPostponing(item) }
            ) {
                animate { viewModel.toggle(item) }
            }
        }
    }

    // MARK: - 昨日残ったもの（未完了救済）

    private var leftoverCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("LEFTOVER", spokenTitle: viewModel.leftoverTitle)
                Text(viewModel.leftoverTitle)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                Text("できなかった日もあります。どうするか選ぶだけで大丈夫です。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(viewModel.leftovers.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        LifeDivider()
                    }
                    leftoverRow(item)
                }
            }
        }
    }

    private func leftoverRow(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(item.title)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.leftoverDetail(for: item))
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityElement(children: .combine)

            LazyVGrid(columns: leftoverActionColumns, spacing: LifeSpacing.xs) {
                smallActionButton("今日に表示", systemImage: "sun.max") {
                    animate { viewModel.showToday(item) }
                }
                smallActionButton("今週に回す", systemImage: "calendar") {
                    animate { viewModel.moveToThisWeek(item) }
                }
                smallActionButton("あとで", systemImage: "clock.arrow.circlepath") {
                    viewModel.startPostponing(item)
                }
                smallActionButton("もうやらない", systemImage: "xmark") {
                    animate { viewModel.dropLeftover(item) }
                }
            }
        }
        .padding(.vertical, LifeSpacing.xxs)
    }

    private func smallActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
                .background(Capsule().fill(LifeColors.primarySubtle))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

            if !viewModel.laterEvents.isEmpty {
                laterEventsSection
            }
        }
    }

    /// NEXT の後に続く今日の予定
    private var laterEventsSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeDivider()
                .padding(.vertical, LifeSpacing.sm)
            LifeSectionTitle("このあと")
            ForEach(viewModel.laterEvents) { event in
                HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                    Text(viewModel.timeText(for: event))
                        .font(LifeTypography.amount)
                        .foregroundStyle(LifeColors.primary)
                    Text(event.title)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: LifeSpacing.minTapTarget)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - 暮らしメモリー

    private var memoryCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                HStack {
                    LifeSectionTitle("MEMORY", spokenTitle: "暮らしメモリー")
                    NavigationLink(value: TodayRoute.memories) {
                        Text("すべて見る")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.primary)
                            .frame(minHeight: LifeSpacing.minTapTarget)
                    }
                    .buttonStyle(.plain)
                }
                Text("暮らしメモリー")
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)

                ForEach(Array(viewModel.visibleMemories.enumerated()), id: \.element.id) { index, memory in
                    if index > 0 {
                        LifeDivider()
                    }
                    memoryRow(memory)
                }
            }
        }
    }

    private func memoryRow(_ memory: LifeMemory) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(memory.title)
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.memoryMessage(memory))
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.memoryCycle(memory))
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: LifeSpacing.xs) {
                if let actionTitle = viewModel.memoryActionTitle(memory) {
                    smallActionButton(actionTitle, systemImage: "plus") {
                        animate { viewModel.performMemoryAction(memory) }
                    }
                }
                if viewModel.canSkipMemory(memory) {
                    smallActionButton("今回はスキップ", systemImage: "forward") {
                        animate { viewModel.skipMemory(memory) }
                    }
                }
            }
        }
        .padding(.vertical, LifeSpacing.xxs)
    }

    // MARK: - 今日の余力（家事オートパイロット）

    private var autopilotCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("ENERGY", spokenTitle: "今日の余力")
                Text("今日の余力")
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)

                HStack(spacing: LifeSpacing.xs) {
                    ForEach(EnergyLevel.allCases) { level in
                        LifeChip(title: "\(level.emoji) \(level.label)", isSelected: viewModel.energy == level) {
                            animate { viewModel.selectEnergy(level) }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("余力 \(level.label)")
                    }
                }

                if viewModel.energy == nil {
                    Text("選ぶと、今日やる家事の量を合わせます。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                } else {
                    Text(viewModel.autopilotSummary)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .padding(.top, LifeSpacing.xxs)
                    ForEach(viewModel.autopilotChores) { chore in
                        LifeTaskRow(
                            title: chore.title,
                            trailing: "\(chore.minutes)分",
                            isCompleted: viewModel.isChoreDone(chore)
                        ) {
                            animate { viewModel.toggleChore(chore) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 習慣

    private var habitCard: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("HABIT", spokenTitle: "習慣")
                ForEach(viewModel.habits) { item in
                    LifeTaskRow(title: item.title, isCompleted: item.isCompleted) {
                        animate { viewModel.toggle(item) }
                    }
                }
                Text("できた日だけ、チェックすれば十分です。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
    }

    // MARK: - Inbox

    private var inboxCard: some View {
        NavigationLink(value: TodayRoute.inbox) {
            LifeCard {
                HStack(spacing: LifeSpacing.sm) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(LifeColors.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                        Text("Inbox")
                            .font(LifeTypography.headline)
                            .foregroundStyle(LifeColors.text)
                        Text(viewModel.inboxSummary)
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    Spacer(minLength: LifeSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Inboxを開いて、まとめて整理できます")
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
