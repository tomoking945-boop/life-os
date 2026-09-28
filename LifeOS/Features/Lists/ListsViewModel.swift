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

    // MARK: - 新規リスト作成（Mock。アプリ再起動で消える）

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
