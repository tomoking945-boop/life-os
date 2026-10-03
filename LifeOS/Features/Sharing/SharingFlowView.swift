import SwiftUI
import UIKit

/// 1タップ家族招待（v2 仕様 9）。
/// 共有したい項目から開き、相手が未参加なら「LINEで共有」「リンクをコピー」を出す。
/// 「招待された側の画面を見る」で、わが家へようこそ → 共有スターターまで Mock で確認できる。
struct SharingFlowView: View {
    let item: LifeItem?
    let store: LifeStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                        Text("パートナーと共有")
                            .font(LifeTypography.editorialTitle)
                            .foregroundStyle(LifeColors.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("パートナーはまだ参加していません。招待すると、この内容から一緒に使えます。")
                            .font(LifeTypography.callout)
                            .foregroundStyle(LifeColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let sharedItem = item {
                        SharedItemPreview(item: sharedItem)
                    }

                    VStack(spacing: LifeSpacing.sm) {
                        // ShareLink は iOS の共有シートを開く。LINE が入っていれば、そこから LINE を選べる。
                        ShareLink(item: inviteText) {
                            LifeButtonLabel(title: "LINEで共有", systemImage: "bubble.left.and.bubble.right")
                        }
                        .buttonStyle(LifePressButtonStyle())

                        LifeButton(didCopy ? "コピーしました" : "リンクをコピー", systemImage: didCopy ? "checkmark" : "link", kind: .secondary) {
                            UIPasteboard.general.string = InviteMessage.mockLink
                            didCopy = true
                        }
                    }

                    Text("試作版のため、実際の招待は送られません。リンクは表示用です。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    LifeDivider()

                    NavigationLink {
                        WelcomeView(item: item, store: store) {
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text("招待された側の画面を見る（Mock）")
                                .font(LifeTypography.callout)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(LifeTypography.footnote)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(LifeColors.primary)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
            }
            .background(LifeColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
        }
    }

    private var inviteText: String {
        InviteMessage.text(inviterName: appState.profile.name, groupName: appState.profile.groupName, item: item)
    }
}

/// 共有する項目の小さなプレビュー（10/10 歯医者 など）
struct SharedItemPreview: View {
    let item: LifeItem

    var body: some View {
        HStack(alignment: .top, spacing: LifeSpacing.md) {
            RoundedRectangle(cornerRadius: LifeSpacing.categoryBar)
                .fill(item.kind.tint)
                .frame(width: LifeSpacing.categoryBar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(dateText)
                    .font(LifeTypography.editorialDate)
                    .foregroundStyle(LifeColors.primary)
                Text(item.title)
                    .font(LifeTypography.editorialHeadline)
                    .foregroundStyle(LifeColors.text)
                Text(item.kind.label)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(LifeSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: LifeRadius.card, style: .continuous)
                .fill(LifeColors.paper)
        )
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        let date = LifeFormatters.shortDate(item.displayDate)
        return item.showsTime ? "\(date) \(LifeFormatters.time(item.displayDate))" : date
    }
}

#Preview {
    let store = LifeStore()
    return SharingFlowView(item: store.items.first, store: store)
        .environment(AppState())
}
