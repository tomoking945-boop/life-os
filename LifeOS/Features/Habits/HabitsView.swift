import SwiftUI

/// 習慣の一覧・追加・編集（2026-10-08「習慣を自分で追加・編集」）。
/// 今日画面の「習慣」の「すべて見る」から開く。行を押すと今日できたかを切り替え、右の「編集」で名前・軽い習慣・くり返しを変える。
struct HabitsView: View {
    @State private var viewModel: HabitsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool

    init(store: LifeStore) {
        _viewModel = State(initialValue: HabitsViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(
                    eyebrow: "RHYTHM",
                    title: "習慣",
                    subtitle: "できた日だけ残します。できなかった日は数えません。"
                )

                addSection

                if viewModel.habits.isEmpty {
                    LifeEmptyState(systemImage: "leaf", title: "習慣はまだありません", message: "水を飲む・ストレッチなど、小さなことから。")
                        .frame(maxWidth: .infinity)
                        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                } else {
                    LifeRuledList(viewModel.habits) { habit in
                        habitRow(habit)
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
            .animation(LifeMotion.animation(LifeMotion.standard, reduceMotion: reduceMotion), value: viewModel.habits)
        }
        .lifeScreenBackground()
        .navigationTitle("習慣")
        .navigationBarTitleDisplayMode(.inline)
        .lifeFeedbackBanner($viewModel.feedback) {
            viewModel.performUndo()
        }
        .quickAddAccessory()
        .sheet(item: $viewModel.editing) { draft in
            HabitEditView(draft: draft) { saved in
                viewModel.save(saved)
            } onDelete: {
                withLifeAnimation(reduceMotion: reduceMotion) { viewModel.delete(draft.id) }
            }
            .lifeSheetPresentation()
        }
    }

    // MARK: - 追加

    private var addSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.sm) {
                TextField("新しい習慣（例：朝に白湯を飲む）", text: $viewModel.newTitle)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.canAdd ? LifeColors.primary : LifeColors.secondaryText)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAdd)
                .accessibilityLabel("習慣を追加")
            }
            .padding(.leading, LifeSpacing.md)
            .frame(minHeight: LifeSpacing.buttonHeight)
            .lifeSurface(.normal, cornerRadius: LifeRadius.field)

            Toggle(isOn: $viewModel.newIsLight) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text("軽い習慣にする")
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Text("余力が「少ない」日にも、今日画面に出します")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .tint(LifeColors.primary)
            .frame(minHeight: LifeSpacing.minTapTarget)

            if let note = viewModel.duplicateNote {
                Text(note)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
    }

    private func add() {
        withLifeAnimation(reduceMotion: reduceMotion) {
            if viewModel.add() {
                isFieldFocused = false
            }
        }
    }

    // MARK: - 行

    private func habitRow(_ habit: Habit) -> some View {
        HStack(alignment: .top, spacing: LifeSpacing.xs) {
            LifeHabitRow(
                title: habit.title,
                message: viewModel.isRestDay(habit)
                    ? "今日はお休みの日です・\(viewModel.detailText(habit))"
                    : "\(viewModel.rhythmMessage(habit))・\(viewModel.detailText(habit))",
                days: viewModel.rhythmDays(habit),
                isDone: viewModel.isDoneToday(habit)
            ) {
                withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) { viewModel.toggleToday(habit) }
            }
            Button {
                viewModel.startEditing(habit)
            } label: {
                Text("編集")
                    .font(LifeTypography.footnoteEmphasis)
                    .foregroundStyle(LifeColors.primary)
                    .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.title)を編集")
        }
    }
}

/// 習慣の編集：名前・軽い習慣・くり返し（毎日／曜日）・削除
struct HabitEditView: View {
    let onSave: (HabitDraft) -> Void
    let onDelete: () -> Void

    @State private var draft: HabitDraft
    @Environment(\.dismiss) private var dismiss

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: LifeSpacing.xxs), count: 7)

    init(draft: HabitDraft, onSave: @escaping (HabitDraft) -> Void, onDelete: @escaping () -> Void) {
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    SettingsTextField(label: "名前", text: $draft.title, onCommit: {})

                    Toggle(isOn: $draft.isLight) {
                        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                            Text("軽い習慣")
                                .font(LifeTypography.body)
                                .foregroundStyle(LifeColors.text)
                            Text("余力が「少ない」日にも、今日画面に出します")
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                    }
                    .tint(LifeColors.primary)
                    .frame(minHeight: LifeSpacing.minTapTarget)

                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        LifeSectionTitle("くり返し")
                        LifeSegmentControl([true, false], selection: $draft.isDaily) { $0 ? "毎日" : "曜日を選ぶ" }
                        if !draft.isDaily {
                            weekdayPicker
                            Text(draft.weekdays.isEmpty ? "曜日を選ばなければ、毎日にします。" : "選んだ曜日だけ、今日画面に出します。")
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                    }

                    Text("名前やくり返しを変えても、できた日の記録はそのまま残ります。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    LifeButton("この習慣を外す", systemImage: "minus.circle", kind: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
            }
            .lifeScreenBackground()
            .navigationTitle("習慣を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(LifeColors.primary)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        LazyVGrid(columns: weekdayColumns, spacing: LifeSpacing.xxs) {
            ForEach(1...7, id: \.self) { weekday in
                let symbol = weekdaySymbol(weekday)
                let isSelected = draft.weekdays.contains(weekday)
                Button {
                    if isSelected {
                        draft.weekdays.remove(weekday)
                    } else {
                        draft.weekdays.insert(weekday)
                    }
                } label: {
                    Text(symbol)
                        .font(LifeTypography.callout)
                        .foregroundStyle(isSelected ? LifeColors.onPrimary : LifeColors.text)
                        .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget)
                        .background(Circle().fill(isSelected ? LifeColors.primary : LifeColors.surface))
                        .overlay(Circle().stroke(isSelected ? LifeColors.primary : LifeColors.divider, lineWidth: LifeSpacing.hairline))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(symbol)曜日")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = LifeCalendar.calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}

#Preview {
    NavigationStack {
        HabitsView(store: LifeStore())
    }
    .environment(AppState())
    .environment(LifeStore())
}
