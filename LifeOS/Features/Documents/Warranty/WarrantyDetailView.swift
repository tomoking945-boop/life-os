import SwiftUI
import UIKit

/// 保証書の詳細（spec 3・5）。Premium 終了後も、閲覧・写真表示・書き出し・削除はできる
struct WarrantyDetailView: View {
    let documentID: WarrantyDocument.ID

    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var viewerStart: ViewerStart?
    @State private var isConfirmingDelete = false
    @State private var isChoosingExport = false
    @State private var exportBundle: ExportBundle?
    @State private var exportFailed = false

    private struct ViewerStart: Identifiable {
        let id: WarrantyAttachment.ID
    }

    private struct ExportBundle: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private var now: Date { LifeCalendar.now }

    private var access: WarrantyAccess {
        WarrantyAccess.resolve(isPremium: appState.isPremium, hasSavedDocuments: !store.warranties.isEmpty)
    }

    var body: some View {
        Group {
            if let document = store.warranty(id: documentID) {
                content(document)
            } else {
                LifeEmptyState(systemImage: "doc", title: "この保証書は見つかりません", message: "削除された可能性があります。")
            }
        }
        .lifeScreenBackground()
        .navigationTitle("保証書")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.canEdit, store.warranty(id: documentID) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編集") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            WarrantyEditorView(repository: store, mode: .edit(documentID))
                .lifeSheetPresentation()
        }
        .fullScreenCover(item: $viewerStart) { start in
            WarrantyPhotoViewer(
                attachments: store.attachments(for: documentID),
                initial: start.id,
                urlFor: { store.warrantyStorage.url(for: $0) },
                canDelete: access.canDelete,
                onDelete: { attachment in store.deleteWarrantyAttachment(id: attachment.id) }
            )
        }
        .sheet(item: $exportBundle, onDismiss: { WarrantyExporter.clearTemporaryFiles() }) { bundle in
            WarrantyShareSheet(items: bundle.urls)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("写真の位置情報", isPresented: $isChoosingExport, titleVisibility: .visible) {
            Button("位置情報を除いて書き出す") { export(removingLocation: true) }
            Button("原本のまま書き出す") { export(removingLocation: false) }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("写真には、撮った場所の情報が残っていることがあります。位置情報を除くと、写真によっては画質がわずかに変わることがあります。保存している原本は変わりません。")
        }
        .confirmationDialog("この保証書を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("保証書と写真を削除", role: .destructive) { delete() }
        } message: {
            Text("保証書の情報・写真・期限のお知らせが、この iPhone から消えます。紙の保証書は残ります。")
        }
        .alert("書き出せませんでした", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("端末のロックを解除してから、もう一度お試しください。")
        }
    }

    // MARK: - 中身

    private func content(_ document: WarrantyDocument) -> some View {
        let attachments = store.attachments(for: document.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                header(document)

                if access == .readOnly {
                    WarrantyReadOnlyNote()
                }

                if let location = document.physicalStorageLocation {
                    storageLocation(location)
                }

                photos(attachments)

                LifeGroupedSection("保証の期限") {
                    VStack(spacing: 0) {
                        if let expiresAt = document.warrantyExpiresAt {
                            SettingsValueRow(title: "保証終了日", value: WarrantyExpiration.dateText(expiresAt))
                            if document.expirationSource == .calculated,
                               let purchase = document.purchaseDate, let duration = document.warrantyDuration {
                                Text(WarrantyExpiration.basisText(purchaseDate: purchase, duration: duration))
                                    .font(LifeTypography.footnote)
                                    .foregroundStyle(LifeColors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.horizontal, LifeSpacing.xs)
                                    .padding(.bottom, LifeSpacing.xs)
                            }
                        } else {
                            SettingsValueRow(title: "保証終了日", value: "未入力")
                        }
                        if let purchase = document.purchaseDate {
                            LifeDivider()
                            SettingsValueRow(title: "購入日", value: WarrantyExpiration.dateText(purchase))
                        }
                        if let duration = document.warrantyDuration {
                            LifeDivider()
                            SettingsValueRow(title: "保証期間", value: duration.label)
                        }
                        LifeDivider()
                        SettingsValueRow(title: "通知", value: reminderText(document))
                    }
                }

                LifeGroupedSection("製品") {
                    VStack(spacing: 0) {
                        SettingsValueRow(title: "カテゴリー", value: document.category.label)
                        optionalRow("メーカー", document.manufacturer)
                        optionalRow("型番", document.modelNumber)
                        optionalRow("製造番号", document.serialNumber)
                        optionalRow("購入店", document.retailer)
                        LifeDivider()
                        SettingsValueRow(title: "所有範囲", value: document.ownership.label)
                    }
                }

                if let note = document.note {
                    LifeGroupedSection("メモ") {
                        Text(note)
                            .font(LifeTypography.body)
                            .foregroundStyle(LifeColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, LifeSpacing.sm)
                            .textSelection(.enabled)
                    }
                }

                VStack(spacing: LifeSpacing.sm) {
                    if access.canExport {
                        LifeButton("書き出す", systemImage: "square.and.arrow.up", kind: .secondary) {
                            if attachments.isEmpty {
                                export(removingLocation: false)
                            } else {
                                isChoosingExport = true
                            }
                        }
                    }
                    if access.canDelete {
                        LifeButton("削除", systemImage: "trash", kind: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
    }

    private func header(_ document: WarrantyDocument) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            Label(document.category.label, systemImage: document.category.systemImage)
                .font(LifeTypography.label)
                .foregroundStyle(LifeColors.secondaryText)
            Text(document.title)
                .font(LifeTypography.display)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: LifeSpacing.xs) {
                LifeCategoryDot(color: statusColor(document))
                Text(WarrantyExpiration.remainingText(for: document, now: now))
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusColor(_ document: WarrantyDocument) -> Color {
        switch WarrantyExpiration.status(of: document, now: now) {
        case .expiringSoon: return LifeCategoryColors.warmGold
        case .active: return LifeColors.primary
        case .expired, .noExpiration: return LifeColors.divider
        }
    }

    private func storageLocation(_ location: String) -> some View {
        HStack(alignment: .top, spacing: LifeSpacing.sm) {
            Image(systemName: "archivebox")
                .font(.title3)
                .foregroundStyle(LifeColors.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text("紙の保管場所")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(location)
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LifeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func photos(_ attachments: [WarrantyAttachment]) -> some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("写真", trailing: "\(attachments.count)枚")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LifeSpacing.sm) {
                        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                            Button {
                                viewerStart = ViewerStart(id: attachment.id)
                            } label: {
                                WarrantyPhotoThumbnail(url: store.warrantyStorage.url(for: attachment), side: 112)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("写真 \(index + 1)枚目を大きく表示")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionalRow(_ title: String, _ value: String?) -> some View {
        if let value {
            LifeDivider()
            SettingsValueRow(title: title, value: value)
        }
    }

    private func reminderText(_ document: WarrantyDocument) -> String {
        guard document.warrantyExpiresAt != nil, !document.reminderOffsetsInDays.isEmpty else { return "なし" }
        guard access.canScheduleReminders else { return "停止中（Premium 終了後）" }
        return document.reminderOffsetsInDays.sorted(by: >)
            .map { $0 == 0 ? "当日" : "\($0)日前" }
            .joined(separator: "・")
    }

    // MARK: - 操作

    private func export(removingLocation: Bool) {
        guard let document = store.warranty(id: documentID) else { return }
        do {
            let urls = try WarrantyExporter.makeExport(
                document: document,
                attachments: store.attachments(for: documentID),
                storage: store.warrantyStorage,
                removingLocation: removingLocation
            )
            exportBundle = ExportBundle(urls: urls)
        } catch {
            exportFailed = true
        }
    }

    private func delete() {
        store.deleteWarranty(id: documentID)
        let currentStore = self.store
        let currentAppState = self.appState
        Task { await LifeNotificationService.shared.resync(store: currentStore, appState: currentAppState) }
        dismiss()
    }
}

/// 共有シート（書き出し）
struct WarrantyShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview("詳細（Premium）") {
    let store = WarrantyPreviewData.store()
    return NavigationStack { WarrantyDetailView(documentID: store.warranties[0].id) }
        .environment(WarrantyPreviewData.appState(plan: .premium))
        .environment(store)
}

#Preview("詳細（Premium 終了後）") {
    let store = WarrantyPreviewData.store()
    return NavigationStack { WarrantyDetailView(documentID: store.warranties[0].id) }
        .environment(WarrantyPreviewData.appState(plan: .free))
        .environment(store)
}
#endif
