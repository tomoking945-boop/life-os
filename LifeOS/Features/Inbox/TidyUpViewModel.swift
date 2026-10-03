import Foundation
import Observation

/// おまかせ整理の1件（Inbox のメモ＋整理の候補）
struct TidyUpEntry: Identifiable, Hashable {
    let inboxID: InboxItem.ID
    let originalText: String
    var suggestion: InboxSuggestion

    var id: InboxItem.ID { inboxID }
}

/// 1日1回の「おまかせ整理」（今日の整理）。
/// 1件ずつ詳しく設定しなくても「全部OK」でまとめて承認できる。
@Observable
final class TidyUpViewModel {
    private let store: LifeStore
    private let now: Date

    var entries: [TidyUpEntry]
    /// 修正中の項目
    var editingEntry: TidyUpEntry?
    /// 「全部OK」で追加した件数（完了表示用）
    private(set) var addedCount = 0
    private(set) var isFinished = false

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
        self.entries = store.inbox
            .filter { $0.isReady(at: now) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { TidyUpEntry(inboxID: $0.id, originalText: $0.text, suggestion: InboxClassifier.suggest(for: $0.text)) }
    }

    var hasEntries: Bool { !entries.isEmpty }

    var approveAllTitle: String { "全部OK（\(entries.count)件）" }

    var finishedText: String { "\(addedCount)件を整理しました" }

    // MARK: - 1件ずつの操作

    /// スキップ：今回の整理から外す（Inbox には残り、次回また出る）
    /// 決定済み（2026-10-02）。
    func skip(_ id: TidyUpEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    /// 後で：明日の整理まで出さない（Inbox には残る）。決定済み（2026-10-02）。
    /// 延期先は日時（postponedUntil）で持っているため、将来「今夜・明日・週末・来週」の
    /// 延期機能（v2 第2回「あとで」）と同じ選択肢・計算に統合できる。
    func postpone(_ id: TidyUpEntry.ID) {
        // 決定済み（2026-10-03）：タスクの「あとで」と同じ延期の計算（PostponeOption）を使う
        store.postponeInbox([id], until: PostponeOption.tomorrow.date(from: now))
        entries.removeAll { $0.id == id }
    }

    func startEditing(_ id: TidyUpEntry.ID) {
        editingEntry = entries.first { $0.id == id }
    }

    /// 個別修正の内容を反映する
    func update(_ id: TidyUpEntry.ID, with suggestion: InboxSuggestion) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = suggestion
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty { updated.title = entries[index].suggestion.title }
        entries[index].suggestion = updated
        editingEntry = nil
    }

    // MARK: - まとめて承認

    /// 全部OK：残っている候補をすべて追加し、Inbox から外す
    func approveAll() {
        let items = entries.map { $0.suggestion.makeItem(today: now) }
        store.add(items)
        store.removeFromInbox(Set(entries.map(\.id)))
        addedCount = items.count
        entries = []
        isFinished = true
    }
}
