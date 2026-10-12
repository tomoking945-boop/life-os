import Foundation
import Observation
import UniformTypeIdentifiers

/// 保証書の登録・編集（spec 4）
///
/// - 写真は確認中のあいだ一時フォルダに置き、保存したときだけ正式な保存先へ移す
/// - キャンセルしたら一時フォルダの写真を消し、空の保証書は作らない
/// - 読み取り候補は「候補を反映」を押すまで入力欄にも保証書にも入れない
@Observable
final class WarrantyEditorViewModel {
    enum Mode: Equatable {
        case create
        case edit(WarrantyDocument.ID)
    }

    /// 画面に出す確認・お知らせ
    enum Prompt: Identifiable, Equatable {
        /// 同じ写真がすでに登録されている（追加するか確かめる）
        case duplicate(id: UUID, existingTitle: String)
        /// 共有を選んだときの確認
        case confirmSharing
        /// 写真を追加・保存できなかった など
        case message(String)

        var id: String {
            switch self {
            case .duplicate(let id, _): return "duplicate-\(id.uuidString)"
            case .confirmSharing: return "sharing"
            case .message(let text): return "message-\(text)"
            }
        }
    }

    let mode: Mode
    private let repository: any WarrantyRepository
    private let documentID: UUID
    private let createdAt: Date

    var draft: WarrantyDraft
    /// 保存済みの写真（編集のとき）
    private(set) var existingAttachments: [WarrantyAttachment]
    private(set) var removedAttachmentIDs: Set<WarrantyAttachment.ID> = []
    /// 確認中の写真（まだ保存先に入れていない）
    private(set) var stagedFiles: [WarrantyStagedFile] = []

    /// 読み取り候補（確認画面に出す。保存しない）
    var proposal: WarrantyExtractionProposal?
    private(set) var isRecognizing = false
    /// 読み取ったが、候補が見つからなかった
    private(set) var recognitionFoundNothing = false
    /// いま出している確認・お知らせ（変えるときは show / dismissPrompt を使う）
    private(set) var prompt: Prompt?
    /// 続けて出す確認・お知らせ（複数の写真をまとめて追加したとき）
    private var promptQueue: [Prompt] = []

    /// 同じ写真の確認を待っているもの
    private struct PendingPhoto {
        let data: Data
        let contentType: UTType
        let originalFileName: String
    }
    private var pendingDuplicates: [UUID: PendingPhoto] = [:]

    init(repository: any WarrantyRepository, mode: Mode, now: Date = Date()) {
        self.repository = repository
        self.mode = mode
        switch mode {
        case .create:
            documentID = UUID()
            createdAt = now
            draft = WarrantyDraft()
            existingAttachments = []
        case .edit(let id):
            let document = repository.warranty(id: id)
            documentID = id
            createdAt = document?.createdAt ?? now
            draft = document.map(WarrantyDraft.init(document:)) ?? WarrantyDraft()
            existingAttachments = repository.attachments(for: id)
        }
    }

    var isCreating: Bool { mode == .create }
    var screenTitle: String { isCreating ? "保証書を登録" : "保証書を編集" }

    /// はじめての登録：アプリを削除すると端末内のデータも消えることを伝える（spec 7）
    var showsFirstRegistrationNote: Bool { isCreating && repository.warranties.isEmpty }

    // MARK: - 写真

    var visibleExistingAttachments: [WarrantyAttachment] {
        existingAttachments.filter { !removedAttachmentIDs.contains($0.id) }
    }

    var photoCount: Int { visibleExistingAttachments.count + stagedFiles.count }
    var remainingPhotoSlots: Int { max(0, WarrantyDocument.maxAttachments - photoCount) }
    var canAddPhoto: Bool { remainingPhotoSlots > 0 }

    /// 撮影・選択した写真（原本のデータ）を追加する。大きさ・形式・枚数・同じ写真を確かめる
    func addPhoto(data: Data, contentType: UTType, originalFileName: String) {
        guard canAddPhoto else {
            show(.message(WarrantyAttachmentError.tooManyAttachments.message))
            return
        }
        do {
            try WarrantyAttachmentStorage.validate(byteCount: Int64(data.count), contentType: contentType)
        } catch let error as WarrantyAttachmentError {
            show(.message(error.message))
            return
        } catch {
            show(.message(WarrantyAttachmentError.writeFailed.message))
            return
        }

        let hash = WarrantyAttachmentStorage.sha256(data)
        if let title = duplicateTitle(for: hash) {
            let id = UUID()
            pendingDuplicates[id] = PendingPhoto(data: data, contentType: contentType, originalFileName: originalFileName)
            show(.duplicate(id: id, existingTitle: title))
            return
        }
        stage(data: data, contentType: contentType, originalFileName: originalFileName)
    }

    // 確認の画面（アラート）が閉じたときは、画面から dismissPrompt を呼ぶ。
    // ボタンの処理（confirmDuplicate など）では閉じる処理をしない（二重に閉じて次の確認を飛ばさないため）

    /// 同じ写真の確認で「追加する」を選んだ
    func confirmDuplicate(_ id: UUID) {
        guard let pending = pendingDuplicates.removeValue(forKey: id) else { return }
        guard canAddPhoto else {
            show(.message(WarrantyAttachmentError.tooManyAttachments.message))
            return
        }
        stage(data: pending.data, contentType: pending.contentType, originalFileName: pending.originalFileName)
    }

    /// 同じ写真の確認で「追加しない」を選んだ
    func cancelDuplicate(_ id: UUID) {
        pendingDuplicates[id] = nil
    }

    /// 確認・お知らせを出す（すでに出ていれば、閉じたあとに出す）
    func show(_ newPrompt: Prompt) {
        if prompt == nil {
            prompt = newPrompt
        } else {
            promptQueue.append(newPrompt)
        }
    }

    /// いまの確認・お知らせを閉じて、次があれば少し後に出す（閉じる動きと重ならないように）
    func dismissPrompt() {
        prompt = nil
        guard !promptQueue.isEmpty else { return }
        let next = promptQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if self.prompt == nil {
                self.prompt = next
            } else {
                self.promptQueue.insert(next, at: 0)
            }
        }
    }

    private func duplicateTitle(for hash: String) -> String? {
        if stagedFiles.contains(where: { $0.sha256 == hash })
            || visibleExistingAttachments.contains(where: { $0.sha256 == hash }) {
            return draft.title.isEmpty ? "この保証書" : draft.title
        }
        if let other = repository.warrantyContainingImage(sha256: hash) {
            return other.title
        }
        return nil
    }

    private func stage(data: Data, contentType: UTType, originalFileName: String) {
        do {
            let file = try repository.warrantyStorage.stage(data: data, contentType: contentType, originalFileName: originalFileName)
            stagedFiles.append(file)
        } catch let error as WarrantyAttachmentError {
            show(.message(error.message))
        } catch {
            show(.message(WarrantyAttachmentError.writeFailed.message))
        }
    }

    func removeStagedFile(_ id: WarrantyStagedFile.ID) {
        guard let file = stagedFiles.first(where: { $0.id == id }) else { return }
        stagedFiles.removeAll { $0.id == id }
        repository.warrantyStorage.discard([file])
    }

    /// 保存済みの写真を取り除く（保存したときに消える）
    func removeExistingAttachment(_ id: WarrantyAttachment.ID) {
        removedAttachmentIDs.insert(id)
    }

    // MARK: - 文字の読み取り（端末内）

    /// 写真の文字を読み取り、候補を作る（確認画面に出す。入力欄には入れない）
    @MainActor
    func recognizeText() async {
        let images = currentImageData()
        guard !images.isEmpty, !isRecognizing else { return }
        isRecognizing = true
        recognitionFoundNothing = false
        defer { isRecognizing = false }
        do {
            let result = try await WarrantyTextRecognizer.proposal(for: images)
            if result.isEmpty {
                recognitionFoundNothing = true
            } else {
                proposal = result
            }
        } catch {
            recognitionFoundNothing = true
        }
    }

    /// 読み取りに使う写真（新しく追加した写真。無ければ保存済みの写真）
    private func currentImageData() -> [Data] {
        let staged = stagedFiles.compactMap { try? Data(contentsOf: $0.url) }
        if !staged.isEmpty { return staged }
        return visibleExistingAttachments.compactMap { try? repository.warrantyStorage.data(for: $0) }
    }

    /// 「候補を反映」：選んだ項目だけ、空いている入力欄に入れる
    func applyProposal(_ edited: WarrantyExtractionProposal, selected: Set<WarrantyFieldKind>) {
        draft.apply(edited, selected: selected)
        proposal = nil
    }

    /// 反映しない（候補は捨てる。保存しない）
    func discardProposal() {
        proposal = nil
    }

    // MARK: - 共有

    /// 共有を選んだとき：写真の枚数と、共有の対象になる項目名を確かめる（spec 11）
    func requestOwnership(_ ownership: Ownership) {
        if ownership == .shared, draft.ownership != .shared {
            show(.confirmSharing)
        } else {
            draft.ownership = ownership
        }
    }

    func confirmSharing() {
        draft.ownership = .shared
    }

    var sharingConfirmationMessage: String {
        var fields = ["製品名"]
        if !draft.manufacturer.isEmpty { fields.append("メーカー") }
        if !draft.modelNumber.isEmpty { fields.append("型番") }
        if !draft.serialNumber.isEmpty { fields.append("製造番号") }
        if !draft.retailer.isEmpty { fields.append("購入店") }
        if !draft.physicalStorageLocation.isEmpty { fields.append("保管場所") }
        if !draft.note.isEmpty { fields.append("メモ") }
        return "写真\(photoCount)枚と、\(fields.joined(separator: "・"))が共有の対象になります。\nいまは同期していないため、相手の端末には送られません。"
    }

    // MARK: - 保存・キャンセル

    var canSave: Bool { draft.canSave }

    /// 保存する。写真は原本のまま保存先へ移す。失敗したら何も変えずに false
    @discardableResult
    func save(now: Date = Date()) -> Bool {
        guard canSave else {
            show(.message("製品名を入力してください。"))
            return false
        }
        let keptIDs = visibleExistingAttachments.map(\.id)
        let document = draft.makeDocument(id: documentID, attachmentIDs: keptIDs, createdAt: createdAt, now: now)
        do {
            try repository.saveWarranty(document, adding: stagedFiles, removing: removedAttachmentIDs, now: now)
            stagedFiles = []
            return true
        } catch let error as WarrantyAttachmentError {
            show(.message(error.message))
        } catch {
            show(.message("保存できませんでした。もう一度お試しください。"))
        }
        return false
    }

    /// キャンセル：確認中の写真を消す（保証書は作らない・変えない）
    func cancel() {
        repository.warrantyStorage.discard(stagedFiles)
        stagedFiles = []
        proposal = nil
    }
}
