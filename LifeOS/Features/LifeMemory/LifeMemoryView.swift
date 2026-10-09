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

    // MARK: - 記録（Calm Future 第3段階）

    /// 前回（例：前回 8/19（水）・妻）。記録もルールの日付も無ければ nil。
    func lastText(_ memory: LifeMemory, profile: UserProfile) -> String? {
        guard let last = LifeMemoryEvaluator.lastDate(memory) else { return nil }
        var text = "前回 \(LifeFormatters.shortDate(last))"
        let latest = (memory.history ?? []).max(by: { $0.date < $1.date })
        if let latest, LifeCalendar.isSameDay(latest.date, last), let by = latest.by {
            text += "・\(profile.displayName(for: by))"
        }
        return text
    }

    /// 平均周期（例：平均 約6週間ごと）。記録が2件以上あるときだけ。
    func averageText(_ memory: LifeMemory) -> String? {
        guard let days = LifeMemoryEvaluator.averageCycleDays(memory) else { return nil }
        return "平均 約\(LifeMemoryEvaluator.elapsedText(days: days))ごと"
    }

    /// 次に必要になりそうな時期（例：次の目安 9/30（水）ごろ）
    func nextText(_ memory: LifeMemory) -> String? {
        guard let next = LifeMemoryEvaluator.nextExpectedDate(memory, now: now) else { return nil }
        if case .sinceLast(_, _) = memory.rule {
            return next <= LifeCalendar.startOfDay(now) ? "次の目安 もうその頃です" : "次の目安 \(LifeFormatters.shortDate(next))ごろ"
        }
        return "次は \(LifeFormatters.shortDate(next))"
    }

    /// 季節による変化（例：冷暖房を使う季節（6〜9月・12〜2月）は30日ごと）
    func seasonText(_ memory: LifeMemory) -> String? {
        guard let seasonal = memory.seasonal else { return nil }
        let current = LifeMemoryEvaluator.isInSeason(seasonal, now: now) ? "・今はこの周期です" : ""
        return "\(seasonal.note)は\(seasonal.dueAfterDays)日ごと\(current)"
    }

    /// 提案を採用／スキップした履歴（例：提案を2回使いました・1回スキップ）
    func decisionText(_ memory: LifeMemory) -> String? {
        LifeMemoryEvaluator.decisionSummary(memory)
    }

    /// 細い線で並べる補足（前回・平均・次の目安・季節・提案の履歴）
    func recordLines(_ memory: LifeMemory, profile: UserProfile) -> [String] {
        [
            lastText(memory, profile: profile),
            averageText(memory),
            nextText(memory),
            seasonText(memory),
            decisionText(memory)
        ].compactMap { $0 }
    }
}

/// 暮らしメモリーの一覧（生活の周期・忘れやすいこと）
/// TODO: メモリーの追加・編集・削除、周期の自動学習は未実装（Mock 表示のみ）。
/// Calm Future 第3段階：前回・誰が対応したか・平均周期・次の目安・季節・提案の履歴を表示する（記録は端末内に保存）。
struct LifeMemoryView: View {
    @State private var viewModel: LifeMemoryViewModel
    @Environment(AppState.self) private var appState

    init(store: LifeStore) {
        _viewModel = State(initialValue: LifeMemoryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(
                    eyebrow: "MEMORY",
                    title: "暮らしメモリー",
                    subtitle: "生活の周期や、忘れやすいことを覚えておきます。"
                )

                if viewModel.memories.isEmpty {
                    // はじめての設定（2026-10-09）：新しく使い始める人は空から始まる
                    LifeEmptyState(systemImage: "clock.arrow.circlepath", title: "まだ覚えていることはありません")
                        .frame(maxWidth: .infinity)
                        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                }

                // Calm Future 第4段階：カードに入れず、細い線で区切る
                LifeRuledList(viewModel.memories) { memory in
                    HStack(alignment: .top, spacing: LifeSpacing.sm) {
                        Image(systemName: viewModel.isDue(memory) ? "bell" : "checkmark.circle")
                            .foregroundStyle(viewModel.isDue(memory) ? LifeColors.accent : LifeColors.secondaryText)
                            .frame(width: LifeSpacing.lg)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                            Text(memory.title)
                                .font(LifeTypography.editorialHeadline)
                                .foregroundStyle(LifeColors.text)
                            Text(viewModel.cycleText(memory))
                                .font(LifeTypography.footnote)
                                .foregroundStyle(LifeColors.secondaryText)
                            Text(viewModel.statusText(memory))
                                .font(LifeTypography.callout)
                                .foregroundStyle(LifeColors.text)
                            // 第3段階：前回・誰が対応したか・平均周期・次の目安・季節・提案の履歴
                            ForEach(viewModel.recordLines(memory, profile: appState.profile), id: \.self) { line in
                                Text(line)
                                    .font(LifeTypography.caption)
                                    .foregroundStyle(LifeColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, LifeSpacing.xxs)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, LifeSpacing.xs)
                    .padding(.vertical, LifeSpacing.md)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
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
