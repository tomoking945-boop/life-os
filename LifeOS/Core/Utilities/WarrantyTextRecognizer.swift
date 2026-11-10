import Foundation
import ImageIO
import Vision

/// 写真の文字を、端末内の Apple Vision（VNRecognizeTextRequest）で読み取る（spec 4）。
///
/// - 画像も読み取った文字も、外部サービスへ送らない（Vision の文字認識は端末内で動く）
/// - 結果は候補（WarrantyExtractionProposal）として返すだけ。保証書のデータには書き込まない
enum WarrantyTextRecognizer {
    enum RecognitionError: Error {
        /// 画像として読めない
        case unreadableImage
    }

    /// 1つの文字のまとまりから受け取る候補の数（Build 22。1番目が読み取りの結果、ほかはレシートの数字の確かめ用）
    static let maxCandidates = 3

    /// 写真（原本のデータ）から文字の行を読み取る。重い処理のため、呼び出し側で待つ（async）。
    /// Build 18：呼び出し側の Task を取り消したら、まだ始まっていない読み取りは始めない（レシートの「キャンセル」。保証書の動きは同じ）
    static func recognizeLines(in imageData: Data) async throws -> [WarrantyRecognizedLine] {
        let task = Task.detached(priority: .userInitiated) {
            try recognizeLinesSynchronously(in: imageData)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// 複数の写真を読み取り、候補を作る
    static func proposal(for images: [Data]) async throws -> WarrantyExtractionProposal {
        var lines: [WarrantyRecognizedLine] = []
        for image in images {
            lines += try await recognizeLines(in: image)
        }
        return WarrantyFieldExtractor.extract(from: lines)
    }

    private static func recognizeLinesSynchronously(in imageData: Data) throws -> [WarrantyRecognizedLine] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RecognitionError.unreadableImage
        }
        let orientation = imageOrientation(source)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try Task.checkCancellation()
        try handler.perform([request])

        let observations = request.results ?? []
        // 上から下、左から右の順に並べる（Vision の座標は左下が原点）
        let sorted = observations.sorted { lhs, rhs in
            let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(dy) > 0.01 { return dy > 0 }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return sorted.compactMap { observation in
            // Build 22：上位3つの候補を受け取る（1番目が今までどおりの文字。2・3番目はレシートの数字の確かめだけに使う）
            let candidates = observation.topCandidates(Self.maxCandidates)
            guard let candidate = candidates.first else { return nil }
            // Build 20：位置も返す（Vision は左下が原点なので、左上が原点の値にする）。保証書の読み取りは使わない
            let box = observation.boundingBox
            return WarrantyRecognizedLine(
                text: candidate.string,
                confidence: candidate.confidence,
                box: RecognizedTextBox(x: Double(box.minX), y: Double(1 - box.maxY), width: Double(box.width), height: Double(box.height)),
                alternatives: candidates.dropFirst().map(\.string)
            )
        }
    }

    /// 写真の向き（EXIF）。撮影した向きのまま読むため
    private static func imageOrientation(_ source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw) else {
            return .up
        }
        return orientation
    }
}
