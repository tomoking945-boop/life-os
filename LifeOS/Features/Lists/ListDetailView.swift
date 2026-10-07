import SwiftUI

/// リスト詳細：項目の追加と、左スワイプでの削除ができる。
/// 決定済み：追加・削除に対応（2026-10-01）。
/// TODO: 項目の編集・並び替え・チェック（行った / 観た など）は未実装。
/// Calm Future 第4段階：List の白い面をやめ、時間帯の背景の上に細い線で並べる（左スワイプの削除はそのまま）。
struct ListDetailView: View {
    let listID: LifeList.ID
    @Bindable var viewModel: ListsViewModel

    @State private var newItemTitle = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if let list = viewModel.list(id: listID) {
                List {
                    Section {
                        addItemRow
                            .listRowSeparator(.hidden)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        if list.items.isEmpty {
                            LifeEmptyState(systemImage: "list.bullet", title: "まだ項目がありません")
                        } else {
                            ForEach(list.items) { item in
                                Text(item.title)
                                    .font(LifeTypography.body)
                                    .foregroundStyle(LifeColors.text)
                                    .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                            }
                            .onDelete { offsets in
                                withAnimation {
                                    viewModel.deleteItems(at: offsets, fromList: listID)
                                }
                            }
                        }
                    } header: {
                        LifeSectionTitle("項目", trailing: viewModel.itemCountText(for: list))
                    } footer: {
                        if !list.items.isEmpty {
                            Text("左にスワイプすると削除できます。")
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(LifeColors.divider)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(list.title)
            } else {
                LifeEmptyState(systemImage: "exclamationmark.circle", title: "リストが見つかりません")
            }
        }
        .lifeScreenBackground()
        .navigationBarTitleDisplayMode(.large)
        .tint(LifeColors.primary)
        .quickAddAccessory()
    }

    private var addItemRow: some View {
        HStack(spacing: LifeSpacing.sm) {
            TextField("項目を追加", text: $newItemTitle)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .focused($isFieldFocused)
                .submitLabel(.done)
                .onSubmit(addItem)
            Button(action: addItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(LifeColors.primary)
                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("項目を追加")
        }
        .padding(.leading, LifeSpacing.md)
        .frame(minHeight: LifeSpacing.buttonHeight)
        .lifeSurface(.normal, cornerRadius: LifeRadius.field)
    }

    private func addItem() {
        if viewModel.addItem(newItemTitle, toList: listID) {
            withAnimation {
                newItemTitle = ""
            }
            isFieldFocused = true
        }
    }
}

#Preview {
    let store = LifeStore()
    let viewModel = ListsViewModel(store: store)
    return NavigationStack {
        ListDetailView(listID: store.lists[0].id, viewModel: viewModel)
    }
    .environment(AppState())
}
