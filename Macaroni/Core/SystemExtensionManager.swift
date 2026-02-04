import Foundation
import SystemExtensions
import os.log

/// Manages system extension activation for virtual camera and audio
final class SystemExtensionManager: NSObject, ObservableObject {
    static let shared = SystemExtensionManager()

    @Published private(set) var cameraExtensionStatus: ExtensionStatus = .unknown
    @Published private(set) var audioExtensionStatus: ExtensionStatus = .unknown

    private let logger = Logger(subsystem: "com.macaroni.app", category: "SystemExtension")

    enum ExtensionStatus: Equatable {
        case unknown
        case notInstalled
        case activating
        case activated
        case needsApproval
        case failed(String)

        static func == (lhs: ExtensionStatus, rhs: ExtensionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown),
                 (.notInstalled, .notInstalled),
                 (.activating, .activating),
                 (.activated, .activated),
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
        print("🔵 [SystemExtensionManager] Activating extension: \(type.identifier)")

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: type.identifier,
            queue: .main
        )
        request.delegate = self
        pendingRequests[type.identifier] = type

        print("🔵 [SystemExtensionManager] Submitting request...")
        OSSystemExtensionManager.shared.submitRequest(request)
        print("🔵 [SystemExtensionManager] Request submitted, setting status to activating")

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
        print("🔴 [SystemExtensionManager] Request FAILED: \(error.localizedDescription)")
        print("🔴 [SystemExtensionManager] Error domain: \((error as NSError).domain), code: \((error as NSError).code)")

        guard let type = extensionType(for: request.identifier) else { return }
        pendingRequests.removeValue(forKey: request.identifier)

        let nsError = error as NSError
        if nsError.domain == OSSystemExtensionErrorDomain {
            switch nsError.code {
            case OSSystemExtensionError.extensionNotFound.rawValue:
                print("🔴 [SystemExtensionManager] Extension not found in bundle")
                updateStatus(for: type, status: .notInstalled)
            case OSSystemExtensionError.authorizationRequired.rawValue:
                print("🔴 [SystemExtensionManager] Authorization required")
                updateStatus(for: type, status: .needsApproval)
            default:
                print("🔴 [SystemExtensionManager] Other error: \(nsError.code)")
                updateStatus(for: type, status: .failed(error.localizedDescription))
            }
        } else {
            updateStatus(for: type, status: .failed(error.localizedDescription))
        }
    }
}
