import Foundation
import AVFoundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "VirtualCameraPreview")

/// Captures and displays output from the Macaroni Virtual Camera
final class VirtualCameraPreview: NSObject, ObservableObject {
    static let shared = VirtualCameraPreview()

    @Published private(set) var isCapturing = false

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureSession: AVCaptureSession?

    private let sessionQueue = DispatchQueue(label: "com.macaroni.virtualcamera.preview")

    override init() {
        super.init()
    }

    /// Start capturing from Macaroni Camera
    func startCapture() {
        guard !isCapturing else { return }

        guard let device = findMacaroniCamera() else {
            logger.warning("Macaroni Camera not found")
            return
        }

        sessionQueue.async { [weak self] in
            self?.setupCaptureSession(with: device)
            self?.captureSession?.startRunning()

            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }

    /// Stop capturing
    func stopCapture() {
        guard isCapturing else { return }

        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()

            DispatchQueue.main.async {
                self?.isCapturing = false
            }
        }
    }

    // MARK: - Private

    private func findMacaroniCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        for device in discoverySession.devices {
            if device.localizedName.contains("Macaroni") {
                return device
            }
        }

        return nil
    }

    private func setupCaptureSession(with device: AVCaptureDevice) {
        captureSession?.stopRunning()

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("Failed to create input for Macaroni Camera")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        captureSession = session

        // Create preview layer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            self.previewLayer = preview
        }
    }
}
