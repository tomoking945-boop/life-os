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

/// レシートの文字の1行（Build 20）。文字・信頼度・写真の中の位置（左上が原点、0〜1）。
/// 読み取りの間だけメモリに持つ一時的な値。保存・送信・ログ出力しない
struct ReceiptRecognizedLine: Hashable {
    var text: String
    /// 0〜1
    var confidence: Float = 1
    /// 位置（分からなければ nil。文字だけの読み取り結果のとき）
    var box: RecognizedTextBox? = nil
}

/// レシートの文字を読み取る窓口（テストでは偽物に差し替える）
protocol ReceiptTextRecognizing {
    /// 写真の文字の行（上から下）。読めなければ throw
    func recognizeLines(in imageData: Data) async throws -> [String]
    /// 写真の文字の行（位置・信頼度つき。Build 20）。読めなければ throw
    func recognizeReceipt(in imageData: Data, detectsDocument: Bool) async throws -> [ReceiptRecognizedLine]
}

extension ReceiptTextRecognizing {
    /// 文字だけを返す窓口（Build 18・19 の偽物など）は、位置なし・信頼度1として扱う
    func recognizeReceipt(in imageData: Data, detectsDocument: Bool) async throws -> [ReceiptRecognizedLine] {
        try await recognizeLines(in: imageData).map { ReceiptRecognizedLine(text: $0) }
    }
}

/// レシートの写真の文字を、端末内の Apple Vision で読み取る（Build 18）。
///
/// - 文字認識は保証書と同じ `WarrantyTextRecognizer` を使う（端末内。外部へ画像も文字も送らない）
/// - 写真は1枚だけ。25MB まで、HEIC・JPEG・PNG だけ
/// - 写真も読み取った文字も保存しない（呼び出し側は候補を作ったら捨てる）
/// - Build 20：読み取る前に、向きを直し・大きすぎれば縮小し・（写真から選んだときは）レシートの範囲を直す（ReceiptImagePreparer）。
///   位置・信頼度も返す。キャンセルしたら、次の段階へ進まない
struct ReceiptTextRecognizer: ReceiptTextRecognizing {
    /// 1枚の上限（保証書の写真と同じ 25MB）
    static let maxBytes = WarrantyAttachmentStorage.maxFileBytes

    func recognizeLines(in imageData: Data) async throws -> [String] {
        try await recognizeReceipt(in: imageData, detectsDocument: true).map(\.text)
    }

    func recognizeReceipt(in imageData: Data, detectsDocument: Bool) async throws -> [ReceiptRecognizedLine] {
        try Task.checkCancellation()
        let prepared = try await Self.prepare(imageData, detectsDocument: detectsDocument)
        try Task.checkCancellation()
        let lines = try await recognizeText(in: prepared.data)
        try Task.checkCancellation()
        return lines.map { ReceiptRecognizedLine(text: $0.text, confidence: $0.confidence, box: $0.box) }
    }

    /// 文字認識（保証書と同じ端末内の部品だけを使う）
    private func recognizeText(in imageData: Data) async throws -> [WarrantyRecognizedLine] {
        try await WarrantyTextRecognizer.recognizeLines(in: imageData)
    }

    /// 写真を整える（重い処理のため画面とは別に動かす。キャンセルを伝える）
    private static func prepare(_ imageData: Data, detectsDocument: Bool) async throws -> PreparedReceiptImage {
        let task = Task.detached(priority: .userInitiated) {
            try ReceiptImagePreparer.prepare(imageData, detectsDocument: detectsDocument)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
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

/// 読み取りの品質（Build 20）。文字が少ない・信頼度が低いときに、撮り直し・確認をすすめる
enum ReceiptReadQuality {
    static let lowQualityMessage = "読み取り精度が低い可能性があります。撮り直すか、内容を確認してください"
    /// これより文字が少なければ「低い」
    static let minimumCharacters = 15
    /// 平均の信頼度がこれより低ければ「低い」
    static let minimumAverageConfidence: Float = 0.5

    static func isLow(_ lines: [ReceiptRecognizedLine]) -> Bool {
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let characters = usable.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        guard characters >= minimumCharacters, !usable.isEmpty else { return true }
        let average = usable.reduce(Float(0)) { $0 + $1.confidence } / Float(usable.count)
        return average < minimumAverageConfidence
    }
}
