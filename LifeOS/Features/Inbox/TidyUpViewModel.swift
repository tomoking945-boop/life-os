import Foundation
import Observation

/// おまかせ整理の1件（Inbox のメモ＋整理の候補）
struct TidyUpEntry: Identifiable, Hashable {
    let inboxID: InboxItem.ID
    let originalText: String
    var suggestion: InboxSuggestion

    var id: InboxItem.ID { inboxID }
}

/// まとめて整理の結果の行（買い物へ 2件 など）
struct TidyUpGroup: Identifiable, Hashable {
    let title: String
    let count: Int

    var id: String { title }
}

/// 1日1回の「おまかせ整理」（今日の整理）。
/// Calm Future 第2段階：最初に全体の整理結果（どこへ何件）を見せ、
/// 「すべて反映」か「内容を確認」（1件ずつの確認）を選ぶ。反映したあとも元に戻せる。
@Observable
final class TidyUpViewModel {
    private let store: LifeStore
    private let now: Date

    var entries: [TidyUpEntry]
    /// 修正中の項目
    var editingEntry: TidyUpEntry?
    /// 最初の全体の整理結果を見せているか（「内容を確認」で1件ずつの確認へ）
    var isShowingSummary: Bool
    /// 反映した件数（完了表示用）
    private(set) var addedCount = 0
    private(set) var isFinished = false

    /// 元に戻すための記録（反映した項目と、Inbox から外したメモ）
    private var appliedItemIDs: Set<LifeItem.ID> = []
    private var appliedMemos: [InboxItem] = []
    private var appliedEntries: [TidyUpEntry] = []

    /// - Parameters:
    ///   - edits: Inbox 画面で「修正」した理解（メモごと）
    ///   - usageStyle: 一人モードでは共有を前面に出さないため、すべて「自分」として整理する
    init(
        store: LifeStore,
        now: Date = LifeCalendar.now,
        edits: [InboxItem.ID: InboxSuggestion] = [:],
        usageStyle: UsageStyle = .shared
    ) {
        self.store = store
        self.now = now
        let entries = store.inbox
            .filter { $0.isReady(at: now) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { memo -> TidyUpEntry in
                var suggestion = edits[memo.id] ?? memo.edit ?? InboxClassifier.suggest(for: memo.text)
                if !usageStyle.showsScopeFilter { suggestion.ownership = .personal }
                return TidyUpEntry(inboxID: memo.id, originalText: memo.text, suggestion: suggestion)
            }
        self.entries = entries
        self.isShowingSummary = !entries.isEmpty
    }

    var hasEntries: Bool { !entries.isEmpty }

    var approveAllTitle: String { "すべて反映（\(entries.count)件）" }

    var finishedText: String { "\(addedCount)件を反映しました" }

    // MARK: - 全体の整理結果

    var summaryTitle: String { "\(entries.count)件を整理しました" }

    /// どこへ何件か（出てきた順）
    var summaryGroups: [TidyUpGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for entry in entries {
            let title = Self.destination(of: entry.suggestion)
            if counts[title] == nil { order.append(title) }
            counts[title, default: 0] += 1
        }
        return order.map { TidyUpGroup(title: $0, count: counts[$0] ?? 0) }
    }

    /// 行き先の言い方。
    /// 新しい解釈：共有 → 家族と共有へ／買い物 → 買い物へ／今日以外 → 明日へ・土曜へ／それ以外は種類ごと。
    static func destination(of suggestion: InboxSuggestion) -> String {
        if suggestion.ownership == .shared { return "家族と共有へ" }
        if suggestion.kind == .shopping { return "買い物へ" }
        if suggestion.day != .today { return "\(suggestion.day.label)へ" }
        switch suggestion.kind {
        case .payment: return "支払いへ"
        case .chore: return "家事へ"
        case .event: return "予定へ"
        case .todo, .habit, .shopping: return "やることへ"
        }
    }

    func showDetails() {
        isShowingSummary = false
    }

    func timingText(for entry: TidyUpEntry) -> String {
        entry.suggestion.timingText(now: now)
    }

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
        updated.applyUserEdit()
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty { updated.title = entries[index].suggestion.title }
        entries[index].suggestion = updated
        // 「入力をもっと賢く」：修正内容をメモにも保存する（スキップ・後でにしても残る）
        store.saveInboxEdit(id, suggestion: updated)
        editingEntry = nil
    }

    // MARK: - まとめて反映

    /// すべて反映（これまでの「全部OK」）：残っている候補をすべて追加し、Inbox から外す
    func approveAll() {
        let items = entries.map { $0.suggestion.makeItem(today: now) }
        let ids = Set(entries.map(\.id))
        appliedMemos = store.inbox.filter { ids.contains($0.id) }
        appliedEntries = entries
        appliedItemIDs = Set(items.map(\.id))

        store.add(items)
        store.removeFromInbox(ids)
        addedCount = items.count
        entries = []
        isFinished = true
    }

    /// 反映したあとに出す「元に戻す」が使えるか
    var canUndoApply: Bool { isFinished && !appliedEntries.isEmpty }

    /// 元に戻す：追加した項目を取り除き、メモを Inbox に戻して、整理結果の画面に戻る
    func undoApply() {
        guard canUndoApply else { return }
        store.removeItems(withIDs: appliedItemIDs)
        store.restoreInbox(appliedMemos)
        entries = appliedEntries
        appliedItemIDs = []
        appliedMemos = []
        appliedEntries = []
        addedCount = 0
        isFinished = false
        isShowingSummary = true
    }
}
