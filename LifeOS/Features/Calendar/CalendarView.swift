import SwiftUI

/// カレンダー（月表示）。日付をタップすると下部にその日の項目を表示する。
/// 週表示は初期版では不要（仕様どおり未実装）。
/// Calm Future 第4段階：時間帯の背景・セリフ体の見出し・カテゴリー色の点・細い線で区切るその日の一覧。
struct CalendarView: View {
    @State private var viewModel: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let store: LifeStore

    init(store: LifeStore, appState: AppState) {
        self.store = store
        _viewModel = State(initialValue: CalendarViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "CALENDAR", title: "カレンダー")

                if viewModel.showsScopeFilter {
                    LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                }

                monthCard
                selectedDaySection
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        // 予定の削除の確認（Build 13）。「予定を削除」は赤（破壊的な操作）
        .alert(
            "この予定を削除しますか？",
            isPresented: Binding(
                get: { viewModel.eventPendingDeletion != nil },
                set: { isPresented in if !isPresented { viewModel.cancelDeleteEvent() } }
            ),
            presenting: viewModel.eventPendingDeletion
        ) { _ in
            Button("予定を削除", role: .destructive) {
                withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                    _ = viewModel.confirmDeleteEvent()
                }
            }
            Button("キャンセル", role: .cancel) { viewModel.cancelDeleteEvent() }
        } message: { item in
            Text("「\(item.title)」を、カレンダーと今日から消します。")
        }
        // 選んだ日から予定を追加（Build 12）。「なんでも追加」はそのまま残す
        .sheet(isPresented: Binding(
            get: { viewModel.eventDraft != nil },
            set: { isPresented in if !isPresented { viewModel.cancelAddingEvent() } }
        )) {
            if let draft = viewModel.eventDraft {
                CalendarEventSheet(draft: draft, sharingBlock: viewModel.eventSharingBlock) { saved in
                    withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                        _ = viewModel.saveEvent(saved)
                    }
                } onCancel: {
                    viewModel.cancelAddingEvent()
                }
                .presentationDetents([.medium, .large])
                .lifeSheetPresentation()
            }
        }
        // 既存の予定を編集（Build 15）。タイトル・日付・終日／時刻を変更する。
        // Build 17：保存先（自分だけ／わが家で共有）も変えられる。「自分だけ」へ変えるときは確認を出す
        .sheet(isPresented: Binding(
            get: { viewModel.eventEditSession != nil },
            set: { isPresented in if !isPresented { viewModel.cancelEditingEvent() } }
        )) {
            if let session = viewModel.eventEditSession {
                CalendarEventSheet(
                    draft: session.draft,
                    sharingBlock: viewModel.editSharingBlock,
                    purpose: .edit,
                    originalDestination: session.originalDestination
                ) { saved in
                    withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                        _ = viewModel.saveEditedEvent(saved)
                    }
                } onCancel: {
                    viewModel.cancelEditingEvent()
                }
                // 「わが家で共有」→「自分だけ」の確認（Build 17）。キャンセルなら何も変えない
                .alert(
                    "自分だけの予定に変更しますか？",
                    isPresented: Binding(
                        get: { viewModel.pendingPersonalConversionDraft != nil },
                        set: { isPresented in if !isPresented { viewModel.cancelPersonalConversion() } }
                    )
                ) {
                    Button("自分だけに変更", role: .destructive) {
                        withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                            _ = viewModel.confirmPersonalConversion()
                        }
                    }
                    Button("キャンセル", role: .cancel) { viewModel.cancelPersonalConversion() }
                } message: {
                    Text("変更すると、この予定はパートナーのカレンダーから削除されます。")
                }
                // 保存先を変えられなかった理由（Build 17）
                .alert(
                    "保存できませんでした",
                    isPresented: Binding(
                        get: { viewModel.eventEditError != nil },
                        set: { isPresented in if !isPresented { viewModel.dismissEventEditError() } }
                    )
                ) {
                    Button("OK", role: .cancel) { viewModel.dismissEventEditError() }
                } message: {
                    Text(viewModel.eventEditError ?? "")
                }
                .presentationDetents([.medium, .large])
                .lifeSheetPresentation()
            }
        }
    }

    // MARK: - 月表示

    /// 月の面（白いカードより弱い、紙色の面）
    private var monthCard: some View {
        VStack(spacing: LifeSpacing.sm) {
            HStack {
                Button(action: viewModel.showPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                }
                .accessibilityLabel("前の月")

                Spacer()
                Text(viewModel.monthTitle)
                    .font(LifeTypography.editorialHeadline)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button(action: viewModel.showNextMonth) {
                    Image(systemName: "chevron.right")
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                }
                .accessibilityLabel("次の月")
            }
            .foregroundStyle(LifeColors.primary)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(LifeTypography.caption)
                        .foregroundStyle(LifeColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: columns, spacing: LifeSpacing.xxs) {
                ForEach(viewModel.dayCells) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: LifeSpacing.minTapTarget)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(LifeSpacing.md)
        .frame(maxWidth: .infinity)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = viewModel.isSelected(date)
        let isToday = viewModel.isToday(date)
        // Build 19：予定は登録した人の色（自分・パートナー・不明）、ほかはカテゴリー色。同じ色は1つ、最大3つ
        let markers = viewModel.dayMarkers(on: date)

        return Button {
            withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                viewModel.select(date)
            }
        } label: {
            VStack(spacing: LifeSpacing.xxs) {
                Text("\(viewModel.dayNumber(of: date))")
                    .font(LifeTypography.calendarDay)
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.text)
                    .frame(width: LifeSpacing.calendarDayDiameter, height: LifeSpacing.calendarDayDiameter)
                    .background {
                        if isSelected {
                            Circle().fill(LifeColors.primary)
                        } else if isToday {
                            Circle().stroke(LifeColors.accent, lineWidth: LifeSpacing.timelineLine)
                        }
                    }
                // その日の項目を小さな点で（数は読み上げのラベルで伝える）
                HStack(spacing: LifeSpacing.calendarDotGap) {
                    ForEach(markers, id: \.self) { marker in
                        Circle()
                            .fill(marker.tint)
                            .frame(width: LifeSpacing.calendarDotDiameter, height: LifeSpacing.calendarDotDiameter)
                    }
                }
                .frame(height: LifeSpacing.calendarDotDiameter)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.accessibilityLabel(for: date))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 選択日の項目

    /// 選んだ日の項目：カードに入れず、セリフ体の日付と細い線で区切る
    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(viewModel.selectedDateEyebrow)
                        .font(LifeTypography.label)
                        .tracking(LifeTypography.labelTracking)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                    Text(viewModel.selectedDateHeadline)
                        .font(LifeTypography.editorialTitle)
                        .foregroundStyle(LifeColors.text)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: LifeSpacing.xs)
                Text("\(viewModel.selectedItems.count)件")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }

            // 選んだ日に予定を追加（Build 12）
            Button(action: viewModel.startAddingEvent) {
                Label("予定を追加", systemImage: "plus")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.primary)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(viewModel.selectedDateHeadline)に予定を追加")

            if viewModel.selectedItems.isEmpty {
                LifeEmptyState(systemImage: "calendar", title: "予定はありません")
                    .frame(maxWidth: .infinity)
                    .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            } else {
                LifeRuledList(viewModel.selectedItems) { item in
                    HStack(spacing: LifeSpacing.xs) {
                        if item.isTask {
                            LifeTaskRow(
                                title: item.title,
                                detail: viewModel.detailText(for: item),
                                isCompleted: item.isCompleted,
                                tint: item.kind.tint,
                                isShared: viewModel.isShared(item)
                            ) {
                                viewModel.toggle(item)
                            }
                        } else if viewModel.canDeleteEvent(item) {
                            // 予定：行の右側のごみ箱ボタン（Build 14）。押すと確認を出す（押しただけでは消さない）。
                            // Build 13 の独自スワイプ（LifeSwipeDeleteRow）は、実機で「削除」を押しても消えなかったため外した。
                            // 原因と直し方は docs/BUILD_14_SHARED_CALENDAR_AND_DELETE_FIX.md
                            CalendarEventRow(
                                time: viewModel.timeText(for: item),
                                title: item.title,
                                detail: viewModel.detailText(for: item),
                                registrant: viewModel.registrant(for: item),
                                isShared: viewModel.isShared(item)
                            )
                            CalendarEventEditButton(title: item.title) {
                                viewModel.startEditingEvent(item)
                            }
                            CalendarEventDeleteButton(title: item.title) {
                                viewModel.requestDeleteEvent(item)
                            }
                        } else {
                            CalendarEventRow(
                                time: viewModel.timeText(for: item),
                                title: item.title,
                                detail: viewModel.detailText(for: item),
                                registrant: viewModel.registrant(for: item),
                                isShared: viewModel.isShared(item)
                            )
                        }
                    }
                    .padding(.vertical, LifeSpacing.xxs)
                }
            }
        }
    }
}

/// 予定の編集ボタン（Build 15）。追加時と同じ入力部品を開き、保存先は変えない。
struct CalendarEventEditButton: View {
    static let accessibilityIdentifier = "calendar.editEvent"

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.primary)
                .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
        .accessibilityLabel("予定を編集")
        .accessibilityHint("「\(title)」のタイトルや日時を変更します")
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }
}

/// 予定の行の右側の削除ボタン（Build 14）。
/// ふつうの Button なので、ScrollView の中でも1回のタップで確実に押せる（スワイプや重なりに頼らない）。
/// 押すと確認を出すだけ（消すのは確認の「予定を削除」）
struct CalendarEventDeleteButton: View {
    /// UI テストで探すための識別子
    static let accessibilityIdentifier = "calendar.deleteEvent"

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.secondaryText)
                .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
        .accessibilityLabel("予定を削除")
        .accessibilityHint("「\(title)」を消す前に確認します")
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }
}

/// 予定の行（チェックなし・時刻付き）。時刻はセリフ体（タイムラインの時刻と同じ）。
/// Build 19：左に登録した人の色の点、補足の行に「自分／パートナー／共有」（色だけに頼らない）。共有マークも出す
struct CalendarEventRow: View {
    let time: String?
    let title: String
    let detail: String
    /// 最初に登録した人（nil なら出さない）
    var registrant: ItemRegistrant? = nil
    /// わが家で共有している予定か（共有マーク）
    var isShared = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
            if let registrant {
                Circle()
                    .fill(registrant.tint)
                    .frame(width: LifeSpacing.calendarDotDiameter * 2, height: LifeSpacing.calendarDotDiameter * 2)
                    .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
            }
            Text(time ?? "終日")
                .font(LifeTypography.timelineTime)
                .foregroundStyle(LifeColors.text)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                HStack(spacing: LifeSpacing.xs) {
                    Text(title)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    if isShared {
                        HouseholdSharedMark()
                    }
                }
                HStack(spacing: LifeSpacing.xs) {
                    if let registrant {
                        CalendarRegistrantBadge(registrant: registrant)
                    }
                    Text(detail)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .combine)
    }
}

/// 予定を登録した人の小さな印（Build 19）：「自分／パートナー／共有」の文字＋その人の色の枠。
/// 文字は本文の色で読みやすくし、色は枠と点だけに使う。VoiceOver は「自分が登録した予定」などと読む
struct CalendarRegistrantBadge: View {
    let registrant: ItemRegistrant

    var body: some View {
        Text(registrant.label)
            .font(LifeTypography.caption)
            .foregroundStyle(LifeColors.text)
            .padding(.horizontal, LifeSpacing.xs)
            .padding(.vertical, 1)
            .background(Capsule().fill(registrant.tint.opacity(0.22)))
            .overlay(Capsule().stroke(registrant.tint, lineWidth: 1))
            .accessibilityLabel(registrant.spokenLabel)
    }
}

extension CalendarDayMarker {
    /// 点の色（予定は登録した人、ほかはカテゴリー）
    var tint: Color {
        switch self {
        case .registrant(let registrant): return registrant.tint
        case .kind(let kind): return kind.tint
        }
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        CalendarView(store: store, appState: appState)
    }
    .environment(appState)
    .environment(store)
}
