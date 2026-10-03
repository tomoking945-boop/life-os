import SwiftUI

/// カレンダー（月表示）。日付をタップすると下部にその日の項目を表示する。
/// 週表示は初期版では不要（仕様どおり未実装）。
struct CalendarView: View {
    @State private var viewModel: CalendarViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private let store: LifeStore

    init(store: LifeStore, appState: AppState) {
        self.store = store
        _viewModel = State(initialValue: CalendarViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                Text("カレンダー")
                    .font(LifeTypography.display)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.showsScopeFilter {
                    LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                }

                monthCard
                selectedDaySection
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .sheet(item: $viewModel.invitingItem) { item in
            SharingFlowView(item: item, store: store)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
        }
    }

    // MARK: - 月表示

    private var monthCard: some View {
        LifeCard(padding: LifeSpacing.md) {
            VStack(spacing: LifeSpacing.sm) {
                HStack {
                    Button(action: viewModel.showPreviousMonth) {
                        Image(systemName: "chevron.left")
                            .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                    }
                    .accessibilityLabel("前の月")

                    Spacer()
                    Text(viewModel.monthTitle)
                        .font(LifeTypography.title)
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
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = viewModel.isSelected(date)
        let isToday = viewModel.isToday(date)
        let hasItems = viewModel.itemCount(on: date) > 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
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
                            Circle().stroke(LifeColors.accent, lineWidth: 1)
                        }
                    }
                Circle()
                    .fill(hasItems ? LifeColors.accent : Color.clear)
                    .frame(width: LifeSpacing.calendarDotDiameter, height: LifeSpacing.calendarDotDiameter)
            }
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.accessibilityLabel(for: date))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 選択日の項目

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle(viewModel.selectedDateTitle, trailing: "\(viewModel.selectedItems.count)件")

            LifeCard {
                if viewModel.selectedItems.isEmpty {
                    LifeEmptyState(systemImage: "calendar", title: "予定はありません")
                } else {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        ForEach(viewModel.selectedItems) { item in
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
                        }
                    }
                }
            }
        }
    }
}

/// 予定の行（チェックなし・時刻付き）
struct CalendarEventRow: View {
    let time: String?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
            Text(time ?? "終日")
                .font(LifeTypography.amount)
                .foregroundStyle(LifeColors.primary)
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
