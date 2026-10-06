import SwiftUI

/// 習慣のリズム（直近7日の柔らかい点）。Calm Future 第3段階。
/// できた日＝明るい点、まだの日＝薄い点、始める前の日＝線の色の点。今日は細い輪で囲む。
/// 点は飾りとして VoiceOver では読まず、行のラベル（「最近、自然に続いています」など）で伝える。
struct LifeRhythmDots: View {
    let days: [HabitRhythmDay]
    var tint: Color = LifeCategoryColors.lavenderGray

    var body: some View {
        HStack(spacing: LifeSpacing.rhythmGap) {
            ForEach(days) { day in
                ZStack {
                    if day.isToday {
                        Circle()
                            .stroke(tint.opacity(LifeRhythmStyle.ringOpacity), lineWidth: LifeSpacing.timelineLine)
                            .frame(width: LifeSpacing.rhythmRing, height: LifeSpacing.rhythmRing)
                    }
                    Circle()
                        .fill(color(for: day.state))
                        .frame(width: LifeSpacing.rhythmDot, height: LifeSpacing.rhythmDot)
                }
                .frame(width: LifeSpacing.rhythmRing, height: LifeSpacing.rhythmRing)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for state: HabitRhythmDay.State) -> Color {
        switch state {
        case .done: return tint
        case .open: return tint.opacity(LifeRhythmStyle.openOpacity)
        case .inactive: return LifeColors.divider
        }
    }
}

/// 習慣の行（チェック＋タイトル＋責めない一言＋7日の点）。
/// LifeTaskRow と同じ並びにして、点をタイトルの下にそろえる。
/// 習慣は「できた日を残す」ものなので、完了でも取り消し線は付けない。
struct LifeHabitRow: View {
    let title: String
    let message: String
    let days: [HabitRhythmDay]
    let isDone: Bool
    var tint: Color = LifeCategoryColors.lavenderGray
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: LifeSpacing.sm) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? LifeColors.primary : LifeColors.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(title)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Text(message)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    LifeRhythmDots(days: days, tint: tint)
                        .padding(.top, LifeSpacing.xxs)
                }

                Spacer(minLength: LifeSpacing.xs)
            }
            .padding(.vertical, LifeSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(message)")
        .accessibilityValue(isDone ? "今日はできました" : "今日はまだ")
        .accessibilityHint("ダブルタップで、今日できたかどうかを切り替えます")
        .accessibilityAddTraits(.isButton)
    }
}

/// 習慣のリズムの見た目の数値
enum LifeRhythmStyle {
    /// まだの日の点の濃さ（警告に見えないよう、ごく薄く）
    static let openOpacity: Double = 0.22
    /// 今日の輪の濃さ
    static let ringOpacity: Double = 0.5
}

#Preview {
    let now = Date()
    let habit = Habit(
        title: "水を飲む",
        isLight: true,
        startedAt: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now,
        doneDays: [1, 2, 4, 5, 6].compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
    )
    return VStack(alignment: .leading) {
        LifeHabitRow(
            title: habit.title,
            message: HabitRhythm.message(for: habit, now: now),
            days: HabitRhythm.days(for: habit, now: now),
            isDone: false
        ) {}
    }
    .padding()
    .background(LifeColors.background)
}
