import Foundation

/// リスト（行きたい場所 / 観たいもの など）
struct LifeList: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var items: [LifeListItem]

    // TODO: リストの「自分 / 共有」区分は仕様未定。

    init(id: UUID = UUID(), title: String, items: [LifeListItem] = []) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// リストの中の1項目
struct LifeListItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}
