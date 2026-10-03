import Foundation

/// 買い物の自動カテゴリー（Mock の固定ロジック）。
/// 品名に含まれる言葉でカテゴリーを決める。AI は使わない。
/// TODO: AI 接続時、または購入履歴から学習する分類に置き換える。
enum ShoppingCategorizer {
    private static let rules: [(keywords: [String], categories: [ShoppingCategory])] = [
        (["牛乳", "ヨーグルト", "チーズ", "卵", "豆腐", "納豆", "バター"], [.food, .chilled]),
        (["肉", "鮭", "魚", "ハム", "ベーコン"], [.food, .chilled]),
        (["パン", "米", "カレールー", "玉ねぎ", "人参", "じゃがいも", "野菜", "パスタ"], [.food]),
        (["ティッシュ", "洗剤", "トイレットペーパー", "シャンプー", "歯ブラシ", "ゴミ袋"], [.dailyGoods]),
        (["お茶", "水", "コーヒー", "ジュース", "ビール"], [.drinks])
    ]

    /// 「牛乳を買う」→「牛乳」
    static func itemName(from title: String) -> String {
        var name = title
        for suffix in ["を買う", "買う"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    static func categories(for title: String) -> [ShoppingCategory] {
        let name = itemName(from: title)
        return rules.first { rule in rule.keywords.contains { name.contains($0) } }?.categories ?? [.other]
    }

    /// 売り場でまとめるときのカテゴリー（冷蔵 → 飲料 → 日用品 → 食品 → その他 の順で優先）
    static func aisle(for title: String) -> ShoppingCategory {
        let categories = categories(for: title)
        for candidate in [ShoppingCategory.chilled, .drinks, .dailyGoods, .food] where categories.contains(candidate) {
            return candidate
        }
        return .other
    }
}
