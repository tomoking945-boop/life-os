import SwiftUI

/// 商品の購入履歴（2026-11-10 Build 23。docs/BUILD_23_EXPENSE_SEARCH_AND_PRICE_HISTORY.md）。
///
/// - 整えた商品名が同じ明細だけをまとめる（「牛乳」と「低脂肪牛乳」は別の商品）
/// - 表示している範囲（すべて／自分／共有）の支出だけ。1件ずつ「自分だけ／わが家で共有」を文字で出す
/// - 過去の参考価格（最新・最安・最高・前回との差）は、単価を比べられる購入記録だけで出す。
///   どちらがお得かは決めない・購入をすすめない（内容量・単位を記録していないため）
/// - 開くたびに今の支出と明細から作る（保存しない。明細を直す・消すと、すぐに反映される）
struct ProductPurchaseHistoryView: View {
    let viewModel: MoneyViewModel
    let target: ProductHistoryTarget

    var body: some View {
        let history = viewModel.purchaseHistory(for: target)
        Form {
            Section {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    Text(history.name)
                        .font(LifeTypography.title)
                        .foregroundStyle(LifeColors.text)
                    Text("購入 \(history.purchaseCount)回")
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    if let latest = history.latestDate {
                        Text("最新の購入 \(LifeFormatters.dateWithYear(latest))")
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    Text("対象：\(viewModel.historyScopeText)")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                .padding(.vertical, LifeSpacing.xxs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headerSpokenLabel(history))
            }

            Section {
                if let summary = history.summary {
                    summaryRows(summary)
                } else if !history.records.isEmpty {
                    Label(PurchaseHistory.unitPriceUnavailableMessage, systemImage: "info.circle")
                        .foregroundStyle(LifeColors.text)
                        .accessibilityLabel(PurchaseHistory.unitPriceUnavailableMessage)
                }
            } header: {
                Text("過去の購入記録（参考価格）")
            } footer: {
                Text(PurchaseHistory.referenceNote)
            }

            Section {
                if history.records.isEmpty {
                    Text("この商品の購入記録はありません")
                        .foregroundStyle(LifeColors.secondaryText)
                } else {
                    ForEach(history.records) { record in
                        recordRow(record)
                    }
                }
            } header: {
                Text("購入ごとの記録（新しい順）")
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .scrollContentBackground(.hidden)
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("購入履歴")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 要約

    @ViewBuilder
    private func summaryRows(_ summary: PurchasePriceSummary) -> some View {
        priceRow(title: "最新の参考価格", record: summary.latest)
        if let lowest = summary.lowest {
            priceRow(title: "これまでの最安（参考）", record: lowest)
        }
        if let highest = summary.highest {
            priceRow(title: "これまでの最高（参考）", record: highest)
        }
        if let difference = summary.differenceFromPrevious, let previous = summary.previous {
            let text = Self.differenceText(difference)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                    Text("前回との差")
                        .foregroundStyle(LifeColors.text)
                    Spacer(minLength: LifeSpacing.xs)
                    Text(text)
                        .font(LifeTypography.amount)
                        .foregroundStyle(LifeColors.text)
                        .multilineTextAlignment(.trailing)
                }
                Text("前回：\(previous.storeName)・\(LifeFormatters.dateWithYear(previous.date))")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .frame(minHeight: LifeSpacing.minTapTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("前回との差 \(text)、前回 \(previous.storeName) \(LifeFormatters.spokenDate(previous.date))")
        }
        if summary.comparedCount < 2 {
            Text("比べられる購入記録が1件のため、最安・最高・前回との差は出していません。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
        if summary.excludedCount > 0 {
            Text("単価が分からない購入記録 \(summary.excludedCount)件は、比べていません。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
        if summary.usesReferencePrice {
            Text("「参考単価」は、商品の金額を数量で割って計算した値です（1円未満は四捨五入）。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
    }

    private func priceRow(title: String, record: PurchaseRecord) -> some View {
        let price = record.price
        let priceText = price.map { "\(LifeFormatters.yen($0.yen))（\(Self.basisLabel($0.basis))）" } ?? "—"
        return VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                Text(title)
                    .foregroundStyle(LifeColors.text)
                Spacer(minLength: LifeSpacing.xs)
                Text(priceText)
                    .font(LifeTypography.amount)
                    .foregroundStyle(LifeColors.text)
                    .multilineTextAlignment(.trailing)
            }
            Text("\(record.storeName)・\(LifeFormatters.dateWithYear(record.date))")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title) \(price.map { "\(Self.basisLabel($0.basis)) \(LifeFormatters.yenSpoken($0.yen))" } ?? "なし")、\(record.storeName) \(LifeFormatters.spokenDate(record.date))"
        )
    }

    // MARK: - 購入ごとの記録

    /// 日付・店名・自分だけ／共有（文字）・商品の金額（右寄せ）。数量・単価・参考単価は補助の行
    private func recordRow(_ record: PurchaseRecord) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(LifeFormatters.dateWithYear(record.date))
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    Text(record.storeName)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: LifeSpacing.xs)
                Text(LifeFormatters.yen(record.amount))
                    .font(LifeTypography.amount)
                    .foregroundStyle(LifeColors.text)
            }
            HStack(spacing: LifeSpacing.xxs) {
                if record.ownership == .shared {
                    HouseholdSharedMark()
                }
                Text(Self.ownershipLabel(record.ownership))
                Text("・")
                Text(Self.quantityAndPriceText(record))
            }
            .font(LifeTypography.footnote)
            .foregroundStyle(LifeColors.secondaryText)
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(record))
    }

    private func headerSpokenLabel(_ history: ProductPurchaseHistory) -> String {
        var parts = [history.name, "購入 \(history.purchaseCount)回"]
        if let latest = history.latestDate { parts.append("最新の購入 \(LifeFormatters.spokenDate(latest))") }
        parts.append("対象 \(viewModel.historyScopeText)")
        return parts.joined(separator: "、")
    }

    // MARK: - 文言（テストでも確かめる）

    static func ownershipLabel(_ ownership: Ownership) -> String {
        ownership == .shared ? "わが家で共有" : "自分だけ"
    }

    static func basisLabel(_ basis: PurchasePrice.Basis) -> String {
        basis == .unitPrice ? "単価" : "参考単価"
    }

    /// 前回との差（「前回より ¥20 高い」「前回より ¥20 安い」「前回と同じ」。どれも参考）
    static func differenceText(_ difference: Int) -> String {
        if difference > 0 { return "前回より \(LifeFormatters.yen(difference)) 高い" }
        if difference < 0 { return "前回より \(LifeFormatters.yen(-difference)) 安い" }
        return "前回と同じ"
    }

    /// 「数量 2・単価 ¥120」「数量 1.5・参考単価 ¥132」「数量・単価は分かりません」（spoken は VoiceOver 用の「120円」）
    static func quantityAndPriceText(_ record: PurchaseRecord, spoken: Bool = false) -> String {
        let yen: (Int) -> String = spoken ? LifeFormatters.yenSpoken : LifeFormatters.yen
        var parts: [String] = []
        if let quantity = record.quantity { parts.append("数量 \(ExpenseLineItemRules.text(for: quantity))") }
        if let price = record.price {
            parts.append("\(basisLabel(price.basis)) \(yen(price.yen))")
        } else if let unitPrice = record.unitPrice {
            parts.append("単価 \(yen(unitPrice))（比べていません）")
        }
        return parts.isEmpty ? "数量・単価は分かりません" : parts.joined(separator: spoken ? "、" : "・")
    }

    static func spokenLabel(_ record: PurchaseRecord) -> String {
        [
            LifeFormatters.spokenDate(record.date),
            record.storeName,
            ownershipLabel(record.ownership),
            "金額 \(LifeFormatters.yenSpoken(record.amount))",
            quantityAndPriceText(record, spoken: true)
        ].joined(separator: "、")
    }
}
