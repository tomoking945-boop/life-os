import Foundation
import Observation

/// 「すぐ追加」の種類
enum QuickAddType: String, CaseIterable, Identifiable, Hashable {
    case todo
    case event
    case shopping
    case expense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "ToDo"
        case .event: return "予定"
        case .shopping: return "買い物"
        case .expense: return "支出"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "checkmark.circle"
        case .event: return "calendar"
        case .shopping: return "bag"
        case .expense: return "yensign.circle"
        }
    }
}

/// 整理結果の1件（チェックON/OFFできる）
struct QuickAddCandidate: Identifiable, Hashable {
    var item: LifeItem
    var isSelected: Bool

    var id: LifeItem.ID { item.id }
}

@Observable
final class QuickAddViewModel {
    private let store: LifeStore
    private let now: Date

    var inputText = ""
    var candidates: [QuickAddCandidate] = []
    /// 整理結果を「自分」「共有」のどちらに追加するか
    /// 決定済み：確認画面で選べるようにする（2026-10-01）。初期値は「自分」。
    var ownership: Ownership = .personal
    var isShowingResults = false
    var isShowingVoiceInputNotice = false
    var isShowingAmountNotice = false

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
    }

    // MARK: - 入力

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「すぐ追加」を押せるか（入力欄が空なら押せない）
    var canQuickAdd: Bool { !trimmedInput.isEmpty }

    func startVoiceInput() {
        // TODO: 音声入力（Speech フレームワーク等）は今回未実装。
        isShowingVoiceInputNotice = true
    }

    /// 「すぐ追加」：整理せず、入力欄の内容をそのまま指定の種類で今日に1件追加する。
    /// 決定済み（2026-10-01）。
    /// TODO: すぐ追加した項目の「自分 / 共有」区分は未定。現状は「自分」として追加する。
    /// TODO: 予定の時刻は入力から読み取らない（終日の予定として追加）。
    /// - Returns: 追加できたら true（シートを閉じる）
    func quickAdd(_ type: QuickAddType) -> Bool {
        guard canQuickAdd else { return false }
        let today = LifeCalendar.startOfDay(now)

        switch type {
        case .todo, .event, .shopping:
            let kind: LifeItemKind
            switch type {
            case .todo: kind = .todo
            case .event: kind = .event
            default: kind = .shopping
            }
            store.add([
                LifeItem(title: trimmedInput, kind: kind, ownership: .personal, date: today, assignee: .me)
            ])

        case .expense:
            // 例：「ランチ 1200」→ 品目「ランチ」・金額 1,200円
            // TODO: 支出のカテゴリーは入力から判断しない。現状は「その他」。
            guard let parsed = Self.parseExpense(trimmedInput) else {
                isShowingAmountNotice = true
                return false
            }
            store.add(Expense(title: parsed.title, amount: parsed.amount, category: .other, date: today))
        }

        inputText = ""
        return true
    }

    /// 入力の最後の数字を金額として取り出す（「ランチ 1,200円」→ ランチ / 1200）
    static func parseExpense(_ text: String) -> (title: String, amount: Int)? {
        guard let regex = try? NSRegularExpression(pattern: "[0-9０-９][0-9０-９,，]*"),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else {
            return nil
        }
        let digits = text[range]
            .applyingTransform(.fullwidthToHalfwidth, reverse: false)?
            .filter(\.isNumber) ?? ""
        guard let amount = Int(digits), amount > 0 else { return nil }

        var title = text
        title.removeSubrange(range)
        title = title
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? "支出" : title, amount)
    }

    /// 「整理する」：AIは使わず、固定のMock結果を表示する。
    /// TODO: 入力欄が空でも押せるかは仕様未定。現状は常に押せる。
    func organize() {
        candidates = MockData.quickAddResults().map { QuickAddCandidate(item: $0, isSelected: true) }
        ownership = .personal
        isShowingResults = true
    }

    // MARK: - 確認画面

    var foundText: String { "\(candidates.count)件見つかりました" }

    var selectedCount: Int { candidates.filter(\.isSelected).count }

    var addButtonTitle: String { "\(selectedCount)件を追加" }

    var canAdd: Bool { selectedCount > 0 }

    func toggleCandidate(_ id: QuickAddCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].isSelected.toggle()
    }

    func displayTitle(for item: LifeItem) -> String {
        item.hasTime ? "\(item.title) \(LifeFormatters.time(item.date))" : item.title
    }

    /// 選択した項目を、選んだ「自分 / 共有」で Mock のデータに追加する
    /// TODO: 共有で追加したときの担当者は仕様未定。現状は「どちらでも」。
    func addSelected() {
        let items = candidates.filter(\.isSelected).map { candidate -> LifeItem in
            var item = candidate.item
            item.ownership = ownership
            item.assignee = (ownership == .personal) ? .me : .either
            return item
        }
        store.add(items)
        reset()
    }

    private func reset() {
        inputText = ""
        candidates = []
        ownership = .personal
        isShowingResults = false
    }
}
