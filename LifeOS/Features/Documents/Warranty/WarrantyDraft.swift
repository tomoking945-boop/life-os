import Foundation

/// 登録・編集中の保証書（画面の入力内容）。保存するまで保証書のデータは変わらない。
struct WarrantyDraft: Equatable {
    var title = ""
    var category: WarrantyCategory = .other
    var manufacturer = ""
    var modelNumber = ""
    var serialNumber = ""
    var retailer = ""
    var purchaseDate: Date?
    var duration: WarrantyDuration?
    /// 直接入力・修正した保証終了日（nil なら購入日＋保証期間から計算）
    var manualExpiration: Date?
    var physicalStorageLocation = ""
    var note = ""
    /// 初期値は必ず「自分」（共有は明示的に選ぶ）
    var ownership: Ownership = .personal
    var reminderOffsets: Set<Int> = WarrantyDocument.defaultReminderOffsets

    init() {}

    init(document: WarrantyDocument) {
        title = document.title
        category = document.category
        manufacturer = document.manufacturer ?? ""
        modelNumber = document.modelNumber ?? ""
        serialNumber = document.serialNumber ?? ""
        retailer = document.retailer ?? ""
        purchaseDate = document.purchaseDate
        duration = document.warrantyDuration
        manualExpiration = document.expirationSource == .manual ? document.warrantyExpiresAt : nil
        physicalStorageLocation = document.physicalStorageLocation ?? ""
        note = document.note ?? ""
        ownership = document.ownership
        reminderOffsets = document.reminderOffsetsInDays
    }

    // MARK: - 保証終了日

    /// 購入日＋保証期間（どちらかが無ければ nil）
    var calculatedExpiration: Date? {
        guard let purchaseDate, let duration else { return nil }
        return WarrantyExpiration.expirationDate(purchaseDate: purchaseDate, duration: duration)
    }

    var expiration: Date? { manualExpiration ?? calculatedExpiration }

    var expirationSource: WarrantyExpirationSource {
        if manualExpiration != nil { return .manual }
        return calculatedExpiration != nil ? .calculated : .none
    }

    /// 算出根拠（計算したときだけ）：「購入日 2026/10/13 ＋ 1年」
    var basisText: String? {
        guard manualExpiration == nil, let purchaseDate, let duration, calculatedExpiration != nil else { return nil }
        return WarrantyExpiration.basisText(purchaseDate: purchaseDate, duration: duration)
    }

    // MARK: - 保存

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optional(_ text: String) -> String? {
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    /// 製品名だけあれば保存できる（spec 13）
    var canSave: Bool { !Self.trimmed(title).isEmpty }

    func makeDocument(id: UUID, attachmentIDs: [UUID], createdAt: Date, now: Date) -> WarrantyDocument {
        WarrantyDocument(
            id: id,
            title: Self.trimmed(title),
            category: category,
            manufacturer: Self.optional(manufacturer),
            modelNumber: Self.optional(modelNumber),
            serialNumber: Self.optional(serialNumber),
            retailer: Self.optional(retailer),
            purchaseDate: purchaseDate.map { LifeCalendar.startOfDay($0) },
            warrantyDuration: duration,
            warrantyExpiresAt: expiration.map { LifeCalendar.startOfDay($0) },
            expirationSource: expirationSource,
            physicalStorageLocation: Self.optional(physicalStorageLocation),
            note: Self.optional(note),
            ownership: ownership,
            attachmentIDs: attachmentIDs,
            reminderOffsetsInDays: reminderOffsets,
            createdAt: createdAt,
            updatedAt: now
        )
    }

    // MARK: - 読み取り候補の反映

    /// その項目に、利用者がすでに値を入れているか（入っていれば候補で上書きしない）
    func isFilled(_ kind: WarrantyFieldKind) -> Bool {
        switch kind {
        case .title: return !Self.trimmed(title).isEmpty
        case .manufacturer: return !Self.trimmed(manufacturer).isEmpty
        case .retailer: return !Self.trimmed(retailer).isEmpty
        case .modelNumber: return !Self.trimmed(modelNumber).isEmpty
        case .serialNumber: return !Self.trimmed(serialNumber).isEmpty
        case .purchaseDate: return purchaseDate != nil
        case .warrantyDuration: return duration != nil
        case .warrantyExpiresAt: return expiration != nil
        }
    }

    /// 「候補を反映」：選んだ項目だけ、まだ入力されていない欄に入れる。反映した項目を返す。
    /// 利用者が入力済みの値は上書きしない（spec 4）
    @discardableResult
    mutating func apply(_ proposal: WarrantyExtractionProposal, selected: Set<WarrantyFieldKind>) -> [WarrantyFieldKind] {
        var applied: [WarrantyFieldKind] = []
        for field in proposal.fields where selected.contains(field.kind) && !isFilled(field.kind) {
            let value = Self.trimmed(field.value)
            guard !value.isEmpty else { continue }
            switch field.kind {
            case .title: title = value
            case .manufacturer: manufacturer = value
            case .retailer: retailer = value
            case .modelNumber: modelNumber = value
            case .serialNumber: serialNumber = value
            case .purchaseDate:
                guard let date = WarrantyFieldExtractor.dates(in: value).first else { continue }
                purchaseDate = date
            case .warrantyDuration:
                guard let parsed = WarrantyFieldExtractor.duration(in: value) else { continue }
                duration = parsed
            case .warrantyExpiresAt:
                guard let date = WarrantyFieldExtractor.dates(in: value).first else { continue }
                manualExpiration = date
            }
            applied.append(field.kind)
        }
        // 購入日と保証期間が入り、終了日を直接入れていなければ、終了日は計算で決まる
        return applied
    }
}
