import SwiftUI

/// 左へスワイプすると、赤い「削除」が出る行（2026-11-01 Build 13。カレンダーの予定の削除）。
/// 一覧が List ではない（ScrollView の中の細い線の一覧）ため、横のドラッグだけを受け取る。
/// 「削除」を押しても、すぐには消さない（onDelete で確認を出す）
struct LifeSwipeDeleteRow<Content: View>: View {
    private let title: String
    private let onDelete: () -> Void
    private let content: Content

    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 「削除」の幅
    private let buttonWidth: CGFloat = 88

    init(title: String = "削除", onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) {
                    close()
                    onDelete()
                } label: {
                    Text(title)
                        .font(LifeTypography.bodyEmphasis)
                        .foregroundStyle(Color.white)
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            content
                .background(LifeColors.background)
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // 横の動きのときだけ（縦のスクロールは邪魔しない）
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-buttonWidth, value.translation.width + (offset < 0 ? -buttonWidth : 0)))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
                                offset = value.translation.width < -buttonWidth / 2 ? -buttonWidth : 0
                            }
                        }
                )
                .onTapGesture {
                    if offset < 0 { close() }
                }
        }
        .clipped()
    }

    private func close() {
        withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) {
            offset = 0
        }
    }
}
