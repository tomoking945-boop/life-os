import SwiftUI

struct ListsView: View {
    @State private var viewModel: ListsViewModel

    init(store: LifeStore) {
        _viewModel = State(initialValue: ListsViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("リスト")
                        .font(LifeTypography.display)
                        .foregroundStyle(LifeColors.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
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

                VStack(spacing: LifeSpacing.md) {
                    ForEach(viewModel.lists) { list in
                        NavigationLink(value: list.id) {
                            listCard(list)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .quickAddAccessory()
        .navigationDestination(for: LifeList.ID.self) { id in
            ListDetailView(listID: id, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isCreatingList) {
            NewListView(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
        }
    }

    private func listCard(_ list: LifeList) -> some View {
        LifeCard {
            HStack {
                Text(list.title)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                Spacer()
                Text(viewModel.itemCountText(for: list))
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                Image(systemName: "chevron.right")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: LifeSpacing.minTapTarget)
        }
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
