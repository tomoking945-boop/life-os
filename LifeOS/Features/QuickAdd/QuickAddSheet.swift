import SwiftUI

/// なんでも追加（Bottom Sheet）。
/// Calm Future 第2段階：入力フォームではなく「生活コンソール」として見せる。
/// 入力するとその場で「LifeOSの理解」が現れ、3つの操作（提案どおり追加・そのまま預ける・詳しく整える）から選ぶ。
struct QuickAddSheet: View {
    @State private var viewModel: QuickAddViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    private let chipColumns = [
        GridItem(.flexible(), spacing: LifeSpacing.xs),
        GridItem(.flexible(), spacing: LifeSpacing.xs)
    ]

    init(store: LifeStore) {
        _viewModel = State(initialValue: QuickAddViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    header
                    inputField

                    if let understanding = viewModel.understanding {
                        understandingPanel(understanding)
                            .transition(.opacity)
                    } else {
                        examples
                    }

                    actions
                    typeSection
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
                .animation(LifeMotion.animation(LifeMotion.quick, reduceMotion: reduceMotion), value: viewModel.understanding)
            }
            .background(LifeAmbientBackground(timeOfDay: appState.ambientPreview ?? LifeTimeOfDay(date: LifeCalendar.now)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $viewModel.isShowingResults) {
                QuickAddConfirmView(viewModel: viewModel) {
                    dismiss()
                }
            }
            .alert("音声入力", isPresented: $viewModel.isShowingVoiceInputNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("音声入力はこの試作版ではまだ使えません。")
            }
            .alert("金額を入力してください", isPresented: $viewModel.isShowingAmountNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("支出は「ランチ 1200」のように、品目と金額を入力してください。")
            }
        }
    }

    // MARK: - 見出し・入力

    private var header: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Text("LIFE CONSOLE")
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            Text("なんでも追加")
                .font(LifeTypography.title)
                .foregroundStyle(LifeColors.text)
                .accessibilityAddTraits(.isHeader)
            Text("思いついたことを、そのまま。LifeOS が整えます。")
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputField: some View {
        HStack(alignment: .top, spacing: LifeSpacing.xs) {
            TextField("何でも入力してください", text: $viewModel.inputText, axis: .vertical)
                .font(LifeTypography.editorialCopy)
                .foregroundStyle(LifeColors.text)
                .lineLimit(2...5)
                .focused($isInputFocused)
                .accessibilityLabel("何でも入力してください")
            Button {
                viewModel.startVoiceInput()
            } label: {
                Image(systemName: "mic")
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("音声入力")
        }
        .padding(.leading, LifeSpacing.md)
        .padding(.vertical, LifeSpacing.xs)
        .padding(.trailing, LifeSpacing.xxs)
        .lifeGlassSurface(cornerRadius: LifeRadius.field)
    }

    /// 入力が空のときの例（押すと入力欄に入る）
    private var examples: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Text("たとえば")
                .font(LifeTypography.caption)
                .foregroundStyle(LifeColors.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LifeSpacing.xs) {
                    ForEach(QuickAddViewModel.examples, id: \.self) { example in
                        LifeCapsuleButton(example) {
                            viewModel.fillExample(example)
                        }
                        .accessibilityHint("入力欄に入れます")
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - LifeOSの理解

    private func understandingPanel(_ understanding: LifeUnderstanding) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeColors.accent)
                Text("LifeOSの理解")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
            }

            Text(understanding.headline)
                .font(LifeTypography.editorialHeadline)
                .foregroundStyle(LifeColors.text)

            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                ForEach(understanding.titles, id: \.self) { title in
                    Text(title)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                }
            }

            HStack(spacing: LifeSpacing.xs) {
                Text(viewModel.understandingTiming ?? "")
                if appState.usageStyle.showsScopeFilter, let ownershipText = understanding.ownershipText {
                    Text("・")
                        .accessibilityHidden(true)
                    Text(ownershipText)
                }
            }
            .font(LifeTypography.callout)
            .foregroundStyle(LifeColors.primary)

            Text(understanding.reason)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LifeSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.suggestion)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 3つの操作

    private var actions: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeButton(viewModel.addAsSuggestedTitle, systemImage: "checkmark") {
                isInputFocused = false
                if viewModel.addAsSuggested(usageStyle: appState.usageStyle) {
                    dismiss()
                }
            }
            .disabled(!viewModel.canAddAsSuggested)

            LifeButton("そのまま預ける", systemImage: "tray.and.arrow.down", kind: .secondary) {
                isInputFocused = false
                if viewModel.saveToInbox() {
                    dismiss()
                }
            }
            .disabled(!viewModel.canQuickAdd)
            .accessibilityHint("分類や日時を決めずに Inbox へ入れます")

            if viewModel.canRefine {
                LifeButton("詳しく整える", systemImage: "slider.horizontal.3", kind: .secondary) {
                    isInputFocused = false
                    viewModel.refine(usageStyle: appState.usageStyle)
                }
            }

            Text(viewModel.understanding == nil
                 ? "そのまま預けると Inbox に入り、あとでまとめて整理できます。入力が空のまま「詳しく整える」を押すと、整理の例を表示します。"
                 : "そのまま預けると、分類や日時は決めずに Inbox に入ります。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 種類を決めて追加（これまでの「すぐ追加」）

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeDivider()
            Text("種類を決めて追加")
                .font(LifeTypography.label)
                .tracking(LifeTypography.labelTracking)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: chipColumns, spacing: LifeSpacing.xs) {
                ForEach(QuickAddType.allCases) { type in
                    LifeChip(title: type.label, systemImage: type.systemImage) {
                        isInputFocused = false
                        if viewModel.quickAdd(type) {
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canQuickAdd)
                    .opacity(viewModel.canQuickAdd ? 1 : 0.4)
                    .accessibilityHint("入力した内容を\(type.label)として今日に追加します")
                }
            }
            Text("整理せずに、選んだ種類でそのまま今日に追加します。支出は「ランチ 1200」のように金額も入力してください。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Text("")
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(store: LifeStore())
                .presentationDetents([.medium, .large])
        }
        .environment(AppState())
}
