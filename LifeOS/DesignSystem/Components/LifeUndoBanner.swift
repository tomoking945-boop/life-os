import SwiftUI
import UIKit

/// 操作のあとに静かに現れる一言と「元に戻す」（Calm Future）。
/// すりガラスの面に浮かべる。強い色・警告色は使わない。
/// `onUndo` が nil のときは一言だけを出す。
struct LifeUndoBanner: View {
    let message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: LifeSpacing.sm) {
            Image(systemName: "checkmark")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.primary)
                .accessibilityHidden(true)
            Text(message)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LifeSpacing.xs)
            if let onUndo {
                Button(action: onUndo) {
                    Text("元に戻す")
                        .font(LifeTypography.footnoteEmphasis)
                        .foregroundStyle(LifeColors.primary)
                        .padding(.horizontal, LifeSpacing.sm)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("直前の操作を取り消します")
            }
        }
        .padding(.leading, LifeSpacing.md)
        .padding(.trailing, onUndo == nil ? LifeSpacing.md : LifeSpacing.xxs)
        .padding(.vertical, LifeSpacing.xxs)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .lifeGlassSurface(cornerRadius: LifeRadius.medium)
        .accessibilityElement(children: .contain)
    }
}

/// 一言と「元に戻す」を画面上部に浮かべ、数秒で消す（Calm Future）。
/// VoiceOver では一言を読み上げる。Reduce Motion のときはフェードだけにする。
private struct LifeFeedbackBannerModifier: ViewModifier {
    @Binding var feedback: LifeFeedback?
    let onUndo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current = feedback {
                    LifeUndoBanner(
                        message: current.message,
                        onUndo: current.undo == nil ? nil : {
                            withLifeAnimation(reduceMotion: reduceMotion) { onUndo() }
                        }
                    )
                    .padding(.horizontal, LifeSpacing.screenHorizontal)
                    .padding(.top, LifeSpacing.xs)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
                }
            }
            .task(id: feedback) {
                guard let current = feedback else { return }
                UIAccessibility.post(notification: .announcement, argument: current.message)
                let seconds = current.undo == nil ? LifeMotion.bannerSeconds : LifeMotion.undoBannerSeconds
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withLifeAnimation(reduceMotion: reduceMotion) { feedback = nil }
            }
    }
}

extension View {
    /// 操作のあとの一言と「元に戻す」を表示する
    func lifeFeedbackBanner(_ feedback: Binding<LifeFeedback?>, onUndo: @escaping () -> Void) -> some View {
        modifier(LifeFeedbackBannerModifier(feedback: feedback, onUndo: onUndo))
    }
}

#Preview {
    VStack(spacing: LifeSpacing.md) {
        LifeUndoBanner(message: "「ゴミ出し」を明日に回しました") {}
        LifeUndoBanner(message: "元に戻しました")
    }
    .padding()
    .background(LifeAmbientBackground(timeOfDay: .morning))
}
