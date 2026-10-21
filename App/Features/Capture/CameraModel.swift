import AVFoundation
import SwiftUI
import UIKit

/// カメラの準備と撮影（AVFoundation）
final class CameraModel: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "studyplan.camera")
    private var isConfigured = false
    private var continuation: CheckedContinuation<UIImage?, Never>?

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .unavailable("カメラが許可されていません。設定アプリで許可するか、「写真から」を使ってください。")
                return
            }
        default:
            state = .unavailable("カメラが許可されていません。設定アプリで許可するか、「写真から」を使ってください。")
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable("この端末ではカメラを使えません。「写真から」を使ってください。")
            return
        }
        let session = self.session, output = self.output, needsConfiguration = !isConfigured
        isConfigured = true
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                if needsConfiguration {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    if session.canAddInput(input) { session.addInput(input) }
                    if session.canAddOutput(output) { session.addOutput(output) }
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                done.resume()
            }
        }
        state = .running
    }

    func stop() {
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    @MainActor
    func capture() async -> UIImage? {
        guard state == .running, continuation == nil else { return nil }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.continuation?.resume(returning: image)
            self.continuation = nil
        }
    }
}

/// カメラの映像を表示する
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
