import Foundation

// Premium「大切な書類」保証書管理 MVP（2026-10-13）：docs/WARRANTY_MANAGEMENT_MVP_SPEC.md 5・6
// 保証書のデータはすべて端末内にだけ保存する（外部サービス・クラウド同期には送らない）。

/// 保証書のカテゴリー
enum WarrantyCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case appliance
    case furniture
    case digital
    case housing
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appliance: return "家電"
        case .furniture: return "家具"
        case .digital: return "デジタル"
        case .housing: return "住宅設備"
        case .other: return "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .appliance: return "refrigerator"
        case .furniture: return "sofa"
        case .digital: return "laptopcomputer"
        case .housing: return "house"
        case .other: return "doc.text"
        }
    }
}

/// 保証期間の単位（日／月／年）
enum WarrantyDurationUnit: String, CaseIterable, Identifiable, Hashable, Codable {
    case day
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "日"
        case .month: return "か月"
        case .year: return "年"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .month: return .month
        case .year: return .year
        }
    }
}

/// 保証期間（例：1年）
struct WarrantyDuration: Hashable, Codable {
    var value: Int
    var unit: WarrantyDurationUnit

    /// 「1年」「6か月」「90日」
    var label: String { "\(value)\(unit.label)" }

    /// 入力できる範囲（0 や極端に長い期間は受け付けない）
    static let valueRange = 1...120
}

/// 保証終了日がどうやって決まったか
enum WarrantyExpirationSource: String, Hashable, Codable {
    /// 終了日なし
    case none
    /// 購入日＋保証期間から計算
    case calculated
    /// 利用者が直接入力・修正
    case manual
}

/// 保証書（spec 6）
struct WarrantyDocument: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var category: WarrantyCategory
    var manufacturer: String?
    var modelNumber: String?
    /// 製造番号。通知本文には出さない
    var serialNumber: String?
    var retailer: String?
    var purchaseDate: Date?
    var warrantyDuration: WarrantyDuration?
    var warrantyExpiresAt: Date?
    var expirationSource: WarrantyExpirationSource
    /// 紙の原本を置いた場所。通知本文には出さない
    var physicalStorageLocation: String?
    var note: String?
    /// 初期値は必ず「自分」
    var ownership: Ownership
    /// 写真の並び順（WarrantyAttachment.id）
    var attachmentIDs: [UUID]
    /// 保証終了の何日前に知らせるか（空なら通知しない）
    var reminderOffsetsInDays: Set<Int>
    var createdAt: Date
    var updatedAt: Date

    /// 通知の初期値：30日前・7日前・当日
    static let defaultReminderOffsets: Set<Int> = [30, 7, 0]
    /// 選べる通知のタイミング
    static let reminderOffsetChoices: [Int] = [30, 7, 0]
    /// 1件あたりの写真の上限
    static let maxAttachments = 10

    init(
        id: UUID = UUID(),
        title: String,
        category: WarrantyCategory = .other,
        manufacturer: String? = nil,
        modelNumber: String? = nil,
        serialNumber: String? = nil,
        retailer: String? = nil,
        purchaseDate: Date? = nil,
        warrantyDuration: WarrantyDuration? = nil,
        warrantyExpiresAt: Date? = nil,
        expirationSource: WarrantyExpirationSource = .none,
        physicalStorageLocation: String? = nil,
        note: String? = nil,
        ownership: Ownership = .personal,
        attachmentIDs: [UUID] = [],
        reminderOffsetsInDays: Set<Int> = WarrantyDocument.defaultReminderOffsets,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.retailer = retailer
        self.purchaseDate = purchaseDate
        self.warrantyDuration = warrantyDuration
        self.warrantyExpiresAt = warrantyExpiresAt
        self.expirationSource = expirationSource
        self.physicalStorageLocation = physicalStorageLocation
        self.note = note
        self.ownership = ownership
        self.attachmentIDs = attachmentIDs
        self.reminderOffsetsInDays = reminderOffsetsInDays
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 検索の対象：製品名・メーカー・型番・購入店・保管場所（spec 3）
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let fields = [title, manufacturer, modelNumber, retailer, physicalStorageLocation].compactMap { $0 }
        return fields.contains { $0.localizedStandardContains(trimmed) }
    }
}

/// 保証書の写真（原本のまま、アプリ専用領域に保存したファイル）
struct WarrantyAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    let documentID: UUID
    /// 元のファイル名（表示用。保存ファイル名には使わない）
    var originalFileName: String
    /// 例：public.heic / public.jpeg / public.png
    var uniformTypeIdentifier: String
    var byteCount: Int64
    var sha256: String
    /// アプリ専用領域（Application Support/LifeOS）からの相対パス。例：WarrantyDocuments/{documentID}/{attachmentID}.heic
    var relativeFilePath: String
    var createdAt: Date
}

// MARK: - 自動読み取りの候補（確認中だけ持つ。保存しない）

/// 読み取り候補の項目
enum WarrantyFieldKind: String, CaseIterable, Identifiable, Hashable {
    case title
    case manufacturer
    case retailer
    case purchaseDate
    case warrantyDuration
    case warrantyExpiresAt
    case modelNumber
    case serialNumber

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "製品名"
        case .manufacturer: return "メーカー"
        case .retailer: return "購入店"
        case .purchaseDate: return "購入日"
        case .warrantyDuration: return "保証期間"
        case .warrantyExpiresAt: return "保証終了日"
        case .modelNumber: return "型番"
        case .serialNumber: return "製造番号"
        }
    }
}

/// 読み取った候補の1項目
struct WarrantyExtractedField: Identifiable, Hashable {
    var kind: WarrantyFieldKind
    /// 表示・反映する値（日付は yyyy/MM/dd、保証期間は「1年」など）
    var value: String
    /// 見つかったほかの候補（複数あるときは「確認が必要」）
    var alternatives: [String] = []
    /// 文字認識の信頼度（0〜1）
    var confidence: Float = 1
    /// 解釈した日付（購入日・保証終了日）
    var date: Date?
    /// 解釈した保証期間
    var duration: WarrantyDuration?

    var id: WarrantyFieldKind { kind }

    /// 信頼度がこれより低いと「確認が必要」
    static let reviewConfidenceThreshold: Float = 0.5

    /// 複数の候補がある・信頼度が低い
    var needsReview: Bool {
        !alternatives.isEmpty || confidence < Self.reviewConfidenceThreshold
    }
}

/// 自動読み取りの結果（spec 6）。利用者が「候補を反映」を押すまで、保証書のデータには書き込まない。
struct WarrantyExtractionProposal: Hashable {
    var recognizedText: String
    var fields: [WarrantyExtractedField]

    func field(_ kind: WarrantyFieldKind) -> WarrantyExtractedField? {
        fields.first { $0.kind == kind }
    }

    var isEmpty: Bool { fields.isEmpty }
}
