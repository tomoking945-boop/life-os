import SwiftUI

/// Inbox（Calm Future 第2段階）。
/// 「未整理タスク一覧」ではなく、生活メモを一時的に置いておく静かなワークスペース。
/// メモごとに、入力した原文・LifeOSの理解（分類候補・日時候補・自分/共有・理由）と
/// 「このまま追加」「修正」「後で」を並べる。「まとめて整理」で、おまかせ整理を開く。
struct InboxView: View {
    @State private var viewModel: InboxViewModel
    private let store: LifeStore

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var newText = ""
    @FocusState private var isFieldFocused: Bool

    init(store: LifeStore) {
        self.store = store
        _viewModel = State(initialValue: InboxViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.xl) {
                header
                addField

                if viewModel.items.isEmpty {
                    LifeEmptyState(systemImage: "tray", title: "Inboxは空です", message: "すっきりしています。")
                        .padding(LifeSpacing.cardPadding)
                        .frame(maxWidth: .infinity)
                        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        LifeDivider()
                        ForEach(viewModel.items) { item in
                            memoRow(item)
                            LifeDivider()
                        }
                    }
                    Text("メモを長押しすると削除できます。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
            .animation(LifeMotion.animation(LifeMotion.standard, reduceMotion: reduceMotion), value: viewModel.items)
        }
        .background(LifeAmbientBackground(timeOfDay: appState.ambientPreview ?? LifeTimeOfDay(date: LifeCalendar.now)))
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
        }
        .lifeFeedbackBanner($viewModel.feedback) {
            viewModel.performUndo()
        }
        .sheet(isPresented: $viewModel.isTidyUpPresented) {
            TidyUpView(store: store, edits: viewModel.edits, usageStyle: appState.usageStyle)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(LifeRadius.sheet)
                .presentationBackground(LifeColors.background)
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

    private func animate(_ changes: () -> Void) {
        withLifeAnimation(reduceMotion: reduceMotion, changes)
    }

    // MARK: - 見出し・入力

    private var header: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Text("WORKSPACE")
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            Text(viewModel.countText)
                .font(LifeTypography.editorialTitle)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)
            Text("思いついたことを、そのまま置いておく場所です。整理はあとでまとめて。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addField: some View {
        HStack(spacing: LifeSpacing.sm) {
            TextField("LifeOSに預ける", text: $newText)
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
            .accessibilityLabel("Inboxに預ける")
        }
        .padding(.leading, LifeSpacing.md)
        .padding(.trailing, LifeSpacing.xxs)
        .frame(minHeight: LifeSpacing.buttonHeight)
        .lifeGlassSurface(cornerRadius: LifeRadius.field)
    }

    // MARK: - メモ

    private func memoRow(_ item: InboxItem) -> some View {
        let suggestion = viewModel.suggestion(for: item)
        let isPostponed = viewModel.isPostponed(item)
        return VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            // 入力した原文
            Text(item.text)
                .font(LifeTypography.editorialHeadline)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)

            if isPostponed {
                HStack(spacing: LifeSpacing.xxs) {
                    Image(systemName: "moon")
                        .accessibilityHidden(true)
                    Text("明日の整理に回しています")
                }
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
            }

            understanding(suggestion, item: item)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LifeSpacing.xs) {
                    memoActions(item, isPostponed: isPostponed)
                }
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    memoActions(item, isPostponed: isPostponed)
                }
            }
        }
        .padding(.vertical, LifeSpacing.lg)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                animate { viewModel.delete(item) }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "削除") {
            animate { viewModel.delete(item) }
        }
    }

    /// LifeOSの理解（分類候補・日時候補・自分/共有・理由）
    private func understanding(_ suggestion: InboxSuggestion, item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: LifeSpacing.sm) {
            RoundedRectangle(cornerRadius: LifeSpacing.categoryBar)
                .fill(suggestion.kind.tint)
                .frame(width: LifeSpacing.categoryBar)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(viewModel.isEdited(item) ? "LifeOSの理解（修正済み）" : "LifeOSの理解")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(suggestion.title)
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                Text(understandingLine(suggestion, item: item))
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suggestion.reasonText)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// 「買い物・食品／冷蔵 ・ 帰宅時に表示 ・ 自分」（一人モードでは自分/共有を出さない）
    private func understandingLine(_ suggestion: InboxSuggestion, item: InboxItem) -> String {
        var parts = [suggestion.categoryText, viewModel.timingText(for: item)]
        if appState.usageStyle.showsScopeFilter {
            parts.append(suggestion.ownershipText)
        }
        return parts.joined(separator: " ・ ")
    }

    @ViewBuilder
    private func memoActions(_ item: InboxItem, isPostponed: Bool) -> some View {
        LifeCapsuleButton("このまま追加", systemImage: "checkmark", isProminent: true) {
            animate { viewModel.addAsIs(item, usageStyle: appState.usageStyle) }
        }
        LifeCapsuleButton("修正", systemImage: "slider.horizontal.3") {
            viewModel.startEditing(item)
        }
        if !isPostponed {
            LifeCapsuleButton("後で", systemImage: "moon") {
                animate { viewModel.postpone(item) }
            }
        }
    }

    private func add() {
        if viewModel.add(newText) {
            animate { newText = "" }
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
