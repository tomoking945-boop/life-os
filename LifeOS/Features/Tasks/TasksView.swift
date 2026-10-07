import SwiftUI

/// やること。Calm Future 第4段階：時間帯の背景・セリフ体の見出し・カードに入れず細い線で区切る一覧。
struct TasksView: View {
    @State private var viewModel: TasksViewModel
    @State private var shoppingViewModel: ShoppingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: LifeStore, appState: AppState) {
        _viewModel = State(initialValue: TasksViewModel(store: store, appState: appState))
        _shoppingViewModel = State(initialValue: ShoppingViewModel(store: store, appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "TASKS", title: "やること")

                LifeSegmentControl(TaskSegment.allCases, selection: $viewModel.segment) { $0.title }

                if viewModel.segment == .shopping {
                    // v2：買い物は専用の表示（売り場ごと・よく買うもの・再購入候補・お店モード）
                    ShoppingSection(viewModel: shoppingViewModel)
                } else {
                    HStack {
                        Spacer()
                        LifeSegmentControl(CompletionFilter.allCases, selection: $viewModel.completion) { $0.title }
                            .fixedSize()
                    }

                    if viewModel.tasks.isEmpty {
                        LifeEmptyState(systemImage: "checkmark.circle", title: viewModel.emptyTitle)
                            .frame(maxWidth: .infinity)
                            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                    } else {
                        LifeRuledList(viewModel.tasks) { item in
                            let avatar = viewModel.avatar(for: item)
                            LifeTaskRow(
                                title: item.title,
                                detail: viewModel.assigneeText(for: item),
                                trailing: viewModel.trailingText(for: item),
                                assigneeName: avatar?.name,
                                assigneeImage: avatar?.image,
                                isCompleted: item.isCompleted,
                                tint: item.kind.tint,
                                onLater: { viewModel.startPostponing(item) }
                            ) {
                                withLifeAnimation(reduceMotion: reduceMotion) {
                                    viewModel.toggle(item)
                                }
                            }
                            .padding(.vertical, LifeSpacing.xxs)
                        }
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .postponeSheet(item: $viewModel.postponingItem) { item, option in
            withLifeAnimation(reduceMotion: reduceMotion) {
                viewModel.postpone(item, to: option)
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        TasksView(store: store, appState: appState)
    }
    .environment(appState)
    .environment(store)
}
