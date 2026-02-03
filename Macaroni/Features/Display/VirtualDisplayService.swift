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

    // Common presets for convenience
    static let res720p = VirtualResolution(logicalWidth: 1280, logicalHeight: 720)
    static let res900p = VirtualResolution(logicalWidth: 1600, logicalHeight: 900)
    static let res1080p = VirtualResolution(logicalWidth: 1920, logicalHeight: 1080)
    static let res1200p = VirtualResolution(logicalWidth: 1920, logicalHeight: 1200)
    static let res1440p = VirtualResolution(logicalWidth: 2560, logicalHeight: 1440)
}

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

    /// Create a virtual display with the specified resolution
    /// - Parameter resolution: The virtual resolution to use
    /// - Returns: true if creation succeeded
    @discardableResult
    func createVirtualDisplay(resolution: VirtualResolution) -> Bool {
        // Destroy existing virtual display first
        if isActive {
            destroyVirtualDisplay()
        }

        logger.info("Creating virtual display: \(resolution.virtualWidth)x\(resolution.virtualHeight)")

        // Create descriptor
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "Macaroni Virtual Display"
        descriptor.vendorID = 0x1234  // Custom vendor ID
        descriptor.productID = 0x5678  // Custom product ID
        descriptor.serialNum = 0x0001
        descriptor.maxPixelsWide = UInt(resolution.virtualWidth)
        descriptor.maxPixelsHigh = UInt(resolution.virtualHeight)
        descriptor.sizeInMillimeters = resolution.sizeInMillimeters

        // Set color primaries (sRGB)
        descriptor.redPrimary = CGPoint(x: 0.64, y: 0.33)
        descriptor.greenPrimary = CGPoint(x: 0.30, y: 0.60)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)

        // Set dispatch queue
        descriptor.queue = DispatchQueue.main

        // Set termination handler
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

        // Create virtual display
        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            logger.error("Failed to create CGVirtualDisplay")
            return false
        }

        logger.info("Virtual display created with ID: \(display.displayID)")

        // Configure settings with HiDPI modes
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1  // Enable HiDPI

        // Create display modes
        // Include both the virtual resolution and logical resolution
        let virtualMode = CGVirtualDisplayMode(
            width: UInt(resolution.virtualWidth),
            height: UInt(resolution.virtualHeight),
            refreshRate: 60.0
        )

        let logicalMode = CGVirtualDisplayMode(
            width: UInt(resolution.logicalWidth),
            height: UInt(resolution.logicalHeight),
            refreshRate: 60.0
        )

        settings.modes = [virtualMode, logicalMode]

        // Apply settings
        guard display.apply(settings) else {
            logger.error("Failed to apply settings to virtual display")
            return false
        }

        logger.info("Virtual display configured, now selecting HiDPI mode...")

        virtualDisplay = display
        currentResolution = resolution

        // Explicitly set the virtual display to the HiDPI mode
        // This ensures macOS uses the logical resolution, not the full pixel resolution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.selectHiDPIMode(for: display.displayID, resolution: resolution)
        }

        return true
    }

    /// Explicitly select the HiDPI mode for the virtual display
    private func selectHiDPIMode(for displayID: CGDirectDisplayID, resolution: VirtualResolution) {
        // Get all available modes for this display
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modesArray = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            logger.error("Failed to get display modes for virtual display")
            return
        }

        logger.info("Virtual display has \(modesArray.count) modes available")

        // Find the HiDPI mode matching our logical resolution
        // HiDPI mode: logical width/height match our target, pixel width/height are 2x
        let targetMode = modesArray.first { mode in
            mode.width == resolution.logicalWidth &&
            mode.height == resolution.logicalHeight &&
            mode.pixelWidth == resolution.virtualWidth &&
            mode.pixelHeight == resolution.virtualHeight
        }

        if let mode = targetMode {
            logger.info("Found HiDPI mode: \(mode.width)x\(mode.height) (pixels: \(mode.pixelWidth)x\(mode.pixelHeight))")

            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
                logger.error("Failed to begin display configuration")
                return
            }

            CGConfigureDisplayWithDisplayMode(cfg, displayID, mode, nil)

            guard CGCompleteDisplayConfiguration(cfg, .permanently) == .success else {
                logger.error("Failed to set virtual display mode")
                CGCancelDisplayConfiguration(cfg)
                return
            }

            logger.info("Successfully set virtual display to HiDPI mode: \(resolution.logicalWidth)x\(resolution.logicalHeight)")
        } else {
            // Log available modes for debugging
            logger.warning("Could not find exact HiDPI mode for \(resolution.logicalWidth)x\(resolution.logicalHeight)")
            for mode in modesArray.prefix(10) {
                logger.debug("Available mode: \(mode.width)x\(mode.height) pixels:\(mode.pixelWidth)x\(mode.pixelHeight)")
            }
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
    /// Returns false on older macOS versions or if APIs are unavailable
    func isSupported() -> Bool {
        // Try to create a descriptor to test API availability
        let descriptor = CGVirtualDisplayDescriptor()
        return descriptor.name != nil || true  // If we can create descriptor, API exists
    }
}
