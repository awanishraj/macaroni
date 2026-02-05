import Foundation
import CoreMediaIO
import os.log

private let logger = Logger(subsystem: "com.macaroni.camera", category: "sink")

/// Sink stream that receives frames from the main Macaroni app
/// Based on OBS's OBSCameraStreamSink implementation
class MacaroniSinkSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _formats: [CMIOExtensionStreamFormat]

    weak var deviceSource: MacaroniDeviceSource?
    var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, streamFormats: [CMIOExtensionStreamFormat], device: CMIOExtensionDevice) {
        self._formats = streamFormats
        super.init()

        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .sink,  // This is a SINK - receives frames from main app
            clockType: .hostTime,
            source: self
        )

        let formatCount = streamFormats.count
        logger.info("Sink stream created with ID: \(streamID.uuidString), \(formatCount) formats")
    }

    // MARK: - CMIOExtensionStreamSource

    var formats: [CMIOExtensionStreamFormat] {
        return _formats
    }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        return [
            .streamActiveFormatIndex,
            .streamFrameDuration,
            .streamSinkBufferQueueSize,
            .streamSinkBuffersRequiredForStartup,
            .streamSinkBufferUnderrunCount,
            .streamSinkEndOfData
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

        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 1
        }

        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }

        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let formatIndex = streamProperties.activeFormatIndex {
            activeFormatIndex = formatIndex
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        logger.info("Client authorized to start sink stream - client: \(String(describing: client))")
        self.client = client
        // Start streaming immediately when authorized - don't wait for startStream
        deviceSource?.startStreamingSink(client: client)
        return true
    }

    func startStream() throws {
        let hasClient = self.client != nil
        logger.info("Sink stream startStream called - client exists: \(hasClient)")
        // Also try to start here in case authorizedToStartStream wasn't called
        if let client = self.client {
            deviceSource?.startStreamingSink(client: client)
        } else {
            logger.warning("startStream called but no client available!")
        }
    }

    func stopStream() throws {
        logger.info("Sink stream stopStream called")
        deviceSource?.stopStreamingSink()
        client = nil
    }
}
