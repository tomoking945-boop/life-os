import SwiftUI

/// おまかせ整理（今日の整理）。
/// Calm Future 第2段階：最初に全体の整理結果（どこへ何件）を見せ、「すべて反映」か「内容を確認」を選ぶ。
/// 「内容を確認」では、これまでどおり1件ずつ 修正・スキップ・後で ができる。反映後も元に戻せる。
struct TidyUpView: View {
    @State private var viewModel: TidyUpViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: LifeStore, edits: [InboxItem.ID: InboxSuggestion] = [:], usageStyle: UsageStyle = .shared) {
        _viewModel = State(initialValue: TidyUpViewModel(store: store, edits: edits, usageStyle: usageStyle))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    header

                    if viewModel.isFinished {
                        finishedView
                    } else if !viewModel.hasEntries {
                        LifeEmptyState(systemImage: "tray", title: "整理するものはありません")
                            .padding(LifeSpacing.cardPadding)
                            .frame(maxWidth: .infinity)
                            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                    } else if viewModel.isShowingSummary {
                        summaryView
                    } else {
                        ForEach(viewModel.entries) { entry in
                            entryCard(entry)
                        }
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
                .animation(LifeMotion.animation(LifeMotion.standard, reduceMotion: reduceMotion), value: viewModel.entries)
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
                bottomButtons
            }
            .sheet(item: $viewModel.editingEntry) { entry in
                TidyUpEditView(entry: entry) { suggestion in
                    viewModel.update(entry.id, with: suggestion)
                }
                .presentationDetents([.large])
                .lifeSheetPresentation()
            }
        }
    }

    private func animate(_ changes: () -> Void) {
        withLifeAnimation(reduceMotion: reduceMotion, changes)
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

    // MARK: - 全体の整理結果

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeColors.accent)
                Text("LifeOSの整理")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityHidden(true)

            Text(viewModel.summaryTitle)
                .font(LifeTypography.editorialTitle)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.summaryGroups) { group in
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title)
                            .font(LifeTypography.body)
                            .foregroundStyle(LifeColors.text)
                        Spacer(minLength: LifeSpacing.md)
                        Text("\(group.count)件")
                            .font(LifeTypography.timelineTime)
                            .foregroundStyle(LifeColors.text)
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget)
                    .accessibilityElement(children: .combine)
                    LifeDivider()
                }
            }

            Text("まだ何も変えていません。「すべて反映」で追加し、「内容を確認」で1件ずつ見直せます。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.suggestion)
    }

    // MARK: - 反映したあと

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            LifeEmptyState(
                systemImage: "checkmark.circle",
                title: viewModel.finishedText,
                message: "今日の整理はおしまいです。"
            )
            if viewModel.canUndoApply {
                LifeCapsuleButton("元に戻す", systemImage: "arrow.uturn.backward") {
                    animate { viewModel.undoApply() }
                }
                .frame(maxWidth: .infinity)
                .accessibilityHint("追加した項目を取り消し、メモを Inbox に戻します")
            }
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity)
        .lifeSurface(.normal)
    }

    // MARK: - 1件ずつの確認（内容を確認）

    private func entryCard(_ entry: TidyUpEntry) -> some View {
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
                Text("\(TidyUpViewModel.destination(of: entry.suggestion))・\(viewModel.timingText(for: entry))")
            }
            .font(LifeTypography.callout)
            .foregroundStyle(LifeColors.primary)
            Text(entry.suggestion.reasonText)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LifeSpacing.xs) {
                    entryActions(entry)
                }
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    entryActions(entry)
                }
            }
            .padding(.top, LifeSpacing.xxs)
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.normal)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func entryActions(_ entry: TidyUpEntry) -> some View {
        LifeCapsuleButton("修正", systemImage: "slider.horizontal.3") {
            viewModel.startEditing(entry.id)
        }
        LifeCapsuleButton("スキップ", systemImage: "forward") {
            animate { viewModel.skip(entry.id) }
        }
        LifeCapsuleButton("後で", systemImage: "moon") {
            animate { viewModel.postpone(entry.id) }
        }
    }

    // MARK: - 下のボタン

    private var bottomButtons: some View {
        VStack(spacing: LifeSpacing.xs) {
            if viewModel.isFinished || !viewModel.hasEntries {
                LifeButton("閉じる", kind: .secondary) { dismiss() }
            } else {
                LifeButton(viewModel.approveAllTitle, systemImage: "checkmark") {
                    animate { viewModel.approveAll() }
                }
                if viewModel.isShowingSummary {
                    LifeButton("内容を確認", systemImage: "list.bullet", kind: .secondary) {
                        animate { viewModel.showDetails() }
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
