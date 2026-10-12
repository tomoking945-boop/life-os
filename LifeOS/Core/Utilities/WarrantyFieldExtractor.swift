import Foundation

/// 文字認識の1行
struct WarrantyRecognizedLine: Hashable {
    var text: String
    /// 0〜1
    var confidence: Float = 1
}

/// 読み取った文字から、保証書の入力候補を作る（spec 4「自動読み取り」）。
///
/// - 候補を作るだけで、保証書のデータには書き込まない（反映は利用者が「候補を反映」を押したときだけ）
/// - 見出し（「お買上げ日」「型番」など）の近くの値を優先し、見つからない項目は候補にしない
/// - 候補が複数ある・信頼度が低い・見出しの無い日付は「確認が必要」にする
/// - 保証が有効かどうかは判断しない
/// - すべて端末内の計算で、外部へは送らない
enum WarrantyFieldExtractor {
    static func extract(from lines: [WarrantyRecognizedLine], calendar: Calendar = LifeCalendar.calendar) -> WarrantyExtractionProposal {
        let normalized = lines
            .map { WarrantyRecognizedLine(text: normalize($0.text), confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
        var collector = Collector()

        for (index, line) in normalized.enumerated() {
            let next = index + 1 < normalized.count ? normalized[index + 1] : nil

            // 日付（購入日・保証終了日）
            if containsAny(line.text, Labels.expiration) {
                let found = dates(in: line.text, calendar: calendar)
                let candidates = found.isEmpty ? (next.map { dates(in: $0.text, calendar: calendar) } ?? []) : found
                for date in candidates {
                    collector.add(.warrantyExpiresAt, value: WarrantyExpiration.dateText(date), confidence: line.confidence, date: date)
                }
            } else if containsAny(line.text, Labels.purchaseDate) {
                let found = dates(in: line.text, calendar: calendar)
                let candidates = found.isEmpty ? (next.map { dates(in: $0.text, calendar: calendar) } ?? []) : found
                for date in candidates {
                    collector.add(.purchaseDate, value: WarrantyExpiration.dateText(date), confidence: line.confidence, date: date)
                }
            }

            // 保証期間
            if containsAny(line.text, Labels.duration), let foundDuration = duration(in: line.text) {
                collector.add(.warrantyDuration, value: foundDuration.label, confidence: line.confidence, duration: foundDuration)
            }

            // 見出しのある文字の項目
            for (kind, labels) in Labels.textFields {
                guard let value = labeledValue(in: line.text, labels: labels, next: next?.text, kind: kind) else { continue }
                collector.add(kind, value: value, confidence: line.confidence)
            }

            // よく知られたメーカー・お店の名前
            if let brand = firstMatch(in: line.text, names: Labels.manufacturers) {
                collector.addFallback(.manufacturer, value: brand, confidence: line.confidence)
            }
            if let shop = firstMatch(in: line.text, names: Labels.retailers) {
                collector.addFallback(.retailer, value: shop, confidence: line.confidence)
            }
        }

        // 見出しの無い日付（レシートなど）：購入日の候補にするが、必ず「確認が必要」
        if collector.values[.purchaseDate] == nil {
            let expirationValues = Set(collector.values[.warrantyExpiresAt]?.map(\.value) ?? [])
            for line in normalized {
                for date in dates(in: line.text, calendar: calendar) {
                    let text = WarrantyExpiration.dateText(date)
                    guard !expirationValues.contains(text) else { continue }
                    collector.add(.purchaseDate, value: text, confidence: min(line.confidence, unlabeledConfidence), date: date)
                }
            }
        }

        let recognizedText = lines.map(\.text).joined(separator: "\n")
        return WarrantyExtractionProposal(recognizedText: recognizedText, fields: collector.fields())
    }

    /// 見出しの無い日付の信頼度（「確認が必要」になる値）
    static let unlabeledConfidence: Float = 0.4

    // MARK: - 見出し

    enum Labels {
        static let purchaseDate = ["お買上げ日", "お買い上げ日", "お買上日", "お買い上げ年月日", "お買上げ年月日", "購入日", "購入年月日", "ご購入日", "販売日", "販売年月日"]
        static let expiration = ["保証期限", "保証終了", "保証満了", "保証期間満了", "保証有効期限", "有効期限"]
        static let duration = ["保証期間", "保証", "本体"]

        static let textFields: [(WarrantyFieldKind, [String])] = [
            (.title, ["製品名", "商品名", "品名", "品目", "品種"]),
            (.modelNumber, ["型番", "型式", "品番", "形名", "形式", "MODEL NO", "MODEL"]),
            (.serialNumber, ["製造番号", "製番", "シリアル番号", "シリアルNO", "シリアル", "SERIAL NO", "SERIAL", "S/N"]),
            (.manufacturer, ["製造販売元", "メーカー", "製造元", "製造者", "発売元"]),
            (.retailer, ["お買上げ店", "お買い上げ店", "販売店名", "販売店", "購入店", "店舗名", "取扱店"])
        ]

        static let manufacturers = [
            "パナソニック", "PANASONIC", "シャープ", "SHARP", "ソニー", "SONY", "日立", "HITACHI", "東芝", "TOSHIBA",
            "三菱電機", "MITSUBISHI", "ダイキン", "DAIKIN", "富士通", "FUJITSU", "キヤノン", "CANON", "エプソン", "EPSON",
            "アイリスオーヤマ", "IRIS OHYAMA", "象印", "タイガー", "ダイソン", "DYSON", "バルミューダ", "BALMUDA",
            "デロンギ", "リンナイ", "RINNAI", "ノーリツ", "NORITZ", "TOTO", "LIXIL", "パロマ", "ブラザー", "BROTHER", "APPLE"
        ]

        static let retailers = [
            "ヨドバシカメラ", "ヨドバシ", "ビックカメラ", "ヤマダデンキ", "ヤマダ電機", "ケーズデンキ", "エディオン", "ジョーシン", "上新電機",
            "ノジマ", "コジマ", "ベスト電器", "AMAZON", "アマゾン", "楽天", "ニトリ", "IKEA", "イケア", "無印良品", "カインズ", "コーナン", "APPLE STORE"
        ]
    }

    // MARK: - 文字の整え

    /// 全角の英数字・記号・空白を半角にする（カタカナはそのまま）。前後の空白を除く
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                scalars.append(Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar)
            case 0x3000:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ text: String, _ labels: [String]) -> Bool {
        let upper = text.uppercased()
        return labels.contains { upper.contains($0.uppercased()) }
    }

    /// 長い名前から順に探す（「ヨドバシカメラ」を「ヨドバシ」より優先）
    private static func firstMatch(in text: String, names: [String]) -> String? {
        let upper = text.uppercased()
        return names.sorted { $0.count > $1.count }.first { upper.contains($0.uppercased()) }
    }

    // MARK: - 日付

    /// 文中の日付（2026年10月13日・2026/10/13・2026-10-13・2026.10.13・令和8年10月13日・R8.10.13）
    private static let westernDatePattern = #"(\d{4})\s*[年/.\-]\s*(\d{1,2})\s*[月/.\-]\s*(\d{1,2})\s*日?"#
    private static let japaneseDatePattern = #"(令和|平成|R|H)\s*(\d{1,2}|元)\s*[年.]\s*(\d{1,2})\s*[月.]\s*(\d{1,2})\s*日?"#

    static func dates(in text: String, calendar: Calendar = LifeCalendar.calendar) -> [Date] {
        var results: [Date] = []
        for match in matches(westernDatePattern, in: text) {
            if let year = Int(match[1]), let month = Int(match[2]), let day = Int(match[3]),
               let date = makeDate(year: year, month: month, day: day, calendar: calendar) {
                results.append(date)
            }
        }
        for match in matches(japaneseDatePattern, in: text) {
            let era = match[1]
            let eraYear = match[2] == "元" ? 1 : Int(match[2]) ?? 0
            let base = (era == "令和" || era == "R") ? 2018 : 1988
            if eraYear > 0, let month = Int(match[3]), let day = Int(match[4]),
               let date = makeDate(year: base + eraYear, month: month, day: day, calendar: calendar) {
                results.append(date)
            }
        }
        return results
    }

    private static func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        // 2026/2/30 のような存在しない日は使わない
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    // MARK: - 保証期間

    /// 「保証期間 お買上げ日から1年間」→ 1年、「12ヶ月」→ 12か月、「90日」→ 90日
    static func duration(in text: String) -> WarrantyDuration? {
        // 日付の部分（2026年10月13日・令和8年 など）を先に取り除いてから探す
        var withoutDates = text
        for pattern in [westernDatePattern, japaneseDatePattern] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                withoutDates = regex.stringByReplacingMatches(
                    in: withoutDates,
                    range: NSRange(location: 0, length: (withoutDates as NSString).length),
                    withTemplate: " "
                )
            }
        }
        let pattern = #"(?<!\d)(\d{1,3})\s*(年|ヶ月|ケ月|か月|カ月|ヵ月|箇月|日)"#
        for match in matches(pattern, in: withoutDates) {
            guard let value = Int(match[1]), WarrantyDuration.valueRange.contains(value) else { continue }
            let unit: WarrantyDurationUnit
            switch match[2] {
            case "年": unit = .year
            case "日": unit = .day
            default: unit = .month
            }
            return WarrantyDuration(value: value, unit: unit)
        }
        return nil
    }

    // MARK: - 見出しのある値

    private static func labeledValue(in text: String, labels: [String], next: String?, kind: WarrantyFieldKind) -> String? {
        let upper = text.uppercased()
        for label in labels.sorted(by: { $0.count > $1.count }) {
            guard let range = upper.range(of: label.uppercased()) else { continue }
            let offset = upper.distance(from: upper.startIndex, to: range.upperBound)
            let rest = String(text.dropFirst(offset))
            let trimmed = trimSeparators(rest)
            let candidate = trimmed.isEmpty ? next.map(trimSeparators) ?? "" : trimmed
            if let value = cleanValue(candidate, kind: kind) {
                return value
            }
        }
        return nil
    }

    private static func trimSeparators(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ":：・.|/-　 ").union(.whitespaces))
    }

    /// 型番・製造番号は英数字のまとまりだけ。そのほかは長すぎない文字
    private static func cleanValue(_ text: String, kind: WarrantyFieldKind) -> String? {
        switch kind {
        case .modelNumber, .serialNumber:
            let code = #"[A-Za-z0-9][A-Za-z0-9\-/.]{2,39}"#
            guard let match = matches(code, in: text).first?.first else { return nil }
            // 数字・英字のどちらかだけでも型番はあるが、すべて同じ記号のものは除く
            return match.rangeOfCharacter(from: .alphanumerics) == nil ? nil : match
        default:
            let value = text.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.count <= 60 else { return nil }
            // 日付だけの行は名前にしない
            guard dates(in: value).isEmpty else { return nil }
            return value
        }
    }

    // MARK: - 正規表現

    /// 一致した部分と各グループの文字列
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : nsText.substring(with: range)
            }
        }
    }

    // MARK: - 候補の集め方

    private struct Candidate {
        var value: String
        var confidence: Float
        var date: Date?
        var duration: WarrantyDuration?
        var isFallback: Bool
    }

    private struct Collector {
        var values: [WarrantyFieldKind: [Candidate]] = [:]

        mutating func add(_ kind: WarrantyFieldKind, value: String, confidence: Float, date: Date? = nil, duration: WarrantyDuration? = nil) {
            insert(kind, Candidate(value: value, confidence: confidence, date: date, duration: duration, isFallback: false))
        }

        /// 見出しの無い名前（メーカー・お店の一覧から見つけたもの）。見出しのある値があればそちらを優先
        mutating func addFallback(_ kind: WarrantyFieldKind, value: String, confidence: Float) {
            insert(kind, Candidate(value: value, confidence: confidence, date: nil, duration: nil, isFallback: true))
        }

        private mutating func insert(_ kind: WarrantyFieldKind, _ candidate: Candidate) {
            var list = values[kind] ?? []
            if let index = list.firstIndex(where: { $0.value == candidate.value }) {
                list[index].confidence = max(list[index].confidence, candidate.confidence)
                list[index].isFallback = list[index].isFallback && candidate.isFallback
            } else {
                list.append(candidate)
            }
            values[kind] = list
        }

        func fields() -> [WarrantyExtractedField] {
            WarrantyFieldKind.allCases.compactMap { kind in
                guard let all = values[kind], !all.isEmpty else { return nil }
                // 見出しのある値があれば、見出しの無い名前は候補から外す
                let labeled = all.filter { !$0.isFallback }
                let list = labeled.isEmpty ? all : labeled
                let primary = list[0]
                return WarrantyExtractedField(
                    kind: kind,
                    value: primary.value,
                    alternatives: list.dropFirst().map(\.value),
                    confidence: list.map(\.confidence).min() ?? primary.confidence,
                    date: primary.date,
                    duration: primary.duration
                )
            }
        }
    }
}
