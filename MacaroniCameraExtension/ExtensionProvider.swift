import Foundation
import CoreMediaIO
import os.log

private let logger = Logger(subsystem: "com.macaroni.camera", category: "provider")

/// Main entry point for the Camera Extension
/// This provides a virtual camera that apps can select
class MacaroniCameraProvider: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: MacaroniDeviceSource!

    init(clientQueue: DispatchQueue?, deviceUUID: UUID, sourceUUID: UUID, sinkUUID: UUID) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = MacaroniDeviceSource(
            localizedName: "Macaroni Camera",
            deviceUUID: deviceUUID,
            sourceUUID: sourceUUID,
            sinkUUID: sinkUUID
        )

        do {
            try provider.addDevice(deviceSource.device)
            logger.info("Device added successfully")
        } catch {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    // MARK: - CMIOExtensionProviderSource

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])

        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Macaroni"
        }

        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // Provider properties are read-only
    }

    func connect(to client: CMIOExtensionClient) throws {
        // Called when a client connects
    }

    func disconnect(from client: CMIOExtensionClient) {
        // Called when a client disconnects
    }
}

// MARK: - Extension Entry Point

@main
class MacaroniCameraExtensionMain {
    static func main() {
        // Read UUIDs from Info.plist (exactly like OBS does)
        guard let deviceUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacaroniCameraDeviceUUID") as? String,
              let sourceUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacaroniCameraSourceUUID") as? String,
              let sinkUUIDString = Bundle.main.object(forInfoDictionaryKey: "MacaroniCameraSinkUUID") as? String
        else {
            fatalError("Missing camera UUIDs in Info.plist")
        }

        guard let deviceUUID = UUID(uuidString: deviceUUIDString),
              let sourceUUID = UUID(uuidString: sourceUUIDString),
              let sinkUUID = UUID(uuidString: sinkUUIDString)
        else {
            fatalError("Invalid camera UUIDs in Info.plist")
        }

        let providerSource = MacaroniCameraProvider(
            clientQueue: nil,
            deviceUUID: deviceUUID,
            sourceUUID: sourceUUID,
            sinkUUID: sinkUUID
        )

        CMIOExtensionProvider.startService(provider: providerSource.provider)

        CFRunLoopRun()
    }
}
