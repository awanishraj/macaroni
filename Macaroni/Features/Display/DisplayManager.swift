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

/// Manages display enumeration, brightness, and resolution
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published private(set) var selectedDisplay: Display?
    @Published private(set) var displayRefreshToken: UUID = UUID()  // Changes when displays are refreshed
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
        setupDisplayNotifications()
        startBrightnessMonitoring()
        setupShortcutHandlers()
    }

    deinit {
        displayRefreshTimer?.invalidate()
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

        let brightnessInt = Int(value * 100)
        ddcService.setBrightness(brightnessInt, for: display.id)

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

        // Don't refresh immediately - the system notification (didChangeScreenParametersNotification)
        // will trigger refreshDisplays() when the resolution actually changes (~1 second later)
        // This ensures we get the correct current mode after the change completes
    }

    func getHiDPIModes(for display: Display) -> [DisplayMode] {
        return display.availableModes.filter { $0.isHiDPI }
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

        NotificationCenter.default.publisher(for: .toggleResolution)
            .sink { [weak self] _ in
                self?.cycleResolution()
            }
            .store(in: &cancellables)
    }

    private func adjustBrightness(by delta: Double) {
        brightness = max(0, min(1, brightness + delta))
    }

    private func cycleResolution() {
        guard let display = selectedDisplay else { return }

        let hidpiModes = getHiDPIModes(for: display)
        guard !hidpiModes.isEmpty else { return }

        if let currentMode = display.currentMode,
           let currentIndex = hidpiModes.firstIndex(of: currentMode) {
            let nextIndex = (currentIndex + 1) % hidpiModes.count
            setResolution(hidpiModes[nextIndex])
        } else {
            setResolution(hidpiModes[0])
        }
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
        guard let display = selectedDisplay,
              display.supportsDDC,
              let currentBrightness = ddcService.getBrightness(for: display.id) else {
            return
        }

        isUpdatingFromExternal = true
        brightness = Double(currentBrightness) / 100.0
        isUpdatingFromExternal = false
    }
}
