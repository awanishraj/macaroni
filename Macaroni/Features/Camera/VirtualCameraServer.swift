import Foundation
import CoreVideo
import CoreImage
import IOSurface
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "VirtualCameraServer")

/// Server that shares camera frames with the virtual camera extension via IOSurface
final class VirtualCameraServer {
    static let shared = VirtualCameraServer()

    // IOSurface for frame sharing (double-buffered)
    private var surfaces: [IOSurface] = []
    private var currentSurfaceIndex = 0
    private let surfaceCount = 2

    // Frame dimensions
    private let width = 1920
    private let height = 1080

    // Mach port name for signaling
    static let portName = "com.macaroni.virtualcamera.frames"

    // CFMessagePort for signaling new frames
    private var messagePort: CFMessagePort?

    // Shared memory for metadata
    private var metadataSurface: IOSurface?

    // State
    private(set) var isRunning = false
    private let queue = DispatchQueue(label: "com.macaroni.virtualcamera.server", qos: .userInteractive)

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    // MARK: - Public API

    func start() {
        queue.async { [weak self] in
            self?.startServer()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopServer()
        }
    }

    /// Send a processed frame to the virtual camera
    func sendFrame(_ ciImage: CIImage) {
        guard isRunning else { return }

        queue.async { [weak self] in
            self?.writeFrame(ciImage)
        }
    }

    // MARK: - Private Methods

    private func startServer() {
        guard !isRunning else { return }

        // Create IOSurfaces for frame sharing
        createSurfaces()

        // Create metadata surface (for frame index, timestamp)
        createMetadataSurface()

        // Register Mach port for signaling
        registerMessagePort()

        isRunning = true
        logger.info("Virtual camera server started")
    }

    private func stopServer() {
        guard isRunning else { return }

        isRunning = false

        // Invalidate message port
        if let port = messagePort {
            CFMessagePortInvalidate(port)
            messagePort = nil
        }

        // Clear surfaces
        surfaces.removeAll()
        metadataSurface = nil

        logger.info("Virtual camera server stopped")
    }

    private func createSurfaces() {
        surfaces.removeAll()

        for i in 0..<surfaceCount {
            let properties: [IOSurfacePropertyKey: Any] = [
                .width: width,
                .height: height,
                .bytesPerElement: 4,
                .bytesPerRow: width * 4,
                .allocSize: width * height * 4,
                .pixelFormat: kCVPixelFormatType_32BGRA
            ]

            guard let surface = IOSurface(properties: properties) else {
                logger.error("Failed to create IOSurface \(i)")
                continue
            }

            // Set global ID for lookup by extension
            // Using a well-known seed based on index
            surface.setAttachment(i as CFTypeRef, forKey: "macaroni.surface.index")

            surfaces.append(surface)
            logger.debug("Created IOSurface \(i): seed=\(surface.seed)")
        }

        // Store surface IDs in a file for the extension to read
        saveSurfaceIDs()
    }

    private func createMetadataSurface() {
        // Small surface for metadata (frame index, timestamp, etc.)
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: 64,
            .height: 1,
            .bytesPerElement: 4,
            .bytesPerRow: 64 * 4,
            .allocSize: 64 * 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]

        metadataSurface = IOSurface(properties: properties)

        if let surface = metadataSurface {
            saveSurfaceID(surface, name: "metadata")
        }
    }

    private func saveSurfaceIDs() {
        // Save IOSurface IDs to a shared location
        let sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.macaroni.virtualcamera")

        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

        for (index, surface) in surfaces.enumerated() {
            saveSurfaceID(surface, name: "frame_\(index)")
        }
    }

    private func saveSurfaceID(_ surface: IOSurface, name: String) {
        let sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.macaroni.virtualcamera")

        let idFile = sharedDir.appendingPathComponent("\(name).id")

        // Use IOSurfaceCreateMachPort to get a mach port that can be shared
        let machPort = IOSurfaceCreateMachPort(surface)

        // Store the mach port send right in bootstrap
        // For simplicity, we'll use a file with surface seed (extension will use IOSurfaceLookup)
        let data = "\(surface.seed)".data(using: .utf8)
        try? data?.write(to: idFile)

        logger.debug("Saved surface \(name) with seed \(surface.seed)")
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
            VirtualCameraServer.portName as CFString,
            { (port, msgid, data, info) -> Unmanaged<CFData>? in
                // Handle incoming messages from extension (e.g., status queries)
                return nil
            },
            &context,
            nil
        )

        if let port = messagePort {
            let runLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            logger.info("Registered message port: \(VirtualCameraServer.portName)")
        } else {
            logger.warning("Failed to create message port - extension may not receive signals")
        }
    }

    private func writeFrame(_ ciImage: CIImage) {
        guard !surfaces.isEmpty else { return }

        // Get next surface (double buffering)
        let surfaceIndex = currentSurfaceIndex
        currentSurfaceIndex = (currentSurfaceIndex + 1) % surfaceCount

        let surface = surfaces[surfaceIndex]

        // Lock surface for writing
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }

        // Get base address
        let baseAddress = surface.baseAddress

        // Scale image to fit surface dimensions
        let scaleX = CGFloat(width) / ciImage.extent.width
        let scaleY = CGFloat(height) / ciImage.extent.height
        let scale = min(scaleX, scaleY)

        var scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the image
        let offsetX = (CGFloat(width) - scaledImage.extent.width) / 2 - scaledImage.extent.origin.x
        let offsetY = (CGFloat(height) - scaledImage.extent.height) / 2 - scaledImage.extent.origin.y
        scaledImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Render to surface
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        ciContext.render(
            scaledImage,
            toBitmap: baseAddress,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .BGRA8,
            colorSpace: colorSpace
        )

        // Update metadata
        updateMetadata(surfaceIndex: surfaceIndex)

        // Signal extension that new frame is ready
        signalNewFrame(surfaceIndex: surfaceIndex)
    }

    private func updateMetadata(surfaceIndex: Int) {
        guard let surface = metadataSurface else { return }

        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }

        let baseAddress = surface.baseAddress
        let metadata = baseAddress.assumingMemoryBound(to: UInt32.self)

        // Metadata layout:
        // [0] = frame counter
        // [1] = current surface index
        // [2] = timestamp low
        // [3] = timestamp high

        let timestamp = mach_absolute_time()

        metadata[0] = metadata[0] &+ 1  // Increment frame counter
        metadata[1] = UInt32(surfaceIndex)
        metadata[2] = UInt32(timestamp & 0xFFFFFFFF)
        metadata[3] = UInt32(timestamp >> 32)
    }

    private func signalNewFrame(surfaceIndex: Int) {
        // Send message to extension with surface index
        guard let remotePort = CFMessagePortCreateRemote(
            kCFAllocatorDefault,
            "com.macaroni.virtualcamera.extension" as CFString
        ) else {
            // Extension not running - that's OK
            return
        }

        var index = UInt32(surfaceIndex)
        let data = Data(bytes: &index, count: 4)

        CFMessagePortSendRequest(
            remotePort,
            0,  // message ID
            data as CFData,
            0.01,  // send timeout
            0,     // receive timeout
            nil,   // reply mode
            nil    // reply data
        )
    }
}
