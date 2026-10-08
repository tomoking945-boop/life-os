import Foundation
import Observation

/// 習慣の編集中の内容
struct HabitDraft: Identifiable, Hashable {
    let id: Habit.ID
    var title: String
    var isLight: Bool
    /// 毎日か（false なら weekdays の曜日だけ）
    var isDaily: Bool
    /// くり返す曜日（日=1 … 土=7）
    var weekdays: Set<Int>

    init(habit: Habit) {
        id = habit.id
        title = habit.title
        isLight = habit.isLight
        switch habit.repeatRule {
        case .daily:
            isDaily = true
            weekdays = []
        case let .weekdays(days):
            isDaily = false
            weekdays = Set(days)
        }
    }

    /// 曜日を1つも選んでいなければ毎日にする
    var repeatRule: HabitRepeat {
        isDaily || weekdays.isEmpty ? .daily : .weekdays(weekdays.sorted())
    }
}

/// 習慣の一覧・追加・編集（2026-10-08「習慣を自分で追加・編集」）
@Observable
final class HabitsViewModel {
    private let store: LifeStore
    let now: Date

    var newTitle = ""
    var newIsLight = false
    /// 編集中の習慣
    var editing: HabitDraft?
    /// 操作のあとの一言と「元に戻す」
    var feedback: LifeFeedback?

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
    }

    var habits: [Habit] { store.habits }

    var canAdd: Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !store.habits.contains { $0.title == trimmed }
    }

    /// 同じ名前の習慣があるときの案内
    var duplicateNote: String? {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, store.habits.contains(where: { $0.title == trimmed }) else { return nil }
        return "「\(trimmed)」はもうあります"
    }

    // MARK: - 表示

    /// くり返し（毎日／月・水・金）
    func repeatText(_ habit: Habit) -> String {
        Self.repeatText(habit.repeatRule)
    }

    static func repeatText(_ rule: HabitRepeat) -> String {
        switch rule {
        case .daily:
            return "毎日"
        case let .weekdays(days):
            let symbols = LifeCalendar.calendar.shortWeekdaySymbols
            return days.sorted()
                .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
                .joined(separator: "・")
        }
    }

    /// 行の補足（毎日・軽い習慣）
    func detailText(_ habit: Habit) -> String {
        habit.isLight ? "\(repeatText(habit))・軽い習慣" : repeatText(habit)
    }

    func rhythmDays(_ habit: Habit) -> [HabitRhythmDay] {
        HabitRhythm.days(for: habit, now: now)
    }

    func rhythmMessage(_ habit: Habit) -> String {
        HabitRhythm.message(for: habit, now: now)
    }

    func isDoneToday(_ habit: Habit) -> Bool {
        habit.isDone(on: now)
    }

    func toggleToday(_ habit: Habit) {
        store.toggleHabit(habit.id, on: now)
    }

    /// 今日はお休みの曜日か（曜日のくり返しで、今日が入っていない）
    func isRestDay(_ habit: Habit) -> Bool {
        !habit.occurs(on: now)
    }

    // MARK: - 追加・編集・削除

    /// 追加する（今日から始める・毎日）。くり返しの曜日はあとで編集できる
    @discardableResult
    func add() -> Bool {
        guard canAdd,
              let habit = store.addHabit(title: newTitle, isLight: newIsLight, repeatRule: .daily, startedAt: now) else {
            return false
        }
        newTitle = ""
        newIsLight = false
        let store = self.store
        feedback = LifeFeedback(message: "「\(habit.title)」を習慣にしました", undo: {
            store.removeHabit(habit.id)
        })
        return true
    }

    func startEditing(_ habit: Habit) {
        editing = HabitDraft(habit: habit)
    }

    func save(_ draft: HabitDraft) {
        store.updateHabit(draft.id, title: draft.title, isLight: draft.isLight, repeatRule: draft.repeatRule)
        editing = nil
    }

    /// 削除する（できた日の記録も含めて「元に戻す」で戻せる）
    func delete(_ id: Habit.ID) {
        editing = nil
        let store = self.store
        guard let removed = store.removeHabit(id) else { return }
        feedback = LifeFeedback(message: "「\(removed.habit.title)」を習慣から外しました", undo: {
            store.restoreHabit(removed.habit, at: removed.index)
        })
    }

    func performUndo() {
        guard let undo = feedback?.undo else { return }
        undo()
        feedback = LifeFeedback(message: "元に戻しました", undo: nil)
    }
}
