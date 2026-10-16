import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 保証書の書き出し（Premium 終了後も使える）。
/// 一時フォルダに「保証書の情報（文字）」と写真のコピーを作り、共有シートで渡す。終わったら一時フォルダを消す。
///
/// spec 7：写真の原本には位置情報などが残っていることがあるため、書き出すときは
/// 「位置情報を除いたコピー」か「原本のまま」かを利用者が選ぶ。保存している原本は変えない。
enum WarrantyExporter {
    enum ExportError: Error {
        case failed
    }

    /// 書き出し用の一時フォルダ
    static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LifeOSWarrantyExport", isDirectory: true)
    }

    /// 書き出すファイルを作る
    /// - Parameter removingLocation: true なら写真の位置情報（GPS）を除いたコピーにする
    static func makeExport(
        document: WarrantyDocument,
        attachments: [WarrantyAttachment],
        storage: WarrantyAttachmentStorage,
        removingLocation: Bool,
        now: Date = Date(),
        root: URL = exportRoot
    ) throws -> [URL] {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            var urls: [URL] = []

            let summaryURL = folder.appendingPathComponent("warranty-info.txt")
            try Data(summaryText(document: document, attachmentCount: attachments.count, now: now).utf8)
                .write(to: summaryURL, options: [.atomic, .completeFileProtection])
            urls.append(summaryURL)

            for (index, attachment) in attachments.enumerated() {
                let original = try storage.data(for: attachment)
                let type = UTType(attachment.uniformTypeIdentifier) ?? .jpeg
                let data = removingLocation ? (dataWithoutLocation(original) ?? original) : original
                let url = folder.appendingPathComponent(String(format: "photo-%02d.%@", index + 1, type.preferredFilenameExtension ?? "img"))
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                urls.append(url)
            }
            return urls
        } catch {
            try? fileManager.removeItem(at: folder)
            throw ExportError.failed
        }
    }

    /// 一時フォルダを消す（共有シートを閉じたとき・起動時）
    static func clearTemporaryFiles(root: URL = exportRoot) {
        try? FileManager.default.removeItem(at: root)
    }

    /// 保証書の情報（書き出す文字）
    static func summaryText(document: WarrantyDocument, attachmentCount: Int, now: Date) -> String {
        var lines = ["保証書：\(document.title)", "カテゴリー：\(document.category.label)"]
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append("\(label)：\(value)") }
        }
        add("メーカー", document.manufacturer)
        add("型番", document.modelNumber)
        add("製造番号", document.serialNumber)
        add("購入店", document.retailer)
        add("購入日", document.purchaseDate.map(WarrantyExpiration.dateText))
        add("保証期間", document.warrantyDuration?.label)
        if let expiresAt = document.warrantyExpiresAt {
            var text = WarrantyExpiration.dateText(expiresAt)
            if document.expirationSource == .calculated, let purchase = document.purchaseDate, let duration = document.warrantyDuration {
                text += "（\(WarrantyExpiration.basisText(purchaseDate: purchase, duration: duration))）"
            }
            lines.append("保証終了日：\(text)")
        }
        add("保管場所", document.physicalStorageLocation)
        add("メモ", document.note)
        lines.append("写真：\(attachmentCount)枚")
        lines.append("")
        lines.append("くらしOS から \(WarrantyExpiration.dateText(now)) に書き出し。保証の内容は保証書の原本で確認してください。")
        return lines.joined(separator: "\n")
    }

    /// 位置情報（GPS）を除いたコピー。
    /// まず画像を作り直さずにメタデータだけを除く方法を使い、できない形式（HEIC など）は、画質を最高にして作り直す。
    /// どちらもできなければ nil（呼び出し側で原本を使うかどうかを決める）
    static func dataWithoutLocation(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        // 1. メタデータだけを除く（再圧縮しない。JPEG・PNG など）
        let lossless = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(lossless, type, 1, nil) {
            let options = [kCGImageMetadataShouldExcludeGPS: true] as CFDictionary
            if CGImageDestinationCopyImageSource(destination, source, options, nil) {
                return lossless as Data
            }
        }

        // 2. 作り直す（GPS の情報を空にする）
        let rebuilt = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(rebuilt, type, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return rebuilt as Data
    }

    /// 位置情報が入っているか（書き出し前の確認・テスト用）
    static func containsLocation(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return properties[kCGImagePropertyGPSDictionary] != nil
    }
}
