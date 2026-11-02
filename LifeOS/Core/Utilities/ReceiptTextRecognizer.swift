import Foundation
import ImageIO
import UniformTypeIdentifiers

/// レシートの写真を読み取れない理由（Build 18）
enum ReceiptImageError: Error, Equatable {
    /// 25MB を超える
    case tooLarge
    /// HEIC・JPEG・PNG 以外
    case unsupportedType
    /// 写真として読めない・文字を読み取れない
    case unreadable
    /// 写真を読み込めなかった（写真から選ぶ）
    case loadFailed

    var message: String {
        switch self {
        case .tooLarge:
            return "25MBを超える写真は読み取れません。手入力できます。"
        case .unsupportedType:
            return "読み取れるのは HEIC・JPEG・PNG の写真です。手入力できます。"
        case .unreadable:
            return "読み取れませんでした。手入力できます。"
        case .loadFailed:
            return "写真を読み込めませんでした。手入力できます。"
        }
    }
}

/// レシートの文字を読み取る窓口（テストでは偽物に差し替える）
protocol ReceiptTextRecognizing {
    /// 写真の文字の行（上から下）。読めなければ throw
    func recognizeLines(in imageData: Data) async throws -> [String]
}

/// レシートの写真の文字を、端末内の Apple Vision（VNRecognizeTextRequest）で読み取る（Build 18）。
///
/// - 文字認識は保証書と同じ `WarrantyTextRecognizer` を使う（端末内。外部へ画像も文字も送らない）
/// - 写真は1枚だけ。25MB まで、HEIC・JPEG・PNG だけ
/// - 写真も読み取った文字も保存しない（呼び出し側は候補を作ったら捨てる）
struct ReceiptTextRecognizer: ReceiptTextRecognizing {
    /// 1枚の上限（保証書の写真と同じ 25MB）
    static let maxBytes = WarrantyAttachmentStorage.maxFileBytes

    func recognizeLines(in imageData: Data) async throws -> [String] {
        try Task.checkCancellation()
        let lines = try await WarrantyTextRecognizer.recognizeLines(in: imageData)
        try Task.checkCancellation()
        return lines.map(\.text)
    }

    /// 読み取る前に確かめる（大きさ・形式）。問題なければ nil
    static func validate(_ data: Data, contentType: UTType? = nil) -> ReceiptImageError? {
        guard !data.isEmpty else { return .unreadable }
        guard Int64(data.count) <= maxBytes else { return .tooLarge }
        let type = contentType ?? detectedType(of: data)
        guard let type else { return .unreadable }
        guard WarrantyAttachmentStorage.supportedType(type) != nil else { return .unsupportedType }
        return nil
    }

    /// データの中身から形式を調べる（拡張子に頼らない）
    static func detectedType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }
}
