import Foundation
import CoreMediaIO
import IOKit
import os.log

/// Provides the video stream for the virtual camera
class MacaroniStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let device: CMIOExtensionDevice

    private let streamFormat: CMIOExtensionStreamFormat
    private var frameTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.macaroni.camera.timer", qos: .userInteractive)

    private var sequenceNumber: UInt64 = 0
    private var isStreaming = false

    // Connection to main app for frame data
    private var frameConnection: NSXPCConnection?

    private let logger = Logger(subsystem: "com.macaroni.camera", category: "stream")

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self.streamFormat = streamFormat
        self.device = device
        super.init()

        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    deinit {
        stopStreaming()
    }

    // MARK: - CMIOExtensionStreamSource

    var formats: [CMIOExtensionStreamFormat] {
        return [streamFormat]
    }

    var activeFormatIndex: Int = 0 {
        didSet {
            if activeFormatIndex != oldValue {
                // Format changed
            }
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        return [
            .streamActiveFormatIndex,
            .streamFrameDuration
        ]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])

        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }

        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: 30)
        }

        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let formatIndex = streamProperties.activeFormatIndex {
            activeFormatIndex = formatIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        return true
    }

    func startStream() throws {
        guard !isStreaming else { return }

        isStreaming = true
        startFrameGeneration()
        logger.info("Stream started")
    }

    func stopStream() throws {
        guard isStreaming else { return }

        isStreaming = false
        stopStreaming()
        logger.info("Stream stopped")
    }

    // MARK: - Frame Generation

    private func startFrameGeneration() {
        frameTimer = DispatchSource.makeTimerSource(queue: timerQueue)
        frameTimer?.schedule(deadline: .now(), repeating: .milliseconds(33)) // ~30fps

        frameTimer?.setEventHandler { [weak self] in
            self?.generateAndSendFrame()
        }

        frameTimer?.resume()
    }

    private func stopStreaming() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func generateAndSendFrame() {
        guard isStreaming else { return }

        // Try to get frame from main app via IPC
        if let pixelBuffer = getFrameFromMainApp() {
            sendFrame(pixelBuffer)
        } else {
            // Generate placeholder frame
            if let placeholderBuffer = createPlaceholderFrame() {
                sendFrame(placeholderBuffer)
            }
        }
    }

    private func getFrameFromMainApp() -> CVPixelBuffer? {
        // In a full implementation, this would:
        // 1. Connect to main app via XPC/IPC
        // 2. Request the latest processed frame
        // 3. Return the frame data

        // For now, return nil to use placeholder
        return nil
    }

    private func sendFrame(_ pixelBuffer: CVPixelBuffer) {
        let timing = createTimingInfo()

        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription?

        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let format = formatDescription else { return }

        var timingInfoCopy = timing
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timingInfoCopy,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else { return }

        do {
            try stream.send(
                buffer,
                discontinuity: [],
                hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * 1_000_000_000)
            )
            sequenceNumber += 1
        } catch {
            logger.error("Failed to send frame: \(error.localizedDescription)")
        }
    }

    private func createTimingInfo() -> CMSampleTimingInfo {
        let now = CMClockGetTime(CMClockGetHostTimeClock())

        return CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )
    }

    // MARK: - Placeholder Frame

    private func createPlaceholderFrame() -> CVPixelBuffer? {
        let width = 1920
        let height = 1080

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        // Fill with a pattern (dark gray with Macaroni text)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // Fill with dark gray
        let gray: UInt32 = 0xFF303030  // BGRA: Gray
        let pixelData = baseAddress.assumingMemoryBound(to: UInt32.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * (bytesPerRow / 4) + x
                pixelData[offset] = gray
            }
        }

        // Draw a simple pattern (gradient bars)
        let barHeight = height / 8
        let colors: [UInt32] = [
            0xFF404040, 0xFF505050, 0xFF606060, 0xFF707070,
            0xFF606060, 0xFF505050, 0xFF404040, 0xFF303030
        ]

        for (index, color) in colors.enumerated() {
            let startY = index * barHeight
            for y in startY..<min(startY + barHeight, height) {
                for x in 0..<width {
                    let offset = y * (bytesPerRow / 4) + x
                    pixelData[offset] = color
                }
            }
        }

        return buffer
    }
}
