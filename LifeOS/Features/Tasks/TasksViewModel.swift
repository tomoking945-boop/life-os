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

    /// TODO: やること画面に「すべて / 自分 / 共有」フィルターを適用するかは仕様未定。現状は全件表示。
    var tasks: [LifeItem] {
        let today = LifeCalendar.startOfDay(now)
        return store.items
            .filter { $0.isTask }
            .filter { item in
                switch segment {
                case .today:
                    return LifeCalendar.isSameDay(item.date, today)
                case .upcoming:
                    return LifeCalendar.startOfDay(item.date) > today
                case .shopping:
                    return item.kind == .shopping
                case .chores:
                    return item.kind == .chore
                }
            }
            .filter { completion == .completed ? $0.isCompleted : !$0.isCompleted }
            .sorted { $0.date < $1.date }
    }

    /// 担当：どちらでも など
    /// TODO: 担当者が未設定の項目の表示は仕様未定。現状は「担当：未設定」。
    func assigneeText(for item: LifeItem) -> String {
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

    func toggle(_ item: LifeItem) {
        store.toggleCompletion(of: item.id)
    }
}
