import Foundation
import CoreMediaIO

/// Represents the virtual camera device
class MacaroniDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: MacaroniStreamSource!

    init(localizedName: String) {
        super.init()

        let deviceID = UUID()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: nil,
            source: self
        )

        // Create and add stream
        let streamID = UUID()
        streamSource = MacaroniStreamSource(
            localizedName: "Macaroni Camera Stream",
            streamID: streamID,
            streamFormat: createStreamFormat(),
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }
    }

    // MARK: - Stream Format

    private func createStreamFormat() -> CMIOExtensionStreamFormat {
        // 1920x1080 @ 30fps, BGRA format
        let formatDescription = createFormatDescription(
            width: 1920,
            height: 1080,
            pixelFormat: kCVPixelFormatType_32BGRA
        )

        return CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration: CMTime(value: 1, timescale: 30),
            minFrameDuration: CMTime(value: 1, timescale: 30),
            validFrameDurations: nil
        )
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
