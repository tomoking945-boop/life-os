import Foundation
import Observation

@Observable
final class ListsViewModel {
    /// v2 第6回：LifeStore ではなく Repository の窓口を通して読み書きする
    private let repository: any ListRepository

    var isCreatingList = false
    var newListTitle = ""

    init(store repository: any ListRepository) {
        self.repository = repository
    }

    var lists: [LifeList] { repository.lists }

    func list(id: LifeList.ID) -> LifeList? {
        repository.list(id: id)
    }

    func itemCountText(for list: LifeList) -> String {
        "\(list.items.count)件"
    }

    // MARK: - リスト内の項目（端末内に保存）

    /// 空白だけの入力は追加しない
    /// 一覧に小さく添える中身の例（例：箱根の温泉・近所の新しいカフェ）。空なら nil。
    /// Calm Future 第4段階：カードの代わりに、中身が少し見える行にした。
    func previewText(for list: LifeList) -> String? {
        let titles = list.items.prefix(Self.previewCount).map(\.title)
        return titles.isEmpty ? nil : titles.joined(separator: "・")
    }

    /// 一覧に添える項目の数
    static let previewCount = 2

    func addItem(_ title: String, toList id: LifeList.ID) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        repository.addItem(trimmed, toList: id)
        return true
    }

    func deleteItems(at offsets: IndexSet, fromList id: LifeList.ID) {
        repository.removeItems(at: offsets, fromList: id)
    }

    // MARK: - 新規リスト作成（端末内に保存）

    private var trimmedTitle: String {
        newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreateList: Bool { !trimmedTitle.isEmpty }

    func startCreatingList() {
        newListTitle = ""
        isCreatingList = true
    }

    func createList() {
        guard canCreateList else { return }
        repository.addList(title: trimmedTitle)
        newListTitle = ""
        isCreatingList = false
    }

    func cancelCreatingList() {
        newListTitle = ""
        isCreatingList = false
    }
}
