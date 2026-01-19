import Foundation
import CoreGraphics

/// Service for managing display resolutions with focus on HiDPI modes
final class ResolutionService {
    static let shared = ResolutionService()

    private init() {}

    // MARK: - Public API

    /// Get all available display modes for a display
    /// - Parameter displayID: The display ID
    /// - Returns: Array of DisplayMode objects
    func getAllModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        guard let modesArray = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }

        return modesArray.map { DisplayMode(mode: $0) }
    }

    /// Get only HiDPI (Retina) modes for a display
    /// - Parameter displayID: The display ID
    /// - Returns: Array of HiDPI DisplayMode objects
    func getHiDPIModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        return getAllModes(for: displayID).filter { $0.isHiDPI }
    }

    /// Get the current display mode
    /// - Parameter displayID: The display ID
    /// - Returns: Current DisplayMode if available
    func getCurrentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let currentCGMode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }

        return DisplayMode(mode: currentCGMode)
    }

    /// Set the display resolution to a specific mode
    /// - Parameters:
    ///   - mode: The DisplayMode to set
    ///   - displayID: The display ID
    /// - Returns: True if successful
    @discardableResult
    func setMode(_ mode: DisplayMode, for displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?

        guard CGBeginDisplayConfiguration(&config) == .success else {
            return false
        }

        guard CGConfigureDisplayWithDisplayMode(config, displayID, mode.mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }

        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            return false
        }

        return true
    }

    /// Get unique resolutions (deduplicated by logical size)
    /// - Parameter displayID: The display ID
    /// - Returns: Array of unique DisplayMode objects
    func getUniqueResolutions(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let allModes = getAllModes(for: displayID)

        // Group by logical resolution and pick the best mode for each
        var uniqueModes: [String: DisplayMode] = [:]

        for mode in allModes {
            let key = "\(mode.width)x\(mode.height)"

            // Prefer HiDPI modes and higher refresh rates
            if let existing = uniqueModes[key] {
                if mode.isHiDPI && !existing.isHiDPI {
                    uniqueModes[key] = mode
                } else if mode.isHiDPI == existing.isHiDPI && mode.refreshRate > existing.refreshRate {
                    uniqueModes[key] = mode
                }
            } else {
                uniqueModes[key] = mode
            }
        }

        // Sort by resolution (descending)
        return uniqueModes.values.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    }

    /// Get unique HiDPI resolutions only
    /// - Parameter displayID: The display ID
    /// - Returns: Array of unique HiDPI DisplayMode objects
    func getUniqueHiDPIResolutions(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let hidpiModes = getHiDPIModes(for: displayID)

        // Group by logical resolution
        var uniqueModes: [String: DisplayMode] = [:]

        for mode in hidpiModes {
            let key = "\(mode.width)x\(mode.height)"

            if let existing = uniqueModes[key] {
                // Prefer higher refresh rate
                if mode.refreshRate > existing.refreshRate {
                    uniqueModes[key] = mode
                }
            } else {
                uniqueModes[key] = mode
            }
        }

        // Sort by resolution (descending)
        return uniqueModes.values.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    }

    /// Check if a display supports HiDPI modes
    /// - Parameter displayID: The display ID
    /// - Returns: True if the display has HiDPI modes available
    func supportsHiDPI(displayID: CGDirectDisplayID) -> Bool {
        return !getHiDPIModes(for: displayID).isEmpty
    }

    /// Get native resolution for a display
    /// - Parameter displayID: The display ID
    /// - Returns: The native DisplayMode if identifiable
    func getNativeMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        let allModes = getAllModes(for: displayID)

        // Native mode is typically the highest resolution
        return allModes.max { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }
    }

    /// Get common resolutions that match aspect ratio
    /// - Parameters:
    ///   - displayID: The display ID
    ///   - aspectRatio: Target aspect ratio (e.g., 16/9)
    /// - Returns: Filtered modes matching aspect ratio
    func getModes(for displayID: CGDirectDisplayID, matchingAspectRatio aspectRatio: Double, tolerance: Double = 0.01) -> [DisplayMode] {
        return getAllModes(for: displayID).filter { mode in
            let modeAspectRatio = Double(mode.width) / Double(mode.height)
            return abs(modeAspectRatio - aspectRatio) < tolerance
        }
    }
}

// MARK: - Resolution Categories

extension ResolutionService {
    /// Common resolution categories
    enum ResolutionCategory: String, CaseIterable {
        case uhd4K = "4K UHD"
        case qhd = "QHD"
        case fullHD = "Full HD"
        case hd = "HD"
        case other = "Other"

        var widthRange: ClosedRange<Int> {
            switch self {
            case .uhd4K: return 3840...4096
            case .qhd: return 2560...2560
            case .fullHD: return 1920...1920
            case .hd: return 1280...1280
            case .other: return 0...10000
            }
        }
    }

    /// Categorize modes by resolution type
    func categorizedModes(for displayID: CGDirectDisplayID) -> [ResolutionCategory: [DisplayMode]] {
        let allModes = getAllModes(for: displayID)
        var categorized: [ResolutionCategory: [DisplayMode]] = [:]

        for mode in allModes {
            let category = categorize(mode)
            categorized[category, default: []].append(mode)
        }

        return categorized
    }

    private func categorize(_ mode: DisplayMode) -> ResolutionCategory {
        let pixelWidth = mode.pixelWidth

        for category in ResolutionCategory.allCases {
            if category.widthRange.contains(pixelWidth) {
                return category
            }
        }

        return .other
    }
}
