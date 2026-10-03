import Foundation

/// 献立の1日分（v2 仕様 12：将来機能「献立 → 買い物」の UI プロトタイプ用 Mock）
struct MealPlanDay: Identifiable, Hashable {
    let id: String
    /// 曜日の表示（月・火・水）
    var dayLabel: String
    var dish: String
    /// 必要な材料（外食などは空）
    var ingredients: [String]
}
