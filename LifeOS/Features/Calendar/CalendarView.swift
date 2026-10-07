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
        .sheet(item: $viewModel.invitingItem) { item in
            SharingFlowView(item: item, store: store)
                .lifeSheetPresentation()
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
        let markerKinds = viewModel.markerKinds(on: date)

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
                // その日の項目の種類をカテゴリー色の小さな点で（数は読み上げのラベルで伝える）
                HStack(spacing: LifeSpacing.calendarDotGap) {
                    ForEach(markerKinds, id: \.self) { kind in
                        Circle()
                            .fill(kind.tint)
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
                                tint: item.kind.tint
                            ) {
                                viewModel.toggle(item)
                            }
                        } else {
                            CalendarEventRow(
                                time: viewModel.timeText(for: item),
                                title: item.title,
                                detail: viewModel.detailText(for: item)
                            )
                        }
                        if viewModel.canShare(item) {
                            Button {
                                viewModel.shareTapped(item)
                            } label: {
                                Image(systemName: "person.2")
                                    .font(LifeTypography.callout)
                                    .foregroundStyle(LifeColors.primary)
                                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.title)をパートナーと共有")
                        }
                    }
                    .padding(.vertical, LifeSpacing.xxs)
                }
            }
        }
    }
}

/// 予定の行（チェックなし・時刻付き）。時刻はセリフ体（タイムラインの時刻と同じ）。
struct CalendarEventRow: View {
    let time: String?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
            Text(time ?? "終日")
                .font(LifeTypography.timelineTime)
                .foregroundStyle(LifeColors.text)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(title)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                Text(detail)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .combine)
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
