import ImageIO
import SwiftUI
import UIKit

/// 保存した原本から、表示用の画像を作る（表示のためだけ。原本は変えない・保存しない）
enum WarrantyImageLoader {
    static func image(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func load(_ url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            image(at: url, maxPixelSize: maxPixelSize)
        }.value
    }
}

/// 写真の小さな表示
struct WarrantyPhotoThumbnail: View {
    let url: URL?
    var side: CGFloat = 88

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous)
                .fill(LifeColors.paper)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: didFail ? "lock.doc" : "photo")
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LifeRadius.small, style: .continuous).stroke(LifeColors.divider, lineWidth: LifeSpacing.hairline))
        .task(id: url) {
            guard let url else { return }
            image = await WarrantyImageLoader.load(url, maxPixelSize: side * 3)
            // 端末のロック中など、読めないときは鍵の印を出す
            didFail = image == nil
        }
        .accessibilityHidden(true)
    }
}

/// 写真を大きく表示する（拡大できる）。Premium 終了後も見られる
struct WarrantyPhotoViewer: View {
    let attachments: [WarrantyAttachment]
    let urlFor: (WarrantyAttachment) -> URL?
    let canDelete: Bool
    let onDelete: (WarrantyAttachment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: WarrantyAttachment.ID?
    @State private var deleting: WarrantyAttachment?

    init(
        attachments: [WarrantyAttachment],
        initial: WarrantyAttachment.ID?,
        urlFor: @escaping (WarrantyAttachment) -> URL?,
        canDelete: Bool,
        onDelete: @escaping (WarrantyAttachment) -> Void
    ) {
        self.attachments = attachments
        self.urlFor = urlFor
        self.canDelete = canDelete
        self.onDelete = onDelete
        _selection = State(initialValue: initial ?? attachments.first?.id)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    WarrantyZoomableImage(url: urlFor(attachment))
                        .tag(Optional(attachment.id))
                        .accessibilityLabel("写真 \(index + 1)枚目（全\(attachments.count)枚）")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .always : .never))
            .background(Color.black)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if canDelete, let current = attachments.first(where: { $0.id == selection }) {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            deleting = current
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("この写真を削除")
                    }
                }
            }
            .confirmationDialog(
                "この写真を削除しますか？",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("写真を削除", role: .destructive) {
                    if let deleting {
                        onDelete(deleting)
                    }
                    deleting = nil
                    dismiss()
                }
            } message: {
                Text("この iPhone の中から写真の原本が消えます。紙の保証書は残ります。")
            }
        }
    }
}

/// ピンチで拡大・ダブルタップで戻す
struct WarrantyZoomableImage: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        scale = 1
                        lastScale = 1
                    }
            } else if didFail {
                VStack(spacing: LifeSpacing.sm) {
                    Image(systemName: "lock.doc")
                        .font(.largeTitle)
                    Text("写真を表示できませんでした")
                        .font(LifeTypography.callout)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else {
                didFail = true
                return
            }
            image = await WarrantyImageLoader.load(url, maxPixelSize: 2800)
            didFail = image == nil
        }
    }
}
