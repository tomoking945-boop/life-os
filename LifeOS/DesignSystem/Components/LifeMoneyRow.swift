import SwiftUI

/// 金額の行（今日 ¥3,520 など）
struct LifeMoneyRow: View {
    let title: String
    let amount: Int
    var detail: String?
    var isEmphasized: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(title)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                if let detail {
                    Text(detail)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
            Spacer(minLength: LifeSpacing.xs)
            Text(LifeFormatters.yen(amount))
                .font(isEmphasized ? LifeTypography.amountLarge : LifeTypography.amount)
                .foregroundStyle(LifeColors.text)
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail, LifeFormatters.yenSpoken(amount)].compactMap { $0 }.joined(separator: "、"))
    }
}

#Preview {
    VStack {
        LifeMoneyRow(title: "今日", amount: 3520)
        LifeMoneyRow(title: "今月", amount: 82450, isEmphasized: true)
        LifeMoneyRow(title: "スーパー", amount: 3520, detail: "食費・9/25（金）")
    }
    .padding()
    .background(LifeColors.background)
}
