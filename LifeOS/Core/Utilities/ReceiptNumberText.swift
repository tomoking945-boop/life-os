import Foundation

/// レシートの数字の読み違いを直す（2026-11-10 Build 22。docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md）。
///
/// - 文字認識は、数字の「0」を「O」、「1」を「I」「l」、「5」を「S」などと読み違えることがある。
///   **金額のはず** の場所（「¥」のあと・「円」の前・行の右端）の数字のまとまりだけを直す（商品名・店名の英字は直さない）
/// - 「1.234」（点の3桁区切り）・「1, 234」「¥1 234」（区切りのあとの空白）を「1,234」にそろえる
/// - すべて端末の中の計算。直した文字は候補を作るためだけに使い、保存・送信・ログ出力しない
enum ReceiptNumberText {
    /// 数字と読み違えやすい英字と、その数字
    static let confusables: [Character: Character] = [
        "O": "0", "o": "0",
        "I": "1", "l": "1", "|": "1",
        "Z": "2", "z": "2",
        "S": "5", "s": "5",
        "G": "6",
        "B": "8"
    ]

    /// 数字のまとまり（数字・読み違えやすい英字・カンマ・点。最初と最後は数字か読み違えやすい英字）
    private static let token = #"[0-9OoIl|ZzSsGB](?:[0-9OoIl|ZzSsGB,.]*[0-9OoIl|ZzSsGB])?"#

    /// 金額の場所の数字の読み違いを直した文字（直す場所が無ければそのまま）
    static func repaired(_ text: String) -> String {
        var result = text
        // 1. 「¥」のあと（「¥1,2O0」「¥ S00」）
        result = repairTokens(in: result, pattern: #"(¥\s*)("# + token + #")(?![A-Za-z])"#, tokenGroup: 2, requireMostlyDigits: false)
        // 2. 「円」の前（「l,980円」）
        result = repairTokens(in: result, pattern: #"(?<![A-Za-z0-9])("# + token + #")(\s*円)"#, tokenGroup: 1, requireMostlyDigits: false)
        // 3. 行の右端（「合計 1O0」「牛乳 l98」）。商品名の型番（「S2」など）は直さないよう、数字が2つ以上・英字は1つまで
        result = repairTokens(in: result, pattern: #"(?:(?<=\s)|^)("# + token + #")(?=\s*[※*★軽外内非]*\s*$)"#, tokenGroup: 1, requireMostlyDigits: true)
        // 4. 区切りのあとの空白（「1, 234」）・「¥1 234」
        result = replace(#"(\d),\s+(\d{3})(?!\d)"#, in: result, with: "$1,$2")
        result = replace(#"(¥\s*\d{1,3})\s(\d{3})(?![\d,])"#, in: result, with: "$1,$2")
        return result
    }

    /// 1つのまとまりを直す：英字を数字にし、「1.234」を「1,234」にする。直せなければ nil
    static func repairedToken(_ token: String, requireMostlyDigits: Bool) -> String? {
        let digits = token.filter { $0.isASCII && $0.isNumber }.count
        let letters = token.filter { confusables[$0] != nil }.count
        guard digits >= 1 else { return nil }
        if requireMostlyDigits {
            guard digits >= 2, letters <= 1 else { return nil }
        } else {
            guard letters <= digits else { return nil }
        }
        var fixed = String(token.map { confusables[$0] ?? $0 })
        // 点の3桁区切り（「1.234」「12.345.678」）はカンマにする（「1.5」のような小数はそのまま）
        if fixed.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            fixed = fixed.replacingOccurrences(of: ".", with: ",")
        }
        return fixed
    }

    /// 値引き・クーポンの行の金額（「-100」「▲100」「△100」「100-」「¥100」。正の数で返す）
    static func discountAmount(in text: String) -> Int? {
        let normalized = text
            .replacingOccurrences(of: "▲", with: "-")
            .replacingOccurrences(of: "△", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        guard let regex = try? NSRegularExpression(pattern: #"-?\s*¥?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*円?-?"#) else { return nil }
        let ns = normalized as NSString
        var last: Int?
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
            // 「10%」の割引率・「3点」は金額ではない
            let end = match.range.location + match.range.length
            let after = end < ns.length ? ns.substring(with: NSRange(location: end, length: 1)) : ""
            if after == "%" || after == "点" || after == "個" { continue }
            guard raw.count <= 9, let value = Int(raw), (1...SharedExpensePayload.maxAmount).contains(value) else { continue }
            last = value
        }
        return last
    }

    private static func repairTokens(in text: String, pattern: String, tokenGroup: Int, requireMostlyDigits: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = text
        // 後ろから置き換える（前の位置がずれないように）
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let range = match.range(at: tokenGroup)
            guard range.location != NSNotFound else { continue }
            let original = ns.substring(with: range)
            guard let fixed = repairedToken(original, requireMostlyDigits: requireMostlyDigits), fixed != original else { continue }
            result = (result as NSString).replacingCharacters(in: range, with: fixed)
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
