import SwiftUI

/// 共有スターター（v2 仕様 10）：「二人の生活OSを30秒で作りましょう。」
/// ゴミの日・よく買うもの・今月の共通予定の3つだけ。どれも省略できる（すべては入力させない）。
struct SharedStarterView: View {
    let store: LifeStore
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState

    @State private var trashWeekdays: Set<Int> = []
    @State private var frequentTitles: Set<String> = []
    @State private var eventTitle = ""
    @State private var eventDate = PostponeOption.weekend.date(from: LifeCalendar.now)

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: LifeSpacing.xxs), count: 7)
    private let chipColumns = [
        GridItem(.flexible(), spacing: LifeSpacing.xs),
        GridItem(.flexible(), spacing: LifeSpacing.xs)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.xl) {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text("二人の生活OSを\n30秒で作りましょう。")
                        .font(LifeTypography.editorialTitle)
                        .foregroundStyle(LifeColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("3つだけ。選ばなくても始められます。")
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                }

                trashSection
                frequentSection
                eventSection

                VStack(spacing: LifeSpacing.sm) {
                    LifeButton("この内容で始める", systemImage: "checkmark") {
                        start()
                    }
                    Button("あとで設定する") {
                        finishWithoutSettings()
                    }
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.lg)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 1. ゴミの日

    private var trashSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("1. ゴミの日")
            LazyVGrid(columns: weekdayColumns, spacing: LifeSpacing.xxs) {
                ForEach(1...7, id: \.self) { weekday in
                    let symbol = weekdaySymbol(weekday)
                    let isSelected = trashWeekdays.contains(weekday)
                    Button {
                        toggle(weekday)
                    } label: {
                        Text(symbol)
                            .font(LifeTypography.callout)
                            .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.text)
                            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
                            .background(Circle().fill(isSelected ? LifeColors.primary : LifeColors.surface))
                            .overlay(Circle().stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(symbol)曜日")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = LifeCalendar.calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    private func toggle(_ weekday: Int) {
        if trashWeekdays.contains(weekday) {
            trashWeekdays.remove(weekday)
        } else {
            trashWeekdays.insert(weekday)
        }
    }

    // MARK: - 2. よく買うもの

    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("2. よく買うもの")
            LazyVGrid(columns: chipColumns, spacing: LifeSpacing.xs) {
                ForEach(MockData.starterFrequentCandidates, id: \.self) { title in
                    LifeChip(title: title, isSelected: frequentTitles.contains(title)) {
                        if frequentTitles.contains(title) {
                            frequentTitles.remove(title)
                        } else {
                            frequentTitles.insert(title)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 3. 今月の共通予定

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("3. 今月の共通予定")
            SettingsTextField(label: "予定（例：実家に帰る）", text: $eventTitle, onCommit: {})
            DatePicker("日にち", selection: $eventDate, in: monthRange, displayedComponents: .date)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .tint(LifeColors.primary)
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }

    /// 今日から今月末まで
    private var monthRange: ClosedRange<Date> {
        let today = LifeCalendar.startOfDay(LifeCalendar.now)
        let startOfMonth = LifeCalendar.startOfMonth(today)
        let nextMonth = LifeCalendar.calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? today
        let endOfMonth = LifeCalendar.calendar.date(byAdding: .second, value: -1, to: nextMonth) ?? today
        return today...max(today, endOfMonth)
    }

    // MARK: - 開始

    private func start() {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedDate = min(max(eventDate, monthRange.lowerBound), monthRange.upperBound)
        store.applySharedStarter(
            trashWeekdays: Array(trashWeekdays),
            frequentTitles: MockData.starterFrequentCandidates.filter { frequentTitles.contains($0) },
            commonEvent: title.isEmpty ? nil : (title: title, date: clampedDate)
        )
        finishWithoutSettings()
    }

    /// Mock：パートナーが参加した状態にして、共有モードで始める
    private func finishWithoutSettings() {
        appState.partnerJoined = true
        appState.usageStyle = .shared
        onFinish()
    }
}

#Preview {
    NavigationStack {
        SharedStarterView(store: LifeStore()) {}
    }
    .environment(AppState())
}
