import Foundation
import CoreMediaIO
import CoreVideo
import CoreImage
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "CMIOSinkSender")

/// Sends frames to the virtual camera extension via CoreMediaIO sink stream
final class CMIOSinkSender {
    static let shared = CMIOSinkSender()

    // Fixed output dimensions (1080p landscape)
    private let width = 1920
    private let height = 1080

    private var deviceID: CMIODeviceID = 0
    private var sinkStreamID: CMIOStreamID = 0
    private var sinkQueue: CMSimpleQueue?
    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMFormatDescription?

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isConnected = false

    private let queue = DispatchQueue(label: "com.macaroni.sinksender", qos: .userInteractive)

    // UUID from extension's Info.plist
    private let macaroniCameraDeviceUUID = "A8D7B8AA-65AD-4D21-9C42-F3D7A8D7B8AA"

    // Reconnection state
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 20  // More attempts, extension may take time

    private init() {}

    // MARK: - Public API

    /// Connect to the virtual camera's sink stream (non-blocking)
    func connect() -> Bool {
        var result = false
        queue.sync {
            if isConnected {
                result = true
                return
            }
            result = connectInternal()
        }
        return result
    }

    /// Disconnect from the sink stream
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopReconnectTimer()
            if self.deviceID != 0 && self.sinkStreamID != 0 {
                CMIODeviceStopStream(self.deviceID, self.sinkStreamID)
            }
            self.resetState()
            logger.info("Disconnected from sink")
        }
    }

    /// Force reconnect to the sink stream (used after extension update)
    func forceReconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.deviceID != 0 && self.sinkStreamID != 0 {
                CMIODeviceStopStream(self.deviceID, self.sinkStreamID)
            }
            self.resetState()
            self.reconnectAttempt = 0
            self.startReconnectTimer()
        }
    }

    /// Send a CIImage frame to the virtual camera
    func sendFrame(_ ciImage: CIImage) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Skip if not connected (reconnect timer will handle it)
            guard self.isConnected, let sinkQueue = self.sinkQueue else {
                return
            }

            guard let pixelBuffer = self.createPixelBuffer(from: ciImage),
                  let sampleBuffer = self.createSampleBuffer(from: pixelBuffer) else {
                return
            }

            // Enqueue to sink
            let unmanagedBuffer = Unmanaged.passRetained(sampleBuffer)
            let status = CMSimpleQueueEnqueue(sinkQueue, element: unmanagedBuffer.toOpaque())
            if status != noErr {
                unmanagedBuffer.release()
                logger.warning("CMSimpleQueueEnqueue failed: \(status)")
                self.isConnected = false
            }
        }
    }

    // MARK: - Private Methods

    private func resetState() {
        sinkQueue = nil
        pixelBufferPool = nil
        deviceID = 0
        sinkStreamID = 0
        isConnected = false
    }

    private func startReconnectTimer() {
        stopReconnectTimer()

        reconnectTimer = DispatchSource.makeTimerSource(queue: queue)
        reconnectTimer?.schedule(deadline: .now() + 0.5, repeating: 1.0)
        reconnectTimer?.setEventHandler { [weak self] in
            self?.attemptReconnect()
        }
        reconnectTimer?.resume()
    }

    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    private func attemptReconnect() {
        reconnectAttempt += 1
        if connectInternal() {
            stopReconnectTimer()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sinkReconnected, object: nil)
            }
        } else if reconnectAttempt >= maxReconnectAttempts {
            stopReconnectTimer()
        }
    }

    private func connectInternal() -> Bool {
        guard let foundDeviceID = findDeviceByUUID() else {
            return false
        }
        self.deviceID = foundDeviceID

        guard let sinkID = getSinkStreamID(deviceID: foundDeviceID) else {
            return false
        }
        self.sinkStreamID = sinkID

        guard let queue = getSinkQueue(streamID: sinkID) else {
            return false
        }
        self.sinkQueue = queue

        createFormatDescription()

        let startStatus = CMIODeviceStartStream(foundDeviceID, sinkID)
        if startStatus != noErr {
            return false
        }

        createPixelBufferPool()
        isConnected = true
        return true
    }

    /// Find device by UUID
    private func findDeviceByUUID() -> CMIODeviceID? {
        // First, ensure virtual camera devices are visible
        // This is required after extension updates
        var allowProperty = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &allowProperty,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )

        guard let targetUUID = CFUUIDCreateFromString(kCFAllocatorDefault, macaroniCameraDeviceUUID as CFString) else {
            return nil
        }

        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var deviceIDs = [CMIODeviceID](repeating: 0, count: deviceCount)

        status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )

            var uid: CFString?
            var uidSize = UInt32(MemoryLayout<CFString?>.size)

            let uidStatus = CMIOObjectGetPropertyData(
                deviceID,
                &uidAddress,
                0,
                nil,
                uidSize,
                &uidSize,
                &uid
            )

            if uidStatus == noErr, let uidString = uid {
                if let deviceUUID = CFUUIDCreateFromString(kCFAllocatorDefault, uidString) {
                    if CFEqual(targetUUID, deviceUUID) {
                        return deviceID
                    }
                }
            }
        }

        return nil
    }

    /// Get sink stream ID (sink is the second stream at index 1)
    private func getSinkStreamID(deviceID: CMIODeviceID) -> CMIOStreamID? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr else { return nil }

        let streamCount = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        guard streamCount >= 2 else { return nil }

        var streamIDs = [CMIOStreamID](repeating: 0, count: streamCount)

        status = CMIOObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &dataSize, &streamIDs)

        guard status == noErr else { return nil }

        return streamIDs[1]  // Sink is at index 1
    }

    private func getSinkQueue(streamID: CMIOStreamID) -> CMSimpleQueue? {
        var queue: Unmanaged<CMSimpleQueue>?

        let status = CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &queue)

        guard status == noErr, let unmanaged = queue else {
            logger.error("CMIOStreamCopyBufferQueue failed: \(status)")
            return nil
        }

        return unmanaged.takeRetainedValue()
    }

    private func createFormatDescription() {
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
    }

    private func createPixelBufferPool() {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
    }

    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        // Scale to fill frame (aspect fill) - crops edges to fill
        let scaleX = CGFloat(width) / ciImage.extent.width
        let scaleY = CGFloat(height) / ciImage.extent.height
        let scale = max(scaleX, scaleY)

        var scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the scaled image
        let offsetX = (CGFloat(width) - scaledImage.extent.width) / 2 - scaledImage.extent.origin.x
        let offsetY = (CGFloat(height) - scaledImage.extent.height) / 2 - scaledImage.extent.origin.y
        scaledImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        ciContext.render(
            scaledImage,
            to: buffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        return buffer
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        guard let format = formatDescription else { return nil }

        let timestamp = UInt64(mach_absolute_time())
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = timestamp * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTimeMake(value: Int64(nanoseconds), timescale: Int32(NSEC_PER_SEC)),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sinkReconnected = Notification.Name("sinkReconnected")
}
