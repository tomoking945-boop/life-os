import Foundation

// わが家で共有の定期支出（2026-11-11 Build 25）。docs/BUILD_25_RECURRING_EXPENSES.md
//
// - 設定：groups/{groupID}/recurringExpenses/{templateID}（11項目だけ）
//   schemaVersion・title・expectedAmount・category・dueDay・startMonthKey・isActive・createdBy・updatedBy・createdAt・updatedAt
// - 月ごとの状態：groups/{groupID}/recurringExpenseOccurrences/{templateID}_{YYYY-MM}（7項目だけ）
//   schemaVersion・templateID・monthKey・status（created / skipped）・expenseID（追加済みは支出の UUID、今月は追加しないは null）・
//   processedBy・processedAt
// - 「今月分を追加」の共有の支出と「追加済み」の記録は、1回の書き込み（WriteBatch。全部が成功するか、全部が失敗する）で一緒に送る。
//   同じ月の記録がすでにあれば Security Rules が断るので、2台で同時に押しても共有の支出は1件だけ
// - 送らないもの：メールアドレス・表示名・端末の情報・通知のトークン・レシートの写真・読み取った全文・商品明細・検索語・自分だけの定期支出
// - 名前・金額はログに出さない。定期支出では通知を送らない（Functions は変えない）

/// 共有の定期支出の送る形・読む形
enum SharedRecurringExpensePayload {
    static let schemaVersion = 1
    /// 設定の文書の項目（Security Rules の hasOnly と同じ）
    static let templateFieldNames: [String] = [
        "schemaVersion", "title", "expectedAmount", "category", "dueDay", "startMonthKey", "isActive",
        "createdBy", "updatedBy", "createdAt", "updatedAt",
    ]
    /// 月ごとの状態の文書の項目（Security Rules の hasOnly と同じ）
    static let occurrenceFieldNames: [String] = [
        "schemaVersion", "templateID", "monthKey", "status", "expenseID", "processedBy", "processedAt",
    ]

    /// 設定を作るときに送る項目（作成者・作成日時は本人・サーバーの時刻）。正しくなければ nil（送らない）
    static func createTemplateFields(for template: RecurringExpenseTemplate) -> [String: SharedItemValue]? {
        guard var fields = updateTemplateFields(for: template) else { return nil }
        fields["schemaVersion"] = .int(schemaVersion)
        fields["createdBy"] = .currentUser
        fields["createdAt"] = .serverTimestamp
        return fields
    }

    /// 設定を変えるときに送る項目（作成者・作成日時・schemaVersion は送らない＝変えない）
    static func updateTemplateFields(for template: RecurringExpenseTemplate) -> [String: SharedItemValue]? {
        guard template.isShared, template.validationError == nil else { return nil }
        return [
            "title": .string(template.title),
            "expectedAmount": .int(template.expectedAmount),
            "category": .string(template.category.rawValue),
            "dueDay": .int(template.dueDay),
            "startMonthKey": .string(template.startMonthKey),
            "isActive": .bool(template.isActive),
            "updatedBy": .currentUser,
            "updatedAt": .serverTimestamp,
        ]
    }

    /// 月ごとの状態を送る項目（処理した人は本人・日時はサーバーの時刻）。正しくなければ nil
    static func occurrenceFields(for occurrence: RecurringOccurrence) -> [String: SharedItemValue]? {
        guard occurrence.isValid else { return nil }
        return [
            "schemaVersion": .int(schemaVersion),
            "templateID": .string(occurrence.templateID.uuidString),
            "monthKey": .string(occurrence.monthKey),
            "status": .string(occurrence.status.rawValue),
            "expenseID": occurrence.expenseID.map { SharedItemValue.string($0.uuidString) } ?? SharedItemValue.null,
            "processedBy": .currentUser,
            "processedAt": .serverTimestamp,
        ]
    }

    /// 受け取った設定の文書。形が違うもの・正しくない値は nil（表示しない）
    static func template(documentID: String, data: [String: Any]) -> RecurringExpenseTemplate? {
        guard let id = UUID(uuidString: documentID),
              data["schemaVersion"] as? Int == schemaVersion,
              let title = data["title"] as? String,
              let amount = data["expectedAmount"] as? Int,
              let categoryRaw = data["category"] as? String, let category = ExpenseCategory(rawValue: categoryRaw),
              let dueDay = data["dueDay"] as? Int,
              let startMonthKey = data["startMonthKey"] as? String,
              let isActive = data["isActive"] as? Bool else { return nil }
        let template = RecurringExpenseTemplate(
            id: id, title: title, expectedAmount: amount, category: category, dueDay: dueDay,
            startMonthKey: startMonthKey, isActive: isActive, ownership: .shared
        )
        guard template.validationError == nil, template.title == RecurringExpenseInput.trimmedTitle(title) else { return nil }
        return template
    }

    /// 受け取った月ごとの状態の文書。文書の ID と templateID・monthKey が合わないもの・形が違うものは nil
    static func occurrence(documentID: String, data: [String: Any]) -> RecurringOccurrence? {
        guard data["schemaVersion"] as? Int == schemaVersion,
              let templateText = data["templateID"] as? String, let templateID = UUID(uuidString: templateText),
              let monthKey = data["monthKey"] as? String,
              let statusRaw = data["status"] as? String, let status = RecurringOccurrence.Status(rawValue: statusRaw),
              documentID == RecurringOccurrence.id(templateID: templateID, monthKey: monthKey) else { return nil }
        let rawExpenseID = data["expenseID"]
        let expenseID: UUID?
        if rawExpenseID == nil || rawExpenseID is NSNull {
            expenseID = nil
        } else if let text = rawExpenseID as? String, let id = UUID(uuidString: text) {
            expenseID = id
        } else {
            return nil
        }
        let occurrence = RecurringOccurrence(templateID: templateID, monthKey: monthKey, status: status, expenseID: expenseID)
        return occurrence.isValid ? occurrence : nil
    }
}

/// 共有の定期支出の保存先（Firestore）。オフラインのときは Firestore が端末にためて、つながったら送る
protocol SharedRecurringExpensesBackend: AnyObject {
    /// groups/{groupID}/recurringExpenses を見張る（わが家につき1つ）
    func listenTemplates(groupID: String, onChange: @escaping ([RecurringExpenseTemplate]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// groups/{groupID}/recurringExpenseOccurrences を見張る（わが家につき1つ）
    func listenOccurrences(groupID: String, onChange: @escaping ([RecurringOccurrence]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// 設定を作る（文書の ID は設定の UUID）
    func createTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    /// 設定を変える（編集・停止・再開。作成者・作成日時は変えない）
    func updateTemplate(groupID: String, id: UUID, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    /// 「今月は追加しない」の記録を作る
    func createSkippedOccurrence(groupID: String, occurrenceID: String, fields: [String: SharedItemValue], completion: @escaping (SharedItemsFailure?) -> Void)
    /// 「今月は追加しない」の記録を消す（未確認に戻す。追加済みは Rules が断る）
    func deleteSkippedOccurrence(groupID: String, occurrenceID: String, completion: @escaping (SharedItemsFailure?) -> Void)
    /// 共有の支出と「追加済み」の記録を、1回の書き込みで一緒に作る（片方だけにはならない）
    func createExpenseWithOccurrence(
        groupID: String,
        expenseID: UUID,
        expenseFields: [String: SharedItemValue],
        occurrenceID: String,
        occurrenceFields: [String: SharedItemValue],
        completion: @escaping (SharedItemsFailure?) -> Void
    )
}
