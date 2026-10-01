import Foundation
import UIKit

/// プロフィール写真を端末内（アプリ専用の保存領域）にだけ保存する。
/// 外部サービスへのアップロードは行わない。
/// TODO: Firebase Storage 接続時は、ここをアップロード処理と組み合わせる。
enum ProfileImageStorage {
    /// 保存時の最大サイズ（長辺のピクセル数）
    private static let maxPixelLength: CGFloat = 1024
    private static let compressionQuality: CGFloat = 0.85

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("profile.jpg")
    }

    static func load() -> UIImage? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        guard let url = fileURL,
              let data = resized(image).jpegData(compressionQuality: compressionQuality) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // 保存に失敗しても、画面上の写真はそのまま使えるため処理は続ける。
        }
    }

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 長辺が maxPixelLength を超える場合だけ縮小する
    private static func resized(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixelLength else { return image }

        let ratio = maxPixelLength / longest
        let targetSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
