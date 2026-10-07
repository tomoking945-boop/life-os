import SwiftUI

/// リスト。Calm Future 第4段階：セリフ体の見出し、リストはカードに入れず細い線で区切り、中身を少し見せる。
struct ListsView: View {
    @State private var viewModel: ListsViewModel

    init(store: LifeStore) {
        _viewModel = State(initialValue: ListsViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "LISTS", title: "リスト") {
                    Button {
                        viewModel.startCreatingList()
                    } label: {
                        Image(systemName: "plus")
                            .font(LifeTypography.headline)
                            .foregroundStyle(LifeColors.primary)
                            .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                            .background(Circle().fill(LifeColors.surface))
                            .overlay(Circle().stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline))
                    }
                    .accessibilityLabel("新しいリストを作成")
                }

                LifeRuledList(viewModel.lists) { list in
                    NavigationLink(value: list.id) {
                        listRow(list)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .navigationDestination(for: LifeList.ID.self) { id in
            ListDetailView(listID: id, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCreatingList) {
            NewListView(viewModel: viewModel)
                .presentationDetents([.medium])
                .lifeSheetPresentation()
        }
    }

    private func listRow(_ list: LifeList) -> some View {
        HStack(alignment: .center, spacing: LifeSpacing.sm) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(list.title)
                    .font(LifeTypography.editorialHeadline)
                    .foregroundStyle(LifeColors.text)
                if let preview = viewModel.previewText(for: list) {
                    Text(preview)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LifeSpacing.xs)
            Text(viewModel.itemCountText(for: list))
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
            Image(systemName: "chevron.right")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LifeSpacing.md)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("リストの詳細を開きます")
    }
}

#Preview {
    let appState = AppState()
    let store = LifeStore()
    return NavigationStack {
        ListsView(store: store)
    }
    .environment(appState)
    .environment(store)
}
