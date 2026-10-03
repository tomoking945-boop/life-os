import Foundation
import Observation

@Observable
final class InboxViewModel {
    private let store: LifeStore
    private let now: Date

    var isTidyUpPresented = false

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
    }

    /// 新しいものが上
    var items: [InboxItem] {
        store.inbox.sorted { $0.createdAt > $1.createdAt }
    }

    var countText: String { "未整理 \(store.inbox.count)件" }

    /// おまかせ整理に出せる件数（「後で」にしたものは除く）
    var readyCount: Int {
        store.inbox.filter { $0.isReady(at: now) }.count
    }

    var canTidyUp: Bool { readyCount > 0 }

    var tidyUpButtonTitle: String { "まとめて整理（\(readyCount)件）" }

    func suggestionText(for item: InboxItem) -> String {
        "候補：\(InboxClassifier.suggest(for: item.text).summary)"
    }

    func isPostponed(_ item: InboxItem) -> Bool {
        !item.isReady(at: now)
    }

    func add(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        store.addToInbox(trimmed, now: now)
        return true
    }

    func delete(at offsets: IndexSet) {
        let current = items
        let ids = Set(offsets.compactMap { current.indices.contains($0) ? current[$0].id : nil })
        store.removeFromInbox(ids)
    }
}
