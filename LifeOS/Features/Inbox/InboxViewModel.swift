import Foundation
import Observation

/// Inbox（Calm Future 第2段階：生活メモを一時的に置く静かなワークスペース）
@Observable
final class InboxViewModel {
    private let store: LifeStore
    private let now: Date

    var isTidyUpPresented = false
    /// 修正中のメモ
    var editingEntry: TidyUpEntry?
    /// 「修正」で変えた理解（メモごと）。
    /// TODO: 修正した内容を保存するかは未定。現状はこの画面を開いている間だけ保持し、まとめて整理にも引き継ぐ。
    private(set) var edits: [InboxItem.ID: InboxSuggestion] = [:]
    /// 操作のあとの一言と「元に戻す」
    var feedback: LifeFeedback?

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

    // MARK: - LifeOSの理解

    /// メモごとの理解（修正していればその内容）
    func suggestion(for item: InboxItem) -> InboxSuggestion {
        edits[item.id] ?? InboxClassifier.suggest(for: item.text)
    }

    func suggestionText(for item: InboxItem) -> String {
        "候補：\(suggestion(for: item).summary)"
    }

    func timingText(for item: InboxItem) -> String {
        suggestion(for: item).timingText(now: now)
    }

    func isEdited(_ item: InboxItem) -> Bool {
        edits[item.id] != nil
    }

    func isPostponed(_ item: InboxItem) -> Bool {
        !item.isReady(at: now)
    }

    // MARK: - 追加・削除

    func add(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        store.addToInbox(trimmed, now: now)
        return true
    }

    /// 1件削除（元に戻せる）
    func delete(_ item: InboxItem) {
        let store = self.store
        store.removeFromInbox([item.id])
        notify("「\(item.text)」を削除しました") {
            store.restoreInbox([item])
        }
    }

    // MARK: - メモごとの操作

    /// このまま追加：理解どおりに追加して Inbox から外す（元に戻せる）。
    /// 一人モードでは共有を前面に出さないため「自分」として追加する。
    func addAsIs(_ item: InboxItem, usageStyle: UsageStyle = .shared) {
        var adjusted = suggestion(for: item)
        if !usageStyle.showsScopeFilter { adjusted.ownership = .personal }
        let newItem = adjusted.makeItem(today: now)
        let store = self.store
        store.add([newItem])
        store.removeFromInbox([item.id])
        notify("「\(newItem.title)」を追加しました") {
            store.removeItems(withIDs: [newItem.id])
            store.restoreInbox([item])
        }
    }

    /// 後で：明日の整理まで出さない（Inbox には残る。元に戻せる）
    func postpone(_ item: InboxItem) {
        let store = self.store
        store.postponeInbox([item.id], until: PostponeOption.tomorrow.date(from: now))
        notify("「\(item.text)」は明日の整理に回しました") {
            store.restoreInbox([item])
        }
    }

    func startEditing(_ item: InboxItem) {
        editingEntry = TidyUpEntry(inboxID: item.id, originalText: item.text, suggestion: suggestion(for: item))
    }

    /// 修正の内容を反映する（タイトルが空なら元のまま）
    func update(_ id: InboxItem.ID, with suggestion: InboxSuggestion) {
        var updated = suggestion
        updated.applyUserEdit()
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty, let current = store.inbox.first(where: { $0.id == id }) {
            updated.title = self.suggestion(for: current).title
        }
        edits[id] = updated
        editingEntry = nil
    }

    // MARK: - 元に戻す

    private func notify(_ message: String, undo: @escaping () -> Void) {
        feedback = LifeFeedback(message: message, undo: undo)
    }

    func performUndo() {
        guard let undo = feedback?.undo else { return }
        undo()
        feedback = LifeFeedback(message: "元に戻しました", undo: nil)
    }
}
