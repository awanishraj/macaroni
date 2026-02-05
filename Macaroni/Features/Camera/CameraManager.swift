import Foundation
import AVFoundation
import Combine
import CoreImage  // For CIImage in frame processing
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "CameraManager")

/// Represents a physical camera device
struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType

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
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    private var captureSession: AVCaptureSession?
    private let videoQueue = DispatchQueue(label: "com.macaroni.camera.video", qos: .userInteractive)

    private let frameProcessor = FrameProcessor()
    private var cancellables = Set<AnyCancellable>()

    // Sink sender for passing frames to camera extension
    private let sinkSender = CMIOSinkSender.shared

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

        // Connect to virtual camera sink (may fail if extension not active, which is fine)
        _ = sinkSender.connect()

        videoQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCapturing = true
            }
        }
    }

    func stopCapture() {
        // Disconnect from virtual camera sink
        sinkSender.disconnect()

        videoQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isCapturing = false
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

        cameras = discoverySession.devices
            .filter { !$0.localizedName.contains("Macaroni") } // Filter out our virtual camera
            .map { device in
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

        // Add output for frame processing
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        captureSession = session
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

        // Extension updates now require app restart (macOS limitation)
        // The CameraMenuView listens for .cameraExtensionNeedsRestart and shows UI
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

        // Process frame and send to virtual camera
        let processedCIImage = frameProcessor.process(ciImage)
        sinkSender.sendFrame(processedCIImage)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame dropped - normal under heavy load
    }
}
