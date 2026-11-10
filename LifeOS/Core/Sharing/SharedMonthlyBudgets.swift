import Foundation

// わが家の共有予算（2026-11-10 Build 24）。docs/BUILD_24_MONTHLY_BUDGET_AND_CATEGORY_SUMMARY.md
//
// - 保存先は Firestore の groups/{groupID}/monthlyBudgets/{YYYY-MM}（月ごとに文書1つ。文書の ID は月のキー）
// - 送るのは：schemaVersion・monthKey・totalAmount・categoryAmounts・updatedBy（本人の UID）・updatedAt（サーバーの時刻）だけ
//   （createdAt は持たない。月の予算は「今の値」だけを使い、作った日時を画面でも集計でも使わないため）
// - 送らないもの：自分だけの予算・支出の金額や名前・検索語・見た履歴・レシートの写真・読み取った全文・メールアドレス・端末の情報
// - わが家のメンバーだけが読み書きできる（Security Rules）。オーナーもパートナーも変えられる。変えた人の UID は画面・ログに出さない
// - 予算の変更の通知は作らない（Functions の通知は items だけ）
// - 金額・予算はログに出さない

/// groups/{groupID}/monthlyBudgets/{YYYY-MM} に書く内容・読む内容
enum SharedMonthlyBudgetPayload {
    /// 保存の形の版
    static let schemaVersion = 1
    /// 文書の項目（Security Rules の hasOnly と同じ）
    static let fieldNames: [String] = ["schemaVersion", "monthKey", "totalAmount", "categoryAmounts", "updatedBy", "updatedAt"]

    /// 送る項目（updatedBy・updatedAt は Firestore の窓口が入れる：本人の UID・サーバーの時刻）。正しくなければ nil（送らない）
    static func fields(for plan: MonthlyBudgetPlan, month: BudgetMonth) -> [String: Any]? {
        guard month.isStorable, plan.validationError == nil else { return nil }
        return [
            "schemaVersion": schemaVersion,
            "monthKey": month.key,
            "totalAmount": plan.totalAmount,
            "categoryAmounts": plan.categoryAmounts,
        ]
    }

    /// 受け取った文書を予算にする。形が違うもの・正しくない金額は nil（表示しない）
    static func snapshot(documentID: String, data: [String: Any]) -> SharedMonthlyBudgetSnapshot? {
        guard let month = BudgetMonth(key: documentID), month.isStorable,
              data["schemaVersion"] as? Int == schemaVersion,
              data["monthKey"] as? String == documentID,
              let total = data["totalAmount"] as? Int,
              let raw = data["categoryAmounts"] as? [String: Any] else { return nil }
        var amounts: [String: Int] = [:]
        for (key, value) in raw {
            guard ExpenseCategory(rawValue: key) != nil, let amount = value as? Int else { return nil }
            amounts[key] = amount
        }
        let plan = MonthlyBudgetPlan(totalAmount: total, rawCategoryAmounts: amounts)
        guard plan.validationError == nil else { return nil }
        return SharedMonthlyBudgetSnapshot(month: month, plan: plan)
    }
}

/// 受け取ったわが家の予算（1か月分）
struct SharedMonthlyBudgetSnapshot: Equatable {
    let month: BudgetMonth
    let plan: MonthlyBudgetPlan
}

/// わが家の予算の保存先（Firestore）。オフラインのときは Firestore が端末にためて、つながったら送る
protocol SharedMonthlyBudgetsBackend: AnyObject {
    /// groups/{groupID}/monthlyBudgets を見張る。変わるたびに一覧で呼ぶ（自分の送信待ちの変更も含む）
    func listen(groupID: String, onChange: @escaping ([SharedMonthlyBudgetSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// 1か月分の予算を置く（作る・置き換える。文書の ID は月のキー）。fields は SharedMonthlyBudgetPayload が作る
    func set(groupID: String, month: BudgetMonth, fields: [String: Any], completion: @escaping (SharedItemsFailure?) -> Void)
    /// 1か月分の予算を消す（予算の解除。無くても成功）
    func delete(groupID: String, month: BudgetMonth, completion: @escaping (SharedItemsFailure?) -> Void)
}
