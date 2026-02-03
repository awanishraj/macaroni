import Foundation
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "DisplayMirrorService")

/// Service to manage display mirroring
///
/// Used to mirror a virtual display to a physical display for crisp HiDPI scaling.
/// When a higher-resolution virtual display mirrors to a lower-resolution physical display,
/// macOS performs supersampling which produces crisp text and UI.
final class DisplayMirrorService {
    static let shared = DisplayMirrorService()

    private var mirroringActive = false
    private var sourceDisplayID: CGDirectDisplayID?
    private var destinationDisplayID: CGDirectDisplayID?

    private init() {
        logger.info("DisplayMirrorService initialized")
    }

    // MARK: - Public API

    /// Check if mirroring is currently active
    var isActive: Bool {
        mirroringActive
    }

    /// Get the source display ID (virtual display)
    var source: CGDirectDisplayID? {
        sourceDisplayID
    }

    /// Get the destination display ID (physical display)
    var destination: CGDirectDisplayID? {
        destinationDisplayID
    }

    /// Start mirroring source display to destination display
    /// - Parameters:
    ///   - source: The display ID to mirror from (virtual display)
    ///   - destination: The display ID to mirror to (physical display)
    /// - Returns: true if mirroring started successfully
    @discardableResult
    func startMirroring(source: CGDirectDisplayID, destination: CGDirectDisplayID) -> Bool {
        logger.info("Starting mirroring: \(source) -> \(destination)")

        // Stop any existing mirroring first
        if mirroringActive {
            stopMirroring()
        }

        var configRef: CGDisplayConfigRef?

        // Begin display configuration
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        guard beginResult == .success, let config = configRef else {
            logger.error("Failed to begin display configuration: \(beginResult.rawValue)")
            return false
        }

        // Configure mirroring: destination mirrors source
        // This makes the physical display (destination) show what's on the virtual display (source)
        let mirrorResult = CGConfigureDisplayMirrorOfDisplay(config, destination, source)
        guard mirrorResult == .success else {
            logger.error("Failed to configure mirroring: \(mirrorResult.rawValue)")
            CGCancelDisplayConfiguration(config)
            return false
        }

        // Complete configuration
        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeResult == .success else {
            logger.error("Failed to complete display configuration: \(completeResult.rawValue)")
            return false
        }

        logger.info("Mirroring started successfully")

        mirroringActive = true
        sourceDisplayID = source
        destinationDisplayID = destination

        return true
    }

    /// Stop mirroring and restore displays to independent mode
    func stopMirroring() {
        guard mirroringActive, let destination = destinationDisplayID else {
            logger.debug("No mirroring to stop")
            return
        }

        logger.info("Stopping mirroring for display \(destination)")

        var configRef: CGDisplayConfigRef?

        // Begin display configuration
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        guard beginResult == .success, let config = configRef else {
            logger.error("Failed to begin display configuration: \(beginResult.rawValue)")
            return
        }

        // Set mirror to kCGNullDirectDisplay to stop mirroring
        // This restores the display to independent mode
        let mirrorResult = CGConfigureDisplayMirrorOfDisplay(config, destination, kCGNullDirectDisplay)
        guard mirrorResult == .success else {
            logger.error("Failed to disable mirroring: \(mirrorResult.rawValue)")
            CGCancelDisplayConfiguration(config)
            return
        }

        // Complete configuration
        let completeResult = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeResult == .success else {
            logger.error("Failed to complete display configuration: \(completeResult.rawValue)")
            return
        }

        logger.info("Mirroring stopped successfully")

        mirroringActive = false
        sourceDisplayID = nil
        destinationDisplayID = nil
    }

    /// Get the primary (master) display ID for a mirrored set
    /// Returns nil if the display is not mirrored
    func getMirrorMaster(for displayID: CGDirectDisplayID) -> CGDirectDisplayID? {
        let master = CGDisplayMirrorsDisplay(displayID)
        return master != kCGNullDirectDisplay ? master : nil
    }

    /// Check if a display is currently mirroring another display
    func isMirroring(displayID: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay
    }

    /// Get all displays in a mirror set
    func getMirrorSet(for displayID: CGDirectDisplayID) -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0

        // First call to get count
        CGGetDisplaysWithRect(CGRect.infinite, 0, nil, &displayCount)

        var allDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &allDisplays, &displayCount)

        // Filter to only displays in the same mirror set
        let masterID = CGDisplayPrimaryDisplay(displayID)
        return allDisplays.filter { CGDisplayPrimaryDisplay($0) == masterID }
    }
}
