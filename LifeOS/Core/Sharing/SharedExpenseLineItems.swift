import Foundation

// わが家で共有する支出の商品明細（2026-11-08 Build 21）。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md
//
// - 保存先は Firestore の groups/{groupID}/expenseLineItems/{expenseID}（支出1件に文書1つ。文書の ID は支出の UUID）
// - 送るのは schemaVersion と rows だけ。rows の1件は「明細ID・商品名・数量・単価・金額」をタブでつないだ文字列
//   （Security Rules が1件ずつの形を正規表現で確かめられるようにするため）。並び順が表示順
// - 送らないもの：レシートの写真・読み取った全文・読み取りの候補・信頼度・位置・メールアドレス・通知トークン・端末の情報・UID
// - 共有の支出を消すときは、明細を先に消してから支出を消す（ルールが、明細が残っている支出の削除を断る）
// - 商品名・金額・UID はログに出さない

/// groups/{groupID}/expenseLineItems/{expenseID} に書く内容・読む内容
enum SharedExpenseLineItemsPayload {
    /// 保存の形の版
    static let schemaVersion = 1
    /// 1件の中の区切り（タブ。商品名からは制御文字を除いているので、区切りと混ざらない）
    static let separator = "\t"

    /// 1件を1行の文字にする（明細ID・商品名・数量・単価・金額）
    static func row(_ item: ExpenseLineItem) -> String {
        [
            item.id.uuidString,
            ExpenseLineItemRules.normalizedName(item.name),
            item.quantity.map(ExpenseLineItemRules.text(for:)) ?? "",
            item.unitPrice.map(String.init) ?? "",
            String(item.amount),
        ].joined(separator: separator)
    }

    /// 送る行（並び順のとおり）。明細が無い・正しくなければ nil（送らない。明細の文書は消す）
    static func rows(for items: [ExpenseLineItem]) -> [String]? {
        guard !items.isEmpty, case .success(let normalized) = ExpenseLineItemRules.normalized(items) else { return nil }
        return normalized.map(row)
    }

    /// 受け取った行を明細にする。形の違う行は表示しない（ほかの行は表示する）
    static func items(from rows: [String]) -> [ExpenseLineItem] {
        var result: [ExpenseLineItem] = []
        for row in rows.prefix(ExpenseLineItemRules.maxCount) {
            let parts = row.components(separatedBy: separator)
            guard parts.count == 5, let id = UUID(uuidString: parts[0]),
                  !result.contains(where: { $0.id == id }) else { continue }
            let name = ExpenseLineItemRules.normalizedName(parts[1])
            guard ExpenseLineItemRules.nameIssue(name) == nil, let amount = ExpenseLineItemRules.yen(from: parts[4]) else { continue }
            let quantity = parts[2].isEmpty ? nil : ExpenseLineItemRules.quantity(from: parts[2])
            if !parts[2].isEmpty, quantity == nil { continue }
            let unitPrice = parts[3].isEmpty ? nil : ExpenseLineItemRules.yen(from: parts[3])
            if !parts[3].isEmpty, unitPrice == nil { continue }
            result.append(ExpenseLineItem(id: id, name: name, quantity: quantity, unitPrice: unitPrice, amount: amount, sortOrder: result.count))
        }
        return result
    }

    /// 受け取った文書を明細にする（形が違えば nil）
    static func items(documentID: String, data: [String: Any]) -> SharedExpenseLineItemsSnapshot? {
        guard let expenseID = UUID(uuidString: documentID),
              data["schemaVersion"] as? Int == schemaVersion,
              let rows = data["rows"] as? [String] else { return nil }
        return SharedExpenseLineItemsSnapshot(expenseID: expenseID, items: items(from: rows))
    }
}

/// 受け取った共有の支出の商品明細（支出1件分）
struct SharedExpenseLineItemsSnapshot: Equatable {
    let expenseID: UUID
    let items: [ExpenseLineItem]
}

/// 共有の支出の商品明細の保存先（Firestore）。オフラインのときは Firestore が端末にためて、つながったら送る
protocol SharedExpenseLineItemsBackend: AnyObject {
    /// groups/{groupID}/expenseLineItems を見張る。変わるたびに一覧で呼ぶ（自分の送信待ちの変更も含む）
    func listen(groupID: String, onChange: @escaping ([SharedExpenseLineItemsSnapshot]) -> Void, onError: @escaping (SharedItemsFailure) -> Void) -> RepositoryObservation
    /// 支出1件分の明細を置く（作る・置き換える。文書の ID は支出の UUID）。completion はサーバーが受け付けた・断ったとき
    func set(groupID: String, expenseID: UUID, rows: [String], completion: @escaping (SharedItemsFailure?) -> Void)
    /// 支出1件分の明細を消す（無くても成功）
    func delete(groupID: String, expenseID: UUID, completion: @escaping (SharedItemsFailure?) -> Void)
}
