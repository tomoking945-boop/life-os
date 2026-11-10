import Foundation

// 家計簿の検索・商品の購入履歴・過去の参考価格（2026-11-10 Build 23）。docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md
//
// - すでに端末に読み込んである支出と商品明細だけを、その場で調べる（新しい保存先・データの形は作らない）
// - 検索語・絞り込み・見た商品・比べた結果は保存しない・送らない・ログに出さない
// - 商品のまとめ方は「整えた商品名が同じ」ものだけ（あいまいな一致・推測で別の商品をまとめない）
// - 価格は「過去の購入記録」「参考価格」として見せるだけ。どちらがお得かは決めない（内容量・単位を記録していないため）

/// 検索の文字の整え方（検索語・店名・商品名の両方に使う）
enum ExpenseSearchText {
    /// 前後の空白を除き、全角・半角をそろえ（Unicode の互換の正規化 NFKC）、英字を小文字にし、続く空白を1つにする。
    /// ひらがな・カタカナ・漢字はそのまま（半角カタカナは全角にそろう）
    static func normalized(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isWhitespace || character.unicodeScalars.allSatisfy({ $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }) {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.append(character)
            }
        }
        return result
    }
}

/// 検索の絞り込み（すべて／自分／共有・月・カテゴリー）。画面のあいだだけ持つ。保存・送信しない
struct ExpenseSearchFilter: Equatable {
    var scope: ScopeFilter = .all
    /// 月の初日（nil はすべての月）
    var month: Date?
    /// nil はすべてのカテゴリー
    var category: ExpenseCategory?

    func includes(_ expense: Expense) -> Bool {
        guard scope.includes(expense.ownership) else { return false }
        if let category, expense.category != category { return false }
        if let month, LifeCalendar.startOfMonth(expense.date) != month { return false }
        return true
    }
}

/// 検索結果の支出1件（同じ支出は1件だけ。商品名で一致したときは、その明細も持つ）
struct ExpenseSearchResult: Identifiable, Equatable {
    let expense: Expense
    /// 店名・支出のタイトルで一致した
    let matchesTitle: Bool
    /// 商品名で一致した明細（表示順）
    let matchedItems: [ExpenseLineItem]

    var id: Expense.ID { expense.id }
}

/// 検索の結果と、調べた数（性能の確認用。同じ支出・明細を2回調べていないか）
struct ExpenseSearchOutcome: Equatable {
    let results: [ExpenseSearchResult]
    /// 絞り込みのあとに調べた支出の数
    let checkedExpenses: Int
    /// 調べた明細の数
    let checkedItems: Int

    static let empty = ExpenseSearchOutcome(results: [], checkedExpenses: 0, checkedItems: 0)
}

enum ExpenseSearch {
    /// 検索結果の1行に出す、一致した商品の数
    static let maxMatchedItemsShown = 3

    /// 店名・支出のタイトルと、商品明細の商品名から、部分一致で探す。検索語が空なら結果も空（通常の一覧へ戻る）。
    /// 新しい日付の順（同じ日は ID の順）。同じ支出は1回だけ
    static func search(
        _ query: String,
        expenses: [Expense],
        lineItems: [Expense.ID: [ExpenseLineItem]],
        filter: ExpenseSearchFilter = ExpenseSearchFilter()
    ) -> ExpenseSearchOutcome {
        let needle = ExpenseSearchText.normalized(query)
        guard !needle.isEmpty else { return .empty }
        var seen: Set<Expense.ID> = []
        var results: [ExpenseSearchResult] = []
        var checkedExpenses = 0
        var checkedItems = 0
        for expense in expenses where filter.includes(expense) && seen.insert(expense.id).inserted {
            checkedExpenses += 1
            let items = lineItems[expense.id] ?? []
            checkedItems += items.count
            let matchesTitle = ExpenseSearchText.normalized(expense.title).contains(needle)
            let matched = items.filter { ExpenseSearchText.normalized($0.name).contains(needle) }
            if matchesTitle || !matched.isEmpty {
                results.append(ExpenseSearchResult(expense: expense, matchesTitle: matchesTitle, matchedItems: matched))
            }
        }
        results.sort { lhs, rhs in
            lhs.expense.date == rhs.expense.date
                ? lhs.expense.id.uuidString < rhs.expense.id.uuidString
                : lhs.expense.date > rhs.expense.date
        }
        return ExpenseSearchOutcome(results: results, checkedExpenses: checkedExpenses, checkedItems: checkedItems)
    }

    /// 絞り込みに出す月（支出のある月だけ。新しい順）
    static func months(in expenses: [Expense]) -> [Date] {
        Array(Set(expenses.map { LifeCalendar.startOfMonth($0.date) })).sorted(by: >)
    }
}

// MARK: - 商品の購入履歴・過去の参考価格

/// 比べるための価格（1つの購入記録の単価）
struct PurchasePrice: Equatable {
    enum Basis: Equatable {
        /// 保存されている単価
        case unitPrice
        /// 商品の金額 ÷ 数量 で計算した参考単価（1円未満は四捨五入）
        case referenceUnitPrice
    }

    let yen: Int
    let basis: Basis
}

/// 購入記録1件（支出の商品明細1件から作る。その場だけ。保存しない）
struct PurchaseRecord: Identifiable, Equatable {
    let expenseID: Expense.ID
    let itemID: ExpenseLineItem.ID
    let date: Date
    /// 店名（支出のタイトル）
    let storeName: String
    /// 商品名（保存されている名前のまま）
    let itemName: String
    let amount: Int
    let quantity: Decimal?
    let unitPrice: Int?
    let ownership: Ownership
    let sortOrder: Int
    /// 比べられる単価（比べられなければ nil：数量が分からない・金額が正しくないなど）
    let price: PurchasePrice?

    var id: String { "\(expenseID.uuidString)-\(itemID.uuidString)" }
}

/// 過去の参考価格の要約（比べられる購入記録だけで作る）
struct PurchasePriceSummary: Equatable {
    /// いちばん新しい、比べられる購入記録
    let latest: PurchaseRecord
    /// これまでの最安・最高（比べられる記録が2件以上のときだけ。同じ価格なら新しい方）
    let lowest: PurchaseRecord?
    let highest: PurchaseRecord?
    /// 前回（latest のひとつ前の、比べられる購入記録）
    let previous: PurchaseRecord?
    /// 比べた購入記録の数
    let comparedCount: Int
    /// 単価が分からないため比べなかった購入記録の数
    let excludedCount: Int

    /// 前回との差（円。正なら前回より高い・負なら安い）
    var differenceFromPrevious: Int? {
        guard let latestYen = latest.price?.yen, let previousYen = previous?.price?.yen else { return nil }
        return latestYen - previousYen
    }

    /// 計算した参考単価をひとつでも使っているか
    var usesReferencePrice: Bool {
        [latest, lowest, highest, previous].compactMap { $0?.price?.basis }.contains(.referenceUnitPrice)
    }
}

/// 同じ商品（整えた商品名が同じ）の購入履歴
struct ProductPurchaseHistory: Equatable {
    /// まとめるための整えた商品名
    let key: String
    /// 表示する商品名（いちばん新しい購入記録の名前）
    let name: String
    /// 新しい順
    let records: [PurchaseRecord]
    /// 比べられる記録があれば要約（無ければ nil：「単価は比較できません」）
    let summary: PurchasePriceSummary?

    var purchaseCount: Int { records.count }
    var latestDate: Date? { records.first?.date }
}

enum PurchaseHistory {
    /// 単価を比べられないときの一言
    static let unitPriceUnavailableMessage = "単価は比較できません（数量・単価が分からない購入記録です）"
    /// 要約に添える一言（購入をすすめない・お得かどうかを決めない）
    static let referenceNote = "過去の購入記録から出した参考価格です。内容量や単位は記録していないため、どちらがお得かは判断できません。"

    /// 同じ商品としてまとめるための名前（前後の空白・全角半角・英字の大小・続く空白だけを整える）
    static func key(for name: String) -> String {
        ExpenseSearchText.normalized(name)
    }

    /// 明細1件の比べられる単価。保存された単価を優先し、無ければ（数量が正しいときだけ）金額 ÷ 数量。
    /// 0円・上限を超える金額・正しくない数量は比べない（0 で割らない）
    static func price(for item: ExpenseLineItem) -> PurchasePrice? {
        let range = 1...ExpenseLineItemRules.maxAmount
        if let unitPrice = item.unitPrice, range.contains(unitPrice) {
            return PurchasePrice(yen: unitPrice, basis: .unitPrice)
        }
        guard let quantity = item.quantity,
              quantity > 0,
              ExpenseLineItemRules.normalizedQuantity(quantity) == quantity,
              range.contains(item.amount) else { return nil }
        var value = Decimal(item.amount) / quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let yen = NSDecimalNumber(decimal: rounded).intValue
        guard range.contains(yen) else { return nil }
        return PurchasePrice(yen: yen, basis: .referenceUnitPrice)
    }

    /// 同じ商品の購入履歴（表示している範囲の支出だけ。新しい順）
    static func history(
        forKey key: String,
        expenses: [Expense],
        lineItems: [Expense.ID: [ExpenseLineItem]],
        scope: ScopeFilter = .all
    ) -> ProductPurchaseHistory {
        var seen: Set<Expense.ID> = []
        var records: [PurchaseRecord] = []
        if !key.isEmpty {
            for expense in expenses where scope.includes(expense.ownership) && seen.insert(expense.id).inserted {
                for item in lineItems[expense.id] ?? [] where Self.key(for: item.name) == key {
                    records.append(PurchaseRecord(
                        expenseID: expense.id, itemID: item.id, date: expense.date, storeName: expense.title,
                        itemName: item.name, amount: item.amount, quantity: item.quantity, unitPrice: item.unitPrice,
                        ownership: expense.ownership, sortOrder: item.sortOrder, price: price(for: item)
                    ))
                }
            }
        }
        records.sort(by: isNewer)
        return ProductPurchaseHistory(key: key, name: records.first?.itemName ?? key, records: records, summary: summary(of: records))
    }

    /// 比べられる購入記録だけで作る要約（新しい順の記録を受け取る）
    static func summary(of records: [PurchaseRecord]) -> PurchasePriceSummary? {
        let priced = records.filter { $0.price != nil }
        guard let latest = priced.first else { return nil }
        let canCompare = priced.count >= 2
        // 同じ価格なら新しい方（priced は新しい順なので、最初に見つかったもの）
        var lowest = latest
        var highest = latest
        for record in priced {
            guard let yen = record.price?.yen else { continue }
            if yen < (lowest.price?.yen ?? yen) { lowest = record }
            if yen > (highest.price?.yen ?? yen) { highest = record }
        }
        return PurchasePriceSummary(
            latest: latest,
            lowest: canCompare ? lowest : nil,
            highest: canCompare ? highest : nil,
            previous: canCompare ? priced[1] : nil,
            comparedCount: priced.count,
            excludedCount: records.count - priced.count
        )
    }

    /// 新しい順（同じ日なら支出の ID の順、同じ支出なら明細の表示順）
    private static func isNewer(_ lhs: PurchaseRecord, _ rhs: PurchaseRecord) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.expenseID != rhs.expenseID { return lhs.expenseID.uuidString < rhs.expenseID.uuidString }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.itemID.uuidString < rhs.itemID.uuidString
    }
}
