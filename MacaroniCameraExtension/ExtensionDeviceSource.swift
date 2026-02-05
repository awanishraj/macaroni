import Foundation
import CoreMediaIO
import CoreVideo
import CoreGraphics
import CoreText
import os.log

private let logger = Logger(subsystem: "com.macaroni.camera", category: "device")

// Frame rate for the virtual camera
private let MacaroniCameraFrameRate: Int = 30

/// Represents the virtual camera device
/// Based on OBS's OBSCameraDeviceSource implementation
class MacaroniDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: MacaroniStreamSource!
    private var sinkSource: MacaroniSinkSource!

    // Streaming state
    private var _streamingCounter: Int = 0
    private var _streamingSinkCounter: Int = 0
    var sinkStarted = false
    var lastTimingInfo = CMSampleTimingInfo()

    // Placeholder frame generation
    private var placeholderTimer: DispatchSourceTimer?
    private var lastFrameTime: CFAbsoluteTime = 0
    private let placeholderQueue = DispatchQueue(label: "com.macaroni.camera.placeholder")

    // Timer for consuming buffers (OBS style)
    private var _consumeBufferTimer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(
        label: "com.macaroni.camera.timer",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem,
        target: .global(qos: .userInteractive)
    )

    init(localizedName: String, deviceUUID: UUID, sourceUUID: UUID, sinkUUID: UUID) {
        super.init()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceUUID,
            legacyDeviceID: nil,
            source: self
        )

        let streamFormats = createStreamFormats()

        // Create SOURCE stream (for apps like Zoom to read from)
        streamSource = MacaroniStreamSource(
            localizedName: "Macaroni Camera Stream",
            streamID: sourceUUID,
            streamFormats: streamFormats,
            device: device
        )
        streamSource.deviceSource = self

        // Create SINK stream (for main app to write to)
        sinkSource = MacaroniSinkSource(
            localizedName: "Macaroni Camera Sink",
            streamID: sinkUUID,
            streamFormats: streamFormats,
            device: device
        )
        sinkSource.deviceSource = self

        do {
            try device.addStream(streamSource.stream)
            try device.addStream(sinkSource.stream)
            logger.info("Device created with fixed UUIDs - device: \(deviceUUID), source: \(sourceUUID), sink: \(sinkUUID)")
        } catch {
            fatalError("Failed to add streams: \(error.localizedDescription)")
        }
    }

    // MARK: - Source Stream Control

    func startStreaming() {
        _streamingCounter += 1
        if _streamingCounter == 1 {
            startPlaceholderTimer()
        }
    }

    func stopStreaming() {
        if _streamingCounter > 1 {
            _streamingCounter -= 1
        } else {
            _streamingCounter = 0
            stopPlaceholderTimer()
        }
    }

    // MARK: - Placeholder Frame Generation

    private func startPlaceholderTimer() {
        placeholderTimer = DispatchSource.makeTimerSource(queue: placeholderQueue)
        placeholderTimer?.schedule(deadline: .now(), repeating: 1.0 / Double(MacaroniCameraFrameRate))
        placeholderTimer?.setEventHandler { [weak self] in
            self?.sendPlaceholderIfNeeded()
        }
        placeholderTimer?.resume()
    }

    private func stopPlaceholderTimer() {
        placeholderTimer?.cancel()
        placeholderTimer = nil
    }

    private func sendPlaceholderIfNeeded() {
        if sinkStarted {
            return
        }
        sendPlaceholderFrame()
    }

    private func sendPlaceholderFrame() {
        guard let pixelBuffer = createPlaceholderPixelBuffer() else {
            return
        }

        // Create sample buffer from pixel buffer
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard let format = formatDescription else { return }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(MacaroniCameraFrameRate)),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else {
            return
        }

        // Send to source stream
        streamSource.stream.send(
            buffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC))
        )
    }

    /// Creates a fresh placeholder pixel buffer each time (OBS approach)
    private func createPlaceholderPixelBuffer() -> CVPixelBuffer? {
        let width = 1920
        let height = 1080

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        // Use noneSkipFirst like OBS does
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        // Fill with dark background
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw text using CoreText - both normal and flipped versions
        let text = "Turn on camera from Macaroni menu" as CFString
        let fontSize: CGFloat = 48

        let font = CTFontCreateWithName("Helvetica Neue" as CFString, fontSize, nil)
        let textColor = CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: textColor
        ]

        guard let attributedString = CFAttributedStringCreate(kCFAllocatorDefault, text, attributes as CFDictionary) else {
            return buffer
        }
        let line = CTLineCreateWithAttributedString(attributedString)

        let textBounds = CTLineGetBoundsWithOptions(line, [])
        let textWidth = textBounds.width
        let textHeight = textBounds.height
        let centerX = CGFloat(width) / 2
        let spacing: CGFloat = 60  // Space between the two lines

        // Draw normal text (upper position)
        let normalY = (CGFloat(height) / 2) + spacing
        context.saveGState()
        context.textPosition = CGPoint(x: centerX - textWidth / 2, y: normalY)
        CTLineDraw(line, context)
        context.restoreGState()

        // Draw horizontally flipped text (lower position)
        let flippedY = (CGFloat(height) / 2) - spacing - textHeight
        context.saveGState()
        // Move to center, flip horizontally, move back
        context.translateBy(x: centerX, y: flippedY + textHeight / 2)
        context.scaleBy(x: -1, y: 1)
        context.translateBy(x: -centerX, y: -(flippedY + textHeight / 2))
        context.textPosition = CGPoint(x: centerX - textWidth / 2, y: flippedY)
        CTLineDraw(line, context)
        context.restoreGState()

        return buffer
    }

    // MARK: - Sink Stream Control (OBS style with timer)

    // Store current client for timer to use
    private var _currentSinkClient: CMIOExtensionClient?

    func startStreamingSink(client: CMIOExtensionClient) {
        // Cancel any existing timer first to handle reconnection
        if let existingTimer = _consumeBufferTimer {
            existingTimer.cancel()
            _consumeBufferTimer = nil
        }

        _streamingSinkCounter += 1
        sinkStarted = true
        _currentSinkClient = client

        // Timer polls at 3x frame rate to avoid missing frames (OBS approach)
        _consumeBufferTimer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        _consumeBufferTimer!.schedule(
            deadline: .now(),
            repeating: 1.0 / (Double(MacaroniCameraFrameRate) * 3.0),
            leeway: .seconds(0)
        )
        _consumeBufferTimer!.setEventHandler { [weak self] in
            guard let self = self, let currentClient = self._currentSinkClient else { return }
            self.consumeBuffer(currentClient)
        }
        _consumeBufferTimer!.resume()
    }

    func stopStreamingSink() {
        sinkStarted = false
        _currentSinkClient = nil
        if _streamingSinkCounter > 1 {
            _streamingSinkCounter -= 1
        } else {
            _streamingSinkCounter = 0
        }
        if let timer = _consumeBufferTimer {
            timer.cancel()
            _consumeBufferTimer = nil
        }
    }

    // MARK: - Buffer Consumption (OBS style)

    private func consumeBuffer(_ client: CMIOExtensionClient) {
        guard sinkStarted else { return }

        sinkSource.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, error in
            guard let self = self else { return }

            if error != nil {
                return
            }

            if let sampleBuffer = sampleBuffer {
                self.lastFrameTime = CFAbsoluteTimeGetCurrent()
                self.lastTimingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())

                let output = CMIOExtensionScheduledOutput(
                    sequenceNumber: sequenceNumber,
                    hostTimeInNanoseconds: UInt64(
                        self.lastTimingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)
                    )
                )

                if self._streamingCounter > 0 {
                    self.streamSource.stream.send(
                        sampleBuffer,
                        discontinuity: [],
                        hostTimeInNanoseconds: UInt64(
                            sampleBuffer.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)
                        )
                    )
                }

                self.sinkSource.stream.notifyScheduledOutputChanged(output)
            }
        }
    }

    // MARK: - Stream Format

    private func createStreamFormats() -> [CMIOExtensionStreamFormat] {
        // 1920x1080 @ 30fps (main format)
        let format = CMIOExtensionStreamFormat(
            formatDescription: createFormatDescription(width: 1920, height: 1080, pixelFormat: kCVPixelFormatType_32BGRA),
            maxFrameDuration: CMTime(value: 1, timescale: Int32(MacaroniCameraFrameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(MacaroniCameraFrameRate)),
            validFrameDurations: nil
        )

        return [format]
    }

    private func createFormatDescription(width: Int32, height: Int32, pixelFormat: OSType) -> CMFormatDescription {
        var formatDescription: CMFormatDescription?

        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: pixelFormat,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let description = formatDescription else {
            fatalError("Failed to create format description")
        }

        return description
    }

    // MARK: - CMIOExtensionDeviceSource

    var availableProperties: Set<CMIOExtensionProperty> {
        return [
            .deviceTransportType,
            .deviceModel
        ]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])

        if properties.contains(.deviceTransportType) {
            // Virtual transport type (0x76727475 = 'vrtu')
            deviceProperties.transportType = 0x76727475
        }

        if properties.contains(.deviceModel) {
            deviceProperties.model = "Macaroni Virtual Camera"
        }

        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // Device properties are read-only
    }
}
