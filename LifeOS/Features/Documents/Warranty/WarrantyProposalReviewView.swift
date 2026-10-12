import SwiftUI

/// 読み取り結果の確認（spec 4）
/// - 候補は目安。利用者が確認・修正して「候補を反映」を押したときだけ入力欄に入る（それまで保証書は変わらない）
/// - 入力済みの項目は上書きしない
/// - 複数の候補・信頼度が低い項目は「確認が必要」
/// - 読み取った文字は表示するだけで保存しない
struct WarrantyProposalReviewView: View {
    private let recognizedText: String
    private let draft: WarrantyDraft
    private let onApply: (WarrantyExtractionProposal, Set<WarrantyFieldKind>) -> Void
    private let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fields: [WarrantyExtractedField]
    @State private var selected: Set<WarrantyFieldKind>

    init(
        proposal: WarrantyExtractionProposal,
        draft: WarrantyDraft,
        onApply: @escaping (WarrantyExtractionProposal, Set<WarrantyFieldKind>) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        recognizedText = proposal.recognizedText
        self.draft = draft
        self.onApply = onApply
        self.onDiscard = onDiscard
        _fields = State(initialValue: proposal.fields)
        _selected = State(initialValue: Set(proposal.fields.map(\.kind).filter { !draft.isFilled($0) }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    SettingsNote(text: "写真の文字から見つけた候補です。読み間違いがあるため、確認・修正してから反映してください。保証が有効かどうかは、保証書の原本で確かめてください。")

                    LifeGroupedSection {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(fields.indices, id: \.self) { index in
                                if index > 0 { LifeDivider() }
                                row($fields[index])
                            }
                        }
                    }

                    DisclosureGroup("読み取った文字（保存しません）") {
                        Text(recognizedText.isEmpty ? "（文字はありませんでした）" : recognizedText)
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, LifeSpacing.xs)
                    }
                    .font(LifeTypography.callout)
                    .tint(LifeColors.primary)

                    VStack(spacing: LifeSpacing.sm) {
                        LifeButton("候補を反映", systemImage: "checkmark") {
                            onApply(WarrantyExtractionProposal(recognizedText: recognizedText, fields: fields), selected)
                            dismiss()
                        }
                        .disabled(selected.isEmpty)
                        LifeButton("反映しない", kind: .secondary) {
                            onDiscard()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.screenVertical)
            }
            .lifeScreenBackground()
            .navigationTitle("読み取り結果の確認")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func row(_ field: Binding<WarrantyExtractedField>) -> some View {
        let kind = field.wrappedValue.kind
        let isFilled = draft.isFilled(kind)
        return VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Toggle(isOn: Binding(
                get: { selected.contains(kind) },
                set: { isOn in
                    if isOn { selected.insert(kind) } else { selected.remove(kind) }
                }
            )) {
                HStack(spacing: LifeSpacing.xs) {
                    Text(kind.label)
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                    if field.wrappedValue.needsReview {
                        Text("確認が必要")
                            .font(LifeTypography.caption)
                            .foregroundStyle(LifeColors.text)
                            .padding(.horizontal, LifeSpacing.xs)
                            .padding(.vertical, LifeSpacing.xxs)
                            .background(Capsule().fill(LifeColors.accentSubtle))
                    }
                }
            }
            .tint(LifeColors.primary)
            .disabled(isFilled)

            TextField(kind.label, text: field.value)
                .font(LifeTypography.body)
                .padding(LifeSpacing.sm)
                .background(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).fill(LifeColors.surface))
                .overlay(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).stroke(LifeColors.divider, lineWidth: 1))
                .disabled(isFilled)
                .accessibilityLabel("\(kind.label)の候補")

            if isFilled {
                Text("入力済みのため反映しません")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            } else if kind == .purchaseDate || kind == .warrantyExpiresAt {
                Text("日付は 2026/10/13 の形で入力してください")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            }

            if !field.wrappedValue.alternatives.isEmpty && !isFilled {
                Menu {
                    ForEach([field.wrappedValue.value] + field.wrappedValue.alternatives, id: \.self) { candidate in
                        Button(candidate) {
                            let all = [field.wrappedValue.value] + field.wrappedValue.alternatives
                            field.wrappedValue.value = candidate
                            field.wrappedValue.alternatives = all.filter { $0 != candidate }
                        }
                    }
                } label: {
                    Label("ほかの候補（\(field.wrappedValue.alternatives.count)）", systemImage: "list.bullet")
                        .font(LifeTypography.callout)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                }
                .tint(LifeColors.primary)
            }
        }
        .padding(.vertical, LifeSpacing.sm)
    }
}

#if DEBUG
#Preview {
    let proposal = WarrantyFieldExtractor.extract(from: [
        WarrantyRecognizedLine(text: "保証書"),
        WarrantyRecognizedLine(text: "品名 冷蔵庫"),
        WarrantyRecognizedLine(text: "型番 AB-123"),
        WarrantyRecognizedLine(text: "お買上げ日 2026年10月13日"),
        WarrantyRecognizedLine(text: "保証期間 お買上げ日より1年間"),
        WarrantyRecognizedLine(text: "2026/10/20", confidence: 0.3)
    ])
    var draft = WarrantyDraft()
    draft.title = "冷蔵庫（入力済み）"
    return WarrantyProposalReviewView(proposal: proposal, draft: draft, onApply: { _, _ in }, onDiscard: {})
}
#endif
