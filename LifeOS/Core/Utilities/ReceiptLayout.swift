import Foundation

/// レシートの1行（Build 20）。同じ高さにある文字のまとまりを左から右へつないだもの。
/// 読み取りの間だけメモリに持つ一時的な値。保存・送信・ログ出力しない
struct ReceiptRow: Hashable {
    /// 行の文字（全角の英数字は半角にそろえたもの。左から右へ空白でつなぐ）
    var text: String
    /// 行の中でいちばん低い信頼度（0〜1）
    var confidence: Float
    /// 行の範囲（位置が分からなければ nil）
    var box: RecognizedTextBox?
}

/// 読み取った文字を、レシートの行にまとめる（Build 20）
enum ReceiptLayout {
    /// 同じ行とみなす高さのずれ（文字の高さに対する割合）
    static let sameRowTolerance = 0.5

    /// 行にまとめる。すべての文字の位置が分かるときは、上から下へ並べ、同じ高さの文字を1行にする。
    /// 位置が分からないときは、読み取った順のまま1つずつを1行にする。空の行は除く
    static func rows(from lines: [ReceiptRecognizedLine]) -> [ReceiptRow] {
        let usable = lines
            .map { ReceiptRecognizedLine(text: ReceiptFieldExtractor.normalize($0.text).trimmingCharacters(in: .whitespacesAndNewlines), confidence: $0.confidence, box: $0.box) }
            .filter { !$0.text.isEmpty }
        let boxes = usable.compactMap(\.box)
        guard !usable.isEmpty, boxes.count == usable.count else {
            return usable.map { ReceiptRow(text: $0.text, confidence: $0.confidence, box: $0.box) }
        }
        // 上から下へ（同じ高さなら左から右へ）
        let sorted = usable.enumerated().sorted { lhs, rhs in
            let a = lhs.element.box!, b = rhs.element.box!
            if a.midY != b.midY { return a.midY < b.midY }
            if a.x != b.x { return a.x < b.x }
            return lhs.offset < rhs.offset
        }.map(\.element)
        var groups: [[ReceiptRecognizedLine]] = []
        for line in sorted {
            let box = line.box!
            if let last = groups.last, let reference = last.first?.box,
               abs(box.midY - reference.midY) <= sameRowTolerance * min(box.height, reference.height) {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let ordered = group.sorted { $0.box!.x < $1.box!.x }
            let minX = ordered.map { $0.box!.x }.min() ?? 0
            let minY = ordered.map { $0.box!.y }.min() ?? 0
            let maxX = ordered.map { $0.box!.maxX }.max() ?? 0
            let maxY = ordered.map { $0.box!.maxY }.max() ?? 0
            return ReceiptRow(
                text: ordered.map(\.text).joined(separator: " "),
                confidence: ordered.map(\.confidence).min() ?? 1,
                box: RecognizedTextBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
    }
}

/// 合計金額の候補（Build 20）。確認画面で選ぶための一時的な候補。保存・送信しない
struct ReceiptAmountCandidate: Identifiable, Hashable {
    enum Kind: Int, Comparable {
        /// 小計（参考。自動では選ばない）
        case subtotal = 0
        /// 合計・お会計・TOTAL
        case total = 1
        /// 総合計・お支払額・ご請求額・GRAND TOTAL など
        case strongTotal = 2

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        /// 順位付けの重み（見出しの強さがいちばん大きい）
        var weight: Double {
            switch self {
            case .strongTotal: return 100
            case .total: return 50
            case .subtotal: return 0
            }
        }
    }

    let amount: Int
    /// 見出し（「合計」「お支払額」「小計」など）
    let label: String
    let kind: Kind
    /// 順位の点数（大きいほど上）
    let score: Double

    var id: String { "\(amount)-\(label)" }

    /// 合計として選んでよい候補か（小計は「選択非推奨」）
    var isRecommended: Bool { kind != .subtotal }

    /// 「¥3,520（合計）」「¥3,200（小計・選択非推奨）」
    var displayText: String {
        isRecommended ? "\(LifeFormatters.yen(amount))（\(label)）" : "\(LifeFormatters.yen(amount))（\(label)・選択非推奨）"
    }

    /// VoiceOver 用
    var spokenLabel: String {
        isRecommended ? "\(label) \(LifeFormatters.yenSpoken(amount))" : "\(label) \(LifeFormatters.yenSpoken(amount))、合計としての選択は非推奨"
    }
}

/// 商品明細の1行（Build 20。確認用）。商品名・数量・単価・金額。読めなかった項目は空（推測で作らない）。
/// 確認画面のメモリの中だけで使い、保存・共有・送信・ログ出力しない
struct ReceiptLineItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// 数量（読めなければ空）
    var quantityText: String
    /// 単価（読めなければ空）
    var unitPriceText: String
    /// その商品の金額（読めなければ空）
    var amountText: String

    init(id: UUID = UUID(), name: String, quantity: Int? = nil, unitPrice: Int? = nil, amount: Int? = nil) {
        self.id = id
        self.name = name
        self.quantityText = quantity.map(String.init) ?? ""
        self.unitPriceText = unitPrice.map(String.init) ?? ""
        self.amountText = amount.map(String.init) ?? ""
    }

    var quantity: Int? { Self.number(from: quantityText, max: 9_999) }
    var unitPrice: Int? { Self.number(from: unitPriceText, max: SharedExpensePayload.maxAmount) }
    var amount: Int? { Self.number(from: amountText, max: SharedExpensePayload.maxAmount) }

    /// 一覧に出す1行（「ティッシュ　2点 × ¥250　¥500」）。読めた項目だけ
    var displayText: String {
        var parts = [name.isEmpty ? "（商品名なし）" : name]
        switch (quantity, unitPrice) {
        case let (quantity?, unitPrice?): parts.append("\(quantity)点 × \(LifeFormatters.yen(unitPrice))")
        case let (quantity?, nil): parts.append("\(quantity)点")
        case let (nil, unitPrice?): parts.append("@\(LifeFormatters.yen(unitPrice))")
        case (nil, nil): break
        }
        parts.append(amount.map(LifeFormatters.yen) ?? "金額なし")
        return parts.joined(separator: "　")
    }

    /// VoiceOver 用（商品名・数量・単価・金額）
    var spokenLabel: String {
        var parts = ["商品名 \(name.isEmpty ? "なし" : name)"]
        if let quantity { parts.append("数量 \(quantity)") }
        if let unitPrice { parts.append("単価 \(LifeFormatters.yenSpoken(unitPrice))") }
        parts.append(amount.map { "金額 \(LifeFormatters.yenSpoken($0))" } ?? "金額 読み取れず")
        return parts.joined(separator: "、")
    }

    /// 全角・カンマ・「円」「¥」「点」「個」を許して整数にする（範囲外・読めなければ nil）
    static func number(from text: String, max: Int) -> Int? {
        let cleaned = ReceiptFieldExtractor.normalize(text)
            .replacingOccurrences(of: #"[¥円,点個\s]"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count <= 9, cleaned.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(cleaned), (1...max).contains(value) else { return nil }
        return value
    }
}

/// 商品明細の合計とレシートの合計の比べ方（Build 20）。一致しなくても支出は保存できる
enum ReceiptLineItemComparison: Equatable {
    /// 明細の合計とレシートの合計が同じ
    case matched(total: Int)
    /// 違う（値引き・税・読み取り違いなど）
    case mismatched(itemsTotal: Int, receiptTotal: Int)
    /// 金額の無い明細がある・合計金額が空のため比べられない
    case insufficient
    /// 明細が無い
    case noItems

    static let matchedMessage = "商品明細の合計と一致しています"
    static let mismatchedMessage = "値引き・税・読み取り違いなどにより、商品明細の合計とレシート合計が一致しません"
    static let insufficientMessage = "比較不能：金額が分からない明細があるか、合計金額が空のため、比べられません"
    static let noItemsMessage = "商品明細を読み取れませんでした"

    static func compare(items: [ReceiptLineItem], receiptTotal: Int?) -> ReceiptLineItemComparison {
        guard !items.isEmpty else { return .noItems }
        let amounts = items.compactMap(\.amount)
        guard amounts.count == items.count, let receiptTotal else { return .insufficient }
        let total = amounts.reduce(0, +)
        return total == receiptTotal ? .matched(total: total) : .mismatched(itemsTotal: total, receiptTotal: receiptTotal)
    }

    var message: String {
        switch self {
        case .matched: return Self.matchedMessage
        case .mismatched: return Self.mismatchedMessage
        case .insufficient: return Self.insufficientMessage
        case .noItems: return Self.noItemsMessage
        }
    }

    var isMismatch: Bool {
        if case .mismatched = self { return true }
        return false
    }
}
