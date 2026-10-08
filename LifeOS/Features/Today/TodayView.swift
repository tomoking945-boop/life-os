import SwiftUI

/// 今日画面の遷移先
enum TodayRoute: Hashable {
    case profile
    case inbox
    case memories
    /// 習慣の一覧・追加・編集（2026-10-08）
    case habits
}

/// 今日画面（Calm Future：生活のコックピット）。
/// 時間帯でごく弱く変わる背景の上に、Ambient Header と Living Timeline を置く。
/// 同じ角丸カードを並べず、余白・細い線・背景面の切り替え・横スクロール・大きな数字で区切る。
struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    ambientHeader
                    if viewModel.showsScopeFilter {
                        LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                    }
                }

                if viewModel.hasNoSchedule {
                    emptyState
                } else {
                    timelineSection
                }

                // LifeOSからの提案（第3段階）：短い提案だけ。押したときだけ変え、「元に戻す」を出す
                if let suggestion = viewModel.suggestion {
                    suggestionCard(suggestion)
                        .transition(.opacity)
                }

                if !viewModel.leftovers.isEmpty {
                    leftoverSection
                }
                if viewModel.showsInviteCard {
                    inviteCard
                }
                if !viewModel.visibleMemories.isEmpty {
                    memorySection
                }

                autopilotSection

                if viewModel.hasHabits {
                    habitSection
                } else {
                    addHabitLink
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
            .animation(LifeMotion.animation(LifeMotion.standard, reduceMotion: reduceMotion), value: viewModel.scope)
        }
        .background(
            LifeAmbientBackground(timeOfDay: viewModel.timeOfDay)
                .animation(LifeMotion.animation(LifeMotion.gentle, reduceMotion: reduceMotion), value: viewModel.timeOfDay)
        )
        .lifeFeedbackBanner($viewModel.feedback) {
            viewModel.performUndo()
        }
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
            case .habits:
                HabitsView(store: store)
            }
        }
        .sheet(isPresented: $viewModel.isShowingInvite) {
            SharingFlowView(item: viewModel.invitingItem, store: store)
                .lifeSheetPresentation()
        }
        .postponeSheet(item: $viewModel.postponingItem) { item, option in
            animate { viewModel.postpone(item, to: option) }
        }
    }

    /// Reduce Motion のときはアニメーションしない
    private func animate(_ changes: () -> Void) {
        withLifeAnimation(reduceMotion: reduceMotion, changes)
    }

    // MARK: - ヘッダー・Ambient Header

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

    /// カードに入れず、背景の上に直接置く一言（いま必要なことだけを静かに出す）
    private var ambientHeader: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            Text(viewModel.greeting)
                .font(LifeTypography.heroTitle)
                .foregroundStyle(LifeColors.text)
            Text(viewModel.ambientMessage)
                .font(LifeTypography.ambientMessage)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            HStack(alignment: .center, spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeColors.accent)
                Text(viewModel.ambientSubMessage)
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Text(viewModel.usageCopy)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .padding(.top, LifeSpacing.xxs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.ambientSpokenText)
    }

    // MARK: - 見出し

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

    /// 少し小さい見出し（余力・習慣・メモリーなど）
    private func compactHeading(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text(eyebrow)
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(LifeTypography.editorialHeadline)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Living Timeline（今日これだけ・NEXT・このあと）

    private var timelineSection: some View {
        let sections = viewModel.timelineSections
        let hasExtra = !viewModel.extraItems.isEmpty
        return VStack(alignment: .leading, spacing: LifeSpacing.md) {
            sectionHeading(eyebrow: "LIVING TIMELINE", title: "今日の流れ")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    LifeTimelineSection(
                        eyebrow: section.slot.eyebrow,
                        japaneseLabel: section.slot.japaneseLabel,
                        spokenLabel: section.slot.spokenLabel,
                        tint: viewModel.markerKind(for: section).tint,
                        isTime: viewModel.isTime(section),
                        isCurrent: viewModel.isCurrent(section),
                        isLast: index == sections.count - 1 && !hasExtra
                    ) {
                        ForEach(section.items) { item in
                            timelineRow(item)
                        }
                    }
                }

                if hasExtra {
                    extraTimelineSection
                }
            }

            if viewModel.isFocusCompleted {
                Text(viewModel.focusCompletedMessage)
                    .font(LifeTypography.editorialCopy)
                    .foregroundStyle(LifeColors.primary)
                    .transition(.opacity)
            }
        }
    }

    /// 「余力があれば」：今日これだけ に入らなかったものを折りたたむ
    private var extraTimelineSection: some View {
        LifeTimelineSection(
            eyebrow: SoftTime.ifYouHaveTime.eyebrow,
            japaneseLabel: SoftTime.ifYouHaveTime.label,
            spokenLabel: SoftTime.ifYouHaveTime.label,
            tint: LifeTimelineStyle.quietDot,
            isLast: true
        ) {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.extraItems) { item in
                        taskRow(item)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func timelineRow(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: LifeSpacing.xs) {
                if let number = viewModel.focusNumber(for: item) {
                    Text(number)
                        .font(LifeTypography.numeral)
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(width: LifeSpacing.timelineNumeralWidth, alignment: .leading)
                        .accessibilityHidden(true)
                }
                LifeTaskRow(
                    title: item.title,
                    detail: viewModel.timelineDetail(for: item),
                    isCompleted: item.isCompleted,
                    tint: item.kind.tint,
                    onLater: { viewModel.startPostponing(item) }
                ) {
                    animate { viewModel.toggle(item) }
                }
            }

            if viewModel.isNextEvent(item) && viewModel.canShare(item) {
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

    private var emptyState: some View {
        LifeEmptyState(systemImage: "leaf", title: "今日の予定はありません", message: "ゆっくり過ごしましょう。")
            .padding(LifeSpacing.cardPadding)
            .frame(maxWidth: .infinity)
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
    }

    // MARK: - 昨日残ったもの（未完了救済）：細い線で区切る

    private var leftoverSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            compactHeading(eyebrow: "LEFTOVER", title: viewModel.leftoverTitle)
            Text("できなかった日もあります。押して、どうするか選ぶだけで大丈夫です。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                LifeDivider()
                ForEach(viewModel.visibleLeftovers) { item in
                    leftoverRow(item)
                    LifeDivider()
                }
            }

            if viewModel.hasHiddenLeftovers {
                Button {
                    animate { viewModel.isShowingAllLeftovers.toggle() }
                } label: {
                    HStack(spacing: LifeSpacing.xs) {
                        Text(viewModel.leftoverToggleTitle)
                            .font(LifeTypography.callout)
                        Image(systemName: viewModel.isShowingAllLeftovers ? "chevron.up" : "chevron.down")
                            .font(LifeTypography.footnote)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(viewModel.isShowingAllLeftovers ? "残っているものを閉じます" : "残っているものをすべて表示します")
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
        LifeCapsuleButton(title, systemImage: systemImage, isFullWidth: true, action: action)
    }

    // MARK: - LifeOSからの提案（第3段階）

    private func suggestionCard(_ suggestion: LifeSuggestion) -> some View {
        LifeSuggestionCard(
            message: suggestion.message,
            reason: suggestion.reason,
            primaryTitle: suggestion.acceptTitle,
            primarySystemImage: "arrow.turn.down.right",
            onPrimary: { animate { viewModel.acceptSuggestion(suggestion) } },
            onSecondary: { animate { viewModel.keepSuggestion(suggestion) } }
        )
    }

    // MARK: - 家族招待：静かな提案として

    private var inviteCard: some View {
        LifeSuggestionCard(
            eyebrow: "FAMILY",
            message: "買い物・家事・予定を、ふたりで同じ画面から。",
            primaryTitle: "パートナーを招待",
            primarySystemImage: "person.badge.plus",
            onPrimary: { viewModel.startInvite() },
            secondaryTitle: nil
        )
    }

    // MARK: - 暮らしメモリー：小さな横スクロール

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(alignment: .bottom) {
                compactHeading(eyebrow: "MEMORY", title: "暮らしメモリー")
                Spacer(minLength: LifeSpacing.xs)
                NavigationLink(value: TodayRoute.memories) {
                    HStack(spacing: LifeSpacing.xxs) {
                        Text(viewModel.hasMoreMemories ? "ほかも見る" : "すべて見る")
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.primary)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.hasMoreMemories ? "ほかのメモリーも見る" : "暮らしメモリーをすべて見る")
            }

            if dynamicTypeSize.isAccessibilitySize {
                // 文字が大きいときは横スクロールにせず、縦に並べる
                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    ForEach(viewModel.visibleMemories) { memory in
                        memoryCard(memory)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: LifeSpacing.sm) {
                        ForEach(viewModel.visibleMemories) { memory in
                            memoryCard(memory)
                                .frame(width: LifeSpacing.insightCardWidth)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LifeSpacing.screenHorizontal)
                }
                // 画面の端まで流れるように見せる（カードの影も切らない）
                .scrollClipDisabled()
                .padding(.horizontal, -LifeSpacing.screenHorizontal)
            }
        }
    }

    private func memoryCard(_ memory: LifeMemory) -> some View {
        LifeInsightCard(
            title: memory.title,
            message: viewModel.memoryMessage(memory),
            detail: viewModel.memoryCycle(memory),
            tint: viewModel.memoryKind(memory).tint
        ) {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                if let actionTitle = viewModel.memoryActionTitle(memory) {
                    LifeCapsuleButton(actionTitle, systemImage: "plus") {
                        animate { viewModel.performMemoryAction(memory) }
                    }
                }
                if viewModel.canSkipMemory(memory) {
                    LifeCapsuleButton("今回はスキップ", systemImage: "forward") {
                        animate { viewModel.skipMemory(memory) }
                    }
                }
            }
        }
    }

    // MARK: - 今日の余力（家事オートパイロット）：背景面を切り替える

    private var autopilotSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            compactHeading(eyebrow: "ENERGY", title: "今日の余力")
            // 絵文字を上・文字を下にして、3つ並べても文字が切れないようにする
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LifeSpacing.xs) {
                    energyTiles
                }
                VStack(spacing: LifeSpacing.xs) {
                    energyTiles
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
                            isCompleted: viewModel.isChoreDone(chore),
                            tint: LifeCategoryColors.terracotta
                        ) {
                            animate { viewModel.toggleChore(chore) }
                        }
                    }
                }
            }
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
    }

    @ViewBuilder
    private var energyTiles: some View {
        ForEach(EnergyLevel.allCases) { level in
            LifeChoiceTile(symbol: level.emoji, title: level.label, isSelected: viewModel.energy == level) {
                animate { viewModel.selectEnergy(level) }
            }
            .accessibilityLabel("余力 \(level.label)")
        }
    }

    // MARK: - 習慣：余白だけで区切る（第3段階：7日の柔らかい点で生活リズムとして見せる）

    /// 習慣が1つも無いときの、静かな入口
    private var addHabitLink: some View {
        NavigationLink(value: TodayRoute.habits) {
            Label("習慣を追加する", systemImage: "leaf")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.primary)
                .frame(minHeight: LifeSpacing.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityHint("習慣の画面を開きます")
    }

    private var habitSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            HStack(alignment: .bottom) {
                compactHeading(eyebrow: "RHYTHM", title: "習慣")
                Spacer(minLength: LifeSpacing.xs)
                NavigationLink(value: TodayRoute.habits) {
                    HStack(spacing: LifeSpacing.xxs) {
                        Text("追加・編集")
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.primary)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("習慣を追加・編集")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.visibleHabits) { habit in
                    LifeHabitRow(
                        title: habit.title,
                        message: viewModel.rhythmMessage(habit),
                        days: viewModel.rhythmDays(habit),
                        isDone: viewModel.isHabitDone(habit)
                    ) {
                        animate { viewModel.toggleHabit(habit) }
                    }
                }
                // 第3段階より前に日付つきで追加した習慣は、従来どおりの行で出す
                ForEach(viewModel.legacyHabitItems) { item in
                    LifeTaskRow(title: item.title, isCompleted: item.isCompleted, tint: LifeCategoryColors.lavenderGray) {
                        animate { viewModel.toggle(item) }
                    }
                }
            }

            if viewModel.canToggleHabits {
                Button {
                    animate { viewModel.isShowingAllHabits.toggle() }
                } label: {
                    HStack(spacing: LifeSpacing.xs) {
                        Text(viewModel.habitToggleTitle)
                            .font(LifeTypography.callout)
                        Image(systemName: viewModel.isShowingAllHabits ? "chevron.up" : "chevron.down")
                            .font(LifeTypography.footnote)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(viewModel.isShowingAllHabits ? "軽い習慣だけにします" : "ほかの習慣も表示します")
            }

            Text(viewModel.habitFootnote)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inbox：細い線で区切る

    private var inboxRow: some View {
        VStack(spacing: 0) {
            LifeDivider()
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
                .padding(.vertical, LifeSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Inboxを開いて、まとめて整理できます")
            LifeDivider()
        }
    }

    // MARK: - MONEY：大きな数字

    private var moneySection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeCategoryColors.warmGold)
                Text("MONEY")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.xl) {
                    todayMoney
                    monthMoney
                }
                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    todayMoney
                    monthMoney
                }
            }

            ProgressView(value: viewModel.budgetRatio)
                .tint(LifeCategoryColors.warmGold)
                .accessibilityLabel("今月の予算")
                .accessibilityValue("\(LifeFormatters.yenSpoken(viewModel.monthSpending))使用、予算\(LifeFormatters.yenSpoken(viewModel.monthlyBudget))")
            Text(viewModel.budgetText)
                .font(LifeTypography.caption)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("お金")
    }

    private var todayMoney: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text("今日")
                .font(LifeTypography.caption)
                .foregroundStyle(LifeColors.secondaryText)
            Text(LifeFormatters.yen(viewModel.todaySpending))
                .font(LifeTypography.bigNumeral)
                .foregroundStyle(LifeColors.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の支出 \(LifeFormatters.yenSpoken(viewModel.todaySpending))")
    }

    private var monthMoney: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text("今月")
                .font(LifeTypography.caption)
                .foregroundStyle(LifeColors.secondaryText)
            Text(LifeFormatters.yen(viewModel.monthSpending))
                .font(LifeTypography.amountLarge)
                .foregroundStyle(LifeColors.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今月の支出 \(LifeFormatters.yenSpoken(viewModel.monthSpending))")
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
