import SwiftUI

/// 「リスト」画面の「大切な書類」（spec 3）。通常のリストより上に小さく置く
struct ImportantDocumentsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    private var now: Date { LifeCalendar.now }

    private var access: WarrantyAccess {
        WarrantyAccess.resolve(isPremium: appState.isPremium, hasSavedDocuments: !store.warranties.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack {
                Text("大切な書類")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Premium")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.text)
                    .padding(.horizontal, LifeSpacing.xs)
                    .padding(.vertical, LifeSpacing.xxs)
                    .background(Capsule().fill(LifeColors.accentSubtle))
            }

            NavigationLink(value: WarrantyRoute.list) {
                HStack(alignment: .center, spacing: LifeSpacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundStyle(LifeColors.primary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                        Text("保証書")
                            .font(LifeTypography.editorialHeadline)
                            .foregroundStyle(LifeColors.text)
                        Text(subtitle)
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: LifeSpacing.xs)
                    if access != .locked {
                        Text("\(store.warranties.count)件")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    Image(systemName: "chevron.right")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(LifeSpacing.md)
                .frame(minHeight: LifeSpacing.minTapTarget)
                .contentShape(Rectangle())
                .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(access == .locked ? "保証書の管理について説明を表示します" : "保証書の一覧を開きます")
        }
    }

    private var subtitle: String {
        switch access {
        case .locked:
            return "保証書を、探さなくていい場所へ"
        case .full, .readOnly:
            let prefix = access == .readOnly ? "閲覧のみ・" : ""
            if let next = WarrantyExpiration.nextExpiring(store.warranties, now: now) {
                return "\(prefix)次の期限：\(next.title)　\(WarrantyExpiration.remainingText(for: next, now: now))"
            }
            return prefix.isEmpty ? "保証期限と保管場所を記録" : "閲覧のみ"
        }
    }
}

/// 「今日」画面の小さな案内（spec 9）：保証終了まで30日以内の保証書があるときだけ
struct WarrantyTodayNotice: View {
    let document: WarrantyDocument
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: LifeCategoryColors.warmGold)
                Text("大切な書類")
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .accessibilityHidden(true)

            NavigationLink(value: WarrantyRoute.detail(document.id)) {
                HStack(spacing: LifeSpacing.sm) {
                    VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                        Text(message)
                            .font(LifeTypography.editorialHeadline)
                            .foregroundStyle(LifeColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("購入店と保証書を確認")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    Spacer(minLength: LifeSpacing.xs)
                    Image(systemName: "chevron.right")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, LifeSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("保証書の詳細を開きます")

            NavigationLink(value: WarrantyRoute.list) {
                Text("すべて見る")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.primary)
                    .frame(minHeight: LifeSpacing.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityHint("保証書の一覧を開きます")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("大切な書類")
    }

    /// 「冷蔵庫の保証があと28日です」
    private var message: String {
        let days = document.warrantyExpiresAt.map { WarrantyExpiration.daysRemaining(until: $0, now: now) } ?? 0
        return days == 0 ? "\(document.title)の保証は今日までです" : "\(document.title)の保証があと\(days)日です"
    }
}

#if DEBUG
#Preview("リストの入口") {
    NavigationStack {
        ImportantDocumentsSection()
            .padding()
            .warrantyDestinations()
    }
    .environment(WarrantyPreviewData.appState(plan: .premium))
    .environment(WarrantyPreviewData.store())
}

#Preview("今日の案内") {
    let store = WarrantyPreviewData.store()
    return NavigationStack {
        WarrantyTodayNotice(document: store.warranties[0], now: LifeCalendar.now)
            .padding()
    }
}
#endif
