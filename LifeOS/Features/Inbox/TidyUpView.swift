import SwiftUI

/// おまかせ整理（今日の整理）。Inbox のメモをまとめて確認し、「全部OK」で追加する。
struct TidyUpView: View {
    @State private var viewModel: TidyUpViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: LifeStore) {
        _viewModel = State(initialValue: TidyUpViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    header

                    if viewModel.isFinished {
                        LifeCard {
                            LifeEmptyState(
                                systemImage: "checkmark.circle",
                                title: viewModel.finishedText,
                                message: "今日の整理はおしまいです。"
                            )
                        }
                    } else if !viewModel.hasEntries {
                        LifeCard {
                            LifeEmptyState(systemImage: "tray", title: "整理するものはありません")
                        }
                    } else {
                        ForEach(viewModel.entries) { entry in
                            entryCard(entry)
                        }
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
                .animation(.easeInOut(duration: 0.2), value: viewModel.entries)
            }
            .background(LifeColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomButton
            }
            .sheet(item: $viewModel.editingEntry) { entry in
                TidyUpEditView(entry: entry) { suggestion in
                    viewModel.update(entry.id, with: suggestion)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LifeColors.background)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Text("今日の整理")
                .font(LifeTypography.display)
                .foregroundStyle(LifeColors.primary)
                .accessibilityAddTraits(.isHeader)
            Text("30秒で終わります")
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.secondaryText)
        }
    }

    private func entryCard(_ entry: TidyUpEntry) -> some View {
        LifeCard {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                Text("「\(entry.originalText)」")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(entry.suggestion.title)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                HStack(spacing: LifeSpacing.xxs) {
                    Image(systemName: "arrow.turn.down.right")
                        .accessibilityHidden(true)
                    Text(entry.suggestion.summary)
                }
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.primary)

                HStack(spacing: LifeSpacing.xs) {
                    actionButton("修正", systemImage: "slider.horizontal.3") {
                        viewModel.startEditing(entry.id)
                    }
                    actionButton("スキップ", systemImage: "forward") {
                        viewModel.skip(entry.id)
                    }
                    actionButton("後で", systemImage: "moon") {
                        viewModel.postpone(entry.id)
                    }
                }
                .padding(.top, LifeSpacing.xxs)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .lineLimit(1)
                .padding(.horizontal, LifeSpacing.sm)
                .frame(minHeight: LifeSpacing.minTapTarget)
                .background(Capsule().fill(LifeColors.primarySubtle))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bottomButton: some View {
        Group {
            if viewModel.isFinished || !viewModel.hasEntries {
                LifeButton("閉じる", kind: .secondary) { dismiss() }
            } else {
                LifeButton(viewModel.approveAllTitle, systemImage: "checkmark") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.approveAll()
                    }
                }
            }
        }
        .padding(.horizontal, LifeSpacing.screenHorizontal)
        .padding(.vertical, LifeSpacing.sm)
        .background(LifeColors.background)
    }
}

/// おまかせ整理の「修正」：タイトル・種類・自分/共有・日付を変える
struct TidyUpEditView: View {
    let entry: TidyUpEntry
    let onSave: (InboxSuggestion) -> Void

    @State private var draft: InboxSuggestion
    @Environment(\.dismiss) private var dismiss

    private let kindColumns = [
        GridItem(.flexible(), spacing: LifeSpacing.xs),
        GridItem(.flexible(), spacing: LifeSpacing.xs),
        GridItem(.flexible(), spacing: LifeSpacing.xs)
    ]

    init(entry: TidyUpEntry, onSave: @escaping (InboxSuggestion) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _draft = State(initialValue: entry.suggestion)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    Text("「\(entry.originalText)」")
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)

                    SettingsTextField(label: "タイトル", text: $draft.title, onCommit: {})

                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        LifeSectionTitle("種類")
                        LazyVGrid(columns: kindColumns, spacing: LifeSpacing.xs) {
                            ForEach(LifeItemKind.allCases, id: \.self) { kind in
                                LifeChip(title: kind.label, isSelected: draft.kind == kind) {
                                    draft.kind = kind
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        LifeSectionTitle("自分 / 共有")
                        LifeSegmentControl(Ownership.allCases, selection: $draft.ownership) { $0.label }
                    }

                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        LifeSectionTitle("いつ")
                        LifeSegmentControl(InboxDay.allCases, selection: $draft.day) { $0.label }
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
            }
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle("修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(LifeColors.primary)
                }
            }
        }
    }
}

#Preview {
    TidyUpView(store: LifeStore())
        .environment(AppState())
}
