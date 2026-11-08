import Foundation

// 支出の商品明細（2026-11-08 Build 21）。docs/BUILD_21_RECEIPT_LINE_ITEM_HISTORY.md
//
// - レシートから支出を保存するとき、確認画面に残っている（利用者が確かめた）明細だけを保存する
// - 持つのは：明細ID・商品名・数量（任意）・単価（任意）・金額・表示順だけ
// - 持たないもの：レシートの写真・読み取った全文・読み取りの候補・信頼度・位置
// - 自分だけの支出の明細は端末（life-store.json）だけ。わが家で共有の支出の明細は
//   Firestore の groups/{groupID}/expenseLineItems/{expenseID}（わが家のメンバーだけ）
// - 商品名・金額はログに出さない

/// 支出の商品明細1件
struct ExpenseLineItem: Identifiable, Hashable, Codable {
    let id: UUID
    /// 商品名（1〜80文字。制御文字は空白にしてから前後の空白を除く）
    var name: String
    /// 数量（分からなければ nil。0 より大きく 10000 未満・小数3桁まで）
    var quantity: Decimal?
    /// 単価（分からなければ nil。0〜999,999,999 円）
    var unitPrice: Int?
    /// その商品の金額（0〜999,999,999 円）
    var amount: Int
    /// 表示順（0 から。保存するときに並び順のとおりに振り直す）
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, quantity: Decimal? = nil, unitPrice: Int? = nil, amount: Int, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, unitPrice, amount, sortOrder
    }

    /// 端末のファイルを読むとき：数量は文字（"1.5"）で保存する（小数の誤差を出さない）。
    /// 読めない値でもファイル全体を読めなくしない（その項目だけ「分からない」にする。形を確かめるのは LifeStore）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Int.self, forKey: .amount)
        sortOrder = (try? container.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        unitPrice = try? container.decodeIfPresent(Int.self, forKey: .unitPrice)
        if let text = try? container.decodeIfPresent(String.self, forKey: .quantity) {
            quantity = ExpenseLineItemRules.quantity(from: text)
        } else {
            quantity = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(quantity.map(ExpenseLineItemRules.text(for:)), forKey: .quantity)
        try container.encodeIfPresent(unitPrice, forKey: .unitPrice)
        try container.encode(amount, forKey: .amount)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    /// 数量・単価の補助の表示（「2点 × ¥250」「1.5点」「@¥98」）。どちらも無ければ nil
    var detailText: String? {
        switch (quantity, unitPrice) {
        case let (quantity?, unitPrice?): return "\(ExpenseLineItemRules.text(for: quantity))点 × \(LifeFormatters.yen(unitPrice))"
        case let (quantity?, nil): return "\(ExpenseLineItemRules.text(for: quantity))点"
        case let (nil, unitPrice?): return "@\(LifeFormatters.yen(unitPrice))"
        case (nil, nil): return nil
        }
    }

    /// VoiceOver 用（商品名・数量・単価・金額）
    var spokenLabel: String {
        var parts = ["商品名 \(name)"]
        if let quantity { parts.append("数量 \(ExpenseLineItemRules.text(for: quantity))") }
        if let unitPrice { parts.append("単価 \(LifeFormatters.yenSpoken(unitPrice))") }
        parts.append("金額 \(LifeFormatters.yenSpoken(amount))")
        return parts.joined(separator: "、")
    }
}

/// 保存できない理由（画面に日本語で出す）
enum ExpenseLineItemIssue: Equatable {
    case emptyName
    case nameTooLong
    case invalidQuantity
    case invalidUnitPrice
    case invalidAmount
    /// 51件目以降
    case tooMany

    var message: String {
        switch self {
        case .emptyName: return "商品名が空のため保存されません。商品名を入れるか、この明細を削除してください。"
        case .nameTooLong: return "商品名が\(ExpenseLineItemRules.maxNameLength)文字を超えているため保存されません。短くしてください。"
        case .invalidQuantity: return "数量が正しくないため保存されません（0より大きい数・小数は3桁まで。分からなければ空にしてください）。"
        case .invalidUnitPrice: return "単価が正しくないため保存されません（0〜999,999,999円の整数。分からなければ空にしてください）。"
        case .invalidAmount: return "金額が正しくないため保存されません（0〜999,999,999円の整数を入れてください）。"
        case .tooMany: return "商品明細は\(ExpenseLineItemRules.maxCount)件までのため、\(ExpenseLineItemRules.maxCount + 1)件目からは保存されません。"
        }
    }
}

/// 保存できない明細1件（何行目か・理由）
struct ExpenseLineItemProblem: Equatable, Identifiable {
    /// 確認画面の並びでの行（1から）
    let row: Int
    let issue: ExpenseLineItemIssue

    var id: Int { row }
    var message: String { "\(row)行目：\(issue.message)" }
}

/// 確認画面の明細を、保存する形にした結果
struct ExpenseLineItemPreparation: Equatable {
    /// 保存する明細（表示順を 0 から振り直したもの。最大50件）
    var items: [ExpenseLineItem]
    /// 保存されない明細と理由
    var problems: [ExpenseLineItemProblem]
}

/// 商品明細の保存・修正・削除がうまくいかなかった理由
enum ExpenseLineItemSaveError: Error, Equatable {
    /// 51件以上
    case tooMany
    /// 形が正しくない
    case invalid(ExpenseLineItemIssue)
    /// 支出が見つからない
    case expenseNotFound
    /// 明細が見つからない
    case lineItemNotFound
    /// 共有の支出を変えられない（わが家に参加していない など）
    case notEditable
    /// 端末に保存できなかった
    case storageFailed

    var message: String {
        switch self {
        case .tooMany: return ExpenseLineItemIssue.tooMany.message
        case .invalid(let issue): return issue.message
        case .expenseNotFound: return "支出が見つかりません。"
        case .lineItemNotFound: return "この商品明細が見つかりません。"
        case .notEditable: return "わが家に参加していないため、共有の支出の商品明細は変えられません。"
        case .storageFailed: return "この iPhone に保存できませんでした。元の内容のままです。"
        }
    }
}

/// 商品明細の決まり（Firestore の Security Rules と同じ上限）
enum ExpenseLineItemRules {
    /// 1支出あたりの最大の件数
    static let maxCount = 50
    /// 商品名の最大の文字数（Unicode の文字単位。ルールの正規表現と同じ数え方）
    static let maxNameLength = 80
    /// 金額・単価の上限
    static let maxAmount = 999_999_999
    /// 数量はこれより小さい（0 より大きく 10000 未満）
    static let quantityLimit: Decimal = 10_000
    /// 数量の小数の桁数（これより細かい数は四捨五入）
    static let quantityScale: Int16 = 3

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// 商品名を整える：制御文字（タブ・改行など）を空白にして、前後の空白を除く
    static func normalizedName(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            return (value < 0x20 || (0x7F...0x9F).contains(value)) ? " " : Character(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 商品名の形の確認（整えたあとの名前で）
    static func nameIssue(_ name: String) -> ExpenseLineItemIssue? {
        if name.isEmpty { return .emptyName }
        if name.unicodeScalars.count > maxNameLength { return .nameTooLong }
        return nil
    }

    /// 数量の文字（全角・「点」「個」も読む）を数にする。小数3桁に四捨五入。範囲外・読めなければ nil
    static func quantity(from text: String) -> Decimal? {
        let cleaned = ReceiptFieldExtractor.normalize(text)
            .replacingOccurrences(of: #"[点個コ\s]"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count <= 12,
              cleaned.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned, locale: posix) else { return nil }
        return normalizedQuantity(value)
    }

    /// 数量を小数3桁に四捨五入し、範囲（0 より大きく 10000 未満）を確かめる
    static func normalizedQuantity(_ value: Decimal) -> Decimal? {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, Int(quantityScale), .plain)
        guard rounded > 0, rounded < quantityLimit else { return nil }
        return rounded
    }

    /// 数量の保存・表示の文字（"2"・"1.5"。指数の形にしない）
    static func text(for quantity: Decimal) -> String {
        var text = NSDecimalNumber(decimal: quantity).description(withLocale: posix)
        // 小数の終わりの 0 と点を除く（"1.50" → "1.5"、"2.000" → "2"）
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// 単価・金額の文字（全角・カンマ・「円」「¥」も読む）を 0〜999,999,999 の整数にする。読めなければ nil
    static func yen(from text: String) -> Int? {
        let cleaned = ReceiptFieldExtractor.normalize(text)
            .replacingOccurrences(of: #"[¥円,\s]"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count <= 9, cleaned.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(cleaned), (0...maxAmount).contains(value) else { return nil }
        return value
    }

    /// 1件の形の確認（保存する形のまま）
    static func issue(of item: ExpenseLineItem) -> ExpenseLineItemIssue? {
        if let issue = nameIssue(item.name) { return issue }
        if let quantity = item.quantity, normalizedQuantity(quantity) != quantity { return .invalidQuantity }
        if let unitPrice = item.unitPrice, !(0...maxAmount).contains(unitPrice) { return .invalidUnitPrice }
        if !(0...maxAmount).contains(item.amount) { return .invalidAmount }
        return nil
    }

    /// 保存する前に、並び順のとおりに表示順を振り直し、すべての形を確かめる（ひとつでも違えば保存しない）
    static func normalized(_ items: [ExpenseLineItem]) -> Result<[ExpenseLineItem], ExpenseLineItemSaveError> {
        guard items.count <= maxCount else { return .failure(.tooMany) }
        var result: [ExpenseLineItem] = []
        var seen: Set<UUID> = []
        for (index, original) in items.enumerated() {
            var item = original
            item.name = normalizedName(item.name)
            if let issue = issue(of: item) { return .failure(.invalid(issue)) }
            // 同じ明細ID が2回あれば、2件目は新しい ID にする（重ならない）
            if seen.contains(item.id) {
                item = ExpenseLineItem(name: item.name, quantity: item.quantity, unitPrice: item.unitPrice, amount: item.amount)
            }
            seen.insert(item.id)
            item.sortOrder = index
            result.append(item)
        }
        return .success(result)
    }

    /// 確認画面（レシートから）の明細を、保存する形にする。正しくない明細・51件目以降は保存せず、理由を返す
    static func prepare(_ drafts: [ReceiptLineItem]) -> ExpenseLineItemPreparation {
        var items: [ExpenseLineItem] = []
        var problems: [ExpenseLineItemProblem] = []
        for (index, draft) in drafts.enumerated() {
            let row = index + 1
            let name = normalizedName(draft.name)
            if let issue = nameIssue(name) {
                problems.append(ExpenseLineItemProblem(row: row, issue: issue))
                continue
            }
            let quantityText = draft.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
            let quantity = quantityText.isEmpty ? nil : self.quantity(from: quantityText)
            if !quantityText.isEmpty, quantity == nil {
                problems.append(ExpenseLineItemProblem(row: row, issue: .invalidQuantity))
                continue
            }
            let unitText = draft.unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let unitPrice = unitText.isEmpty ? nil : yen(from: unitText)
            if !unitText.isEmpty, unitPrice == nil {
                problems.append(ExpenseLineItemProblem(row: row, issue: .invalidUnitPrice))
                continue
            }
            guard let amount = yen(from: draft.amountText) else {
                problems.append(ExpenseLineItemProblem(row: row, issue: .invalidAmount))
                continue
            }
            guard items.count < maxCount else {
                problems.append(ExpenseLineItemProblem(row: row, issue: .tooMany))
                continue
            }
            items.append(ExpenseLineItem(id: draft.id, name: name, quantity: quantity, unitPrice: unitPrice, amount: amount, sortOrder: items.count))
        }
        return ExpenseLineItemPreparation(items: items, problems: problems)
    }

    /// 詳細画面で1件を直した内容を、保存する形にする（正しくなければ理由）
    static func edited(_ original: ExpenseLineItem, name: String, quantityText: String, unitPriceText: String, amountText: String) -> Result<ExpenseLineItem, ExpenseLineItemSaveError> {
        let cleanName = normalizedName(name)
        if let issue = nameIssue(cleanName) { return .failure(.invalid(issue)) }
        let quantityValue = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = quantityValue.isEmpty ? nil : self.quantity(from: quantityValue)
        if !quantityValue.isEmpty, quantity == nil { return .failure(.invalid(.invalidQuantity)) }
        let unitValue = unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitPrice = unitValue.isEmpty ? nil : yen(from: unitValue)
        if !unitValue.isEmpty, unitPrice == nil { return .failure(.invalid(.invalidUnitPrice)) }
        guard let amount = yen(from: amountText) else { return .failure(.invalid(.invalidAmount)) }
        var item = original
        item.name = cleanName
        item.quantity = quantity
        item.unitPrice = unitPrice
        item.amount = amount
        return .success(item)
    }
}

extension ReceiptLineItemComparison {
    /// 保存した明細とレシートの合計（支出の金額）の比較（Build 21）
    static func compare(saved items: [ExpenseLineItem], receiptTotal: Int?) -> ReceiptLineItemComparison {
        guard !items.isEmpty else { return .noItems }
        guard let receiptTotal else { return .insufficient }
        let total = items.reduce(0) { $0 + $1.amount }
        return total == receiptTotal ? .matched(total: total) : .mismatched(itemsTotal: total, receiptTotal: receiptTotal)
    }
}

/// 端末のファイル（life-store.json）に保存する、自分だけの支出の商品明細（Build 21）。
/// 以前の保存データには無い。読めない記録・明細があっても飛ばすだけで、ファイル全体（ほかのデータ）は読めるようにする
struct ExpenseLineItemRecords: Codable, Equatable {
    struct Record: Codable, Equatable {
        var expenseID: UUID
        var items: [ExpenseLineItem]

        init(expenseID: UUID, items: [ExpenseLineItem]) {
            self.expenseID = expenseID
            self.items = items
        }

        private enum CodingKeys: String, CodingKey {
            case expenseID, items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            expenseID = try container.decode(UUID.self, forKey: .expenseID)
            var list = try container.nestedUnkeyedContainer(forKey: .items)
            var decoded: [ExpenseLineItem] = []
            while !list.isAtEnd {
                if (try? list.decodeNil()) == true { continue }
                if let item = try? list.decode(ExpenseLineItem.self) {
                    decoded.append(item)
                } else if (try? list.decode(SkippedValue.self)) == nil {
                    break
                }
            }
            items = decoded
        }
    }

    var records: [Record]

    init(records: [Record]) {
        self.records = records
    }

    init(from decoder: Decoder) throws {
        var decoded: [Record] = []
        if var list = try? decoder.unkeyedContainer() {
            while !list.isAtEnd {
                if (try? list.decodeNil()) == true { continue }
                if let record = try? list.decode(Record.self) {
                    decoded.append(record)
                } else if (try? list.decode(SkippedValue.self)) == nil {
                    break
                }
            }
        }
        records = decoded
    }

    func encode(to encoder: Encoder) throws {
        var list = encoder.unkeyedContainer()
        for record in records {
            try list.encode(record)
        }
    }

    /// 読めない値を読み飛ばすための入れ物（何でも受け取って捨てる）
    private struct SkippedValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
