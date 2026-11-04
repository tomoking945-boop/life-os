import Foundation

/// 合計金額を決められなかった理由（Build 18）
enum ReceiptAmountIssue: Equatable {
    /// 「合計」などの見出しの近くに金額が無い
    case notFound
    /// 合計の候補が複数あり、どれか決められない
    case ambiguous

    var message: String {
        switch self {
        case .notFound:
            return "合計金額を読み取れませんでした。レシートを見て金額を入れてください。"
        case .ambiguous:
            return "合計金額の候補が複数あるため、金額を空にしました。レシートを見て金額を入れてください。"
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
    /// 店名をレシートから読み取れたか
    var isTitleFromReceipt: Bool
    /// 日付をレシートから読み取れたか
    var isDateFromReceipt: Bool
    /// 合計金額を決められなかった理由
    var amountIssue: ReceiptAmountIssue?

    /// 確認画面に出す一言（読み取れなかった項目）
    var notes: [String] {
        var notes: [String] = []
        if let amountIssue { notes.append(amountIssue.message) }
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
        let normalized = lines.map(normalize).filter { !$0.isEmpty }
        let (amount, issue) = totalAmount(in: normalized)
        let foundDate = purchaseDate(in: normalized, calendar: calendar)
        let foundTitle = storeName(in: normalized)
        return ReceiptExtractionProposal(
            title: foundTitle ?? fallbackTitle,
            amount: amount,
            date: foundDate ?? LifeCalendar.startOfDay(today),
            category: category(in: normalized, storeName: foundTitle),
            isTitleFromReceipt: foundTitle != nil,
            isDateFromReceipt: foundDate != nil,
            amountIssue: amount == nil ? (issue ?? .notFound) : nil
        )
    }

    static func extract(from lines: [WarrantyRecognizedLine], today: Date, calendar: Calendar = LifeCalendar.calendar) -> ReceiptExtractionProposal {
        extract(from: lines.map(\.text), today: today, calendar: calendar)
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
        static let totals = ["合計", "お会計", "TOTAL"]
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

    /// 合計金額。決められないときは (nil, 理由)
    static func totalAmount(in lines: [String]) -> (Int?, ReceiptAmountIssue?) {
        var candidates: [(rank: Int, amount: Int)] = []
        for (index, line) in lines.enumerated() {
            let upper = line.uppercased()
            guard !containsAny(upper, Labels.notTotal) else { continue }
            let rank: Int
            let label: String
            if let strong = longestLabel(in: upper, Labels.strongTotals) {
                rank = 2
                label = strong
            } else if let normal = longestLabel(in: upper, Labels.totals) {
                rank = 1
                label = normal
            } else {
                continue
            }
            guard let range = upper.range(of: label) else { continue }
            let offset = upper.distance(from: upper.startIndex, to: range.upperBound)
            let rest = String(line.dropFirst(offset))
            if let amount = amounts(in: rest).last {
                candidates.append((rank, amount))
            } else if index + 1 < lines.count {
                // 見出しの次の行が金額だけのとき（「合計」の下に「¥1,080」）
                let next = lines[index + 1]
                let nextUpper = next.uppercased()
                guard !containsAny(nextUpper, Labels.notTotal),
                      longestLabel(in: nextUpper, Labels.strongTotals + Labels.totals) == nil,
                      isAmountOnly(next),
                      let amount = amounts(in: next).last else { continue }
                candidates.append((rank, amount))
            }
        }
        guard let topRank = candidates.map(\.rank).max() else { return (nil, .notFound) }
        let values = Set(candidates.filter { $0.rank == topRank }.map(\.amount))
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

    /// 店名にしない行の言葉
    private static let notStoreName = [
        "TEL", "電話", "FAX", "〒", "住所", "登録番号", "登録NO", "インボイス", "適格",
        "ありがとう", "いらっしゃいませ", "ようこそ", "ご来店", "毎度", "お待ちして", "またのお越し",
        "領収", "レシート", "RECEIPT", "明細", "お客様", "控え", "営業時間", "年中無休", "定休",
        "WWW", "HTTP", ".COM", ".JP", "アプリ", "公式", "ポイント", "担当", "レジ", "責任者", "NO.", "#"
    ]

    /// 店名（上の方の行から）。決められなければ nil
    static func storeName(in lines: [String]) -> String? {
        for line in lines.prefix(8) {
            let upper = line.uppercased()
            // 日付・合計の行より下は店名を探さない
            if !WarrantyFieldExtractor.dates(in: line).isEmpty
                || longestLabel(in: upper, Labels.strongTotals + Labels.totals) != nil
                || line.contains("¥") {
                break
            }
            let candidate = line
                .replacingOccurrences(of: #"^(店名|店舗名|店舗)\s*[:：]?\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*=-_~・|<>[]【】「」 ").union(.whitespaces))
            if isStoreName(candidate) {
                return String(candidate.prefix(maxTitleLength))
            }
        }
        return nil
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
        // 住所
        if text.range(of: #"(丁目|番地|\d+\s*-\s*\d+)"#, options: .regularExpression) != nil { return false }
        if text.range(of: #"(都|道|府|県).{0,6}(市|区|郡|町|村)"#, options: .regularExpression) != nil { return false }
        return true
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

    /// いちばん長く一致した見出し（「総合計」を「合計」より優先）
    private static func longestLabel(in upper: String, _ labels: [String]) -> String? {
        labels.map { $0.uppercased() }.sorted { $0.count > $1.count }.first { upper.contains($0) }
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
