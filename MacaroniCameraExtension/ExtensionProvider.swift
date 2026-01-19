import Foundation
import CoreMediaIO

/// Main entry point for the Camera Extension
/// This provides a virtual camera that apps can select
class MacaroniCameraProvider: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: MacaroniDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = MacaroniDeviceSource(localizedName: "Macaroni Camera")

        do {
            try provider.addDevice(deviceSource.device)
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
        let providerSource = MacaroniCameraProvider(clientQueue: nil)

        CMIOExtensionProvider.startService(provider: providerSource.provider)

        CFRunLoopRun()
    }
}
