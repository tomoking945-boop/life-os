import SwiftUI

/// なんでも追加（Bottom Sheet）
struct QuickAddSheet: View {
    @State private var viewModel: QuickAddViewModel
    @Environment(\.dismiss) private var dismiss
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
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        Text("なんでも追加")
                            .font(LifeTypography.title)
                            .foregroundStyle(LifeColors.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("何でも入力してください")
                            .font(LifeTypography.callout)
                            .foregroundStyle(LifeColors.secondaryText)
                    }

                    inputField

                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        LifeButton("とりあえず保存", systemImage: "tray.and.arrow.down", kind: .secondary) {
                            isInputFocused = false
                            if viewModel.saveToInbox() {
                                dismiss()
                            }
                        }
                        .disabled(!viewModel.canQuickAdd)
                        Text("分類や日時は決めずにInboxへ。あとでまとめて整理できます。")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LifeButton("音声入力", systemImage: "mic", kind: .secondary) {
                        viewModel.startVoiceInput()
                    }

                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        LifeSectionTitle("すぐ追加")
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
                        Text("入力してから押すと、整理せずにそのまま追加します。支出は「ランチ 1200」のように金額も入力してください。")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LifeButton("整理する", systemImage: "sparkles") {
                        isInputFocused = false
                        viewModel.organize()
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
            }
            .background(LifeColors.background.ignoresSafeArea())
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

    private var inputField: some View {
        TextField("入力欄", text: $viewModel.inputText, axis: .vertical)
            .font(LifeTypography.body)
            .foregroundStyle(LifeColors.text)
            .lineLimit(3...6)
            .focused($isInputFocused)
            .padding(LifeSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                    .fill(LifeColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                    .stroke(LifeColors.divider, lineWidth: 1)
            )
            .accessibilityLabel("何でも入力してください")
    }
}

#Preview {
    Text("")
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(store: LifeStore())
                .presentationDetents([.medium, .large])
        }
}
