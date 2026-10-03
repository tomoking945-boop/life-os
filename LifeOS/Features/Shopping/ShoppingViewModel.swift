import Foundation
import Observation

/// 売り場ごとにまとめた買い物
struct ShoppingAisleGroup: Identifiable, Hashable {
    let category: ShoppingCategory
    let items: [LifeItem]

    var id: String { category.rawValue }
}

/// 買い物（v2 仕様 11：自動カテゴリー・よく買うもの・再購入候補・ワンタップ追加・店内で見やすいチェック）
@Observable
final class ShoppingViewModel {
    private let store: LifeStore
    private let appState: AppState
    private let now: Date

    /// 店内で見やすい大きなチェック表示
    var isStoreMode = false
    /// 操作のあとに短く出す一言
    var feedbackMessage: String?

    /// 再購入候補にする日数（前回購入からこの日数以上）
    /// TODO: 品目ごとの購入周期の学習は未実装。現状は一律7日。
    private let repurchaseAfterDays = 7

    init(store: LifeStore, appState: AppState, now: Date = LifeCalendar.now) {
        self.store = store
        self.appState = appState
        self.now = now
    }

    // MARK: - 買い物リスト

    /// まだ買っていない買い物（日付に関係なく、買い物リストとしてすべて出す）
    var openItems: [LifeItem] {
        store.items
            .filter { $0.kind == .shopping && !$0.isCompleted && !$0.isDropped }
            .sorted { $0.displayDate < $1.displayDate }
    }

    /// 売り場ごと（冷蔵 → 食品 → 飲料 → 日用品 → その他）
    var groups: [ShoppingAisleGroup] {
        let order: [ShoppingCategory] = [.chilled, .food, .drinks, .dailyGoods, .other]
        return order.compactMap { category in
            let items = openItems.filter { ShoppingCategorizer.aisle(for: $0.title) == category }
            return items.isEmpty ? nil : ShoppingAisleGroup(category: category, items: items)
        }
    }

    /// 今日かごに入れたもの（完了した買い物のうち、今日の分）
    var boughtItems: [LifeItem] {
        store.items.filter {
            $0.kind == .shopping && $0.isCompleted && !$0.isDropped && LifeCalendar.isSameDay($0.displayDate, now)
        }
    }

    func categoryText(for item: LifeItem) -> String {
        ShoppingCategorizer.categories(for: item.title).map(\.label).joined(separator: " / ")
    }

    func toggle(_ item: LifeItem) {
        let isBuying = !item.isCompleted
        store.toggleCompletion(of: item.id)
        if isBuying {
            store.markPurchased(item.title, now: now)
        }
    }

    // MARK: - よく買うもの・再購入候補

    var frequentPurchases: [FrequentPurchase] { store.frequentPurchases }

    func isInList(_ purchase: FrequentPurchase) -> Bool {
        openItems.contains { ShoppingCategorizer.itemName(from: $0.title) == purchase.title }
    }

    func daysSinceLastPurchase(_ purchase: FrequentPurchase) -> Int? {
        purchase.lastPurchasedAt.map { LifeMemoryEvaluator.daysBetween($0, now) }
    }

    /// 前回購入から一定日数たっていて、まだリストに無いもの
    var repurchaseCandidates: [FrequentPurchase] {
        frequentPurchases
            .filter { purchase in
                guard !isInList(purchase), let days = daysSinceLastPurchase(purchase) else { return false }
                return days >= repurchaseAfterDays
            }
            .sorted { (daysSinceLastPurchase($0) ?? 0) > (daysSinceLastPurchase($1) ?? 0) }
    }

    func lastPurchasedText(_ purchase: FrequentPurchase) -> String {
        guard let days = daysSinceLastPurchase(purchase) else { return "購入記録なし" }
        return days == 0 ? "今日購入" : "前回購入から\(days)日"
    }

    /// 家族・パートナーモードでは共有の買い物として追加する
    private var defaultOwnership: Ownership {
        appState.usageStyle == .shared ? .shared : .personal
    }

    /// ワンタップ追加
    func add(_ purchase: FrequentPurchase) {
        let added = store.addShopping([purchase.title], ownership: defaultOwnership, now: now)
        feedbackMessage = added > 0 ? "「\(purchase.title)」を追加しました" : "「\(purchase.title)」はもうリストにあります"
    }

    // MARK: - 献立から作る

    func addFromMealPlan(_ names: [String]) -> Int {
        store.addShopping(names, ownership: defaultOwnership, now: now)
    }
}
