import Foundation
import SwiftUI
import Combine
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "DisplayManager")

/// Represents a display mode with resolution information
struct DisplayMode: Identifiable, Hashable {
    let id: UUID = UUID()
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    var displayName: String {
        if isHiDPI {
            return "\(width) × \(height) @ \(Int(refreshRate))Hz (HiDPI)"
        } else {
            return "\(width) × \(height) @ \(Int(refreshRate))Hz"
        }
    }

    init(mode: CGDisplayMode) {
        self.mode = mode
        self.width = mode.width
        self.height = mode.height
        self.refreshRate = mode.refreshRate
        self.pixelWidth = mode.pixelWidth
        self.pixelHeight = mode.pixelHeight
        self.isHiDPI = mode.pixelWidth > mode.width
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.refreshRate == rhs.refreshRate &&
        lhs.isHiDPI == rhs.isHiDPI
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(refreshRate)
        hasher.combine(isHiDPI)
    }
}

/// Represents a connected display
struct Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let supportsDDC: Bool
    var currentBrightness: Int?
    var availableModes: [DisplayMode]
    var currentMode: DisplayMode?

    var displayID: CGDirectDisplayID { id }
}

/// Represents a resolution option that can be either native or achieved via virtual display
struct ResolutionOption {
    let width: Int
    let height: Int
    let isVirtual: Bool  // true = requires virtual display, false = native mode available
    let nativeMode: DisplayMode?
}

/// Manages display enumeration, brightness, and resolution
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var selectedDisplay: Display?
    @Published private(set) var displayRefreshToken: UUID = UUID()  // Changes when displays are refreshed
    @Published private(set) var crispHiDPIActive = false

    /// Physical display ID to use for DDC when crisp HiDPI mirroring is active
    private var physicalDisplayIDForDDC: CGDirectDisplayID?

    @Published var brightness: Double = 1.0 {
        didSet {
            if !isUpdatingFromExternal {
                setBrightness(brightness)

                // If user manually changes brightness, disable auto-brightness
                if !isUpdatingFromAutoBrightness && Preferences.shared.autoBrightnessEnabled {
                    Preferences.shared.autoBrightnessEnabled = false
                    logger.info("Auto-brightness disabled due to manual adjustment")
                }
            }
        }
    }

    private let ddcService = DDCService.shared
    private let virtualDisplayService = VirtualDisplayService.shared
    private let mirrorService = DisplayMirrorService.shared
    private var displayRefreshTimer: Timer?
    private var isUpdatingFromExternal = false
    private var isUpdatingFromAutoBrightness = false

    /// Set brightness from auto-brightness service without disabling auto mode
    func setAutoBrightness(_ value: Double) {
        isUpdatingFromAutoBrightness = true
        brightness = value
        isUpdatingFromAutoBrightness = false
    }
    private var cancellables = Set<AnyCancellable>()

    init() {
        refreshDisplays()
        restoreSelectedDisplay()
        setupDisplayNotifications()
        startBrightnessMonitoring()
        setupShortcutHandlers()
        restoreCrispHiDPIState()
    }

    /// Restore previously selected display from preferences
    private func restoreSelectedDisplay() {
        if let savedDisplayID = Preferences.shared.selectedDisplayID,
           let savedDisplay = displays.first(where: { $0.id == savedDisplayID }) {
            selectedDisplay = savedDisplay
            if let currentBrightness = savedDisplay.currentBrightness {
                isUpdatingFromExternal = true
                brightness = Double(currentBrightness) / 100.0
                isUpdatingFromExternal = false
            }
        }
    }

    /// Restore crisp HiDPI state from preferences
    private func restoreCrispHiDPIState() {
        guard Preferences.shared.crispHiDPIEnabled else { return }
        guard let display = selectedDisplay, !display.isBuiltIn else { return }

        // Parse saved resolution (format: "WIDTHxHEIGHT")
        let savedResolution = Preferences.shared.crispHiDPIResolution
        let components = savedResolution.replacingOccurrences(of: "VirtualResolution(logicalWidth: ", with: "")
            .replacingOccurrences(of: ", logicalHeight: ", with: "x")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: "x")

        if components.count == 2,
           let width = Int(components[0]),
           let height = Int(components[1]) {
            let resolution = VirtualResolution(logicalWidth: width, logicalHeight: height)
            logger.info("Restoring crisp HiDPI with \(resolution.displayName)")

            // Find the REAL physical display by checking which external display has DDC support
            // The virtual display won't have an IOAVService, so it won't show up in DDC external displays
            let ddcExternalDisplays = ddcService.getExternalDisplays()

            // Use first DDC-capable external display as the physical display
            let physicalID = ddcExternalDisplays.first ?? display.id
            physicalDisplayIDForDDC = physicalID

            // Delay to allow display system to settle after app launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.enableCrispHiDPI(resolution: resolution, physicalDisplayID: physicalID)
            }
        }
    }

    deinit {
        displayRefreshTimer?.invalidate()
        // Clean up virtual display on app quit
        if crispHiDPIActive {
            mirrorService.stopMirroring()
            virtualDisplayService.destroyVirtualDisplay()
        }
    }

    // MARK: - Public API

    func refreshDisplays() {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        guard CGGetActiveDisplayList(16, &displayIDs, &displayCount) == .success else {
            return
        }

        displays = displayIDs.prefix(Int(displayCount)).map { displayID in
            createDisplay(from: displayID)
        }

        // Select first external display, or first display if no external
        if selectedDisplay == nil {
            selectedDisplay = displays.first { !$0.isBuiltIn } ?? displays.first
            if let display = selectedDisplay, let currentBrightness = display.currentBrightness {
                isUpdatingFromExternal = true
                brightness = Double(currentBrightness) / 100.0
                isUpdatingFromExternal = false
            }
        } else if let currentSelected = selectedDisplay,
                  let updatedDisplay = displays.first(where: { $0.id == currentSelected.id }) {
            // Update selectedDisplay with refreshed data (including new currentMode)
            selectedDisplay = updatedDisplay
        }

        // Signal that displays were refreshed (for UI updates)
        displayRefreshToken = UUID()
    }

    func selectDisplay(_ display: Display) {
        selectedDisplay = display
        Preferences.shared.selectedDisplayID = display.id

        if let currentBrightness = display.currentBrightness {
            isUpdatingFromExternal = true
            brightness = Double(currentBrightness) / 100.0
            isUpdatingFromExternal = false
        }
    }

    func setBrightness(_ value: Double) {
        guard let display = selectedDisplay else { return }

        // When crisp HiDPI is active, we need to find the REAL physical display for DDC
        // The virtual display won't have an IOAVService, so we use DDC service cache
        let targetDisplayID: CGDirectDisplayID
        if crispHiDPIActive {
            // PRIMARY: Get physical display from DDC service cache - this is ALWAYS correct
            // because only the real physical display will have an IOAVService
            if let ddcPhysical = ddcService.getPhysicalDisplayWithDDC() {
                targetDisplayID = ddcPhysical
                if physicalDisplayIDForDDC != ddcPhysical {
                    physicalDisplayIDForDDC = ddcPhysical
                }
            } else if let mirrorDest = mirrorService.destination {
                targetDisplayID = mirrorDest
            } else if let physicalID = physicalDisplayIDForDDC {
                targetDisplayID = physicalID
            } else {
                targetDisplayID = display.id
            }
        } else {
            targetDisplayID = display.id
        }

        let brightnessInt = Int(value * 100)
        ddcService.setBrightness(brightnessInt, for: targetDisplayID)

        // Update display state
        if let index = displays.firstIndex(where: { $0.id == display.id }) {
            displays[index].currentBrightness = brightnessInt
            selectedDisplay = displays[index]
        }
    }

    func setResolution(_ mode: DisplayMode) {
        guard let display = selectedDisplay else { return }

        let config = UnsafeMutablePointer<CGDisplayConfigRef?>.allocate(capacity: 1)
        defer { config.deallocate() }

        guard CGBeginDisplayConfiguration(config) == .success else { return }

        CGConfigureDisplayWithDisplayMode(config.pointee, display.id, mode.mode, nil)

        CGCompleteDisplayConfiguration(config.pointee, .permanently)
    }

    /// Set resolution using a ResolutionOption (handles both native and virtual resolutions)
    func setResolutionOption(_ option: ResolutionOption, for display: Display) {
        if option.isVirtual {
            // Virtual resolution - create virtual display + mirror for crisp HiDPI
            logger.info("Setting virtual resolution: \(option.width)x\(option.height)")

            let virtualRes = VirtualResolution(logicalWidth: option.width, logicalHeight: option.height)

            // Select this display and enable virtual display
            selectedDisplay = display
            enableCrispHiDPI(resolution: virtualRes)
        } else {
            // Native resolution - use native mode, disable virtual display if active
            logger.info("Setting native resolution: \(option.width)x\(option.height)")

            // Disable virtual display first if active
            if crispHiDPIActive {
                disableCrispHiDPI()
                // Wait for virtual display to be disabled before setting native mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if let mode = option.nativeMode {
                        self?.setResolution(mode)
                    }
                }
            } else if let mode = option.nativeMode {
                setResolution(mode)
            }
        }
    }

    func getHiDPIModes(for display: Display) -> [DisplayMode] {
        return display.availableModes.filter { $0.isHiDPI }
    }

    // MARK: - Crisp HiDPI Scaling

    /// Enable crisp HiDPI mode for the selected external display
    /// Creates a virtual display at higher resolution and mirrors it to the physical display
    /// - Parameters:
    ///   - resolution: The virtual resolution to use
    ///   - physicalDisplayID: Optional explicit physical display ID for DDC (used during restore)
    /// - Returns: true if successfully enabled
    @discardableResult
    func enableCrispHiDPI(resolution: VirtualResolution, physicalDisplayID: CGDirectDisplayID? = nil) -> Bool {
        guard let display = selectedDisplay, !display.isBuiltIn else {
            logger.warning("Crisp HiDPI requires an external display")
            return false
        }

        logger.info("Enabling crisp HiDPI with \(resolution.displayName) for display \(display.name)")

        // Store physical display ID for DDC commands during mirroring
        // Use provided ID (from restore) or current display ID
        let physicalID = physicalDisplayID ?? display.id
        physicalDisplayIDForDDC = physicalID
        logger.info("Physical display ID for DDC: \(physicalID)")

        // Check if mirroring is already active for this display pair
        // If so, we only need to change the virtual display mode, not restart mirroring
        let needsMirroring = !mirrorService.isActive || mirrorService.destination != physicalID

        // Create virtual display with completion handler
        virtualDisplayService.createVirtualDisplay(resolution: resolution) { [weak self] success in
            guard let self = self else { return }

            guard success else {
                logger.error("Failed to create virtual display")
                return
            }

            guard let virtualID = self.virtualDisplayService.displayID else {
                logger.error("Virtual display created but ID not available")
                self.virtualDisplayService.destroyVirtualDisplay()
                return
            }

            // Only start mirroring if not already mirroring to this display
            if needsMirroring {
                guard self.mirrorService.startMirroring(source: virtualID, destination: physicalID) else {
                    logger.error("Failed to start mirroring")
                    self.virtualDisplayService.destroyVirtualDisplay()
                    return
                }
            }

            logger.info("Crisp HiDPI enabled successfully")
            self.crispHiDPIActive = true

            Preferences.shared.crispHiDPIEnabled = true
            Preferences.shared.crispHiDPIResolution = String(describing: resolution)
        }

        return true
    }

    /// Disable crisp HiDPI mode and restore normal display operation
    func disableCrispHiDPI() {
        logger.info("Disabling crisp HiDPI")

        // Clear physical display ID
        physicalDisplayIDForDDC = nil

        // Stop mirroring first
        mirrorService.stopMirroring()

        // Wait a moment before destroying virtual display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }

            // Destroy virtual display
            self.virtualDisplayService.destroyVirtualDisplay()

            logger.info("Crisp HiDPI disabled")
            self.crispHiDPIActive = false

            // Save preference
            Preferences.shared.crispHiDPIEnabled = false

            // Refresh displays to update state
            self.refreshDisplays()
        }
    }

    /// Check if crisp HiDPI is supported
    var isCrispHiDPISupported: Bool {
        virtualDisplayService.isSupported()
    }

    /// Get the current virtual resolution if crisp HiDPI is active
    var currentVirtualResolution: VirtualResolution? {
        virtualDisplayService.resolution
    }

    // MARK: - Resolution Helpers

    /// Get available resolutions for a display
    /// For external displays, offers virtual resolutions for crisp HiDPI scaling
    /// Only includes resolutions matching the display's native aspect ratio
    func availableResolutions(for display: Display) -> [ResolutionOption] {
        var resolutions: [ResolutionOption] = []

        // Get native panel resolution (highest non-HiDPI mode where pixels = logical)
        let maxNativeMode = display.availableModes
            .filter { !$0.isHiDPI && $0.width == $0.pixelWidth }
            .max { $0.width * $0.height < $1.width * $1.height }

        // Determine native aspect ratio
        let nativeAspect: Double
        if let native = maxNativeMode {
            nativeAspect = Double(native.width) / Double(native.height)
        } else {
            nativeAspect = 16.0 / 9.0  // Default to 16:9
        }

        // Helper to check if resolution matches aspect ratio (within 2% tolerance)
        func matchesAspect(_ width: Int, _ height: Int) -> Bool {
            let aspect = Double(width) / Double(height)
            return abs(aspect - nativeAspect) / nativeAspect < 0.02
        }

        // Minimum resolution height (576p - close to 600p, clean 16:9)
        let minHeight = 576

        // For external displays, add virtual resolutions for crisp scaling
        if !display.isBuiltIn {
            let virtualOptions: [(Int, Int)]

            let is16by9 = abs(nativeAspect - 16.0/9.0) < 0.02
            let is16by10 = abs(nativeAspect - 16.0/10.0) < 0.02

            if is16by9 {
                virtualOptions = [
                    (1024, 576),
                    (1152, 648),
                    (1280, 720),
                    (1366, 768),
                    (1600, 900),
                    (1792, 1008),
                    (1920, 1080),
                    (2048, 1152),
                    (2560, 1440),
                ]
            } else if is16by10 {
                virtualOptions = [
                    (1280, 800),
                    (1440, 900),
                    (1680, 1050),
                    (1920, 1200),
                    (2560, 1600),
                ]
            } else {
                virtualOptions = [
                    (1280, 720),
                    (1600, 900),
                    (1920, 1080),
                ]
            }

            for (w, h) in virtualOptions {
                guard h >= minHeight else { continue }
                if let native = maxNativeMode, native.width == w && native.height == h {
                    continue
                }
                resolutions.append(ResolutionOption(width: w, height: h, isVirtual: true, nativeMode: nil))
            }
        }

        // Add native HiDPI modes that match aspect ratio and minimum height
        for mode in display.availableModes.filter({ $0.isHiDPI }) {
            guard matchesAspect(mode.width, mode.height) && mode.height >= minHeight else { continue }
            if !resolutions.contains(where: { $0.width == mode.width && $0.height == mode.height }) {
                resolutions.append(ResolutionOption(width: mode.width, height: mode.height, isVirtual: false, nativeMode: mode))
            }
        }

        // Add native panel resolution (1:1 pixel mapping - always sharp)
        if let native = maxNativeMode {
            if !resolutions.contains(where: { $0.width == native.width && $0.height == native.height }) {
                resolutions.append(ResolutionOption(width: native.width, height: native.height, isVirtual: false, nativeMode: native))
            }
        }

        // Sort by height (smallest first)
        return resolutions.sorted { $0.height < $1.height }
    }

    /// Step resolution up (+1) or down (-1) through the available resolutions list
    func stepResolution(direction: Int) {
        guard let display = selectedDisplay else { return }

        let resolutions = availableResolutions(for: display)
        guard !resolutions.isEmpty else { return }

        // Determine current resolution
        let currentWidth: Int
        let currentHeight: Int

        if crispHiDPIActive, let virtualRes = currentVirtualResolution {
            currentWidth = virtualRes.logicalWidth
            currentHeight = virtualRes.logicalHeight
        } else if let currentMode = display.currentMode {
            currentWidth = currentMode.width
            currentHeight = currentMode.height
        } else {
            return
        }

        // Find current index
        let currentIndex: Int
        if let index = resolutions.firstIndex(where: { $0.width == currentWidth && $0.height == currentHeight }) {
            currentIndex = index
        } else {
            // Find closest by area
            let currentArea = currentWidth * currentHeight
            currentIndex = resolutions.enumerated().min(by: {
                abs($0.element.width * $0.element.height - currentArea) <
                abs($1.element.width * $1.element.height - currentArea)
            })?.offset ?? 0
        }

        // Step and clamp
        let newIndex = min(max(currentIndex + direction, 0), resolutions.count - 1)
        guard newIndex != currentIndex else { return }

        let selectedRes = resolutions[newIndex]
        setResolutionOption(selectedRes, for: display)
    }

    // MARK: - Shortcut Handlers

    private func setupShortcutHandlers() {
        NotificationCenter.default.publisher(for: .brightnessUp)
            .sink { [weak self] _ in
                self?.adjustBrightness(by: 0.1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .brightnessDown)
            .sink { [weak self] _ in
                self?.adjustBrightness(by: -0.1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .resolutionUp)
            .sink { [weak self] _ in
                self?.stepResolution(direction: -1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .resolutionDown)
            .sink { [weak self] _ in
                self?.stepResolution(direction: 1)
            }
            .store(in: &cancellables)
    }

    private func adjustBrightness(by delta: Double) {
        brightness = max(0, min(1, brightness + delta))
    }

    // MARK: - Private Methods

    private func createDisplay(from displayID: CGDirectDisplayID) -> Display {
        let name = getDisplayName(displayID) ?? "Display \(displayID)"
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0

        logger.info("Processing display \(displayID) - \(name), isBuiltIn: \(isBuiltIn)")

        // For external displays, try DDC
        var supportsDDC = false
        var currentBrightness: Int?

        if !isBuiltIn {
            logger.info("Checking DDC support for external display \(displayID)")
            supportsDDC = ddcService.supportsDDC(displayID: displayID)
            logger.info("DDC support: \(supportsDDC)")

            if supportsDDC {
                currentBrightness = ddcService.getBrightness(for: displayID)
                logger.info("Current brightness: \(currentBrightness ?? -1)")
            }
        }

        let modes = getDisplayModes(for: displayID)
        let currentMode = getCurrentMode(for: displayID, from: modes)
        let hidpiModes = modes.filter { $0.isHiDPI }

        logger.info("Display \(name) has \(modes.count) modes, \(hidpiModes.count) HiDPI")

        return Display(
            id: displayID,
            name: name,
            isBuiltIn: isBuiltIn,
            supportsDDC: supportsDDC,
            currentBrightness: currentBrightness,
            availableModes: modes,
            currentMode: currentMode
        )
    }

    private func getDisplayName(_ displayID: CGDirectDisplayID) -> String? {
        // Get display info from IOKit using modern API
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return "Display \(displayID)"
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any]

            if let names = info?[kDisplayProductName] as? [String: String],
               let name = names.values.first {
                IOObjectRelease(service)
                return name
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return "Display \(displayID)"
    }

    private func getDisplayModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        // Include all modes, including HiDPI variants and scaled modes
        // kCGDisplayShowDuplicateLowResolutionModes reveals HiDPI versions of resolutions
        let options: CFDictionary = [
            kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue as Any
        ] as CFDictionary

        guard let modesArray = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            logger.error("Failed to get display modes for display \(displayID)")
            return []
        }

        logger.info("Found \(modesArray.count) total modes for display \(displayID)")

        // Filter to unique resolutions and log HiDPI modes
        let modes = modesArray.map { DisplayMode(mode: $0) }
        let hidpiModes = modes.filter { $0.isHiDPI }
        logger.info("Found \(hidpiModes.count) HiDPI modes")

        // Log the max HiDPI mode for debugging
        if let maxHiDPI = hidpiModes.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            logger.info("Max HiDPI: \(maxHiDPI.width)x\(maxHiDPI.height) (pixels: \(maxHiDPI.pixelWidth)x\(maxHiDPI.pixelHeight))")
        }

        return modes
    }

    private func getCurrentMode(for displayID: CGDirectDisplayID, from modes: [DisplayMode]) -> DisplayMode? {
        guard let currentCGMode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }

        let isCurrentHiDPI = currentCGMode.pixelWidth > currentCGMode.width

        // First try exact match including refresh rate
        if let exactMatch = modes.first(where: { mode in
            mode.width == currentCGMode.width &&
            mode.height == currentCGMode.height &&
            mode.refreshRate == currentCGMode.refreshRate &&
            mode.isHiDPI == isCurrentHiDPI
        }) {
            return exactMatch
        }

        // Fallback: match by dimensions and pixel dimensions (ignore refresh rate)
        if let dimensionMatch = modes.first(where: { mode in
            mode.width == currentCGMode.width &&
            mode.height == currentCGMode.height &&
            mode.pixelWidth == currentCGMode.pixelWidth &&
            mode.pixelHeight == currentCGMode.pixelHeight
        }) {
            return dimensionMatch
        }

        // Last resort: match by pixel dimensions only
        return modes.first { mode in
            mode.pixelWidth == currentCGMode.pixelWidth &&
            mode.pixelHeight == currentCGMode.pixelHeight
        }
    }

    private func setupDisplayNotifications() {
        // Monitor for display configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Clear DDC caches when display configuration changes
            // This handles display connect/disconnect
            self?.ddcService.clearCaches()
            self?.refreshDisplays()
        }
    }

    private func startBrightnessMonitoring() {
        // Poll brightness periodically for external updates
        displayRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateBrightnessFromDisplay()
        }
    }

    private func updateBrightnessFromDisplay() {
        guard let display = selectedDisplay else {
            return
        }

        // When crisp HiDPI is active, get the REAL physical display from DDC service
        let targetDisplayID: CGDirectDisplayID
        if crispHiDPIActive {
            // PRIMARY: Get physical display from DDC service cache
            if let ddcPhysical = ddcService.getPhysicalDisplayWithDDC() {
                targetDisplayID = ddcPhysical
            } else if let mirrorDest = mirrorService.destination {
                targetDisplayID = mirrorDest
            } else if let physicalID = physicalDisplayIDForDDC {
                targetDisplayID = physicalID
            } else if display.supportsDDC {
                targetDisplayID = display.id
            } else {
                return
            }
        } else {
            guard display.supportsDDC else { return }
            targetDisplayID = display.id
        }

        guard let currentBrightness = ddcService.getBrightness(for: targetDisplayID) else {
            return
        }

        isUpdatingFromExternal = true
        brightness = Double(currentBrightness) / 100.0
        isUpdatingFromExternal = false
    }
}
