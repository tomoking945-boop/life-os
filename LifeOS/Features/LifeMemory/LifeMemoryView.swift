import Observation
import SwiftUI

@Observable
final class LifeMemoryViewModel {
    private let store: LifeStore
    private let now: Date

    init(store: LifeStore, now: Date = LifeCalendar.now) {
        self.store = store
        self.now = now
    }

    var memories: [LifeMemory] { store.memories }

    func cycleText(_ memory: LifeMemory) -> String {
        LifeMemoryEvaluator.cycleText(memory, now: now)
    }

    func statusText(_ memory: LifeMemory) -> String {
        LifeMemoryEvaluator.isDue(memory, now: now) ? LifeMemoryEvaluator.message(memory, now: now) : "まだ大丈夫です"
    }

    func isDue(_ memory: LifeMemory) -> Bool {
        LifeMemoryEvaluator.isDue(memory, now: now)
    }
}

/// 暮らしメモリーの一覧（生活の周期・忘れやすいこと）
/// TODO: メモリーの追加・編集・削除、周期の自動学習は未実装（Mock 表示のみ）。
struct LifeMemoryView: View {
    @State private var viewModel: LifeMemoryViewModel

    init(store: LifeStore) {
        _viewModel = State(initialValue: LifeMemoryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text("暮らしメモリー")
                        .font(LifeTypography.display)
                        .foregroundStyle(LifeColors.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("生活の周期や、忘れやすいことを覚えておきます。")
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LifeCard(padding: LifeSpacing.md) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.memories.enumerated()), id: \.element.id) { index, memory in
                            if index > 0 {
                                LifeDivider()
                            }
                            HStack(alignment: .top, spacing: LifeSpacing.sm) {
                                Image(systemName: viewModel.isDue(memory) ? "bell" : "checkmark.circle")
                                    .foregroundStyle(viewModel.isDue(memory) ? LifeColors.accent : LifeColors.secondaryText)
                                    .frame(width: LifeSpacing.lg)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                                    Text(memory.title)
                                        .font(LifeTypography.bodyEmphasis)
                                        .foregroundStyle(LifeColors.text)
                                    Text(viewModel.cycleText(memory))
                                        .font(LifeTypography.footnote)
                                        .foregroundStyle(LifeColors.secondaryText)
                                    Text(viewModel.statusText(memory))
                                        .font(LifeTypography.callout)
                                        .foregroundStyle(LifeColors.text)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, LifeSpacing.xs)
                            .padding(.vertical, LifeSpacing.sm)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("暮らしメモリー")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}

#Preview {
    NavigationStack {
        LifeMemoryView(store: LifeStore())
    }
    .environment(AppState())
}
