import Foundation
import CoreMediaIO
import IOKit
import os.log

private let logger = Logger(subsystem: "com.macaroni.camera", category: "stream")

/// Provides the video stream for the virtual camera
class MacaroniStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let device: CMIOExtensionDevice

    private let streamFormat: CMIOExtensionStreamFormat
    private var frameTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.macaroni.camera.timer", qos: .userInteractive)

    private var sequenceNumber: UInt64 = 0
    private var isStreaming = false

    // Frame receiver for getting frames from main app
    private let frameReceiver = FrameReceiver.shared

    // Track frame changes
    private var lastFrameCounter: UInt32 = 0

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

        // Connect to main app
        frameReceiver.connect()

        // Set up frame callback
        frameReceiver.onFrameReady = { [weak self] surfaceIndex in
            // Frame is ready - will be picked up on next timer tick
        }
    }

    deinit {
        stopStreaming()
        frameReceiver.disconnect()
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

        // Try to reconnect if not connected
        if !frameReceiver.isConnected {
            frameReceiver.connect()
        }

        startFrameGeneration()
        logger.info("Stream started, connected to main app: \(self.frameReceiver.isConnected)")
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

        // Try to get frame from main app
        if frameReceiver.isConnected, let pixelBuffer = frameReceiver.getLatestFrame() {
            let currentCounter = frameReceiver.getFrameCounter()

            // Only send if frame changed (or send anyway for smooth output)
            sendFrame(pixelBuffer)
            lastFrameCounter = currentCounter
        } else {
            // Generate placeholder frame when main app not connected
            if let placeholderBuffer = createPlaceholderFrame() {
                sendFrame(placeholderBuffer)
            }
        }
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

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelData = baseAddress.assumingMemoryBound(to: UInt32.self)

        // Fill with dark gray background
        let bgColor: UInt32 = 0xFF1a1a1a  // BGRA: Dark gray

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * (bytesPerRow / 4) + x
                pixelData[offset] = bgColor
            }
        }

        // Draw "Macaroni Camera" text area (centered box)
        let boxWidth = 400
        let boxHeight = 100
        let boxX = (width - boxWidth) / 2
        let boxY = (height - boxHeight) / 2
        let boxColor: UInt32 = 0xFF2d2d2d  // Slightly lighter gray

        for y in boxY..<(boxY + boxHeight) {
            for x in boxX..<(boxX + boxWidth) {
                let offset = y * (bytesPerRow / 4) + x
                pixelData[offset] = boxColor
            }
        }

        // Draw border around box
        let borderColor: UInt32 = 0xFF4a9eff  // Blue accent
        let borderWidth = 2

        // Top and bottom borders
        for x in boxX..<(boxX + boxWidth) {
            for b in 0..<borderWidth {
                let topOffset = (boxY + b) * (bytesPerRow / 4) + x
                let bottomOffset = (boxY + boxHeight - 1 - b) * (bytesPerRow / 4) + x
                pixelData[topOffset] = borderColor
                pixelData[bottomOffset] = borderColor
            }
        }

        // Left and right borders
        for y in boxY..<(boxY + boxHeight) {
            for b in 0..<borderWidth {
                let leftOffset = y * (bytesPerRow / 4) + (boxX + b)
                let rightOffset = y * (bytesPerRow / 4) + (boxX + boxWidth - 1 - b)
                pixelData[leftOffset] = borderColor
                pixelData[rightOffset] = borderColor
            }
        }

        // Draw simple "M" icon in center
        let iconSize = 40
        let iconX = (width - iconSize) / 2
        let iconY = (height - iconSize) / 2
        let iconColor: UInt32 = 0xFFffffff  // White

        // Draw M shape
        for y in 0..<iconSize {
            // Left leg
            for x in 0..<6 {
                let offset = (iconY + y) * (bytesPerRow / 4) + (iconX + x)
                pixelData[offset] = iconColor
            }
            // Right leg
            for x in (iconSize - 6)..<iconSize {
                let offset = (iconY + y) * (bytesPerRow / 4) + (iconX + x)
                pixelData[offset] = iconColor
            }
            // Left diagonal (top half)
            if y < iconSize / 2 {
                let diagX = iconX + 6 + y / 2
                for dx in 0..<4 {
                    let offset = (iconY + y) * (bytesPerRow / 4) + diagX + dx
                    if diagX + dx < iconX + iconSize {
                        pixelData[offset] = iconColor
                    }
                }
            }
            // Right diagonal (top half)
            if y < iconSize / 2 {
                let diagX = iconX + iconSize - 10 - y / 2
                for dx in 0..<4 {
                    let offset = (iconY + y) * (bytesPerRow / 4) + diagX + dx
                    if diagX + dx > iconX {
                        pixelData[offset] = iconColor
                    }
                }
            }
        }

        return buffer
    }
}
