import Foundation

/// 入力した文から時刻を読み取る（「入力をもっと賢く」2026-10-07・ルールのみ、AI は使わない）。
///
/// 読み取る書き方：
/// - 10:30 ／ １０：３０（全角も可）
/// - 10時 ／ 10時半 ／ 10時30分
/// - 午前・午後を前に付けた書き方（午後3時）
/// 後ろに付いた「に」「から」も一緒に取り除く（「19時に美容院」→ 美容院）。
///
/// 新しい解釈：
/// - 午前・午後が無い 1〜6時は午後とみなす（「3時 銀行」→ 15:00）。生活の予定は午後が多いため
/// - 「1時間」のように「時間」と続くものは時刻として読まない
enum TimeReader {
    struct Match: Hashable {
        let time: ClockTime
        /// 時刻として読んだ部分（「19時に」）。理由の表示には `clue` を使う
        let matchedText: String
        /// 理由に出す手がかり（「19時」「10:30」）
        let clue: String
        /// 時刻の部分を取り除いた文
        let remainingText: String
    }

    /// 午前・午後が無いとき、午後とみなす時の範囲
    static let assumedAfternoonHours = 1...6

    private static let pattern =
        "(午前|午後)?\\s*([0-9]{1,2})(?:[:]([0-9]{2})|時(?:(半)|([0-9]{1,2})分)?(?!間))\\s*(?:から|に)?"

    static func read(_ text: String) -> Match? {
        let normalized = normalizeDigits(text)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let wholeRange = Range(match.range, in: text),
              let hourText = substring(normalized, match.range(at: 2)),
              var hour = Int(hourText) else {
            return nil
        }

        var minute = 0
        if let colonMinute = substring(normalized, match.range(at: 3)) {
            minute = Int(colonMinute) ?? -1
        } else if substring(normalized, match.range(at: 4)) != nil {
            minute = 30
        } else if let minuteText = substring(normalized, match.range(at: 5)) {
            minute = Int(minuteText) ?? -1
        }

        switch substring(normalized, match.range(at: 1)) ?? "" {
        case "午後":
            if hour < 12 { hour += 12 }
        case "午前":
            if hour == 12 { hour = 0 }
        default:
            if assumedAfternoonHours.contains(hour) { hour += 12 }
        }

        guard let time = ClockTime(hour: hour, minute: minute) else { return nil }

        let matchedText = String(text[wholeRange])
        var clue = matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        for particle in ["から", "に"] where clue.hasSuffix(particle) {
            clue = String(clue.dropLast(particle.count))
        }
        var remaining = text
        remaining.replaceSubrange(wholeRange, with: " ")
        while remaining.contains("  ") {
            remaining = remaining.replacingOccurrences(of: "  ", with: " ")
        }
        remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        return Match(
            time: time,
            matchedText: matchedText,
            clue: clue.trimmingCharacters(in: .whitespacesAndNewlines),
            remainingText: remaining
        )
    }

    /// 全角の数字とコロンを半角にする（1文字ずつ置き換えるので、位置は変わらない）
    static func normalizeDigits(_ text: String) -> String {
        String(text.map { character -> Character in
            switch character {
            case "０": return "0"
            case "１": return "1"
            case "２": return "2"
            case "３": return "3"
            case "４": return "4"
            case "５": return "5"
            case "６": return "6"
            case "７": return "7"
            case "８": return "8"
            case "９": return "9"
            case "：": return ":"
            default: return character
            }
        })
    }

    private static func substring(_ text: String, _ range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
