import Foundation
import Observation
import UIKit

/// やることの上部切り替え
enum TaskSegment: String, CaseIterable, Hashable {
    case today
    case upcoming
    case shopping
    case chores

    var title: String {
        switch self {
        case .today: return "今日"
        case .upcoming: return "今後"
        case .shopping: return "買い物"
        case .chores: return "家事"
        }
    }
}

/// 完了 / 未完了の切り替え
enum CompletionFilter: String, CaseIterable, Hashable {
    case incomplete
    case completed

    var title: String {
        switch self {
        case .incomplete: return "未完了"
        case .completed: return "完了"
        }
    }
}

@Observable
final class TasksViewModel {
    private let store: LifeStore
    private let appState: AppState
    private let now: Date

    var segment: TaskSegment = .today
    var completion: CompletionFilter = .incomplete

    init(store: LifeStore, appState: AppState, now: Date = LifeCalendar.now) {
        self.store = store
        self.appState = appState
        self.now = now
    }

    // MARK: - すべて / 自分 / 共有（2026-10-28）

    /// 2026-10-28：わが家で共有する ToDo・買い物を始めたので、やること画面にも「すべて / 自分 / 共有」を付ける
    /// （2026-09-28 の「付けない」を変更。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）。今日画面と同じ切り替えを使う
    var showsScopeFilter: Bool { appState.usageStyle.showsScopeFilter }

    var scope: ScopeFilter {
        get { appState.scope }
        set { appState.scope = newValue }
    }

    /// わが家で共有している項目か（共有マーク）
    func isShared(_ item: LifeItem) -> Bool {
        store.isHouseholdItem(item.id)
    }

    // MARK: - 共有の通知から開いたとき（2026-10-28 Build 8）

    /// 共有の通知をタップしたときに開く切り替え（AppState から）
    var requestedSegment: TaskSegment? { appState.pendingTasksSegment }

    /// 通知から開いたとき：ToDo は「今日」、買い物は「買い物」、未完了を出す。項目は変えない
    func applyRequestedSegment() {
        guard let segment = appState.pendingTasksSegment else { return }
        self.segment = segment
        completion = .incomplete
        appState.pendingTasksSegment = nil
    }

    // MARK: - 編集（名前・保存先・削除。2026-10-28）

    var editingItem: LifeItem?

    func startEditing(_ item: LifeItem) {
        editingItem = item
    }

    /// 編集画面に渡す置き場
    var storeForEditing: LifeStore { store }

    /// 習慣は今日画面の「習慣」に表示し、やること画面には出さない。
    /// 端末の項目とわが家の共有項目を一緒に出す（同じ項目は1回だけ）
    var tasks: [LifeItem] {
        let today = LifeCalendar.startOfDay(now)
        let scope = appState.effectiveScope
        return store.visibleItems
            .filter { $0.isTask && !$0.isHabit && !$0.isDropped && scope.includes($0.ownership) }
            .filter { item in
                switch segment {
                case .today:
                    return LifeCalendar.isSameDay(item.displayDate, today)
                case .upcoming:
                    return LifeCalendar.startOfDay(item.displayDate) > today
                case .shopping:
                    return item.kind == .shopping
                case .chores:
                    return item.kind == .chore
                }
            }
            .filter { completion == .completed ? $0.isCompleted : !$0.isCompleted }
            .sorted { $0.displayDate < $1.displayDate }
    }

    /// 担当：どちらでも など
    /// TODO: 担当者が未設定の項目の表示は仕様未定。現状は「担当：未設定」。
    func assigneeText(for item: LifeItem) -> String {
        if isShared(item) { return HouseholdSharedMark.label }
        guard let assignee = item.assignee else { return "担当：未設定" }
        return "担当：\(appState.profile.displayName(for: assignee))"
    }

    /// 担当者のアバター（どちらでも・未設定のときは表示しない）
    func avatar(for item: LifeItem) -> (name: String, image: UIImage?)? {
        switch item.assignee {
        case .me:
            return (appState.profile.name, appState.profileImage)
        case .partner:
            return (appState.profile.partnerName, nil)
        case .either, .none:
            return nil
        }
    }

    func trailingText(for item: LifeItem) -> String? {
        switch segment {
        case .today, .upcoming:
            return item.kind.label
        case .shopping, .chores:
            return nil
        }
    }

    var emptyTitle: String {
        completion == .completed ? "完了した項目はありません" : "やることはありません"
    }

    // MARK: - あとで

    /// 「あとで」シートの対象
    var postponingItem: LifeItem?

    func startPostponing(_ item: LifeItem) {
        postponingItem = item
    }

    func postpone(_ item: LifeItem, to option: PostponeOption) {
        store.reschedule(item.id, to: option.date(from: now))
    }

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }
}
