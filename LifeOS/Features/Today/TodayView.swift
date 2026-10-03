import SwiftUI

/// 今日画面の遷移先
enum TodayRoute: Hashable {
    case profile
    case inbox
    case memories
}

/// 今日画面（v2 Editorial Living）。
/// 同じ白いカードを並べるのではなく、セクションごとに大きさ・背景・文字・カテゴリー色に強弱をつける。
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
            VStack(alignment: .leading, spacing: LifeSpacing.xl) {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    header
                    hero
                    if viewModel.showsScopeFilter {
                        LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                    }
                }

                if let message = viewModel.feedbackMessage {
                    feedbackBanner(message)
                        .transition(.opacity)
                }

                if !viewModel.focusItems.isEmpty {
                    focusSection
                }
                if !viewModel.leftovers.isEmpty {
                    leftoverSection
                }
                if let next = viewModel.nextEvent {
                    nextSection(next)
                }
                if viewModel.showsInviteCard {
                    inviteCard
                }
                if viewModel.hasNoSchedule {
                    LifeCard {
                        LifeEmptyState(systemImage: "leaf", title: "今日の予定はありません", message: "ゆっくり過ごしましょう。")
                    }
                }
                if !viewModel.visibleMemories.isEmpty {
                    memorySection
                }

                autopilotSection

                if !viewModel.habits.isEmpty {
                    habitSection
                }
                if viewModel.inboxCount > 0 {
                    inboxRow
                }

                moneySection

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
        .sheet(isPresented: $viewModel.isShowingInvite) {
            SharingFlowView(item: viewModel.invitingItem, store: store)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
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
            withAnimation(.easeInOut(duration: 0.3)) { changes() }
        }
    }

    // MARK: - ヘッダー・ヒーロー

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(viewModel.dateTitle)
                    .font(LifeTypography.editorialDate)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.japaneseDateTitle)
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityElement(children: .ignore)
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

    private var hero: some View {
        LifeHeroCard {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                Text(viewModel.greeting)
                    .font(LifeTypography.heroTitle)
                    .foregroundStyle(LifeColors.onHero)
                Text(viewModel.subtitle)
                    .font(LifeTypography.editorialCopy)
                    .foregroundStyle(LifeColors.onHeroSecondary)
                Text(viewModel.usageCopy)
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.onHeroSecondary)
                    .padding(.top, LifeSpacing.xs)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 家族招待

    private var inviteCard: some View {
        LifeEditorialCard(eyebrow: "FAMILY", title: "パートナーを招待", tint: LifeCategoryColors.mistBlue) {
            Text("買い物・家事・予定を、ふたりで同じ画面から。")
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
            LifeButton("招待する", systemImage: "person.badge.plus", kind: .secondary) {
                viewModel.startInvite()
            }
        }
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
    }

    /// セクションの小見出し＋セリフ体の大見出し
    private func sectionHeading(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text(eyebrow)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(LifeTypography.editorialTitle)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - 今日これだけ

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            sectionHeading(eyebrow: "TODAY", title: "今日これだけ")

            LifeCard(padding: LifeSpacing.md) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    ForEach(Array(viewModel.focusItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            LifeDivider()
                        }
                        HStack(alignment: .center, spacing: LifeSpacing.sm) {
                            Text(viewModel.focusNumber(index))
                                .font(LifeTypography.numeral)
                                .foregroundStyle(LifeColors.accent)
                                .accessibilityHidden(true)
                            taskRow(item)
                        }
                    }

                    if viewModel.isFocusCompleted {
                        Text(viewModel.focusCompletedMessage)
                            .font(LifeTypography.editorialCopy)
                            .foregroundStyle(LifeColors.primary)
                            .padding(.top, LifeSpacing.sm)
                            .transition(.opacity)
                    }
                }
            }

            if !viewModel.restItems.isEmpty {
                Button {
                    animate { viewModel.isShowingRest.toggle() }
                } label: {
                    HStack(spacing: LifeSpacing.xs) {
                        Text(viewModel.restToggleTitle)
                            .font(LifeTypography.callout)
                        Image(systemName: viewModel.isShowingRest ? "chevron.up" : "chevron.down")
                            .font(LifeTypography.footnote)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(viewModel.isShowingRest ? "残りのやることを閉じます" : "残りのやることを表示します")

                if viewModel.isShowingRest {
                    VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                        ForEach(viewModel.restItems) { item in
                            taskRow(item)
                        }
                    }
                    .padding(.horizontal, LifeSpacing.md)
                    .transition(.opacity)
                }
            }
        }
    }

    private func taskRow(_ item: LifeItem) -> some View {
        LifeTaskRow(
            title: item.title,
            detail: viewModel.detailText(for: item),
            isCompleted: item.isCompleted,
            tint: item.kind.tint,
            onLater: { viewModel.startPostponing(item) }
        ) {
            animate { viewModel.toggle(item) }
        }
    }

    // MARK: - 昨日残ったもの（未完了救済）

    private var leftoverSection: some View {
        LifeEditorialCard(eyebrow: "LEFTOVER", title: viewModel.leftoverTitle) {
            Text("できなかった日もあります。押して、どうするか選ぶだけで大丈夫です。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
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
        let isExpanded = viewModel.expandedLeftoverID == item.id
        return VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Button {
                animate { viewModel.toggleLeftoverExpansion(item) }
            } label: {
                HStack(spacing: LifeSpacing.sm) {
                    LifeCategoryDot(color: item.kind.tint)
                    Text(item.title)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Spacer(minLength: LifeSpacing.xs)
                    Text(viewModel.leftoverDetail(for: item))
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title)、\(viewModel.leftoverDetail(for: item))")
            .accessibilityHint(isExpanded ? "選択肢を閉じます" : "どうするか選べます")

            if isExpanded {
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
                .padding(.bottom, LifeSpacing.xs)
                .transition(.opacity)
            }
        }
    }

    private func smallActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, LifeSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
                .background(Capsule().fill(LifeColors.surface))
                .overlay(Capsule().stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - NEXT

    private func nextSection(_ item: LifeItem) -> some View {
        HStack(alignment: .top, spacing: LifeSpacing.md) {
            RoundedRectangle(cornerRadius: LifeSpacing.categoryBar)
                .fill(LifeItemKind.event.tint)
                .frame(width: LifeSpacing.categoryBar)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("NEXT")
                        .font(LifeTypography.label)
                        .tracking(LifeTypography.labelTracking)
                        .foregroundStyle(LifeColors.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.md) {
                        Text(viewModel.timeText(for: item))
                            .font(LifeTypography.timeLarge)
                            .foregroundStyle(LifeColors.primary)
                        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                            Text(item.title)
                                .font(LifeTypography.editorialHeadline)
                                .foregroundStyle(LifeColors.text)
                            Text(viewModel.remainingText(for: item))
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("次の予定、\(viewModel.timeText(for: item))、\(item.title)、\(viewModel.remainingText(for: item))")

                if viewModel.canShare(item) {
                    Button {
                        viewModel.shareTapped(item)
                    } label: {
                        Label("パートナーと共有", systemImage: "person.2")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.primary)
                            .frame(minHeight: LifeSpacing.minTapTarget)
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.laterEvents.isEmpty {
                    LifeDivider()
                        .padding(.vertical, LifeSpacing.xs)
                    Text("このあと")
                        .font(LifeTypography.label)
                        .tracking(LifeTypography.labelTracking)
                        .foregroundStyle(LifeColors.secondaryText)
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
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .fill(LifeColors.paper)
        )
    }

    // MARK: - 暮らしメモリー

    private var memorySection: some View {
        LifeEditorialCard(eyebrow: "MEMORY", title: "暮らしメモリー", tint: LifeCategoryColors.sage) {
            ForEach(Array(viewModel.visibleMemories.enumerated()), id: \.element.id) { index, memory in
                if index > 0 {
                    LifeDivider()
                }
                memoryRow(memory)
            }
            NavigationLink(value: TodayRoute.memories) {
                HStack(spacing: LifeSpacing.xxs) {
                    Text(viewModel.hasMoreMemories ? "ほかのメモリーも見る" : "すべて見る")
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.primary)
                .frame(minHeight: LifeSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
        }
    }

    private func memoryRow(_ memory: LifeMemory) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(memory.title)
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                Text(viewModel.memoryMessage(memory))
                    .font(LifeTypography.editorialCopy)
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

    private var autopilotSection: some View {
        LifeEditorialCard(eyebrow: "ENERGY", title: "今日の余力", tint: LifeCategoryColors.terracotta) {
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
                VStack(alignment: .leading, spacing: 0) {
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

    private var habitSection: some View {
        LifeEditorialCard(eyebrow: "HABIT", title: "習慣", tint: LifeCategoryColors.lavenderGray) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.habits) { item in
                    LifeTaskRow(title: item.title, isCompleted: item.isCompleted) {
                        animate { viewModel.toggle(item) }
                    }
                }
            }
            Text("できた日だけ、チェックすれば十分です。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
    }

    // MARK: - Inbox

    private var inboxRow: some View {
        NavigationLink(value: TodayRoute.inbox) {
            HStack(spacing: LifeSpacing.sm) {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(LifeColors.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("Inbox")
                        .font(LifeTypography.editorialHeadline)
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
            .padding(LifeSpacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                    .fill(LifeColors.paper)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Inboxを開いて、まとめて整理できます")
    }

    // MARK: - MONEY

    private var moneySection: some View {
        LifeEditorialCard(eyebrow: "MONEY", tint: LifeCategoryColors.warmGold) {
            LifeMoneyRow(title: "今日", amount: viewModel.todaySpending)
            LifeDivider()
            LifeMoneyRow(title: "今月", amount: viewModel.monthSpending, isEmphasized: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("お金")
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
