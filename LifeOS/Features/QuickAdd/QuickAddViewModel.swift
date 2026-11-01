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
    /// 文の中の日付が存在しなかったときの説明（「2027年2月30日はありません」）。
    /// あるあいだは追加できない（確認画面で日付を選ぶと消える。Build 12）
    var dateNote: String? = nil

    var id: LifeItem.ID { item.id }
}

@Observable
final class QuickAddViewModel {
    private let store: LifeStore
    private let now: Date

    var inputText = ""
    var candidates: [QuickAddCandidate] = []
    /// 保存先（自分だけ／わが家で共有）。2026-10-28：初期値は必ず「自分だけ」。
    /// 「わが家で共有」は利用者が選んだときだけ（AI・自動の分類は選ばない）。共有できるのは ToDo・買い物だけ
    var destination: SaveDestination = .initial
    var isShowingResults = false
    var isShowingVoiceInputNotice = false
    var isShowingAmountNotice = false
    /// 「種類を決めて追加」の予定で、存在しない日付が書かれていた（Build 12。黙って保存しない）
    var isShowingDateNotice = false

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
    }

    /// 「わが家で共有」を選べるか（わが家に参加していて、ToDo・買い物のどちらかがオン）
    var canChooseDestination: Bool {
        store.canShareInHousehold(.todo) || store.canShareInHousehold(.shopping)
    }

    /// 実際に使う保存先（選べないときは「自分だけ」）
    private var effectiveDestination: SaveDestination {
        canChooseDestination ? destination : .personal
    }

    // MARK: - 入力

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「すぐ追加」を押せるか（入力欄が空なら押せない）
    var canQuickAdd: Bool { !trimmedInput.isEmpty }

    /// とりあえず保存：分類・日時・担当を決めずに Inbox へ入れる（v2 おまかせInbox）
    /// - Returns: 保存できたら true（シートを閉じる）
    func saveToInbox() -> Bool {
        guard canQuickAdd else { return false }
        store.addToInbox(trimmedInput, now: now)
        inputText = ""
        return true
    }

    func startVoiceInput() {
        // TODO: 音声入力（Speech フレームワーク等）は今回未実装。
        isShowingVoiceInputNotice = true
    }

    /// 「すぐ追加」：整理せず、入力欄の内容をそのまま指定の種類で今日に1件追加する。
    /// 決定済み（2026-10-01）。
    /// 決定済み：すぐ追加した項目は「自分」として追加する（2026-10-01）。
    /// 「入力をもっと賢く」（2026-10-07）：予定は「19時 美容院」のような時刻を読み取り、時刻つきで追加する（無ければ終日）。
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
            if kind == .event {
                // Build 12：「12月25日 19時 美容院」のような日付も読む（無ければ今日）。存在しない日付なら保存しない
                guard let event = Self.quickEvent(from: trimmedInput, now: now) else {
                    isShowingDateNotice = true
                    return false
                }
                store.add([event])
            } else {
                // ToDo・買い物は、選んだ保存先へ（初期値は自分だけ。予定は Build 7 では共有しない）
                store.add([
                    LifeItem(title: trimmedInput, kind: kind, ownership: .personal, date: today, assignee: .me)
                ], destination: kind == .event ? .personal : effectiveDestination)
            }

        case .expense:
            // 例：「ランチ 1200」→ 品目「ランチ」・金額 1,200円
            // Calm Future 第2段階：「提案どおり追加」と同じルールで品目からカテゴリーを決める（分からなければ「その他」）
            guard let parsed = Self.parseExpense(trimmedInput) else {
                isShowingAmountNotice = true
                return false
            }
            let category = LifeInterpreter.expenseCategory(for: parsed.title)
            store.add(Expense(title: parsed.title, amount: parsed.amount, category: category, date: today))
        }

        inputText = ""
        return true
    }

    /// 「種類を決めて追加」の予定：日付（あれば）・時刻（あれば）を読み、いつも「自分」の予定にする。
    /// 存在しない日付が書かれていれば nil（保存しない）
    static func quickEvent(from text: String, now: Date) -> LifeItem? {
        var title = text
        var day = LifeCalendar.startOfDay(now)
        if let dateMatch = DateReader.read(title, now: now), !dateMatch.remainingText.isEmpty {
            guard let date = dateMatch.date else { return nil }
            day = date
            title = dateMatch.remainingText
        }
        if let timeMatch = TimeReader.read(title), !timeMatch.remainingText.isEmpty {
            return LifeItem(title: timeMatch.remainingText, kind: .event, ownership: .personal,
                            date: timeMatch.time.date(on: day), hasTime: true, assignee: .me)
        }
        return LifeItem(title: title, kind: .event, ownership: .personal, date: day, assignee: .me)
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

    // MARK: - 生活コンソール（Calm Future 第2段階）

    /// 入力例（押すと入力欄に入る）
    static let examples = ["土曜に母へ電話", "牛乳とティッシュ", "ランチ 1200"]

    func fillExample(_ example: String) {
        inputText = example
    }

    /// LifeOSの理解（入力中もその場で変わる。ルールのみ）
    var understanding: LifeUnderstanding? {
        LifeInterpreter.understand(inputText, now: now)
    }

    /// 理解の「いつ」
    var understandingTiming: String? {
        understanding?.timing(now: now)
    }

    /// 「提案どおり追加」の文言（2件以上なら件数も）
    var addAsSuggestedTitle: String {
        guard let count = understanding?.count, count > 1 else { return "提案どおり追加" }
        return "提案どおり追加（\(count)件）"
    }

    /// 「提案どおり追加」を押せるか
    var canAddAsSuggested: Bool { understanding != nil }

    /// 「詳しく整える」を押せるか（支出は「種類を決めて追加」の支出か、提案どおり追加で足りるため出さない）
    var canRefine: Bool {
        guard let understanding else { return true }
        if case .expense(_, _, _) = understanding.outcome { return false }
        return true
    }

    /// 提案どおり追加：理解したとおりに追加する。
    /// 自動の分類は「共有」を選ばない。わが家で共有するのは、利用者が保存先で選んだときの ToDo・買い物だけ（2026-10-28）。
    /// 一人モードでは共有を前面に出さないため、常に「自分」として追加する。
    /// - Returns: 追加できたら true（シートを閉じる）
    @discardableResult
    func addAsSuggested(usageStyle: UsageStyle) -> Bool {
        guard let understanding else { return false }
        switch understanding.outcome {
        case let .items(suggestions):
            // Build 12：存在しない日付が書かれていたら、黙って保存しない。確認画面で日付を選んでもらう
            if suggestions.contains(where: \.needsDateConfirmation) {
                refine(usageStyle: usageStyle)
                return false
            }
            let items = suggestions.map { $0.makeItem(today: now) }
            store.add(items, destination: usageStyle.showsScopeFilter ? effectiveDestination : .personal)
        case let .expense(title, amount, category):
            store.add(Expense(title: title, amount: amount, category: category, date: LifeCalendar.startOfDay(now)))
        }
        inputText = ""
        return true
    }

    /// 詳しく整える：理解した内容を1件ずつ確認・選択できる画面へ。
    /// 入力が空のときは、これまでの「整理する」と同じく整理の例（Mock）を出す。
    func refine(usageStyle: UsageStyle) {
        guard let understanding, case let .items(suggestions) = understanding.outcome else {
            organize()
            return
        }
        candidates = suggestions.map {
            QuickAddCandidate(item: $0.makeItem(today: now), isSelected: true, dateNote: $0.dateProblem)
        }
        // 保存先は、利用者がこの画面で選んだもの（初期値は自分だけ）。自動の分類からは決めない
        if !usageStyle.showsScopeFilter { destination = .personal }
        isShowingResults = true
    }

    /// 「整理する」：AIは使わず、固定のMock結果を表示する。
    /// TODO: 入力欄が空でも押せるかは仕様未定。現状は常に押せる。
    func organize() {
        candidates = MockData.quickAddResults().map { QuickAddCandidate(item: $0, isSelected: true) }
        destination = .initial
        isShowingResults = true
    }

    // MARK: - 確認画面

    var foundText: String { "\(candidates.count)件見つかりました" }

    var selectedCount: Int { candidates.filter(\.isSelected).count }

    var addButtonTitle: String { "\(selectedCount)件を追加" }

    /// 追加できるか（選んだ項目があり、日付を確かめる必要のある項目が残っていない）
    var canAdd: Bool {
        selectedCount > 0 && !candidates.contains { $0.isSelected && $0.dateNote != nil }
    }

    // MARK: - 日付（Build 12）

    /// 日付を選べるか（予定と、日付を確かめる必要のある項目）。アプリ独自の「1週間先まで」などの上限は付けない
    func canChooseDate(_ candidate: QuickAddCandidate) -> Bool {
        candidate.item.kind == .event || candidate.dateNote != nil
    }

    /// 「詳しく整える」で日付を選ぶ。時刻のある項目は、時刻をそのままにして日付だけ変える
    func setDate(_ date: Date, for id: QuickAddCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        var item = candidates[index].item
        let day = LifeCalendar.startOfDay(date)
        item.date = item.hasTime ? ClockTime(date: item.date).date(on: day) : day
        candidates[index].item = item
        candidates[index].dateNote = nil
    }

    /// 柔らかい時間の選択肢（決めない＋帰宅時・夜・余力があれば・今週中）
    static let softTimeOptions: [SoftTime?] = [nil] + SoftTime.allCases.map { Optional($0) }

    /// 柔らかい時間を選べるか（時刻の決まっている項目は時刻を優先するため選べない）
    func canChooseSoftTime(_ item: LifeItem) -> Bool {
        !item.hasTime
    }

    /// 柔らかい時間の表示（決めない／帰宅時 など）
    static func softTimeLabel(_ softTime: SoftTime?) -> String {
        softTime?.label ?? "決めない"
    }

    /// 「詳しく整える」で、項目ごとに柔らかい時間を選ぶ（「入力をもっと賢く」2026-10-07）
    func setSoftTime(_ softTime: SoftTime?, for id: QuickAddCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }),
              canChooseSoftTime(candidates[index].item) else { return }
        candidates[index].item.softTime = softTime
    }

    func toggleCandidate(_ id: QuickAddCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].isSelected.toggle()
    }

    func displayTitle(for item: LifeItem) -> String {
        item.hasTime ? "\(item.title) \(LifeFormatters.time(item.date))" : item.title
    }

    /// 確認画面の補足（種類・いつ）
    func detailText(for item: LifeItem) -> String {
        var parts = [item.kind.label]
        if !LifeCalendar.isSameDay(item.date, now) {
            parts.append(LifeFormatters.dateNoting(item.date, now: now))
        }
        if let softTime = item.softTime {
            parts.append(softTime.label)
        }
        return parts.joined(separator: "・")
    }

    /// 選択した項目を、選んだ保存先へ追加する（わが家で共有にできるのは ToDo・買い物だけ。ほかは自分だけ）
    func addSelected() {
        let items = candidates.filter(\.isSelected).map(\.item)
        store.add(items, destination: effectiveDestination)
        reset()
    }

    private func reset() {
        inputText = ""
        candidates = []
        destination = .initial
        isShowingResults = false
    }
}
