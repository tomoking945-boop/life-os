import SwiftUI
import UIKit

/// チェックできるタスク行。
/// 完了状態はアイコンの形と取り消し線でも示し、色だけに依存しない。
struct LifeTaskRow: View {
    let title: String
    var detail: String?
    var trailing: String?
    var assigneeName: String?
    var assigneeImage: UIImage?
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: LifeSpacing.sm) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? LifeColors.primary : LifeColors.secondaryText)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(title)
                        .font(LifeTypography.body)
                        .foregroundStyle(isCompleted ? LifeColors.secondaryText : LifeColors.text)
                        .strikethrough(isCompleted, color: LifeColors.secondaryText)
                    if let detail {
                        Text(detail)
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                }

                Spacer(minLength: LifeSpacing.xs)

                if let trailing {
                    Text(trailing)
                        .font(LifeTypography.caption)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                if let assigneeName {
                    LifeAvatar(name: assigneeName, image: assigneeImage, size: .small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail, trailing].compactMap { $0 }.joined(separator: "、"))
        .accessibilityValue(isCompleted ? "完了" : "未完了")
        .accessibilityHint("ダブルタップで完了と未完了を切り替えます")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack {
        LifeTaskRow(title: "牛乳を買う", detail: "担当：どちらでも", isCompleted: false) {}
        LifeTaskRow(title: "電気代を払う", detail: "担当：自分", assigneeName: "池上", isCompleted: true) {}
    }
    .padding()
    .background(LifeColors.background)
}
