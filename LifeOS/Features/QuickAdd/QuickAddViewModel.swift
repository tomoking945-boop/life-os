import Foundation
import Observation

/// 「すぐ追加」の種類
enum QuickAddType: String, CaseIterable, Identifiable, Hashable {
    case todo
    case event
    case shopping
    case expense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "ToDo"
        case .event: return "予定"
        case .shopping: return "買い物"
        case .expense: return "支出"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "checkmark.circle"
        case .event: return "calendar"
        case .shopping: return "bag"
        case .expense: return "yensign.circle"
        }
    }
}

/// 整理結果の1件（チェックON/OFFできる）
struct QuickAddCandidate: Identifiable, Hashable {
    var item: LifeItem
    var isSelected: Bool

    var id: LifeItem.ID { item.id }
}

@Observable
final class QuickAddViewModel {
    private let store: LifeStore

    var inputText = ""
    /// TODO: 「すぐ追加」ボタンを押したときの動作（種類を指定して即登録する / 入力欄に種類を付ける 等）は仕様未定。
    /// 現状は選択状態を切り替えるだけ。
    var selectedType: QuickAddType?
    var candidates: [QuickAddCandidate] = []
    var isShowingResults = false
    var isShowingVoiceInputNotice = false

    init(store: LifeStore) {
        self.store = store
    }

    // MARK: - 入力

    func toggleQuickType(_ type: QuickAddType) {
        selectedType = (selectedType == type) ? nil : type
    }

    func startVoiceInput() {
        // TODO: 音声入力（Speech フレームワーク等）は今回未実装。
        isShowingVoiceInputNotice = true
    }

    /// 「整理する」：AIは使わず、固定のMock結果を表示する。
    /// TODO: 入力欄が空でも押せるかは仕様未定。現状は常に押せる。
    func organize() {
        candidates = MockData.quickAddResults().map { QuickAddCandidate(item: $0, isSelected: true) }
        isShowingResults = true
    }

    // MARK: - 確認画面

    var foundText: String { "\(candidates.count)件見つかりました" }

    var selectedCount: Int { candidates.filter(\.isSelected).count }

    var addButtonTitle: String { "\(selectedCount)件を追加" }

    var canAdd: Bool { selectedCount > 0 }

    func toggleCandidate(_ id: QuickAddCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].isSelected.toggle()
    }

    func displayTitle(for item: LifeItem) -> String {
        item.hasTime ? "\(item.title) \(LifeFormatters.time(item.date))" : item.title
    }

    /// 選択した項目を Mock のデータに追加する
    func addSelected() {
        let items = candidates.filter(\.isSelected).map(\.item)
        store.add(items)
        reset()
    }

    private func reset() {
        inputText = ""
        selectedType = nil
        candidates = []
        isShowingResults = false
    }
}
