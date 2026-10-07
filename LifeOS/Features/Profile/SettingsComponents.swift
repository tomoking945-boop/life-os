import SwiftUI

/// 設定画面の共通レイアウト（背景・余白・タイトル・なんでも追加）
struct SettingsScreen<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                content
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
    }
}

/// 名前などを入力する欄。入力を確定（完了 / 画面を離れる）したときに onCommit を呼ぶ。
struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle(label)
            TextField(label, text: $text)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .submitLabel(.done)
                .onSubmit(onCommit)
                .padding(LifeSpacing.md)
                .frame(minHeight: LifeSpacing.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                        .fill(LifeColors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                        .stroke(LifeColors.divider, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

/// 値を表示するだけの行（例：テーマ　ライト）
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: LifeSpacing.sm) {
            Text(title)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
            Spacer(minLength: LifeSpacing.xs)
            Text(value)
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, LifeSpacing.xs)
        .frame(minHeight: LifeSpacing.buttonHeight)
        .accessibilityElement(children: .combine)
    }
}

/// ON/OFF スイッチの行
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
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
        }
        .tint(LifeColors.primary)
        .padding(.horizontal, LifeSpacing.xs)
        .frame(minHeight: LifeSpacing.buttonHeight)
    }
}

/// 設定画面の注記
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LifeTypography.footnote)
            .foregroundStyle(LifeColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
