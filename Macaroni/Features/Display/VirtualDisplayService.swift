import Foundation
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "VirtualDisplayService")

/// Represents a virtual resolution for HiDPI scaling
struct VirtualResolution: Hashable {
    let logicalWidth: Int
    let logicalHeight: Int

    /// Virtual resolution is 2x logical for HiDPI
    var virtualWidth: Int { logicalWidth * 2 }
    var virtualHeight: Int { logicalHeight * 2 }

    var displayName: String {
        "\(logicalWidth)x\(logicalHeight)"
    }

    /// Physical size in mm (affects DPI calculation)
    /// Using standard 27" monitor dimensions
    var sizeInMillimeters: CGSize {
        CGSize(width: 597, height: 336)
    }
}

/// Maximum virtual display size - large enough to support all HiDPI modes up to 1440p
/// Using 5120x2880 (5K) which is 2x of 2560x1440
private let maxVirtualWidth = 5120
private let maxVirtualHeight = 2880

/// Service to manage virtual display creation for crisp HiDPI scaling
///
/// Creates a virtual display at higher resolution that mirrors to a physical display.
/// When macOS renders at 2x scale and downsamples to the physical display,
/// text and UI appear crisp rather than blurry.
final class VirtualDisplayService {
    static let shared = VirtualDisplayService()

    private var virtualDisplay: CGVirtualDisplay?
    private var currentResolution: VirtualResolution?

    private init() {
        logger.info("VirtualDisplayService initialized")
    }

    // MARK: - Public API

    /// Check if a virtual display is currently active
    var isActive: Bool {
        virtualDisplay != nil
    }

    /// Get the display ID of the active virtual display
    var displayID: CGDirectDisplayID? {
        virtualDisplay?.displayID
    }

    /// Get the current virtual resolution
    var resolution: VirtualResolution? {
        currentResolution
    }

    /// Create or reuse virtual display and set it to the specified resolution
    /// - Parameters:
    ///   - resolution: The virtual resolution to use
    ///   - completion: Called when the virtual display is fully ready (HiDPI mode set)
    func createVirtualDisplay(resolution: VirtualResolution, completion: @escaping (Bool) -> Void) {
        // If virtual display already exists, just change the mode (no recreation needed)
        if let existingDisplay = virtualDisplay {
            logger.info("Reusing existing virtual display, switching to \(resolution.logicalWidth)x\(resolution.logicalHeight)")
            selectHiDPIMode(for: existingDisplay.displayID, resolution: resolution) { [weak self] success in
                if success {
                    self?.currentResolution = resolution
                }
                completion(success)
            }
            return
        }

        // Create new virtual display at max size to support all resolutions
        logger.info("Creating virtual display at \(maxVirtualWidth)x\(maxVirtualHeight)")

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "Macaroni Virtual Display"
        descriptor.vendorID = 0x1234
        descriptor.productID = 0x5678
        descriptor.serialNum = 0x0001
        descriptor.maxPixelsWide = UInt(maxVirtualWidth)
        descriptor.maxPixelsHigh = UInt(maxVirtualHeight)
        descriptor.sizeInMillimeters = CGSize(width: 597, height: 336)

        // Set color primaries (sRGB)
        descriptor.redPrimary = CGPoint(x: 0.64, y: 0.33)
        descriptor.greenPrimary = CGPoint(x: 0.30, y: 0.60)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)

        descriptor.queue = DispatchQueue.main

        descriptor.terminationHandler = { [weak self] displayID, error in
            logger.info("Virtual display \(displayID) terminated")
            if let error = error {
                logger.error("Termination error: \(String(describing: error))")
            }
            DispatchQueue.main.async {
                self?.virtualDisplay = nil
                self?.currentResolution = nil
            }
        }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            logger.error("Failed to create CGVirtualDisplay")
            completion(false)
            return
        }

        logger.info("Virtual display created with ID: \(display.displayID)")

        // Configure settings with all supported HiDPI modes
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1

        // Add all supported modes (16:9 resolutions)
        let supportedModes: [(Int, Int)] = [
            (1024, 576),   // 576p
            (1152, 648),   // 648p
            (1280, 720),   // 720p
            (1366, 768),   // 768p
            (1600, 900),   // 900p
            (1792, 1008),  // 1008p
            (1920, 1080),  // 1080p
            (2048, 1152),  // 1152p
            (2560, 1440),  // 1440p
        ]

        var modes: [CGVirtualDisplayMode] = []
        for (w, h) in supportedModes {
            let mode = CGVirtualDisplayMode(width: UInt(w), height: UInt(h), refreshRate: 60.0)
            modes.append(mode)
        }
        // Also add the max pixel resolution mode
        modes.append(CGVirtualDisplayMode(width: UInt(maxVirtualWidth), height: UInt(maxVirtualHeight), refreshRate: 60.0))

        settings.modes = modes

        guard display.apply(settings) else {
            logger.error("Failed to apply settings to virtual display")
            completion(false)
            return
        }

        virtualDisplay = display

        // Select the requested HiDPI mode after a brief delay for display to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.selectHiDPIMode(for: display.displayID, resolution: resolution) { success in
                if success {
                    self?.currentResolution = resolution
                }
                completion(success)
            }
        }
    }

    /// Explicitly select the HiDPI mode for the virtual display
    /// - Returns: true via completion if mode was set successfully
    private func selectHiDPIMode(for displayID: CGDirectDisplayID, resolution: VirtualResolution, completion: @escaping (Bool) -> Void) {
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modesArray = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            logger.error("Failed to get display modes for virtual display")
            completion(false)
            return
        }

        logger.info("Looking for \(resolution.logicalWidth)x\(resolution.logicalHeight) HiDPI mode")

        // Find HiDPI mode matching our logical resolution
        let targetMode = modesArray.first { mode in
            mode.width == resolution.logicalWidth &&
            mode.height == resolution.logicalHeight &&
            mode.pixelWidth > mode.width  // HiDPI indicator
        }

        if let mode = targetMode {
            logger.info("Found mode: \(mode.width)x\(mode.height) @\(mode.pixelWidth)x\(mode.pixelHeight)")

            let result = CGDisplaySetDisplayMode(displayID, mode, nil)
            if result == .success {
                logger.info("Mode switch complete")
                completion(true)
            } else {
                logger.error("CGDisplaySetDisplayMode failed: \(result.rawValue)")
                completion(false)
            }
        } else {
            logger.warning("Could not find HiDPI mode for \(resolution.logicalWidth)x\(resolution.logicalHeight)")
            let hidpiModes = modesArray.filter { $0.pixelWidth > $0.width }
            for mode in hidpiModes.prefix(10) {
                logger.debug("Available: \(mode.width)x\(mode.height) @\(mode.pixelWidth)x\(mode.pixelHeight)")
            }
            completion(false)
        }
    }

    /// Destroy the active virtual display
    func destroyVirtualDisplay() {
        guard virtualDisplay != nil else {
            logger.debug("No virtual display to destroy")
            return
        }

        logger.info("Destroying virtual display")

        // Simply release the reference - the system will clean up
        virtualDisplay = nil
        currentResolution = nil

        logger.info("Virtual display destroyed")
    }

    /// Check if CGVirtualDisplay APIs are available
    func isSupported() -> Bool {
        return true
    }
}
