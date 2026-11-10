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
    /// ほかの読み方の行（Build 22。Vision の2番目・3番目の候補で1か所ずつ置き換えたもの。最大3つ。数字の確かめだけに使う）
    var alternatives: [String] = []
}

/// 読み取った文字を、レシートの行にまとめる（Build 20）
enum ReceiptLayout {
    /// 同じ行とみなす高さのずれ（文字の高さに対する割合）
    static let sameRowTolerance = 0.5

    /// 1行あたりの、ほかの読み方の行の最大の数（Build 22。計算の量を増やしすぎない）
    static let maxAlternativeRows = 3

    /// 行にまとめる。すべての文字の位置が分かるときは、上から下へ並べ、同じ高さの文字を1行にする。
    /// 位置が分からないときは、読み取った順のまま1つずつを1行にする。空の行は除く。
    /// Build 22：全角を半角にしたあと、金額の場所の数字の読み違い（「1O0」「¥S00」など）を直す（ReceiptNumberText）
    static func rows(from lines: [ReceiptRecognizedLine]) -> [ReceiptRow] {
        let usable = lines
            .map { line in
                ReceiptRecognizedLine(
                    text: cleaned(line.text),
                    confidence: line.confidence,
                    box: line.box,
                    alternatives: Array(line.alternatives.map(cleaned).filter { !$0.isEmpty }.prefix(maxAlternativeRows))
                )
            }
            .filter { !$0.text.isEmpty }
        let boxes = usable.compactMap(\.box)
        guard !usable.isEmpty, boxes.count == usable.count else {
            return usable.map { line in
                ReceiptRow(text: line.text, confidence: line.confidence, box: line.box, alternatives: line.alternatives.filter { $0 != line.text })
            }
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
            // ほかの読み方の行：1つのまとまりだけを、その2番目・3番目の候補に置き換える（最大3つ）
            var alternatives: [String] = []
            for (index, segment) in ordered.enumerated() {
                for alternative in segment.alternatives where alternative != segment.text {
                    var texts = ordered.map(\.text)
                    texts[index] = alternative
                    let joined = texts.joined(separator: " ")
                    if alternatives.count < maxAlternativeRows, !alternatives.contains(joined) {
                        alternatives.append(joined)
                    }
                }
            }
            return ReceiptRow(
                text: ordered.map(\.text).joined(separator: " "),
                confidence: ordered.map(\.confidence).min() ?? 1,
                box: RecognizedTextBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                alternatives: alternatives
            )
        }
    }

    /// 全角を半角にし、前後の空白を除き、金額の場所の数字の読み違いを直す
    static func cleaned(_ text: String) -> String {
        ReceiptNumberText.repaired(ReceiptFieldExtractor.normalize(text).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// 合計金額の候補（Build 20）。確認画面で選ぶための一時的な候補。保存・送信しない
struct ReceiptAmountCandidate: Identifiable, Hashable {
    enum Kind: Int, Comparable {
        /// 小計・税・お預り・お釣りなどから計算した金額（Build 22。参考。自動では選ばない）
        case calculated = -1
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
            case .calculated: return -10
            }
        }
    }

    let amount: Int
    /// 見出し（「合計」「お支払額」「小計」など）
    let label: String
    let kind: Kind
    /// 順位の点数（大きいほど上）
    let score: Double
    /// 小計・税・お預り・お釣り・商品明細の合計から計算した金額と合うか（Build 22）
    var isConsistent = false

    var id: String { "\(amount)-\(label)" }

    /// 合計として選んでよい候補か（小計・計算は「選択非推奨」「確認してください」）
    var isRecommended: Bool { kind == .total || kind == .strongTotal }

    /// 「¥3,520（合計）」「¥3,200（小計・選択非推奨）」「¥3,520（計算・確認してください）」
    var displayText: String {
        switch kind {
        case .total, .strongTotal: return "\(LifeFormatters.yen(amount))（\(label)）"
        case .subtotal: return "\(LifeFormatters.yen(amount))（\(label)・選択非推奨）"
        case .calculated: return "\(LifeFormatters.yen(amount))（小計・税などから計算・確認してください）"
        }
    }

    /// VoiceOver 用
    var spokenLabel: String {
        switch kind {
        case .total, .strongTotal: return "\(label) \(LifeFormatters.yenSpoken(amount))"
        case .subtotal: return "\(label) \(LifeFormatters.yenSpoken(amount))、合計としての選択は非推奨"
        case .calculated: return "小計や税などから計算した金額 \(LifeFormatters.yenSpoken(amount))、レシートで確かめてください"
        }
    }
}

/// 合計金額の決め方の結果（Build 22）。一時的な値。保存・送信しない
struct ReceiptAmountAnalysis: Equatable {
    /// 候補（順位の高い順）
    var candidates: [ReceiptAmountCandidate]
    /// 自動で金額欄に入れる金額（決められなければ nil）
    var amount: Int?
    /// 決められなかった理由
    var issue: ReceiptAmountIssue?
    /// 入れたが確かめてほしいこと
    var warning: String?
}

/// 合計金額を確かめるための、レシートの中のほかの金額（Build 22）。一時的な値。保存・送信しない
struct ReceiptTotalsEvidence: Equatable {
    /// 小計
    var subtotal: Int?
    /// 外税・消費税の合計（8%・10% の複数の税率の行を足す。内税は足さない）
    var outerTax = 0
    /// 値引き・割引・クーポンの合計（正の数）
    var discount = 0
    /// お預り
    var deposit: Int?
    /// お釣り（0円も含む）
    var change: Int?
    /// ポイントで払った金額
    var pointsUsed = 0
    /// 商品明細の金額の合計（すべての明細に金額があるときだけ）
    var itemsTotal: Int?

    /// 小計から計算した合計（小計＋外税、小計＋外税－値引き。値引きが小計に含まれている形と、含まれていない形の両方）
    var subtotalValues: [Int] {
        guard let subtotal else { return [] }
        return Self.unique([subtotal + outerTax, subtotal + outerTax - discount])
    }

    /// お預り－お釣り（ポイントで払った分を足した形も）
    var paymentValues: [Int] {
        guard let deposit, let change, deposit >= change else { return [] }
        return Self.unique([deposit - change, deposit - change + pointsUsed])
    }

    /// 商品明細の合計から計算した合計（税・値引きを足し引きした形も）
    var itemValues: [Int] {
        guard let itemsTotal else { return [] }
        return Self.unique([itemsTotal, itemsTotal + outerTax, itemsTotal - discount, itemsTotal + outerTax - discount])
    }

    /// 強い手掛かり（小計・お預り－お釣り）から計算した合計
    var strongValues: [Int] { Self.unique(subtotalValues + paymentValues) }

    /// どれかの計算と合うか
    func supports(_ value: Int) -> Bool {
        subtotalValues.contains(value) || paymentValues.contains(value) || itemValues.contains(value)
    }

    /// 2つ以上の別々の計算（小計・お預り－お釣り・商品明細）がそろって示す金額（1つに決まるときだけ）
    var agreedValue: Int? {
        let groups = [Set(subtotalValues), Set(paymentValues), Set(itemValues)].filter { !$0.isEmpty }
        var counts: [Int: Int] = [:]
        for group in groups {
            for value in group { counts[value, default: 0] += 1 }
        }
        let agreed = counts.filter { $0.value >= 2 }.map(\.key)
        return agreed.count == 1 ? agreed.first : nil
    }

    private static func unique(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        for value in values where value > 0 && value <= SharedExpensePayload.maxAmount && !result.contains(value) {
            result.append(value)
        }
        return result
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

    /// 数量×単価が金額と合わない（Build 22。読み違いかもしれないので、確認画面で知らせる。値は変えない）
    var hasArithmeticMismatch: Bool {
        guard let quantity, let unitPrice, let amount else { return false }
        return quantity * unitPrice != amount
    }
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
