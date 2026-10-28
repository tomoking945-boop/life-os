import SwiftUI

/// 共有の保存がうまくいかなかったときのお知らせ（2026-10-28 Build 9）。
/// 例：「共有できなかったため、自分だけに保存しました（権限がありません）。」
/// 以前は SharedItemsService がお知らせを作っても、どの画面にも出していなかった（項目が黙って「自分だけ」に移り、消えたように見えた）
struct SharedSyncNoticeBanner: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: LifeSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.accent)
                .accessibilityHidden(true)
            Text(message)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LifeSpacing.xs)
            Button("閉じる", action: onClose)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.primary)
                .frame(minHeight: LifeSpacing.minTapTarget)
        }
        .padding(.horizontal, LifeSpacing.md)
        .padding(.vertical, LifeSpacing.xs)
        .lifeGlassSurface(cornerRadius: LifeRadius.field)
        .padding(.horizontal, LifeSpacing.screenHorizontal)
        .accessibilityElement(children: .combine)
    }
}
