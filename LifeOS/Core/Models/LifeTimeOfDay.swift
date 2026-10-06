import Foundation

/// 時間帯（Calm Future）。背景のごく弱いグラデーションと挨拶に使う。
/// 色は DesignSystem 側（LifeAmbientColors）で決める。ここは時刻の区切りだけを持つ。
enum LifeTimeOfDay: String, CaseIterable, Identifiable, Hashable {
    case morning
    case day
    case evening
    case night

    var id: String { rawValue }

    /// 時刻から時間帯を決める。
    /// 新しい解釈：朝 5〜10時台／昼 11〜15時台／夕方 16〜18時台／夜 19〜4時台（仕様に区切りの時刻は無い）。
    init(date: Date, calendar: Calendar = LifeCalendar.calendar) {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: self = .morning
        case 11..<16: self = .day
        case 16..<19: self = .evening
        default: self = .night
        }
    }

    var label: String {
        switch self {
        case .morning: return "朝"
        case .day: return "昼"
        case .evening: return "夕方"
        case .night: return "夜"
        }
    }

    /// 挨拶（英語・セリフ体で表示）
    var greeting: String {
        switch self {
        case .morning: return "Good morning."
        case .day: return "Good afternoon."
        case .evening, .night: return "Good evening."
        }
    }
}
