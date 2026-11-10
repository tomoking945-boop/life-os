import Foundation

/// 合計金額を決められなかった理由（Build 18）
enum ReceiptAmountIssue: Equatable {
    /// 「合計」などの見出しの近くに金額が無い
    case notFound
    /// 合計の候補が複数あり、どれか決められない
    case ambiguous
    /// 合計の見出しの金額が、小計・税・お預り・お釣りなどから計算した金額と合わない（Build 22）
    case inconsistent

    var message: String {
        switch self {
        case .notFound:
            return "合計金額を読み取れませんでした。レシートを見て金額を入れてください。"
        case .ambiguous:
            return "合計金額の候補が複数あるため、金額を空にしました。レシートを見て金額を入れてください。"
        case .inconsistent:
            return "合計金額が、小計・税やお預り・お釣りから計算した金額と合わないため、空にしました。レシートを見て候補から選ぶか、金額を入れてください。"
        }
    }
}

/// レシートから作った支出の候補（Build 18。docs/BUILD_18_RECEIPT_TO_BUDGET.md）。
/// 候補を作るだけで、家計簿には書き込まない（利用者が確認画面で「保存」を押したときだけ支出になる）。
/// 読み取った全文は持たない（店名・金額・日付・カテゴリーの4つの候補だけ）
struct ReceiptExtractionProposal: Equatable {
    /// 店名（決められなければ「レシート」）
    var title: String
    /// 合計金額（1〜999,999,999 円。決められなければ nil＝空のまま確認画面を開く）
    var amount: Int?
    /// 購入日（読み取れなければ今日）
    var date: Date
    /// カテゴリー（確かな手掛かりが無ければ「その他」）
    var category: ExpenseCategory
    /// 店名の候補（Build 19。上から順に最大5件・重複なし。最初の候補が title）。
    /// 確認画面で選ぶための一時的な候補。保存・送信しない（確認画面を閉じたら手放す）
    var storeCandidates: [String] = []
    /// 合計金額の候補（Build 20。順位の高い順に最大5件。小計は「選択非推奨」の参考）。一時的な候補。保存・送信しない
    var amountCandidates: [ReceiptAmountCandidate] = []
    /// 商品明細の候補（Build 20。確認用。保存・送信しない）
    var lineItems: [ReceiptLineItem] = []
    /// 読み取りの精度が低いかもしれない（文字が少ない・信頼度が低い。Build 20）
    var isLowQuality = false
    /// 店名をレシートから読み取れたか
    var isTitleFromReceipt: Bool
    /// 日付をレシートから読み取れたか
    var isDateFromReceipt: Bool
    /// 合計金額を決められなかった理由
    var amountIssue: ReceiptAmountIssue?
    /// 合計金額は入れたが、確かめてほしいこと（Build 22。小計・税などと合わないとき）
    var amountWarning: String? = nil

    /// 確認画面に出す一言（読み取れなかった項目）
    var notes: [String] {
        var notes: [String] = []
        if isLowQuality { notes.append(ReceiptReadQuality.lowQualityMessage) }
        if let amountIssue { notes.append(amountIssue.message) }
        if let amountWarning { notes.append(amountWarning) }
        if !isDateFromReceipt { notes.append("日付を読み取れなかったため、今日にしました。") }
        if !isTitleFromReceipt { notes.append("お店の名前を読み取れなかったため、「レシート」にしました。") }
        return notes
    }
}

/// 読み取ったレシートの文字から、支出の候補を作る（Build 18）。
///
/// - すべて端末の中の計算。外部へは送らない。読み取った文字は候補を作ったら捨てる（保存しない・ログに出さない）
/// - 合計金額は「合計」「総合計」「お買上金額」「お支払額」「請求額」「TOTAL」などの見出しの近くの金額だけを使う。
///   小計・消費税・お預り・お釣り・値引き・点数・電話番号・郵便番号・カード番号・時刻などは合計にしない。
///   決められないときは nil（推測した金額は入れない）
/// - 日付は存在する日だけ（2026/2/30 などは使わず、別の日に直さない）。読めなければ今日
/// - 店名は上の方の行から。電話番号・住所・登録番号・あいさつなどは店名にしない。決められなければ「レシート」
/// - カテゴリーは、確かな手掛かりが1種類だけあるときだけ。それ以外は「その他」
enum ReceiptFieldExtractor {
    /// 店名を決められないときの名前
    static let fallbackTitle = "レシート"
    /// 店名の長さの上限（家計簿のタイトルは 200 文字まで。店名はもっと短い）
    static let maxTitleLength = 40

    static func extract(from lines: [String], today: Date, calendar: Calendar = LifeCalendar.calendar) -> ReceiptExtractionProposal {
        extract(from: lines.map { ReceiptRecognizedLine(text: $0) }, today: today, calendar: calendar)
    }

    static func extract(from lines: [WarrantyRecognizedLine], today: Date, calendar: Calendar = LifeCalendar.calendar) -> ReceiptExtractionProposal {
        extract(from: lines.map { ReceiptRecognizedLine(text: $0.text, confidence: $0.confidence, box: $0.box, alternatives: $0.alternatives) }, today: today, calendar: calendar)
    }

    /// 位置・信頼度つきの行から候補を作る（Build 20）。位置があれば、同じ高さの文字を1行にまとめ、
    /// 店名・合計の候補の順位付けに位置・文字の大きさ・信頼度を使う。位置が無ければ、上から下の順の行として扱う
    static func extract(from lines: [ReceiptRecognizedLine], today: Date, calendar: Calendar = LifeCalendar.calendar) -> ReceiptExtractionProposal {
        let rows = ReceiptLayout.rows(from: lines)
        let texts = rows.map(\.text)
        // Build 22：合計の候補を、小計・税・値引き・お預り・お釣り・商品明細の合計と照らし合わせて決める
        let analysis = amountAnalysis(in: rows)
        let amountCandidates = analysis.candidates
        let amount = analysis.amount
        let issue = analysis.issue
        let foundDate = purchaseDate(in: texts, calendar: calendar)
        let candidates = storeNames(in: rows)
        let foundTitle = candidates.first
        return ReceiptExtractionProposal(
            title: foundTitle ?? fallbackTitle,
            amount: amount,
            date: foundDate ?? LifeCalendar.startOfDay(today),
            category: category(in: texts, storeName: foundTitle),
            storeCandidates: candidates,
            amountCandidates: Array(amountCandidates.prefix(maxAmountCandidates)),
            lineItems: lineItems(in: rows),
            isLowQuality: ReceiptReadQuality.isLow(lines),
            isTitleFromReceipt: foundTitle != nil,
            isDateFromReceipt: foundDate != nil,
            amountIssue: amount == nil ? (issue ?? .notFound) : nil,
            amountWarning: amount == nil ? nil : analysis.warning
        )
    }

    // MARK: - 文字の整え

    /// 全角の英数字・記号を半角に（保証書と同じ）。「￥」「\」は「¥」にそろえる
    static func normalize(_ text: String) -> String {
        WarrantyFieldExtractor.normalize(text)
            .replacingOccurrences(of: "￥", with: "¥")
            .replacingOccurrences(of: "\\", with: "¥")
    }

    // MARK: - 合計金額

    enum Labels {
        /// はっきり「支払う合計」を表す見出し（優先）
        static let strongTotals = [
            "総合計", "合計金額", "税込合計", "お買上金額", "お買上げ金額", "お買い上げ金額", "お買上計", "お買上げ計",
            "お支払額", "お支払金額", "お支払い金額", "お支払合計", "お支払い合計", "ご請求額", "ご請求金額", "請求額", "請求金額",
            "領収金額", "TOTAL AMOUNT", "GRAND TOTAL", "AMOUNT DUE"
        ]
        /// 一般的な合計の見出し
        static let totals = ["合計", "お会計", "TOTAL", "現計"]
        /// 合計ではない行（この言葉がある行の金額は、合計の候補にしない）
        static let notTotal = [
            "小計", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL",
            "消費税", "内税", "外税", "税額", "税率", "対象", "TAX",
            "お預り", "お預かり", "預り", "預かり", "お釣", "おつり", "釣銭", "つり銭", "CHANGE", "CASH", "現金",
            "値引", "割引", "DISCOUNT", "クーポン",
            "点数", "個数", "ITEM", "QTY", "ポイント", "POINT",
            "電話", "TEL", "番号", "NO.", "会員", "カード", "CARD"
        ]
    }

    /// 小計の見出し（Build 20：合計にはしないが「小計・選択非推奨」の参考候補にする）
    static let subtotalLabels = ["小計", "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL"]
    /// 確認画面に出す合計金額の候補の最大の数（Build 20）
    static let maxAmountCandidates = 5

    /// 合計金額。決められないときは (nil, 理由)（文字だけの行。Build 20 から候補の順位付けと同じ決まり）
    static func totalAmount(in lines: [String]) -> (Int?, ReceiptAmountIssue?) {
        let analysis = amountAnalysis(in: ReceiptLayout.rows(from: lines.map { ReceiptRecognizedLine(text: $0) }))
        return (analysis.amount, analysis.amount == nil ? (analysis.issue ?? .notFound) : nil)
    }

    /// 合計金額の候補（Build 20）。順位の高い順・同じ「金額と見出し」は1つだけ
    static func amountCandidates(in rows: [ReceiptRow]) -> [ReceiptAmountCandidate] {
        amountAnalysis(in: rows).candidates
    }

    /// 合計が小計・税などと合わないときの一言（Build 22）
    static let inconsistentWarning = "合計金額が、小計・税やお預り・お釣りから計算した金額と合いません。レシートで確かめてください。"

    /// 合計金額の決め方（Build 22。docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md）
    ///
    /// 1. 見出し（総合計・お支払額・合計・現計・TOTAL など）の近くの金額を候補にする（Build 20 と同じ）
    /// 2. 小計＋外税（－値引き）・お預り－お釣り・商品明細の合計を計算し、候補と照らし合わせる（合う候補を上の順位に。
    ///    Vision の2番目・3番目の読み方の方が合うなら、そちらの数字を使う）
    /// 3. 自動で入れるのは、いちばん強い見出しの候補が1つの金額にそろうときだけ（Build 18 と同じ）。
    ///    そのうえで、2つ以上の別々の計算がそろって別の金額を示すときは、自動で入れない（.inconsistent）。
    ///    計算が1つだけ合わないときは、金額は入れるが「確かめてください」と出す
    static func amountAnalysis(in rows: [ReceiptRow]) -> ReceiptAmountAnalysis {
        let evidence = totalsEvidence(in: rows)
        var candidates = labeledAmountCandidates(in: rows, evidence: evidence)
        var (amount, issue) = selectedAmount(from: candidates)
        var warning: String?
        if let value = amount, !evidence.supports(value) {
            if let agreed = evidence.agreedValue, agreed != value {
                // 別々の計算がそろって別の金額を示す：読み違いの疑いが強いので、自動で入れない
                amount = nil
                issue = .inconsistent
            } else if !evidence.strongValues.isEmpty {
                warning = inconsistentWarning
            }
        }
        // 計算でそろった金額が候補に無ければ、「計算」の候補として出す（自動では選ばない）
        if amount == nil, let agreed = evidence.agreedValue, !candidates.contains(where: { $0.amount == agreed }) {
            candidates.append(ReceiptAmountCandidate(amount: agreed, label: "計算", kind: .calculated, score: 0, isConsistent: true))
        }
        return ReceiptAmountAnalysis(candidates: candidates, amount: amount, issue: amount == nil ? (issue ?? .notFound) : nil, warning: warning)
    }

    /// 見出しの近くの合計金額の候補（Build 20・22）。順位の高い順・同じ「金額と見出し」は1つだけ。
    ///
    /// - 見出しの行の右側（同じ行）の金額を優先し、無ければ直下の「金額だけの行」を使う
    ///   （Build 22：「(税込)」のような短い行を1つ挟んでもよい。「¥3,」「520」のように2行に分かれた数字もつなぐ）
    /// - 強い見出し（総合計・お支払額など）＞ 合計 ＞ 小計（参考・選択非推奨）の順。同じ強さなら、計算と合う・
    ///   レシートの下の方・同じ行・信頼度の高いものを上にする
    /// - お預り・お釣り・税・値引き・点数・ポイント・カード番号・電話番号などの行は候補にしない
    static func labeledAmountCandidates(in rows: [ReceiptRow], evidence: ReceiptTotalsEvidence) -> [ReceiptAmountCandidate] {
        var found: [ReceiptAmountCandidate] = []
        let lastIndex = max(rows.count - 1, 1)
        for (index, row) in rows.enumerated() {
            let upper = row.text.uppercased()
            let kind: ReceiptAmountCandidate.Kind
            let label: String
            // レシートの中で一致した見出し（「SUBTOTAL」など。表示は「小計」にそろえる）
            let matched: String
            if let subtotal = matchedLabel(in: upper, subtotalLabels) {
                // 小計（「対象」「税」など、ほかの合計ではない言葉が一緒なら使わない）
                let others = Labels.notTotal.filter { !subtotalLabels.contains($0) }
                guard !containsAny(upper.replacingOccurrences(of: subtotal.uppercased(), with: " "), others) else { continue }
                kind = .subtotal
                label = "小計"
                matched = subtotal
            } else if containsAny(upper, Labels.notTotal) {
                continue
            } else if let strong = matchedLabel(in: upper, Labels.strongTotals) {
                kind = .strongTotal
                label = strong
                matched = strong
            } else if let normal = matchedLabel(in: upper, Labels.totals) {
                kind = .total
                label = normal
                matched = normal
            } else {
                continue
            }
            var foundAmount: Int? = amountAfter(matched, in: row.text) ?? nil
            var sourceRow = row
            var isSameRow = true
            if foundAmount == nil, let below = amountBelow(rows, labelIndex: index) {
                // 見出しの直下の行が金額だけのとき（「合計」の下に「¥1,080」）
                foundAmount = below.amount
                sourceRow = below.row
                isSameRow = false
            }
            // Vision のほかの読み方での金額（同じ見出しのあと・直下の行）
            var alternatives = row.alternatives.compactMap { amountAfter(matched, in: $0) ?? nil }
            if !isSameRow {
                alternatives += sourceRow.alternatives.compactMap { amounts(in: $0).last }
            }
            if foundAmount == nil {
                foundAmount = alternatives.first
            } else if let value = foundAmount, !evidence.supports(value),
                      let better = alternatives.first(where: { evidence.supports($0) }) {
                // 1番目の読み方は計算と合わないが、ほかの読み方が合う：そちらを使う
                foundAmount = better
            }
            guard let amount = foundAmount else { continue }
            let position = row.box?.midY ?? Double(index) / Double(lastIndex)
            let confidence = Double(min(row.confidence, sourceRow.confidence))
            let consistent = evidence.supports(amount)
            let score = kind.weight + position * 10 + confidence * 3 + (isSameRow ? 2 : 1) + (consistent ? 20 : 0)
            found.append(ReceiptAmountCandidate(amount: amount, label: label, kind: kind, score: score, isConsistent: consistent))
        }
        // 順位の高い順。同じ「金額と見出し」は、順位の高い方だけ
        var results: [ReceiptAmountCandidate] = []
        for candidate in found.enumerated().sorted(by: { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }).map(\.element)
        where !results.contains(where: { $0.id == candidate.id }) {
            results.append(candidate)
        }
        return results
    }

    /// 見出しのあとの金額（同じ行）。見出しが見つからなければ nil、金額が無ければ .some(nil)
    private static func amountAfter(_ label: String, in text: String) -> Int?? {
        let upper = text.uppercased()
        guard let range = upper.range(of: label.uppercased()) else { return nil }
        let offset = upper.distance(from: upper.startIndex, to: range.upperBound)
        return .some(amounts(in: String(text.dropFirst(offset))).last)
    }

    /// 見出しの直下の金額だけの行（「(税込)」のような短い行を1つ挟んでもよい。2行に分かれた数字もつなぐ）
    private static func amountBelow(_ rows: [ReceiptRow], labelIndex: Int) -> (amount: Int, row: ReceiptRow)? {
        var index = labelIndex + 1
        guard index < rows.count else { return nil }
        // 数字の無い短い行（「(税込)」「(内税)」）を1つだけ飛ばす
        if isShortNote(rows[index].text), index + 1 < rows.count {
            index += 1
        }
        let next = rows[index]
        let nextUpper = next.text.uppercased()
        guard !containsAny(nextUpper, Labels.notTotal),
              matchedLabel(in: nextUpper, Labels.strongTotals + Labels.totals + subtotalLabels) == nil else { return nil }
        // 2行に分かれた数字（「¥3,」の下に「520」）
        if index + 1 < rows.count,
           next.text.range(of: #"^¥?\s*\d{1,3},?$"#, options: .regularExpression) != nil,
           rows[index + 1].text.range(of: #"^\d{3}(,\d{3})*\s*円?$"#, options: .regularExpression) != nil {
            let joined = (next.text + rows[index + 1].text).replacingOccurrences(of: " ", with: "")
            if let value = amounts(in: joined).last { return (value, next) }
        }
        guard isAmountOnly(next.text), let value = amounts(in: next.text).last else { return nil }
        return (value, next)
    }

    /// 数字の無い短い行（「(税込)」など）
    private static func isShortNote(_ text: String) -> Bool {
        text.count <= 8 && text.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) == nil
            && matchedLabel(in: text.uppercased(), Labels.strongTotals + Labels.totals + subtotalLabels) == nil
    }

    // MARK: - 合計の確かめ（Build 22）

    /// 外税・消費税の行（内税・対象額の行は除く）
    private static func isOuterTaxRow(_ upper: String) -> Bool {
        guard !containsAny(upper, ["内", "対象", "INCL"]) else { return false }
        return containsAny(upper, ["外税", "消費税", "TAX"]) && !containsAny(upper, ["小計", "SUBTOTAL", "SUB TOTAL"])
    }

    /// 合計を確かめるための、レシートの中のほかの金額
    static func totalsEvidence(in rows: [ReceiptRow]) -> ReceiptTotalsEvidence {
        var evidence = ReceiptTotalsEvidence()
        for (index, row) in rows.enumerated() {
            let upper = row.text.uppercased()
            if let subtotal = matchedLabel(in: upper, subtotalLabels) {
                let others = Labels.notTotal.filter { !subtotalLabels.contains($0) }
                if !containsAny(upper.replacingOccurrences(of: subtotal.uppercased(), with: " "), others) {
                    let value = (amountAfter(subtotal, in: row.text) ?? nil) ?? amountBelow(rows, labelIndex: index)?.amount
                    if let value { evidence.subtotal = value }
                }
                continue
            }
            if isOuterTaxRow(upper), let value = amounts(in: row.text).last {
                evidence.outerTax += value
                continue
            }
            if containsAny(upper, ["値引", "割引", "DISCOUNT", "クーポン"]), !containsAny(upper, ["対象"]),
               let value = ReceiptNumberText.discountAmount(in: row.text) {
                evidence.discount += value
                continue
            }
            if containsAny(upper, ["ポイント", "POINT"]), containsAny(upper, ["利用", "使用", "支払"]),
               let value = amounts(in: row.text).last {
                evidence.pointsUsed += value
                continue
            }
            if containsAny(upper, ["お預", "預り", "預かり"]), let value = amounts(in: row.text).last {
                evidence.deposit = value
                continue
            }
            if containsAny(upper, ["お釣", "おつり", "釣銭", "つり銭", "CHANGE"]) {
                if let value = amounts(in: row.text).last {
                    evidence.change = value
                } else if row.text.range(of: #"(^|[\s¥])0\s*円?$"#, options: .regularExpression) != nil {
                    evidence.change = 0
                }
            }
        }
        let items = lineItems(in: rows)
        if !items.isEmpty, items.allSatisfy({ $0.amount != nil }) {
            evidence.itemsTotal = items.compactMap(\.amount).reduce(0, +)
        }
        return evidence
    }

    /// 自動で金額欄に入れる合計（Build 18 と同じ決まり）。いちばん強い見出しの候補が1つの金額にそろうときだけ。
    /// 小計は自動で入れない。強い候補で金額が違えば (nil, .ambiguous)、候補が無ければ (nil, .notFound)
    static func selectedAmount(from candidates: [ReceiptAmountCandidate]) -> (Int?, ReceiptAmountIssue?) {
        let recommended = candidates.filter(\.isRecommended)
        guard let topKind = recommended.map(\.kind).max() else { return (nil, .notFound) }
        let values = Set(recommended.filter { $0.kind == topKind }.map(\.amount))
        // 同じ見出しの強さで違う金額が複数あるときは、決めない（推測した金額を入れない）
        guard values.count == 1, let value = values.first else { return (nil, .ambiguous) }
        return (value, nil)
    }

    /// 文中の金額（1〜999,999,999 円の整数）。電話番号・郵便番号・カード番号・日付・時刻・点数などは除く
    static func amounts(in text: String) -> [Int] {
        var cleaned = text
        for pattern in ignoredNumberPatterns {
            cleaned = replace(pattern, in: cleaned, with: " ")
        }
        // 「¥1,080-」のような末尾の「-」は金額の終わりの印として扱う
        cleaned = replace(#"(\d)-(?=\s|$)"#, in: cleaned, with: "$1")
        var results: [Int] = []
        let nsText = cleaned as NSString
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return [] }
        for match in regex.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length)) {
            let digitsRange = match.range(at: 1)
            guard digitsRange.location != NSNotFound else { continue }
            let raw = nsText.substring(with: digitsRange)
            let digits = raw.replacingOccurrences(of: ",", with: "")
            guard digits.count <= 9, let value = Int(digits), (1...SharedExpensePayload.maxAmount).contains(value) else { continue }
            // 直前・直後が数字や記号の一部なら、金額ではない（番号・小数・比率など）
            let before = digitsRange.location > 0 ? nsText.substring(with: NSRange(location: digitsRange.location - 1, length: 1)) : ""
            let afterLocation = match.range.location + match.range.length
            let after = afterLocation < nsText.length ? nsText.substring(with: NSRange(location: afterLocation, length: 1)) : ""
            if before.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789,-/:.#*")) != nil { continue }
            if after.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789,-/:.%点個件枚#*")) != nil { continue }
            results.append(value)
        }
        return results
    }

    /// 金額：「¥」は前、「円」は後ろ（どちらも無くてもよい）。3桁区切りのカンマは正しい形だけ
    private static let amountPattern = #"¥?\s*(\d{1,3}(?:,\d{3})+|\d+)(?!,\d)\s*(?:円)?"#

    /// 金額として読まない数字（先に消しておく）
    private static let ignoredNumberPatterns = [
        // 日付
        #"\d{4}\s*[年/.\-]\s*\d{1,2}\s*[月/.\-]\s*\d{1,2}\s*日?"#,
        #"(令和|平成|R|H)\s*(\d{1,2}|元)\s*[年.]\s*\d{1,2}\s*[月.]\s*\d{1,2}\s*日?"#,
        // 時刻
        #"\d{1,2}:\d{2}(:\d{2})?"#,
        #"\d{1,2}時\d{1,2}分"#,
        // 電話番号・郵便番号
        #"\(?0\d{1,4}\)?[\-\s]?\d{1,4}[\-\s]\d{3,4}"#,
        #"〒?\s*\d{3}-\d{4}"#,
        // カード番号（伏せ字を含む）
        #"(\d{4}[\s\-*]){3}\d{1,4}"#,
        #"[*X]{2,}[\s\-*X]*\d{2,4}"#,
        // 登録番号（インボイス）
        #"T\d{13}"#
    ]

    /// 金額だけの行か（¥・円・空白・カンマ以外の文字が無い）
    private static func isAmountOnly(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: #"[¥円,\s]"#, with: "", options: .regularExpression)
        return !stripped.isEmpty && stripped.allSatisfy(\.isNumber)
    }

    // MARK: - 日付

    /// 購入日（上から最初の、存在する日付）。有効期限などの行は見ない
    static func purchaseDate(in lines: [String], calendar: Calendar) -> Date? {
        for line in lines where !containsAny(line.uppercased(), ["期限", "有効", "まで", "EXPIRE"]) {
            if let date = WarrantyFieldExtractor.dates(in: line, calendar: calendar).first {
                return date
            }
        }
        return nil
    }

    // MARK: - 店名

    /// 店名にしない行の言葉（Build 19：番号・伝票・取引・合計・小計・税・商品の行も除く）
    private static let notStoreName = [
        "TEL", "電話", "FAX", "〒", "住所", "登録番号", "登録NO", "インボイス", "適格",
        "ありがとう", "いらっしゃいませ", "ようこそ", "ご来店", "毎度", "お待ちして", "またのお越し",
        "領収", "レシート", "RECEIPT", "明細", "お客様", "控え", "営業時間", "年中無休", "定休",
        "WWW", "HTTP", ".COM", ".JP", "アプリ", "公式", "ポイント", "担当", "レジ", "責任者", "NO.", "#",
        "番号", "伝票", "取引", "合計", "小計", "税", "商品", "点数",
        // Build 20
        "お預", "お釣", "おつり", "カード", "CARD", "会員", "支払", "現金", "CASH", "CHANGE"
    ]

    /// 店名の候補の最大の数（Build 19）
    static let maxStoreCandidates = 5
    /// 店名を探す行の範囲（レシートの上の方）
    static let storeSearchLines = 10

    /// 店名（いちばん確からしい候補）。決められなければ nil
    static func storeName(in lines: [String]) -> String? {
        storeNames(in: lines).first
    }

    /// 店名の候補（Build 19）。レシートの上の方から最大5件。同じ候補は1つだけ
    static func storeNames(in lines: [String]) -> [String] {
        storeNames(in: ReceiptLayout.rows(from: lines.map { ReceiptRecognizedLine(text: $0) }))
    }

    /// 店名らしい言葉（順位を少し上げる。Build 20）
    static let storeLikeWords = ["店", "屋", "堂", "館", "商店", "薬局", "スーパー", "マート", "ストア", "ドラッグ", "STORE", "SHOP", "MART", "MARKET"]

    /// 店名の候補（Build 19・20）。最大5件・同じ候補は1つだけ。
    ///
    /// - 日付・合計・金額・商品の明細の行より下は探さない。電話番号・郵便番号・住所・登録番号・レシート番号・レジ番号・
    ///   担当・時刻・URL・あいさつ・合計・小計・税・お預り・お釣り・カード・会員・ポイント・商品の明細は候補にしない
    /// - 位置が分かるとき（Build 20）：上にあるほど・周りより文字が大きいほど・信頼度が高いほど・「店名：」の近く・
    ///   店名らしい言葉があるほど上の順位。位置が分からないときは、Build 19 と同じく上から下の順
    static func storeNames(in rows: [ReceiptRow]) -> [String] {
        let usesLayout = !rows.isEmpty && rows.allSatisfy { $0.box != nil }
        let heights = rows.compactMap { $0.box?.height }.sorted()
        let medianHeight = heights.isEmpty ? 0 : heights[heights.count / 2]
        var scored: [(name: String, score: Double)] = []
        var afterLabel = false
        for row in rows.prefix(storeSearchLines) {
            if isHeaderBoundary(row.text) { break }
            let hasLabel = row.text.range(of: #"^(店名|店舗名|店舗)\s*[:：]?"#, options: .regularExpression) != nil
            let candidate = row.text
                .replacingOccurrences(of: #"^(店名|店舗名|店舗)\s*[:：]?\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*=-_~・|<>[]【】「」 ").union(.whitespaces))
            let labelNearby = hasLabel || afterLabel
            afterLabel = hasLabel && candidate.isEmpty
            guard isStoreName(candidate) else { continue }
            let name = String(candidate.prefix(maxTitleLength))
            var score = 0.0
            if usesLayout, let box = row.box {
                score += (1 - box.midY) * 3
                if medianHeight > 0 { score += min(box.height / medianHeight, 2) * 2 }
                score += Double(row.confidence)
                if labelNearby { score += 2 }
                if containsAny(name.uppercased(), storeLikeWords) { score += 1 }
            }
            scored.append((name, score))
        }
        // 位置が分かるときは順位の高い順（同じ点数なら上から）。分からないときは上から下の順のまま
        let ordered = usesLayout
            ? scored.enumerated().sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }.map(\.element.name)
            : scored.map(\.name)
        var results: [String] = []
        for name in ordered where !results.contains(name) {
            results.append(name)
            if results.count == maxStoreCandidates { break }
        }
        return results
    }

    /// レシートの上の部分（お店の情報）の終わりか：日付・合計の見出し・金額・商品の明細の行
    private static func isHeaderBoundary(_ line: String) -> Bool {
        let upper = line.uppercased()
        if !WarrantyFieldExtractor.dates(in: line).isEmpty { return true }
        if longestLabel(in: upper, Labels.strongTotals + Labels.totals) != nil { return true }
        if line.contains("¥") { return true }
        // 商品の明細（「牛乳 198」「牛乳 1,980円」「パン 2点」「@100」「×2」など）
        if line.range(of: #"\S\s+(\d{1,3}(,\d{3})+|\d{2,})\s*円?$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"(\d+\s*(点|個)$|@\s*\d|\s[x×]\s*\d)"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }

    private static func isStoreName(_ text: String) -> Bool {
        guard text.count >= 2, text.count <= 60 else { return false }
        let upper = text.uppercased()
        guard !containsAny(upper, notStoreName) else { return false }
        // 電話番号・郵便番号・番号ばかりの行は店名にしない。
        // 数えるのは半角の 0〜9 だけ（全角の数字は normalize で半角になっている）。
        // 「八百屋」「三越」などの漢数字は数字として数えない（Character.isNumber は漢数字も数字とするため使わない）
        let digits = text.unicodeScalars.filter { (48...57).contains($0.value) }.count
        guard Double(digits) / Double(text.count) <= 0.3 else { return false }
        guard text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2 else { return false }
        // 時刻
        if text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return false }
        // 住所
        if text.range(of: #"(丁目|番地|\d+\s*-\s*\d+)"#, options: .regularExpression) != nil { return false }
        if text.range(of: #"(都|道|府|県).{0,6}(市|区|郡|町|村)"#, options: .regularExpression) != nil { return false }
        return true
    }

    // MARK: - 商品明細（Build 20。確認用）

    /// 商品明細の最大の数
    static let maxLineItems = 50

    /// 明細の終わり（この行から下は商品ではない）：合計・小計・支払いの行
    private static let lineItemsEnd = [
        "小計", "SUBTOTAL", "SUB TOTAL", "合計", "お会計", "TOTAL", "総合計", "お買上", "お買い上", "お支払", "ご請求", "請求額", "領収金額",
        "お預", "預り", "預かり", "お釣", "おつり", "釣銭", "つり銭", "支払", "現金", "CASH", "CHANGE",
        "クレジット", "電子マネー", "AMOUNT DUE", "現計"
    ]

    /// 商品にしない行の言葉（税・値引き・ポイント・カード・電話・住所・番号・担当・あいさつなど）
    private static let notLineItem = [
        "消費税", "内税", "外税", "税率", "税額", "対象", "TAX", "値引", "割引", "DISCOUNT", "クーポン",
        "ポイント", "POINT", "カード", "CARD", "会員", "TEL", "電話", "FAX", "〒", "住所", "登録", "インボイス",
        "レジ", "担当", "責任者", "NO.", "番号", "伝票", "取引", "領収", "レシート", "RECEIPT", "明細",
        "WWW", "HTTP", ".COM", ".JP", "ありがとう", "いらっしゃいませ", "ご来店", "またのお越し", "営業時間",
        "点数", "個数", "買上点", "ITEM", "QTY"
    ]

    /// 商品明細の候補（Build 20）。店名・住所・日時より下、小計・合計・支払いより上の行から作る。
    ///
    /// - 左の商品名と、同じ行（または直後の行）の右の金額を組み合わせる
    /// - 数量・単価は「2点」「2個」「2 x 198」「2×198」「@198」「198円×2」「単198」の形のときだけ。読めなければ空
    /// - 商品名が無く、数量・単価・金額だけの行は、直前の商品の空いている項目に入れる（上書きしない）
    /// - 金額も単価も無い行は商品にしない。推測で作らない
    static func lineItems(in rows: [ReceiptRow]) -> [ReceiptLineItem] {
        var start = 0
        var end = rows.count
        for (index, row) in rows.enumerated() where containsAny(row.text.uppercased(), lineItemsEnd) {
            end = index
            break
        }
        // 日付・時刻の行（お店の情報の終わり）より下から
        for index in 0..<end where !WarrantyFieldExtractor.dates(in: rows[index].text).isEmpty
            || rows[index].text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil {
            start = index + 1
        }
        guard start < end else { return [] }
        var items: [ReceiptLineItem] = []
        for row in rows[start..<end] {
            guard let parsed = bestLineItemParse(row) else { continue }
            if parsed.name.isEmpty {
                // 商品名の無い行：直前の商品の空いている項目だけを埋める
                guard var last = items.popLast() else { continue }
                if last.quantityText.isEmpty, let quantity = parsed.quantity { last.quantityText = String(quantity) }
                if last.unitPriceText.isEmpty, let unitPrice = parsed.unitPrice { last.unitPriceText = String(unitPrice) }
                if last.amountText.isEmpty, let amount = parsed.amount { last.amountText = String(amount) }
                items.append(last)
            } else {
                items.append(ReceiptLineItem(name: parsed.name, quantity: parsed.quantity, unitPrice: parsed.unitPrice, amount: parsed.amount))
            }
        }
        return Array(items.filter { $0.amount != nil || $0.unitPrice != nil }.prefix(maxLineItems))
    }

    /// 1行の読み方を決める（Build 22）。数量×単価が金額と合わないとき・金額が読めないときは、
    /// Vision のほかの読み方の中から、数量×単価と金額が合うもの（または金額が読めるもの）を使う。商品名は1番目の読み方のまま
    static func bestLineItemParse(_ row: ReceiptRow) -> (name: String, quantity: Int?, unitPrice: Int?, amount: Int?)? {
        guard let main = parseLineItem(row.text) else { return nil }
        func fits(_ parsed: (name: String, quantity: Int?, unitPrice: Int?, amount: Int?)) -> Bool {
            guard let quantity = parsed.quantity, let unitPrice = parsed.unitPrice, let amount = parsed.amount else { return false }
            return quantity * unitPrice == amount
        }
        let needsCheck: Bool
        if let quantity = main.quantity, let unitPrice = main.unitPrice, let amount = main.amount {
            needsCheck = quantity * unitPrice != amount
        } else {
            needsCheck = main.amount == nil
        }
        guard needsCheck else { return main }
        for alternative in row.alternatives {
            guard let parsed = parseLineItem(alternative) else { continue }
            if fits(parsed) || (main.amount == nil && parsed.amount != nil && parsed.quantity == main.quantity && parsed.unitPrice == main.unitPrice) {
                return (main.name, parsed.quantity, parsed.unitPrice, parsed.amount)
            }
        }
        return main
    }

    /// 1行を「商品名・数量・単価・金額」に分ける。商品の行ではなければ nil
    static func parseLineItem(_ text: String) -> (name: String, quantity: Int?, unitPrice: Int?, amount: Int?)? {
        let upper = text.uppercased()
        guard !containsAny(upper, notLineItem) else { return nil }
        // 日付・時刻・電話番号・住所の行は商品にしない
        if !WarrantyFieldExtractor.dates(in: text).isEmpty { return nil }
        if text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return nil }
        if text.range(of: #"(丁目|番地|(都|道|府|県).{0,6}(市|区|郡|町|村))"#, options: .regularExpression) != nil { return nil }
        var rest = text
        var quantity: Int?
        var unitPrice: Int?
        let number = #"(¥?\s*\d{1,3}(?:,\d{3})+\s*円?|¥?\s*\d+\s*円?)"#
        // 「2 x 198」「2×198」「198円×2」「¥198×2」
        if let match = firstMatch(number + #"\s*(?:点|個|コ)?\s*[x×X＊]\s*"# + number, in: rest) {
            let left = match.groups[0], right = match.groups[1]
            let leftValue = ReceiptLineItem.number(from: left, max: SharedExpensePayload.maxAmount)
            let rightValue = ReceiptLineItem.number(from: right, max: SharedExpensePayload.maxAmount)
            let leftIsMoney = left.contains("¥") || left.contains("円")
            let rightIsMoney = right.contains("¥") || right.contains("円")
            if leftIsMoney, !rightIsMoney {
                (unitPrice, quantity) = (leftValue, rightValue.flatMap { $0 <= 999 ? $0 : nil })
            } else if rightIsMoney, !leftIsMoney {
                (quantity, unitPrice) = (leftValue.flatMap { $0 <= 999 ? $0 : nil }, rightValue)
            } else if let leftValue, leftValue <= 99 {
                (quantity, unitPrice) = (leftValue, rightValue)
            } else if let rightValue, rightValue <= 99 {
                (unitPrice, quantity) = (leftValue, rightValue)
            }
            if quantity != nil || unitPrice != nil { rest = match.removed }
        }
        // 「@198」「単198」「単価198」
        if unitPrice == nil, let match = firstMatch(#"(?:@|単価|単)\s*"# + number, in: rest) {
            unitPrice = ReceiptLineItem.number(from: match.groups[0], max: SharedExpensePayload.maxAmount)
            rest = match.removed
        }
        // 「2点」「2個」「2コ」（「6枚切」「3個入」は商品名の一部）
        if quantity == nil, let match = firstMatch(#"(?<![\d,])(\d{1,3})\s*(?:点|個|コ)(?![入切])"#, in: rest) {
            quantity = Int(match.groups[0])
            rest = match.removed
        }
        // 右端の金額（空白か「¥」のあと。末尾の「※」「*」「軽」「外」「内」は税の印）
        var amount: Int?
        if let match = firstMatch(#"(?:^|\s|(?=¥))(¥?\s*\d{1,3}(?:,\d{3})+|¥?\s*\d+)\s*円?-?\s*[※*★軽外内非]*\s*$"#, in: rest) {
            if let value = amounts(in: match.groups[0]).last {
                amount = value
                rest = match.removed
            }
        }
        // 商品名：先頭の商品コード（4桁以上の数字）と印を取る
        let name = rest
            .replacingOccurrences(of: #"^\s*\d{4,}\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "※*★・-_=|:：@×").union(.whitespaces))
        let letters = name.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if letters == 0 {
            // 記号・数字だけの行は、数量・単価・金額があるときだけ（直前の商品の続き）
            guard quantity != nil || unitPrice != nil || amount != nil else { return nil }
            return ("", quantity, unitPrice, amount)
        }
        return (String(name.prefix(maxTitleLength)), quantity, unitPrice, amount)
    }

    /// 最初の一致（かっこの中身と、一致した部分を空白に置き換えた文字）
    private static func firstMatch(_ pattern: String, in text: String) -> (groups: [String], removed: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        let groups = (1..<match.numberOfRanges).map { index -> String in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : nsText.substring(with: range)
        }
        return (groups, nsText.replacingCharacters(in: match.range, with: " "))
    }

    // MARK: - カテゴリー

    /// 確かな手掛かり（お店の種類・よく知られたお店の名前・交通・燃料）
    static let categoryKeywords: [(ExpenseCategory, [String])] = [
        (.diningOut, [
            "レストラン", "食堂", "居酒屋", "カフェ", "CAFE", "COFFEE", "珈琲", "喫茶", "ラーメン", "らーめん", "寿司", "鮨",
            "焼肉", "焼き鳥", "焼鳥", "そば処", "うどん", "定食", "ダイニング", "ファミレス", "イートイン", "店内飲食",
            "マクドナルド", "MCDONALD", "スターバックス", "STARBUCKS", "ドトール", "サイゼリヤ", "ガスト", "すき家", "吉野家",
            "松屋", "モスバーガー", "ケンタッキー", "コメダ"
        ]),
        (.transport, [
            "乗車", "運賃", "乗車券", "定期券", "きっぷ", "切符", "タクシー", "TAXI", "ガソリン", "給油", "軽油", "ハイオク",
            "ENEOS", "エネオス", "出光", "コスモ石油", "駐車料金", "高速道路", "鉄道"
        ]),
        (.dailyGoods, [
            "ドラッグ", "薬局", "薬品", "マツモトキヨシ", "マツキヨ", "ウエルシア", "ツルハ", "スギ薬局", "サンドラッグ",
            "ココカラファイン", "ダイコクドラッグ", "ホームセンター", "カインズ", "コーナン", "DCM", "ビバホーム", "コメリ",
            "ダイソー", "DAISO", "セリア", "キャンドゥ"
        ]),
        (.food, [
            "スーパー", "マーケット", "MARKET", "食品館", "食料品", "生鮮", "青果", "精肉", "鮮魚", "イオン", "AEON",
            "イトーヨーカドー", "西友", "SEIYU", "マルエツ", "ヤオコー", "業務スーパー", "成城石井", "まいばすけっと", "いなげや"
        ])
    ]

    /// カテゴリー。手掛かりが1種類だけのときだけ、そのカテゴリー（複数・無しなら「その他」）
    static func category(in lines: [String], storeName: String?) -> ExpenseCategory {
        let text = (lines + [storeName ?? ""]).joined(separator: "\n").uppercased()
        let matched = Set(categoryKeywords.compactMap { category, keywords in
            containsAny(text, keywords) ? category : nil
        })
        guard matched.count == 1, let category = matched.first else { return .other }
        return category
    }

    // MARK: - 共通

    private static func containsAny(_ upper: String, _ words: [String]) -> Bool {
        words.contains { upper.contains($0.uppercased()) }
    }

    /// いちばん長く一致した見出し（元の書き方のまま返す。Build 20）
    private static func matchedLabel(in upper: String, _ labels: [String]) -> String? {
        labels.sorted { $0.count > $1.count }.first { upper.contains($0.uppercased()) }
    }

    /// いちばん長く一致した見出し（「総合計」を「合計」より優先）
    private static func longestLabel(in upper: String, _ labels: [String]) -> String? {
        labels.map { $0.uppercased() }.sorted { $0.count > $1.count }.first { upper.contains($0) }
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
