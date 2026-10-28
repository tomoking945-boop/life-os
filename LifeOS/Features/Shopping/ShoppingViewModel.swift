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

    /// まだ買っていない買い物（日付に関係なく、買い物リストとしてすべて出す）。
    /// 端末の買い物とわが家の共有の買い物を一緒に出し、「すべて / 自分 / 共有」で絞る（2026-10-28）
    var openItems: [LifeItem] {
        let scope = appState.effectiveScope
        return store.visibleItems
            .filter { $0.kind == .shopping && !$0.isCompleted && !$0.isDropped && scope.includes($0.ownership) }
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
        let scope = appState.effectiveScope
        return store.visibleItems.filter {
            $0.kind == .shopping && $0.isCompleted && !$0.isDropped && LifeCalendar.isSameDay($0.displayDate, now)
                && scope.includes($0.ownership)
        }
    }

    /// わが家で共有している買い物か（共有マーク）
    func isShared(_ item: LifeItem) -> Bool {
        store.isHouseholdItem(item.id)
    }

    // MARK: - 追加先（2026-10-28）

    /// 追加先（自分だけ／わが家で共有）。初期値は必ず「自分だけ」
    var destination: SaveDestination = .initial

    /// 「わが家で共有」を選べるか（わが家に参加していて、買い物がオン）
    var canChooseDestination: Bool {
        appState.usageStyle.showsScopeFilter && store.canShareInHousehold(.shopping)
    }

    private var effectiveDestination: SaveDestination {
        canChooseDestination ? destination : .personal
    }

    /// 編集画面
    var editingItem: LifeItem?
    var storeForEditing: LifeStore { store }

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

    /// ワンタップ追加（2026-10-28：自動で共有にしない。選んだ追加先へ。初期値は自分だけ）
    func add(_ purchase: FrequentPurchase) {
        let added = store.addShopping([purchase.title], destination: effectiveDestination, now: now)
        feedbackMessage = added > 0 ? "「\(purchase.title)」を追加しました" : "「\(purchase.title)」はもうリストにあります"
    }

    // MARK: - 献立から作る

    func addFromMealPlan(_ names: [String]) -> Int {
        store.addShopping(names, destination: effectiveDestination, now: now)
    }
}
