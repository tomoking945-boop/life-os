import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 読み取りの前に整えたレシートの写真（Build 20）。メモリの中だけで使い、保存・送信しない
struct PreparedReceiptImage {
    /// 文字認識に渡すデータ（向きを直し、大きすぎれば縮小したもの。JPEG）
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    /// レシートの範囲を見つけて、傾き・切り抜きを直したか
    let isPerspectiveCorrected: Bool
}

/// レシートの写真を、文字を読み取りやすい形に整える（Build 20。docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md）。
///
/// - すべて端末の中の処理（ImageIO・Core Image・Vision）。写真は保存・送信しない
/// - 向き（EXIF）を直す。長い辺が `maxPixelSize` を超えるときは、文字が読める大きさを保って縮小する
///   （元の大きさで展開せず、縮小しながら読み込むので、大きな写真でもメモリを使い続けない）
/// - 「写真から選ぶ」のときは、レシートの範囲（四隅）を見つけられれば、傾きを直して切り抜く。
///   見つからない・小さすぎるときは、そのまま使う（書類スキャンで撮ったものは、すでに直っている）
enum ReceiptImagePreparer {
    /// 文字認識に渡す写真の長い辺の上限（レシートの小さな文字が読める大きさ）
    static let maxPixelSize = 3000
    /// レシートの範囲として使う最低の信頼度
    static let minimumDocumentConfidence: Float = 0.6
    /// 見つけた範囲が写真のこれより小さければ、切り抜かない（誤検出で文字を切り落とさない）
    static let minimumDocumentArea: Double = 0.2

    enum PreparationError: Error {
        case unreadable
    }

    /// 写真を整える。`detectsDocument` が true なら、レシートの範囲を見つけて傾き・切り抜きを直す
    static func prepare(_ data: Data, detectsDocument: Bool = true, maxPixelSize: Int = ReceiptImagePreparer.maxPixelSize) throws -> PreparedReceiptImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw PreparationError.unreadable
        }
        // 向きを直しながら、長い辺を maxPixelSize 以下にして読み込む（元の大きさより大きくはしない）
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, longestSide(source) ?? maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PreparationError.unreadable
        }
        try Task.checkCancellation()
        var image = upright
        var corrected = false
        if detectsDocument, let document = correctedDocument(upright) {
            image = document
            corrected = true
        }
        try Task.checkCancellation()
        guard let encoded = jpegData(image) else { throw PreparationError.unreadable }
        return PreparedReceiptImage(data: encoded, pixelWidth: image.width, pixelHeight: image.height, isPerspectiveCorrected: corrected)
    }

    /// 元の写真の長い辺（向きを直す前の値。縦横どちらでも長い方）
    private static func longestSide(_ source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(width, height)
    }

    /// レシートの範囲（四隅）を見つけて、傾きを直して切り抜く。見つからなければ nil
    static func correctedDocument(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              observation.confidence >= minimumDocumentConfidence else { return nil }
        // 範囲が小さすぎるときは使わない（文字を切り落とさない）
        let area = Double(observation.boundingBox.width * observation.boundingBox.height)
        guard area >= minimumDocumentArea else { return nil }
        let input = CIImage(cgImage: image)
        let width = input.extent.width
        let height = input.extent.height
        func vector(_ point: CGPoint) -> CIVector { CIVector(x: point.x * width, y: point.y * height) }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(observation.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(observation.topRight), forKey: "inputTopRight")
        filter.setValue(vector(observation.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(vector(observation.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage, output.extent.width >= 1, output.extent.height >= 1 else { return nil }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent)
    }

    /// 薄い印字向けに整えた写真（Build 22）：白黒にして、コントラストを上げ、薄い文字を濃くする。
    /// 2回目の読み取り（1回目の精度が低いとき）だけに使う。メモリの中だけ。作れなければ nil
    static func enhancedForFaintPrint(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let input = CIImage(cgImage: image)
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(input, forKey: kCIInputImageKey)
        controls.setValue(0.0, forKey: kCIInputSaturationKey)
        controls.setValue(enhancedContrast, forKey: kCIInputContrastKey)
        guard let gray = controls.outputImage, let gamma = CIFilter(name: "CIGammaAdjust") else { return nil }
        gamma.setValue(gray, forKey: kCIInputImageKey)
        // 1 より大きいと暗い色（薄い印字）が濃くなる
        gamma.setValue(enhancedGamma, forKey: "inputPower")
        guard let output = gamma.outputImage,
              let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent) else { return nil }
        return jpegData(result)
    }

    /// 薄い印字向けの補正の強さ（Build 22）
    static let enhancedContrast = 1.4
    static let enhancedGamma = 1.5

    /// JPEG にする（メモリの中だけ）
    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
