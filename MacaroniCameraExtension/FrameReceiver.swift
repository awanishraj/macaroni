import Foundation
import CoreVideo
import IOSurface
import os.log

private let logger = Logger(subsystem: "com.macaroni.camera", category: "FrameReceiver")

/// Receives frames from the main app via shared IOSurface
final class FrameReceiver {
    static let shared = FrameReceiver()

    // Cached surfaces
    private var frameSurfaces: [IOSurface] = []
    private var metadataSurface: IOSurface?

    // Frame dimensions (must match server)
    let width = 1920
    let height = 1080

    // Message port for receiving signals
    private var messagePort: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?

    // Callback when new frame is available
    var onFrameReady: ((Int) -> Void)?

    // State
    private(set) var isConnected = false
    private var lastFrameIndex: UInt32 = 0

    private init() {}

    // MARK: - Public API

    func connect() {
        logger.info("Attempting to connect to main app...")

        // Load surface IDs from shared location
        loadSurfaces()

        // Register message port for frame signals
        registerMessagePort()

        if !frameSurfaces.isEmpty {
            isConnected = true
            logger.info("Connected to main app - \(self.frameSurfaces.count) surfaces available")
        } else {
            logger.warning("Could not connect to main app - no surfaces found")
        }
    }

    func disconnect() {
        isConnected = false

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let port = messagePort {
            CFMessagePortInvalidate(port)
            messagePort = nil
        }

        frameSurfaces.removeAll()
        metadataSurface = nil

        logger.info("Disconnected from main app")
    }

    /// Get the latest frame as a CVPixelBuffer
    func getLatestFrame() -> CVPixelBuffer? {
        guard isConnected, !frameSurfaces.isEmpty else {
            return nil
        }

        // Read metadata to get current surface index
        let surfaceIndex = getCurrentSurfaceIndex()

        guard surfaceIndex < frameSurfaces.count else {
            return nil
        }

        let surface = frameSurfaces[surfaceIndex]

        // Create CVPixelBuffer from IOSurface
        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ] as CFDictionary,
            &unmanagedPixelBuffer
        )

        if status != kCVReturnSuccess {
            logger.error("Failed to create pixel buffer from IOSurface: \(status)")
            return nil
        }

        return unmanagedPixelBuffer?.takeRetainedValue()
    }

    /// Get current frame counter for change detection
    func getFrameCounter() -> UInt32 {
        guard let surface = metadataSurface else { return 0 }

        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }

        let baseAddress = surface.baseAddress
        let metadata = baseAddress.assumingMemoryBound(to: UInt32.self)
        return metadata[0]
    }

    // MARK: - Private Methods

    private func loadSurfaces() {
        let sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.macaroni.virtualcamera")

        frameSurfaces.removeAll()

        // Load frame surfaces
        for i in 0..<2 {
            let idFile = sharedDir.appendingPathComponent("frame_\(i).id")

            guard let seedString = try? String(contentsOf: idFile, encoding: .utf8),
                  let seed = UInt32(seedString) else {
                logger.warning("Could not read surface ID for frame_\(i)")
                continue
            }

            // Look up IOSurface by seed
            guard let surface = IOSurfaceLookup(seed) else {
                logger.warning("Could not find IOSurface with seed \(seed)")
                continue
            }

            frameSurfaces.append(surface)
            logger.debug("Loaded frame surface \(i) with seed \(seed)")
        }

        // Load metadata surface
        let metadataFile = sharedDir.appendingPathComponent("metadata.id")
        if let seedString = try? String(contentsOf: metadataFile, encoding: .utf8),
           let seed = UInt32(seedString),
           let surface = IOSurfaceLookup(seed) {
            metadataSurface = surface
            logger.debug("Loaded metadata surface with seed \(seed)")
        }
    }

    private func registerMessagePort() {
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        messagePort = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            "com.macaroni.virtualcamera.extension" as CFString,
            { (port, msgid, data, info) -> Unmanaged<CFData>? in
                guard let info = info else { return nil }

                let receiver = Unmanaged<FrameReceiver>.fromOpaque(info).takeUnretainedValue()

                if let data = data as Data? {
                    // Parse surface index from message
                    let surfaceIndex = data.withUnsafeBytes { $0.load(as: UInt32.self) }
                    receiver.onFrameReady?(Int(surfaceIndex))
                }

                return nil
            },
            &context,
            nil
        )

        if let port = messagePort {
            runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            logger.info("Registered extension message port")
        } else {
            logger.warning("Failed to create extension message port")
        }
    }

    private func getCurrentSurfaceIndex() -> Int {
        guard let surface = metadataSurface else {
            // If no metadata, alternate between surfaces
            return Int(lastFrameIndex % 2)
        }

        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }

        let baseAddress = surface.baseAddress
        let metadata = baseAddress.assumingMemoryBound(to: UInt32.self)
        let frameCounter = metadata[0]
        let surfaceIndex = metadata[1]

        // Check if frame changed
        if frameCounter != lastFrameIndex {
            lastFrameIndex = frameCounter
        }

        return Int(surfaceIndex)
    }
}
