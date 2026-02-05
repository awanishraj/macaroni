import Foundation
import SystemExtensions
import CoreMediaIO
import os.log

extension Notification.Name {
    static let cameraExtensionDidUpdate = Notification.Name("cameraExtensionDidUpdate")
    static let cameraExtensionNeedsRestart = Notification.Name("cameraExtensionNeedsRestart")
}

/// Manages system extension activation for virtual camera and audio
final class SystemExtensionManager: NSObject, ObservableObject {
    static let shared = SystemExtensionManager()

    @Published private(set) var cameraExtensionStatus: ExtensionStatus = .unknown
    @Published private(set) var audioExtensionStatus: ExtensionStatus = .unknown

    private let logger = Logger(subsystem: "com.macaroni.app", category: "SystemExtension")

    // UUID from extension's Info.plist - MUST match exactly
    private let macaroniCameraDeviceUUID = "A8D7B8AA-65AD-4D21-9C42-F3D7A8D7B8AA"

    // Key for storing installed extension version
    private let installedCameraVersionKey = "installedCameraExtensionVersion"

    enum ExtensionStatus: Equatable {
        case unknown
        case notInstalled
        case activating
        case activated
        case needsUpdate
        case needsApproval
        case failed(String)

        static func == (lhs: ExtensionStatus, rhs: ExtensionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown),
                 (.notInstalled, .notInstalled),
                 (.activating, .activating),
                 (.activated, .activated),
                 (.needsUpdate, .needsUpdate),
                 (.needsApproval, .needsApproval):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private enum ExtensionType {
        case camera
        case audio

        var identifier: String {
            switch self {
            case .camera: return "com.macaroni.app.camera-extension"
            case .audio: return "com.macaroni.app.audio-extension"
            }
        }
    }

    private var pendingRequests: [String: ExtensionType] = [:]

    private override init() {
        super.init()
        // Check if extension is already installed on launch
        checkCameraExtensionStatus()
    }

    // MARK: - Extension Status Detection

    /// Check if the camera extension is already installed by looking for the Macaroni Camera device
    func checkCameraExtensionStatus() {
        // Allow CMIOExtension devices to be visible
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &property,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )

        // Find Macaroni Camera by UUID
        if findMacaroniCameraDevice() {
            // Check if update is needed
            if needsExtensionUpdate() {
                logger.info("Macaroni Camera device found but needs update")
                DispatchQueue.main.async {
                    self.cameraExtensionStatus = .needsUpdate
                }
            } else {
                logger.info("Macaroni Camera device found - extension is up to date")
                DispatchQueue.main.async {
                    self.cameraExtensionStatus = .activated
                }
            }
        } else {
            logger.info("Macaroni Camera device not found - extension not installed")
            DispatchQueue.main.async {
                self.cameraExtensionStatus = .notInstalled
            }
        }
    }

    /// Get the bundled extension version from the app bundle
    private func getBundledExtensionVersion() -> String? {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return nil }
        let extensionURL = bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/com.macaroni.app.camera-extension.systemextension")

        guard let bundle = Bundle(url: extensionURL) else {
            logger.warning("Could not find camera extension bundle at: \(extensionURL.path)")
            return nil
        }
        return bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// Check if the installed extension needs an update
    private func needsExtensionUpdate() -> Bool {
        guard let bundledVersion = getBundledExtensionVersion() else {
            logger.warning("Could not get bundled extension version")
            return false
        }
        let installedVersion = UserDefaults.standard.string(forKey: installedCameraVersionKey)

        logger.info("Version check - bundled: \(bundledVersion), installed: \(installedVersion ?? "none")")

        // If no installed version recorded, or versions differ, needs update
        if installedVersion == nil || installedVersion != bundledVersion {
            logger.info("Extension needs update")
            return true
        }
        return false
    }

    /// Record the current extension version as installed
    private func recordInstalledVersion() {
        if let version = getBundledExtensionVersion() {
            UserDefaults.standard.set(version, forKey: installedCameraVersionKey)
            logger.info("Recorded installed camera extension version: \(version)")
        }
    }

    /// Find the Macaroni Camera device by checking device UIDs
    private func findMacaroniCameraDevice() -> Bool {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard result == kCMIOHardwareNoError, dataSize > 0 else {
            return false
        }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: deviceCount)

        result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &dataSize,
            &devices
        )

        guard result == kCMIOHardwareNoError else {
            return false
        }

        // Check each device for our UUID
        for deviceID in devices {
            if let uid = getDeviceUID(deviceID), uid.contains(macaroniCameraDeviceUUID) {
                return true
            }
            // Also check by name as fallback
            if let name = getDeviceName(deviceID), name.contains("Macaroni") {
                return true
            }
        }

        return false
    }

    private func getDeviceUID(_ deviceID: CMIOObjectID) -> String? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard result == kCMIOHardwareNoError else { return nil }

        var uid: CFString? = nil
        result = CMIOObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &dataSize, &uid)
        guard result == kCMIOHardwareNoError, let uidString = uid else { return nil }

        return uidString as String
    }

    private func getDeviceName(_ deviceID: CMIOObjectID) -> String? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        var result = CMIOObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard result == kCMIOHardwareNoError else { return nil }

        var name: CFString? = nil
        result = CMIOObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &dataSize, &name)
        guard result == kCMIOHardwareNoError, let nameString = name else { return nil }

        return nameString as String
    }

    // MARK: - Public API

    /// Activate the camera extension (CMIOExtension)
    func activateCameraExtension() {
        activateExtension(.camera)
    }

    /// Activate the audio extension (DriverKit)
    func activateAudioExtension() {
        activateExtension(.audio)
    }

    /// Activate both extensions
    func activateAllExtensions() {
        activateCameraExtension()
        activateAudioExtension()
    }

    /// Deactivate the camera extension
    func deactivateCameraExtension() {
        deactivateExtension(.camera)
    }

    /// Deactivate the audio extension
    func deactivateAudioExtension() {
        deactivateExtension(.audio)
    }

    // MARK: - Private Methods

    private func activateExtension(_ type: ExtensionType) {
        logger.info("Requesting activation of extension: \(type.identifier)")

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: type.identifier,
            queue: .main
        )
        request.delegate = self
        pendingRequests[type.identifier] = type

        OSSystemExtensionManager.shared.submitRequest(request)
        updateStatus(for: type, status: .activating)
    }

    private func deactivateExtension(_ type: ExtensionType) {
        logger.info("Requesting deactivation of extension: \(type.identifier)")

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: type.identifier,
            queue: .main
        )
        request.delegate = self
        pendingRequests[type.identifier] = type

        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func updateStatus(for type: ExtensionType, status: ExtensionStatus) {
        DispatchQueue.main.async {
            switch type {
            case .camera:
                self.cameraExtensionStatus = status
            case .audio:
                self.audioExtensionStatus = status
            }
        }
    }

    private func extensionType(for identifier: String) -> ExtensionType? {
        return pendingRequests[identifier]
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing existing extension version \(existing.bundleVersion) with \(ext.bundleVersion)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("Extension activation needs user approval: \(request.identifier)")

        if let type = extensionType(for: request.identifier) {
            updateStatus(for: type, status: .needsApproval)
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.info("Extension request finished: \(request.identifier) result: \(String(describing: result))")

        guard let type = extensionType(for: request.identifier) else { return }
        pendingRequests.removeValue(forKey: request.identifier)

        switch result {
        case .completed:
            updateStatus(for: type, status: .activated)
            if type == .camera {
                recordInstalledVersion()
                // macOS caches CMIO devices per-process, so new extension devices
                // won't appear without app restart. Notify UI to show restart prompt.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cameraExtensionNeedsRestart, object: nil)
                }
            }
            logger.info("Extension activated successfully: \(request.identifier)")
        case .willCompleteAfterReboot:
            updateStatus(for: type, status: .needsApproval)
            logger.info("Extension will complete after reboot: \(request.identifier)")
        @unknown default:
            updateStatus(for: type, status: .failed("Unknown result"))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("Extension request failed: \(request.identifier) error: \(error.localizedDescription)")

        guard let type = extensionType(for: request.identifier) else { return }
        pendingRequests.removeValue(forKey: request.identifier)

        let nsError = error as NSError
        if nsError.domain == OSSystemExtensionErrorDomain {
            switch nsError.code {
            case OSSystemExtensionError.extensionNotFound.rawValue:
                updateStatus(for: type, status: .notInstalled)
            case OSSystemExtensionError.authorizationRequired.rawValue:
                updateStatus(for: type, status: .needsApproval)
            default:
                updateStatus(for: type, status: .failed(error.localizedDescription))
            }
        } else {
            updateStatus(for: type, status: .failed(error.localizedDescription))
        }
    }
}
