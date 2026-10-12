import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 保証書の登録・編集（spec 4・5）。Premium のときだけ開く。
/// 写真を追加 → 端末内で文字を読み取る → 読み取り結果の確認 → 期限・保管場所・共有範囲を入力 → 保存 → 通知を予約し直す
struct WarrantyEditorView: View {
    @State private var viewModel: WarrantyEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var isChoosingPhotoSource: Bool
    @State private var isLoadingPhotos = false
    @State private var didSave = false

    init(repository: any WarrantyRepository, mode: WarrantyEditorViewModel.Mode) {
        _viewModel = State(initialValue: WarrantyEditorViewModel(repository: repository, mode: mode))
        // 新しく登録するときは、最初に写真の追加方法を出す
        _isChoosingPhotoSource = State(initialValue: mode == .create)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                    photoSection
                    recognitionSection
                    basicSection
                    dateSection
                    storageSection
                    ownershipSection
                    reminderSection
                    if viewModel.showsFirstRegistrationNote {
                        SettingsNote(text: "保証書と写真は、この iPhone の中にだけ保存されます。アプリを削除すると、保証書のデータと写真も消えます（紙の保証書は大切に保管してください）。")
                    }
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.screenVertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .lifeScreenBackground()
            .navigationTitle(viewModel.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!viewModel.canSave)
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear {
            // 保存せずに閉じたときは、確認中の写真を消す（空の保証書は作らない）
            if !didSave { viewModel.cancel() }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            WarrantyCameraView { data, type in
                viewModel.addPhoto(data: data, contentType: type, originalFileName: "撮影した写真.\(type.preferredFilenameExtension ?? "jpg")")
                recognizeAfterAdding()
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.proposal != nil },
            set: { if !$0 { viewModel.discardProposal() } }
        )) {
            if let proposal = viewModel.proposal {
                WarrantyProposalReviewView(
                    proposal: proposal,
                    draft: viewModel.draft,
                    onApply: { edited, selected in viewModel.applyProposal(edited, selected: selected) },
                    onDiscard: { viewModel.discardProposal() }
                )
                .lifeSheetPresentation()
            }
        }
        .alert(
            alertTitle,
            isPresented: Binding(get: { viewModel.prompt != nil }, set: { if !$0 { viewModel.dismissPrompt() } }),
            presenting: viewModel.prompt
        ) { prompt in
            switch prompt {
            case .duplicate(let id, _):
                Button("追加する") { viewModel.confirmDuplicate(id) }
                Button("追加しない", role: .cancel) { viewModel.cancelDuplicate(id) }
            case .confirmSharing:
                Button("共有にする") { viewModel.confirmSharing() }
                Button("自分のままにする", role: .cancel) {}
            case .message:
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            switch prompt {
            case .duplicate(_, let title):
                Text("同じ写真が「\(title)」に登録されています。")
            case .confirmSharing:
                Text(viewModel.sharingConfirmationMessage)
            case .message(let text):
                Text(text)
            }
        }
    }

    private var alertTitle: String {
        switch viewModel.prompt {
        case .duplicate: return "同じ写真があります"
        case .confirmSharing: return "共有にしますか？"
        case .message, .none: return "お知らせ"
        }
    }

    // MARK: - 写真

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("写真", trailing: "\(viewModel.photoCount)／\(WarrantyDocument.maxAttachments)枚")

            if viewModel.photoCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LifeSpacing.sm) {
                        ForEach(viewModel.visibleExistingAttachments) { attachment in
                            removablePhoto(url: store.warrantyStorage.url(for: attachment)) {
                                viewModel.removeExistingAttachment(attachment.id)
                            }
                        }
                        ForEach(viewModel.stagedFiles) { file in
                            removablePhoto(url: file.url) {
                                viewModel.removeStagedFile(file.id)
                            }
                        }
                    }
                    .padding(.vertical, LifeSpacing.xxs)
                }
            }

            if isLoadingPhotos {
                ProgressView("写真を読み込んでいます…")
                    .font(LifeTypography.footnote)
            }

            if isChoosingPhotoSource && viewModel.photoCount == 0 {
                VStack(spacing: LifeSpacing.sm) {
                    cameraButton
                    libraryButton
                    LifeButton("あとで追加", kind: .secondary) {
                        isChoosingPhotoSource = false
                    }
                }
                SettingsNote(text: "HEIC・JPEG・PNG、1枚25MBまで。写真は撮ったまま（原本のまま）保存します。")
            } else if viewModel.canAddPhoto {
                HStack(spacing: LifeSpacing.sm) {
                    cameraButton
                    libraryButton
                }
            }
        }
    }

    private var cameraButton: some View {
        LifeButton("カメラで撮る", systemImage: "camera", kind: .secondary) {
            isShowingCamera = true
        }
        .disabled(!viewModel.canAddPhoto)
    }

    private var libraryButton: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: max(1, viewModel.remainingPhotoSlots),
            matching: .images,
            preferredItemEncoding: .current
        ) {
            LifeButtonLabel(title: "写真から選ぶ", systemImage: "photo.on.rectangle", kind: .secondary)
        }
        .buttonStyle(LifePressButtonStyle())
        .disabled(!viewModel.canAddPhoto)
    }

    private func removablePhoto(url: URL?, onRemove: @escaping () -> Void) -> some View {
        WarrantyPhotoThumbnail(url: url)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(LifeColors.onPrimary, LifeColors.text.opacity(0.7))
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget, alignment: .topTrailing)
                }
                .accessibilityLabel("この写真を取り除く")
            }
    }

    /// 写真の原本を読み込む（PhotosPicker は別の画面で動くため、写真全体へのアクセス許可は不要）
    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        let before = viewModel.stagedFiles.count
        for item in items {
            guard let type = item.supportedContentTypes.first(where: { WarrantyAttachmentStorage.supportedType($0) != nil }) else {
                viewModel.show(.message(WarrantyAttachmentError.unsupportedType.message))
                continue
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                viewModel.show(.message("写真を読み込めませんでした。"))
                continue
            }
            viewModel.addPhoto(data: data, contentType: type, originalFileName: "選んだ写真.\(type.preferredFilenameExtension ?? "jpg")")
        }
        photoItems = []
        isLoadingPhotos = false
        if viewModel.stagedFiles.count > before {
            recognizeAfterAdding()
        }
    }

    /// 写真を追加したら、端末内で文字を読み取る
    private func recognizeAfterAdding() {
        isChoosingPhotoSource = false
        Task { await viewModel.recognizeText() }
    }

    // MARK: - 読み取り

    @ViewBuilder
    private var recognitionSection: some View {
        if viewModel.isRecognizing {
            HStack(spacing: LifeSpacing.sm) {
                ProgressView()
                Text("この iPhone の中で文字を読み取っています…")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        } else if viewModel.photoCount > 0 {
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                if viewModel.recognitionFoundNothing {
                    SettingsNote(text: "文字を読み取れませんでした。そのまま手入力で保存できます。")
                }
                Button {
                    Task { await viewModel.recognizeText() }
                } label: {
                    Label("写真から文字を読み取る", systemImage: "text.viewfinder")
                        .font(LifeTypography.callout)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                }
                .foregroundStyle(LifeColors.primary)
            }
        }
    }

    // MARK: - 入力欄

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            WarrantyTextField(label: "製品名（必須）", text: $viewModel.draft.title, placeholder: "例：冷蔵庫")
            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("カテゴリー")
                Picker("カテゴリー", selection: $viewModel.draft.category) {
                    ForEach(WarrantyCategory.allCases) { category in
                        Label(category.label, systemImage: category.systemImage).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .tint(LifeColors.primary)
            }
            WarrantyTextField(label: "メーカー", text: $viewModel.draft.manufacturer)
            WarrantyTextField(label: "型番", text: $viewModel.draft.modelNumber)
            WarrantyTextField(label: "製造番号", text: $viewModel.draft.serialNumber, note: "通知には表示しません")
            WarrantyTextField(label: "購入店", text: $viewModel.draft.retailer)
        }
    }

    private var purchaseDateBinding: Binding<Date> {
        Binding(get: { viewModel.draft.purchaseDate ?? LifeCalendar.startOfDay(Date()) },
                set: { viewModel.draft.purchaseDate = $0 })
    }

    private var durationBinding: Binding<WarrantyDuration> {
        Binding(get: { viewModel.draft.duration ?? WarrantyDuration(value: 1, unit: .year) },
                set: { viewModel.draft.duration = $0 })
    }

    private var manualExpirationBinding: Binding<Date> {
        Binding(get: { viewModel.draft.manualExpiration ?? LifeCalendar.startOfDay(Date()) },
                set: { viewModel.draft.manualExpiration = $0 })
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("保証の期限")
            LifeGroupedSection {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggleRow(title: "購入日", isOn: Binding(
                        get: { viewModel.draft.purchaseDate != nil },
                        set: { viewModel.draft.purchaseDate = $0 ? LifeCalendar.startOfDay(Date()) : nil }
                    ))
                    if viewModel.draft.purchaseDate != nil {
                        DatePicker("購入日", selection: purchaseDateBinding, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .padding(.horizontal, LifeSpacing.xs)
                            .frame(minHeight: LifeSpacing.buttonHeight)
                    }
                    LifeDivider()
                    SettingsToggleRow(title: "保証期間", isOn: Binding(
                        get: { viewModel.draft.duration != nil },
                        set: { viewModel.draft.duration = $0 ? WarrantyDuration(value: 1, unit: .year) : nil }
                    ))
                    if viewModel.draft.duration != nil {
                        Stepper(value: durationBinding.value, in: WarrantyDuration.valueRange) {
                            Text(durationBinding.wrappedValue.label)
                                .font(LifeTypography.body)
                                .foregroundStyle(LifeColors.text)
                        }
                        .padding(.horizontal, LifeSpacing.xs)
                        .frame(minHeight: LifeSpacing.buttonHeight)
                        Picker("単位", selection: durationBinding.unit) {
                            ForEach(WarrantyDurationUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, LifeSpacing.xs)
                        .padding(.bottom, LifeSpacing.sm)
                    }
                    LifeDivider()
                    expirationRows
                }
            }
        }
    }

    @ViewBuilder
    private var expirationRows: some View {
        let draft = viewModel.draft
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            if draft.manualExpiration != nil {
                DatePicker("保証終了日", selection: manualExpirationBinding, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .frame(minHeight: LifeSpacing.buttonHeight)
                if draft.calculatedExpiration != nil {
                    smallButton("購入日＋保証期間で計算し直す") { viewModel.draft.manualExpiration = nil }
                } else {
                    smallButton("保証終了日を消す") { viewModel.draft.manualExpiration = nil }
                }
            } else if let calculated = draft.calculatedExpiration {
                SettingsValueRow(title: "保証終了日", value: WarrantyExpiration.dateText(calculated))
                if let basis = draft.basisText {
                    Text(basis)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .padding(.horizontal, LifeSpacing.xs)
                }
                smallButton("終了日を直接修正する") { viewModel.draft.manualExpiration = calculated }
            } else {
                SettingsValueRow(title: "保証終了日", value: "未入力")
                Text("購入日と保証期間を入れると計算します。終了日だけを入れることもできます。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .padding(.horizontal, LifeSpacing.xs)
                smallButton("終了日を直接入力する") { viewModel.draft.manualExpiration = LifeCalendar.startOfDay(Date()) }
            }
        }
        .padding(.vertical, LifeSpacing.xs)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(LifeTypography.callout)
            .foregroundStyle(LifeColors.primary)
            .padding(.horizontal, LifeSpacing.xs)
            .frame(minHeight: LifeSpacing.minTapTarget)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            WarrantyTextField(label: "紙の保管場所", text: $viewModel.draft.physicalStorageLocation,
                              placeholder: "例：リビングの書類ケース、上から2段目", note: "通知には表示しません")
            WarrantyTextField(label: "メモ", text: $viewModel.draft.note, placeholder: "例：修理の窓口", isMultiline: true)
        }
    }

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("所有範囲")
            LifeSegmentControl(Ownership.allCases, selection: Binding(
                get: { viewModel.draft.ownership },
                set: { viewModel.requestOwnership($0) }
            )) { $0.label }
            SettingsNote(text: "初めは「自分」です。共有は、選んだときだけになります。")
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("通知（9:00）")
            LifeGroupedSection {
                VStack(spacing: 0) {
                    ForEach(Array(WarrantyDocument.reminderOffsetChoices.enumerated()), id: \.element) { index, offset in
                        if index > 0 { LifeDivider() }
                        SettingsToggleRow(
                            title: offset == 0 ? "保証終了の当日" : "保証終了の\(offset)日前",
                            isOn: Binding(
                                get: { viewModel.draft.reminderOffsets.contains(offset) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.draft.reminderOffsets.insert(offset)
                                    } else {
                                        viewModel.draft.reminderOffsets.remove(offset)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            SettingsNote(text: appState.notificationSettings.warrantyRemindersEnabled
                ? "保証終了日が入っているときだけお知らせします。通知に製造番号・保管場所は表示しません。"
                : "通知設定で「保証書の期限」がオフのため、お知らせしません。")
        }
    }

    // MARK: - 保存

    private func save() {
        guard viewModel.save() else { return }
        didSave = true
        let needsNotification = !viewModel.draft.reminderOffsets.isEmpty && viewModel.draft.expiration != nil
        let service = LifeNotificationService.shared
        let currentStore = self.store
        let currentAppState = self.appState
        Task {
            if needsNotification && currentAppState.notificationSettings.warrantyRemindersEnabled {
                await service.requestAuthorizationIfNeeded()
            }
            await service.resync(store: currentStore, appState: currentAppState)
        }
        dismiss()
    }
}

/// 保証書の入力欄
struct WarrantyTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var note: String?
    var isMultiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle(label)
            Group {
                if isMultiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(2...6)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(LifeTypography.body)
            .foregroundStyle(LifeColors.text)
            .padding(LifeSpacing.md)
            .frame(minHeight: LifeSpacing.buttonHeight)
            .background(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).fill(LifeColors.surface))
            .overlay(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).stroke(LifeColors.divider, lineWidth: 1))
            .accessibilityLabel(label)
            if let note {
                Text(note)
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
    }
}

#if DEBUG
#Preview("新規登録") {
    let store = LifeStore()
    return WarrantyEditorView(repository: store, mode: .create)
        .environment(WarrantyPreviewData.appState(plan: .premium))
        .environment(store)
}

#Preview("編集") {
    let store = WarrantyPreviewData.store()
    return WarrantyEditorView(repository: store, mode: .edit(store.warranties[0].id))
        .environment(WarrantyPreviewData.appState(plan: .premium))
        .environment(store)
}
#endif
