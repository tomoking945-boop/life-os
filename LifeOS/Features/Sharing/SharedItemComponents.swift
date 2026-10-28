import SwiftUI

// わが家で共有する ToDo・買い物の小さな部品（2026-10-28。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）

/// わが家で共有している項目の小さな印（色だけに頼らず、読み上げでも伝える）
struct HouseholdSharedMark: View {
    static let label = "わが家で共有"

    var body: some View {
        Image(systemName: "person.2.fill")
            .font(LifeTypography.caption)
            .foregroundStyle(LifeColors.primary)
            .accessibilityLabel(Self.label)
    }
}

/// 保存先を選ぶ（自分だけ／わが家で共有）。初期値は呼ぶ側で必ず「自分だけ」にする
struct SaveDestinationPicker: View {
    @Binding var selection: SaveDestination
    var note: String = "わが家で共有にできるのは ToDo・買い物だけです。予定などは自分だけに保存します。"

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle("保存先")
            LifeSegmentControl(SaveDestination.allCases, selection: $selection) { $0.title }
            Text(note)
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// ToDo・買い物の編集（名前・保存先・削除）。2026-10-28
///
/// - 自分だけの項目は「わが家で共有」に変えられる（わが家の設定でオンの種類だけ）。
///   端末の項目は、サーバーで保存が確かめられるまで消さない
/// - わが家で共有している項目を「自分だけ」に戻す機能は、次の段階（データを失わない手順を確かめてから）
/// - 削除：わが家で共有している項目は、相手の画面からも消える
struct LifeItemEditSheet: View {
    let item: LifeItem
    let store: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var destination: SaveDestination
    @State private var isConfirmingDelete = false

    init(item: LifeItem, store: LifeStore) {
        self.item = item
        self.store = store
        _title = State(initialValue: item.title)
        _destination = State(initialValue: store.isHouseholdItem(item.id) ? .household : .personal)
    }

    private var isShared: Bool { store.isHouseholdItem(item.id) }
    private var canConvert: Bool { !isShared && store.canShareInHousehold(item.kind) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                    SettingsTextField(label: "名前", text: $title, onCommit: {})

                    if isShared {
                        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                            HStack(spacing: LifeSpacing.xs) {
                                HouseholdSharedMark()
                                Text("わが家で共有しています")
                                    .font(LifeTypography.bodyEmphasis)
                                    .foregroundStyle(LifeColors.text)
                            }
                            SettingsNote(text: "変更・完了・削除は、パートナーの画面にも反映されます。「自分だけ」に戻す機能は、今後対応します。")
                        }
                    } else if canConvert {
                        SaveDestinationPicker(selection: $destination, note: "「わが家で共有」にすると、パートナーの画面にも表示されます。共有の保存が終わるまで、この iPhone の項目は消しません。")
                    }

                    LifeButton("保存", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(trimmedTitle.isEmpty)

                    LifeButton("削除", systemImage: "trash", kind: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.lg)
            }
            .lifeScreenBackground()
            .navigationTitle(item.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("削除しますか？", isPresented: $isConfirmingDelete) {
                Button("削除", role: .destructive) {
                    store.deleteItem(item.id)
                    dismiss()
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text(isShared ? "わが家で共有している項目です。パートナーの画面からも消えます。" : "この iPhone から消えます。")
            }
        }
    }

    private func save() {
        if trimmedTitle != item.title {
            store.rename(item.id, to: trimmedTitle)
        }
        if destination == .household, canConvert {
            store.convertToHousehold(item.id)
        }
        dismiss()
    }
}
