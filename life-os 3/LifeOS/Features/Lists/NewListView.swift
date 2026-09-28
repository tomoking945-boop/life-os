import SwiftUI

/// 新規リスト作成（Mock。保存はメモリ上のみ）
struct NewListView: View {
    @Bindable var viewModel: ListsViewModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            HStack {
                Text("新しいリスト")
                    .font(LifeTypography.title)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("キャンセル") {
                    viewModel.cancelCreatingList()
                }
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.secondaryText)
                .frame(minHeight: LifeSpacing.minTapTarget)
            }

            TextField("リスト名", text: $viewModel.newListTitle)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .focused($isFieldFocused)
                .submitLabel(.done)
                .onSubmit { viewModel.createList() }
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
                .accessibilityLabel("リスト名")

            LifeButton("作成する") {
                viewModel.createList()
            }
            .disabled(!viewModel.canCreateList)

            Spacer(minLength: 0)
        }
        .padding(LifeSpacing.screenHorizontal)
        .onAppear { isFieldFocused = true }
    }
}
