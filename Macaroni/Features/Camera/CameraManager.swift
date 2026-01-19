import Foundation
import AVFoundation
import Combine
import CoreImage
import AppKit
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "CameraManager")

/// Represents a physical camera device
struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType

    var isBuiltIn: Bool {
        position != .unspecified
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CameraDevice, rhs: CameraDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages camera capture and processing
final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var cameras: [CameraDevice] = []
    @Published private(set) var selectedCamera: CameraDevice?
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var currentFrame: CIImage?
    @Published private(set) var processedFrame: NSImage?
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    /// Preview layer for displaying camera feed
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "com.macaroni.camera.video", qos: .userInteractive)

    private let frameProcessor = FrameProcessor()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        checkAuthorization()
        setupCameras()
        setupNotifications()
        setupShortcutHandlers()
        bindPreferences()
    }

    deinit {
        stopCapture()
    }

    // MARK: - Public API

    func requestAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted {
                    self?.setupCameras()
                }
            }
        }
    }

    func selectCamera(_ camera: CameraDevice) {
        let wasCapturing = isCapturing

        if wasCapturing {
            stopCapture()
        }

        selectedCamera = camera
        Preferences.shared.selectedCameraID = camera.id

        if wasCapturing {
            startCapture()
        }
    }

    func startCapture() {
        guard authorizationStatus == .authorized else {
            requestAuthorization()
            return
        }

        guard let camera = selectedCamera,
              let device = AVCaptureDevice(uniqueID: camera.id) else {
            return
        }

        setupCaptureSession(with: device)

        videoQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }

    func stopCapture() {
        videoQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isCapturing = false
                self?.currentFrame = nil
                self?.processedFrame = nil
            }
        }
    }

    func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    // MARK: - Frame Access for Virtual Camera

    /// Get the latest processed frame for virtual camera output
    func getLatestProcessedFrame() -> CIImage? {
        guard let frame = currentFrame else { return nil }
        return frameProcessor.process(frame)
    }

    // MARK: - Private Methods

    private func checkAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func setupCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        cameras = discoverySession.devices.map { device in
            CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                position: device.position,
                deviceType: device.deviceType
            )
        }

        // Restore saved camera or select first available
        if let savedID = Preferences.shared.selectedCameraID,
           let savedCamera = cameras.first(where: { $0.id == savedID }) {
            selectedCamera = savedCamera
        } else {
            selectedCamera = cameras.first
        }
    }

    private func setupCaptureSession(with device: AVCaptureDevice) {
        captureSession?.stopRunning()

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Add input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("Failed to create input for device")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Add output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        videoOutput = output
        captureSession = session

        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview
    }

    private func setupNotifications() {
        // Monitor for camera connect/disconnect
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupCameras()
        }

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AVCaptureDevice,
               device.uniqueID == self?.selectedCamera?.id {
                self?.stopCapture()
            }
            self?.setupCameras()
        }
    }

    private func setupShortcutHandlers() {
        NotificationCenter.default.publisher(for: .toggleCameraPreview)
            .sink { [weak self] _ in
                self?.toggleCapture()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .cycleRotation)
            .sink { [weak self] _ in
                self?.cycleRotation()
            }
            .store(in: &cancellables)
    }

    private func bindPreferences() {
        // React to preference changes
        Preferences.shared.$cameraRotation
            .dropFirst()
            .sink { [weak self] rotation in
                self?.frameProcessor.rotation = rotation
            }
            .store(in: &cancellables)

        Preferences.shared.$horizontalFlip
            .dropFirst()
            .sink { [weak self] flip in
                self?.frameProcessor.horizontalFlip = flip
            }
            .store(in: &cancellables)

        Preferences.shared.$verticalFlip
            .dropFirst()
            .sink { [weak self] flip in
                self?.frameProcessor.verticalFlip = flip
            }
            .store(in: &cancellables)

        Preferences.shared.$frameStyle
            .dropFirst()
            .sink { [weak self] style in
                self?.frameProcessor.frameStyle = style
            }
            .store(in: &cancellables)
    }

    private func cycleRotation() {
        Preferences.shared.cameraRotation = Preferences.shared.cameraRotation.next
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        // Process frame
        let processedCIImage = frameProcessor.process(ciImage)

        // Convert to NSImage for preview
        let context = CIContext()
        guard let cgImage = context.createCGImage(processedCIImage, from: processedCIImage.extent) else {
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        DispatchQueue.main.async { [weak self] in
            self?.currentFrame = ciImage
            self?.processedFrame = nsImage
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame was dropped, could log for debugging
    }
}
