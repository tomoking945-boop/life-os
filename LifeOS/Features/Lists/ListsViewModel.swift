import Foundation
import Observation

@Observable
final class ListsViewModel {
    private let store: LifeStore

    var isCreatingList = false
    var newListTitle = ""

    init(store: LifeStore) {
        self.store = store
    }

    var lists: [LifeList] { store.lists }

    func list(id: LifeList.ID) -> LifeList? {
        store.list(id: id)
    }

    func itemCountText(for list: LifeList) -> String {
        "\(list.items.count)件"
    }

    // MARK: - リスト内の項目（端末内に保存）

    /// 空白だけの入力は追加しない
    func addItem(_ title: String, toList id: LifeList.ID) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        store.addItem(trimmed, toList: id)
        return true
    }

    func deleteItems(at offsets: IndexSet, fromList id: LifeList.ID) {
        store.removeItems(at: offsets, fromList: id)
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
        store.addList(title: trimmedTitle)
        newListTitle = ""
        isCreatingList = false
    }

    func cancelCreatingList() {
        newListTitle = ""
        isCreatingList = false
    }
}
