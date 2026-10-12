import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// 保証書の写真を追加・保存できなかった理由
enum WarrantyAttachmentError: Error, Equatable {
    /// 1ファイル25MBを超える
    case tooLarge(byteCount: Int64)
    /// HEIC・JPEG・PNG 以外
    case unsupportedType
    /// 1件10枚を超える
    case tooManyAttachments
    /// 保存先が見つからない
    case storageUnavailable
    /// 書き込み・移動に失敗した（途中まで保存したファイルは消してある）
    case writeFailed

    var message: String {
        switch self {
        case .tooLarge:
            return "25MBを超える写真は追加できません。"
        case .unsupportedType:
            return "追加できるのは HEIC・JPEG・PNG の写真です（PDF は今後対応予定です）。"
        case .tooManyAttachments:
            return "写真は1件につき\(WarrantyDocument.maxAttachments)枚までです。"
        case .storageUnavailable, .writeFailed:
            return "写真を保存できませんでした。空き容量を確かめて、もう一度お試しください。"
        }
    }
}

/// 確認中の写真（一時フォルダに置いた原本）。保存すると正式な保存先へ移す。キャンセルしたら消す。
struct WarrantyStagedFile: Identifiable, Hashable {
    /// 保存したときの WarrantyAttachment.id にもなる
    let id: UUID
    let url: URL
    let originalFileName: String
    let contentType: UTType
    let byteCount: Int64
    let sha256: String
}

/// 保証書の写真を、原本のまま端末内（アプリ専用領域）に保存する（spec 4・7）。
///
/// - 画像は再圧縮しない（受け取った Data をそのまま書く／ファイルをそのまま移す）
/// - 保存先：Application Support/LifeOS/WarrantyDocuments/{documentID}/{attachmentID}.{拡張子}
///   ファイル名に製品名・メーカー名・製造番号は使わない（UUID だけ）
/// - ファイル保護は `.complete`（端末のロック中は読み出せない）
/// - 保存の途中で失敗したら、そこまでに移したファイルを戻し、孤立ファイルを残さない
/// - 外部サービスには送らない
final class WarrantyAttachmentStorage {
    /// 1ファイルの上限（25MB）
    static let maxFileBytes: Int64 = 25 * 1024 * 1024
    /// 追加できる形式
    static let allowedTypes: [UTType] = [.heic, .heif, .jpeg, .png]
    /// 保存先のフォルダ名
    static let directoryName = "WarrantyDocuments"

    private let rootProvider: () -> URL?
    private let stagingProvider: () -> URL
    private let fileManager: FileManager

    /// ファイルの移動（テストで失敗を起こし、ロールバックを確かめるために差し替える）
    var moveItem: (URL, URL) throws -> Void

    /// - Parameters:
    ///   - root: 保存の土台（nil なら LocalStorage と同じアプリ専用領域）
    ///   - staging: 確認中の写真を置く一時フォルダ（nil なら端末の一時フォルダ）
    init(root: URL? = nil, staging: URL? = nil, fileManager: FileManager = .default) {
        if let root {
            rootProvider = { root }
        } else {
            rootProvider = { LocalStorage.rootDirectory }
        }
        if let staging {
            stagingProvider = { staging }
        } else {
            stagingProvider = {
                FileManager.default.temporaryDirectory.appendingPathComponent("LifeOSWarrantyDraft", isDirectory: true)
            }
        }
        self.fileManager = fileManager
        moveItem = { source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    // MARK: - 形式・大きさ

    /// 追加できる形式なら、その形式を返す
    static func supportedType(_ type: UTType) -> UTType? {
        allowedTypes.contains(where: { type.conforms(to: $0) }) ? type : nil
    }

    /// 追加する前の確認（大きさ・形式）
    static func validate(byteCount: Int64, contentType: UTType) throws {
        guard supportedType(contentType) != nil else { throw WarrantyAttachmentError.unsupportedType }
        guard byteCount <= maxFileBytes else { throw WarrantyAttachmentError.tooLarge(byteCount: byteCount) }
    }

    /// 同じ画像かどうかを調べるための SHA-256（16進数）
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 確認中の写真（一時フォルダ）

    /// 撮影・選択した原本を、そのまま一時フォルダに置く（再圧縮しない）
    func stage(data: Data, contentType: UTType, originalFileName: String) throws -> WarrantyStagedFile {
        try Self.validate(byteCount: Int64(data.count), contentType: contentType)
        let directory = stagingProvider()
        let id = UUID()
        let url = directory.appendingPathComponent(Self.fileName(id: id, contentType: contentType))
        do {
            try createProtectedDirectory(directory)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? fileManager.removeItem(at: url)
            throw WarrantyAttachmentError.writeFailed
        }
        return WarrantyStagedFile(
            id: id,
            url: url,
            originalFileName: originalFileName,
            contentType: contentType,
            byteCount: Int64(data.count),
            sha256: Self.sha256(data)
        )
    }

    /// 確認中の写真を消す（キャンセル・写真の取り消し）
    func discard(_ files: [WarrantyStagedFile]) {
        for file in files {
            try? fileManager.removeItem(at: file.url)
        }
    }

    /// 一時フォルダを空にする（起動時。前回の途中で残ったもの）
    func clearStaging() {
        try? fileManager.removeItem(at: stagingProvider())
    }

    // MARK: - 正式な保存

    /// 確認中の写真を保証書の保存先へ移す。途中で失敗したら、移したものを一時フォルダへ戻して throw する
    func commit(_ files: [WarrantyStagedFile], documentID: UUID, now: Date) throws -> [WarrantyAttachment] {
        guard !files.isEmpty else { return [] }
        guard let root = rootProvider() else { throw WarrantyAttachmentError.storageUnavailable }
        let directory = documentDirectory(root: root, documentID: documentID)
        let existedBefore = fileManager.fileExists(atPath: directory.path)

        var moved: [(source: URL, destination: URL)] = []
        var attachments: [WarrantyAttachment] = []
        do {
            try createProtectedDirectory(directory)
            for file in files {
                let name = Self.fileName(id: file.id, contentType: file.contentType)
                let destination = directory.appendingPathComponent(name)
                try moveItem(file.url, destination)
                moved.append((file.url, destination))
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
                attachments.append(
                    WarrantyAttachment(
                        id: file.id,
                        documentID: documentID,
                        originalFileName: file.originalFileName,
                        uniformTypeIdentifier: file.contentType.identifier,
                        byteCount: file.byteCount,
                        sha256: file.sha256,
                        relativeFilePath: "\(Self.directoryName)/\(documentID.uuidString)/\(name)",
                        createdAt: now
                    )
                )
            }
        } catch {
            // ロールバック：移したファイルを一時フォルダへ戻す（戻せなければ消す）。孤立ファイルを残さない
            for item in moved.reversed() {
                do {
                    try fileManager.moveItem(at: item.destination, to: item.source)
                } catch {
                    try? fileManager.removeItem(at: item.destination)
                }
            }
            if !existedBefore {
                try? fileManager.removeItem(at: directory)
            }
            throw WarrantyAttachmentError.writeFailed
        }
        return attachments
    }

    // MARK: - 読み出し・削除

    func url(for attachment: WarrantyAttachment) -> URL? {
        rootProvider()?.appendingPathComponent(attachment.relativeFilePath)
    }

    /// 原本のデータ（端末のロック中は読めない）
    func data(for attachment: WarrantyAttachment) throws -> Data {
        guard let url = url(for: attachment) else { throw WarrantyAttachmentError.storageUnavailable }
        return try Data(contentsOf: url)
    }

    func fileExists(for attachment: WarrantyAttachment) -> Bool {
        guard let url = url(for: attachment) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// 写真を1枚消す
    func delete(_ attachment: WarrantyAttachment) {
        guard let url = url(for: attachment) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// 保証書の写真をすべて消す（フォルダごと）
    func deleteFiles(for documentID: UUID) {
        guard let root = rootProvider() else { return }
        try? fileManager.removeItem(at: documentDirectory(root: root, documentID: documentID))
    }

    /// どの保証書からも参照されていないファイル（孤立ファイル）と空のフォルダを消す。消した数を返す
    @discardableResult
    func removeOrphans(keeping attachments: [WarrantyAttachment]) -> Int {
        guard let root = rootProvider() else { return 0 }
        let base = root.appendingPathComponent(Self.directoryName, isDirectory: true)
        let keep = Set(attachments.map(\.relativeFilePath))
        var removed = 0
        guard let folders = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return 0 }
        for folder in folders {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                try? fileManager.removeItem(at: folder)
                removed += 1
                continue
            }
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var remaining = files.count
            for file in files {
                let relative = "\(Self.directoryName)/\(folder.lastPathComponent)/\(file.lastPathComponent)"
                if !keep.contains(relative) {
                    try? fileManager.removeItem(at: file)
                    removed += 1
                    remaining -= 1
                }
            }
            if remaining == 0 {
                try? fileManager.removeItem(at: folder)
            }
        }
        return removed
    }

    /// 保存先にあるファイルの数（テスト・確認用）
    func storedFileCount() -> Int {
        guard let root = rootProvider() else { return 0 }
        let base = root.appendingPathComponent(Self.directoryName, isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    // MARK: - 補助

    private func documentDirectory(root: URL, documentID: UUID) -> URL {
        root.appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    private func createProtectedDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
    }

    /// 保存ファイル名：UUID と拡張子だけ（製品名などは使わない）
    static func fileName(id: UUID, contentType: UTType) -> String {
        "\(id.uuidString).\(contentType.preferredFilenameExtension ?? "img")"
    }
}
