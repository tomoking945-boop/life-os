import SwiftUI

/// おまかせInbox：分類せずに保存した生活メモの一覧。
/// 「まとめて整理」で、おまかせ整理（今日の整理）を開く。
struct InboxView: View {
    @State private var viewModel: InboxViewModel
    private let store: LifeStore

    @State private var newText = ""
    @FocusState private var isFieldFocused: Bool

    init(store: LifeStore) {
        self.store = store
        _viewModel = State(initialValue: InboxViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text(viewModel.countText)
                        .font(LifeTypography.title)
                        .foregroundStyle(LifeColors.text)
                    Text("思いついたことを、そのまま置いておく場所です。整理はあとでまとめて。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, LifeSpacing.xs)
                .listRowBackground(Color.clear)
            }

            Section {
                addRow
            }
            .listRowBackground(LifeColors.surface)

            Section {
                if viewModel.items.isEmpty {
                    LifeEmptyState(systemImage: "tray", title: "Inboxは空です", message: "すっきりしています。")
                } else {
                    ForEach(viewModel.items) { item in
                        inboxRow(item)
                    }
                    .onDelete { offsets in
                        withAnimation { viewModel.delete(at: offsets) }
                    }
                }
            } header: {
                LifeSectionTitle("メモ")
            } footer: {
                if !viewModel.items.isEmpty {
                    Text("左にスワイプすると削除できます。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .listRowBackground(LifeColors.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .tint(LifeColors.primary)
        .safeAreaInset(edge: .bottom) {
            LifeButton(viewModel.tidyUpButtonTitle, systemImage: "sparkles") {
                viewModel.isTidyUpPresented = true
            }
            .disabled(!viewModel.canTidyUp)
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.sm)
            .background(LifeColors.background)
        }
        .sheet(isPresented: $viewModel.isTidyUpPresented) {
            TidyUpView(store: store)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
        }
    }

    private var addRow: some View {
        HStack(spacing: LifeSpacing.sm) {
            TextField("とりあえず保存", text: $newText)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .focused($isFieldFocused)
                .submitLabel(.done)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(LifeColors.primary)
                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Inboxに保存")
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
    }

    private func inboxRow(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text(item.text)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
            HStack(spacing: LifeSpacing.xxs) {
                Image(systemName: viewModel.isPostponed(item) ? "moon" : "sparkles")
                    .accessibilityHidden(true)
                Text(viewModel.isPostponed(item) ? "明日の整理に回しています" : viewModel.suggestionText(for: item))
            }
            .font(LifeTypography.footnote)
            .foregroundStyle(LifeColors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func add() {
        if viewModel.add(newText) {
            withAnimation { newText = "" }
            isFieldFocused = true
        }
    }
}

#Preview {
    let store = LifeStore()
    return NavigationStack {
        InboxView(store: store)
    }
    .environment(AppState())
    .environment(store)
}
