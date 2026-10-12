import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// カメラで保証書を撮る。撮影した写真は、カメラが作ったデータ（HEIC か JPEG）をそのまま渡す（再圧縮しない）。
/// カメラを使えない・許可されていないときは、理由と「設定を開く」を表示する（アプリは止まらない）。
struct WarrantyCameraView: View {
    let onCapture: (Data, UTType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var controller = WarrantyCameraController()
    @State private var state: CameraState = .checking
    @State private var isCapturing = false

    enum CameraState: Equatable {
        case checking
        case ready
        case denied
        case unavailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .checking:
                ProgressView().tint(.white)
            case .ready:
                WarrantyCameraPreview(session: controller.session)
                    .ignoresSafeArea()
                    .accessibilityLabel("カメラの映像")
                shutter
            case .denied:
                message(
                    "カメラの使用が許可されていません",
                    detail: "設定アプリの「生活OS」でカメラを許可すると撮影できます。写真から選ぶこともできます。",
                    showsSettings: true
                )
            case .unavailable:
                message(
                    "この端末ではカメラを使えません",
                    detail: "「写真から選ぶ」で追加できます。",
                    showsSettings: false
                )
            }
            VStack {
                HStack {
                    Button("閉じる") { dismiss() }
                        .font(LifeTypography.button)
                        .foregroundStyle(.white)
                        .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
                    Spacer()
                }
                .padding(.horizontal, LifeSpacing.md)
                Spacer()
            }
        }
        .task {
            state = await controller.prepare()
            if state == .ready {
                controller.start()
            }
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var shutter: some View {
        VStack {
            Spacer()
            Text("保証書・レシート・製品ラベルを枠いっぱいに")
                .font(LifeTypography.footnote)
                .foregroundStyle(.white)
                .padding(.bottom, LifeSpacing.sm)
            Button {
                guard !isCapturing else { return }
                isCapturing = true
                controller.capture { result in
                    isCapturing = false
                    if case let (data, type)? = result {
                        onCapture(data, type)
                        dismiss()
                    }
                }
            } label: {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().fill(.white).padding(8))
            }
            .disabled(isCapturing)
            .accessibilityLabel("撮影する")
            .padding(.bottom, LifeSpacing.xl)
        }
    }

    private func message(_ title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: LifeSpacing.md) {
            Image(systemName: "camera")
                .font(.largeTitle)
            Text(title)
                .font(LifeTypography.headline)
            Text(detail)
                .font(LifeTypography.callout)
                .multilineTextAlignment(.center)
            if showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("設定を開く") { openURL(url) }
                    .font(LifeTypography.button)
                    .padding(.horizontal, LifeSpacing.lg)
                    .frame(minHeight: LifeSpacing.buttonHeight)
                    .background(Capsule().fill(.white))
                    .foregroundStyle(.black)
            }
        }
        .foregroundStyle(.white)
        .padding(LifeSpacing.xl)
    }
}

/// AVFoundation のカメラ。写真は fileDataRepresentation（カメラが作ったファイルのデータ）をそのまま使う
final class WarrantyCameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lifeos.warranty.camera")
    private var isConfigured = false
    private var completion: (((Data, UTType)?) -> Void)?
    private var capturedType: UTType = .jpeg

    /// 許可を確かめて、カメラを準備する
    func prepare() async -> WarrantyCameraView.CameraState {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            return .denied
        }
        return configure() ? .ready : .unavailable
    }

    private func configure() -> Bool {
        guard !isConfigured else { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        isConfigured = true
        return true
    }

    func start() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// 撮影する。HEIC が使えれば HEIC、無ければ JPEG（どちらもカメラが作ったまま）
    func capture(completion: @escaping ((Data, UTType)?) -> Void) {
        self.completion = completion
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            capturedType = .heic
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            capturedType = .jpeg
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: (Data, UTType)?
        if error == nil, let data = photo.fileDataRepresentation() {
            result = (data, capturedType)
        } else {
            result = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.completion?(result)
            self?.completion = nil
        }
    }
}

/// カメラの映像
struct WarrantyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
