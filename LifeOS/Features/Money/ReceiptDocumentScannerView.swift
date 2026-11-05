import SwiftUI
import UIKit
import VisionKit

/// レシートを撮る方法（Build 20。docs/BUILD_20_RECEIPT_ACCURACY_AND_LINE_ITEM_PREVIEW.md）
enum ReceiptCaptureMode: Equatable {
    /// iOS の書類スキャン（レシートの輪郭を見つけ、傾きを直して切り抜く。この iPhone の中だけの処理）
    case documentScanner
    /// 今までのカメラ（保証書と同じ部品）
    case camera

    /// 使える方法。書類スキャンを使えない端末では、今までのカメラ
    static func preferred(isDocumentScannerSupported: Bool = VNDocumentCameraViewController.isSupported) -> ReceiptCaptureMode {
        isDocumentScannerSupported ? .documentScanner : .camera
    }
}

/// 書類スキャンの結果（Build 20）
enum ReceiptScanOutcome: Equatable {
    /// 1枚目のページ（JPEG。メモリの中だけ）
    case scanned(Data)
    /// 利用者がキャンセルした（何も読み取らない・何も残さない）
    case cancelled
    /// 書類スキャンが失敗した（今までのカメラで撮り直せるようにする）
    case failed

    /// 今までのカメラへ切り替えるか
    var fallsBackToCamera: Bool { self == .failed }
}

/// iOS の書類スキャン（VisionKit）でレシート1枚を撮る（Build 20）。
///
/// - 輪郭の検出・傾きの補正・切り抜きは iOS がこの iPhone の中で行う。写真は外部へ送らない・保存しない
/// - 何枚撮っても、使うのは1枚目だけ（レシートは1枚）
/// - 結果は1回だけ返す（二重に読み取りを始めない）
struct ReceiptDocumentScannerView: UIViewControllerRepresentable {
    let onFinish: (ReceiptScanOutcome) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: (ReceiptScanOutcome) -> Void
        private var didFinish = false

        init(onFinish: @escaping (ReceiptScanOutcome) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let data = scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.9) else {
                finish(.failed)
                return
            }
            finish(.scanned(data))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            finish(.cancelled)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finish(.failed)
        }

        private func finish(_ outcome: ReceiptScanOutcome) {
            guard !didFinish else { return }
            didFinish = true
            onFinish(outcome)
        }
    }
}
