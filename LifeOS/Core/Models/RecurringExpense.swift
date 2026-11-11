import Foundation

// 固定費・定期支出（2026-11-11 Build 25）。docs/BUILD_25_RECURRING_EXPENSES.md
//
// - 家賃・通信費・保険・サブスクなど、毎月くり返す支出の「設定」と、月ごとの「状態」（追加済み・今月は追加しない）
// - 支出は自動で作らない。表示している月に候補を1件だけ出し、利用者が「今月分を追加」→ 支出の確認画面で「保存」を押したときだけ、
//   ふつうの支出を1件作り、その月を「追加済み」にする（同じ設定の同じ月は1件だけ）
// - 候補は支出ではない（予算・集計・検索に入れない）
// - 自分だけの設定と状態は端末の life-store.json だけ。わが家で共有の設定と状態は Firestore の
//   groups/{groupID}/recurringExpenses/{templateID} と groups/{groupID}/recurringExpenseOccurrences/{templateID}_{YYYY-MM}
// - 名前・金額はログに出さない

/// 定期支出の設定（毎月くり返す支出のひな形）
struct RecurringExpenseTemplate: Identifiable, Equatable, Codable {
    /// 名前の長さの上限（Security Rules と同じ 80。Unicode の文字の数で数える）
    static let maxTitleLength = 80
    /// 金額の上限（支出と同じ）
    static let maxAmount = 999_999_999

    let id: UUID
    /// 名前（前後の空白を除いた 1〜80 文字。改行・制御文字なし）
    var title: String
    /// 目安金額（1〜999,999,999 円）
    var expectedAmount: Int
    var category: ExpenseCategory
    /// 毎月の支払日（1〜31。その日が無い月は月の最終日）
    var dueDay: Int
    /// 開始月（YYYY-MM）。この月より前には候補を出さない。再開したときは再開した月にする
    var startMonthKey: String
    /// 停止中は false（新しい月の候補を出さない）
    var isActive: Bool
    /// 保存先（自分だけ／わが家で共有）。保存したあとは変えない
    let ownership: Ownership

    var startMonth: BudgetMonth? { BudgetMonth(key: startMonthKey) }
    var isShared: Bool { ownership == .shared }

    /// 保存できない理由（保存できるなら nil）
    var validationError: RecurringExpenseError? {
        if let problem = RecurringExpenseInput.titleProblem(title) { return problem }
        guard (1...Self.maxAmount).contains(expectedAmount) else {
            return .amount(expectedAmount < 0 ? .negative : (expectedAmount == 0 ? .zeroNotAllowed : .tooLarge))
        }
        guard (1...31).contains(dueDay) else { return .invalidDueDay }
        guard let month = startMonth, month.isStorable else { return .invalidMonth }
        return nil
    }

    /// その月の支払予定日（その日が無い月は月の最終日。端末の暦で）
    func dueDate(in month: BudgetMonth, calendar: Calendar = LifeCalendar.calendar) -> Date {
        let day = min(dueDay, month.dayCount(calendar: calendar))
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: day)) ?? month.firstDay(calendar: calendar)
    }
}

/// 月ごとの状態（追加済み・今月は追加しない）。「未確認」は記録しない（記録が無い＝未確認）
struct RecurringOccurrence: Identifiable, Equatable, Codable {
    enum Status: String, Codable, Equatable {
        /// 追加済み（支出を作った）
        case created
        /// 今月は追加しない
        case skipped
    }

    let templateID: UUID
    /// 対象の月（YYYY-MM）
    let monthKey: String
    let status: Status
    /// 追加済みなら作った支出の ID。今月は追加しないなら nil
    let expenseID: UUID?

    /// 文書の ID（{templateID}_{YYYY-MM}）
    var id: String { Self.id(templateID: templateID, monthKey: monthKey) }

    static func id(templateID: UUID, monthKey: String) -> String {
        "\(templateID.uuidString)_\(monthKey)"
    }

    /// 形が正しいか（追加済みは支出の ID があり、今月は追加しないは無い）
    var isValid: Bool {
        guard BudgetMonth(key: monthKey)?.isStorable == true else { return false }
        switch status {
        case .created: return expenseID != nil
        case .skipped: return expenseID == nil
        }
    }
}

/// 表示している月の候補の状態（色だけに頼らず文字で出す）
enum RecurringCandidateState: Equatable {
    /// 未確認（まだ追加していない）
    case unconfirmed
    /// 追加済み
    case created
    /// 今月は追加しない
    case skipped

    var label: String {
        switch self {
        case .unconfirmed: return "未確認"
        case .created: return "追加済み"
        case .skipped: return "今月は追加しない"
        }
    }
}

/// 表示している月の候補（1つの設定につき、1か月に1件だけ）。支出ではない（予算・集計・検索に入れない）
struct RecurringCandidate: Identifiable, Equatable {
    let template: RecurringExpenseTemplate
    let month: BudgetMonth
    /// その月の支払予定日
    let dueDate: Date
    let state: RecurringCandidateState
    /// 追加済みなら、その月の記録
    let occurrence: RecurringOccurrence?

    var id: String { RecurringOccurrence.id(templateID: template.id, monthKey: month.key) }
}

/// 定期支出を保存できない理由（画面に日本語で出す）
enum RecurringExpenseError: Error, Equatable {
    case titleMissing
    case titleTooLong
    case titleHasControlCharacters
    case amountMissing
    case amount(BudgetAmountProblem)
    case invalidDueDay
    case invalidMonth
    /// 支出の日付が対象の月の外
    case dateOutsideMonth(BudgetMonth)
    /// その月はもう追加済み・今月は追加しないにしてある
    case alreadyProcessed
    /// 追加済みは未確認に戻せない
    case cannotUndoCreated
    /// 見つからない
    case notFound
    /// 停止中
    case paused
    /// 共有の操作ができない（理由の文）
    case notEditable(String)
    /// 端末に保存できなかった
    case saveFailed
    /// 支出として正しくない（タイトル・金額）
    case invalidExpense

    var message: String {
        switch self {
        case .titleMissing: return "名前を入れてください。"
        case .titleTooLong: return "名前は80文字以内で入れてください。"
        case .titleHasControlCharacters: return "名前に改行などの特別な文字は使えません。"
        case .amountMissing: return "目安金額を入れてください（1〜999,999,999円）。"
        case .amount(let problem): return "目安金額：\(problem.message)"
        case .invalidDueDay: return "支払日は1〜31日から選んでください。"
        case .invalidMonth: return "開始月は2000年1月〜2099年12月から選んでください。"
        case .dateOutsideMonth(let month): return "日付は\(month.title)の中から選んでください。別の月の支出は、ふつうの「支出を追加」から入れてください。"
        case .alreadyProcessed: return "この月はもう確認済みです（同じ月の支出は1件だけ作ります）。"
        case .cannotUndoCreated: return "追加済みの月は未確認に戻せません（二重に登録しないため）。"
        case .notFound: return "この定期支出は見つかりません。"
        case .paused: return "停止中の定期支出です。再開すると候補が出ます。"
        case .notEditable(let reason): return reason
        case .saveFailed: return "保存できませんでした。もう一度お試しください。"
        case .invalidExpense: return "タイトルと金額（1〜999,999,999円）を入れてください。"
        }
    }
}

/// 定期支出の入力欄の読み方
enum RecurringExpenseInput {
    /// 前後の空白を除いた名前
    static func trimmedTitle(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 名前の問題（空・81文字以上・改行や制御文字）。正しければ nil
    static func titleProblem(_ text: String) -> RecurringExpenseError? {
        let title = trimmedTitle(text)
        if title.isEmpty { return .titleMissing }
        // 制御文字（Unicode の Cc）と改行は使えない（Security Rules の [[:cntrl:]] より広い。絵文字をつなぐ文字などの Cf は使える）
        if title.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0) }) {
            return .titleHasControlCharacters
        }
        if title.unicodeScalars.count > RecurringExpenseTemplate.maxTitleLength { return .titleTooLong }
        return nil
    }

    /// 目安金額（全角・カンマ・「円」「¥」は読む。空・0・負・小数・文字・上限超えは理由）
    static func amount(_ text: String) -> Result<Int, RecurringExpenseError> {
        switch BudgetAmountInput.parse(text, allowsZero: false) {
        case .failure(let problem): return .failure(.amount(problem))
        case .success(nil): return .failure(.amountMissing)
        case .success(let value?): return .success(value)
        }
    }
}

/// 定期支出の入力（設定の画面のあいだだけ。保存するまで設定は変わらない）
struct RecurringExpenseDraft: Equatable, Identifiable {
    /// 設定の ID（新しい設定なら新しい ID）
    let id: UUID
    let isNew: Bool
    var title: String
    var amountText: String
    var category: ExpenseCategory
    var dueDay: Int
    var startMonth: BudgetMonth
    /// 保存先（新しい設定の初期値は必ず「自分だけ」。保存したあとは変えない）
    var destination: SaveDestination
    /// 停止中か（編集のときだけ使う）
    let isActive: Bool

    /// 新しい設定（保存先は「自分だけ」）
    init(newIn month: BudgetMonth, dueDay: Int = 27) {
        id = UUID()
        isNew = true
        title = ""
        amountText = ""
        category = .other
        self.dueDay = dueDay
        startMonth = month
        destination = .personal
        isActive = true
    }

    /// 今ある設定の編集（保存先は変えない）
    init(editing template: RecurringExpenseTemplate, fallbackMonth: BudgetMonth) {
        id = template.id
        isNew = false
        title = template.title
        amountText = String(template.expectedAmount)
        category = template.category
        dueDay = template.dueDay
        startMonth = template.startMonth ?? fallbackMonth
        destination = template.isShared ? .household : .personal
        isActive = template.isActive
    }

    /// 保存する設定。正しくなければ理由
    func validated() -> Result<RecurringExpenseTemplate, RecurringExpenseError> {
        if let problem = RecurringExpenseInput.titleProblem(title) { return .failure(problem) }
        let amount: Int
        switch RecurringExpenseInput.amount(amountText) {
        case .failure(let error): return .failure(error)
        case .success(let value): amount = value
        }
        guard (1...31).contains(dueDay) else { return .failure(.invalidDueDay) }
        guard startMonth.isStorable else { return .failure(.invalidMonth) }
        let template = RecurringExpenseTemplate(
            id: id,
            title: RecurringExpenseInput.trimmedTitle(title),
            expectedAmount: amount,
            category: category,
            dueDay: dueDay,
            startMonthKey: startMonth.key,
            isActive: isActive,
            ownership: destination == .household ? .shared : .personal
        )
        if let error = template.validationError { return .failure(error) }
        return .success(template)
    }

    /// 欄の下に出す理由（正しければ nil）
    var problem: RecurringExpenseError? {
        if case .failure(let error) = validated() { return error }
        return nil
    }
}

/// 候補を作る決まり（画面・今日の画面・テストで同じものを使う）
enum RecurringExpenseSchedule {
    /// その月の候補（1つの設定につき1件だけ）。
    /// - 記録（追加済み・今月は追加しない）がある月は、その状態で出す（停止中・開始月より前でも、記録は残す）
    /// - 記録が無い月は、動いている設定で、開始月以降のときだけ「未確認」で出す（停止中は出さない）
    static func candidates(
        templates: [RecurringExpenseTemplate],
        occurrences: [String: RecurringOccurrence],
        month: BudgetMonth,
        calendar: Calendar = LifeCalendar.calendar
    ) -> [RecurringCandidate] {
        var seen: Set<UUID> = []
        var result: [RecurringCandidate] = []
        for template in templates where seen.insert(template.id).inserted {
            let occurrence = occurrences[RecurringOccurrence.id(templateID: template.id, monthKey: month.key)]
            let state: RecurringCandidateState
            switch occurrence?.status {
            case .created?: state = .created
            case .skipped?: state = .skipped
            case nil:
                guard template.isActive, let start = template.startMonth, month >= start else { continue }
                state = .unconfirmed
            }
            result.append(RecurringCandidate(
                template: template, month: month, dueDate: template.dueDate(in: month, calendar: calendar),
                state: state, occurrence: occurrence
            ))
        }
        return result.sorted { lhs, rhs in
            lhs.dueDate == rhs.dueDate ? lhs.template.id.uuidString < rhs.template.id.uuidString : lhs.dueDate < rhs.dueDate
        }
    }

    /// 今日の画面に出す候補（今月の未確認で、支払予定日を過ぎた・今日・7日以内のもの）
    static func needsReview(_ candidates: [RecurringCandidate], today: Date, calendar: Calendar = LifeCalendar.calendar) -> [RecurringCandidate] {
        let month = BudgetMonth(date: today, calendar: calendar)
        let start = calendar.startOfDay(for: today)
        guard let limit = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return candidates.filter { $0.state == .unconfirmed && $0.month == month && calendar.startOfDay(for: $0.dueDate) <= limit }
    }
}

/// 端末に保存する自分だけの定期支出（設定と月ごとの状態）。読めない記録・正しくない記録は飛ばす（ファイル全体を読めなくしない）
struct RecurringExpenseRecords: Codable, Equatable {
    var templates: [RecurringExpenseTemplate]
    var occurrences: [RecurringOccurrence]

    init(templates: [RecurringExpenseTemplate], occurrences: [RecurringOccurrence]) {
        self.templates = templates
        self.occurrences = occurrences
    }

    private enum CodingKeys: String, CodingKey {
        case templates
        case occurrences
    }

    /// 1件ずつ読む（読めない1件だけを飛ばす）
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        let rawTemplates = (try? container?.decodeIfPresent([Lenient<RecurringExpenseTemplate>].self, forKey: .templates)) ?? nil
        let rawOccurrences = (try? container?.decodeIfPresent([Lenient<RecurringOccurrence>].self, forKey: .occurrences)) ?? nil
        var ids: Set<UUID> = []
        templates = (rawTemplates ?? []).compactMap(\.value).filter {
            $0.ownership == .personal && $0.validationError == nil && ids.insert($0.id).inserted
        }
        var occurrenceIDs: Set<String> = []
        occurrences = (rawOccurrences ?? []).compactMap(\.value).filter {
            $0.isValid && ids.contains($0.templateID) && occurrenceIDs.insert($0.id).inserted
        }
    }
}
