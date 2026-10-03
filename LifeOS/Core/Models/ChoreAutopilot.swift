import Foundation

/// 今日の余力（家事オートパイロット）
enum EnergyLevel: String, CaseIterable, Identifiable, Hashable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .low: return "😮‍💨"
        case .normal: return "🙂"
        case .high: return "💪"
        }
    }

    var label: String {
        switch self {
        case .low: return "少ない"
        case .normal: return "普通"
        case .high: return "余裕あり"
        }
    }

    /// 余力の大きさ（少ない=0 … 余裕あり=2）
    var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        }
    }
}

/// 家事の候補。`minimumEnergy` 以上の余力のときに今日の家事に入る。
struct ChoreTemplate: Identifiable, Hashable, Codable {
    /// 保存しても変わらない識別子（例："trash"）
    let id: String
    var title: String
    var minutes: Int
    var minimumEnergy: EnergyLevel

    /// 指定の余力で今日やる家事
    static func chores(for energy: EnergyLevel, from templates: [ChoreTemplate]) -> [ChoreTemplate] {
        templates.filter { $0.minimumEnergy.rank <= energy.rank }
    }
}

/// その日の家事オートパイロットの状態（日付が変わると新しい日として扱う）
struct AutopilotDay: Hashable, Codable {
    var day: Date
    var energy: EnergyLevel?
    var doneChoreIDs: [String]
}
