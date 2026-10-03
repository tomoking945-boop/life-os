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
