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

    /// 写真（原本のデータ）から文字の行を読み取る。重い処理のため、呼び出し側で待つ（async）
    static func recognizeLines(in imageData: Data) async throws -> [WarrantyRecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            try recognizeLinesSynchronously(in: imageData)
        }.value
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
        try handler.perform([request])

        let observations = request.results ?? []
        // 上から下、左から右の順に並べる（Vision の座標は左下が原点）
        let sorted = observations.sorted { lhs, rhs in
            let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(dy) > 0.01 { return dy > 0 }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return sorted.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return WarrantyRecognizedLine(text: candidate.string, confidence: candidate.confidence)
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
