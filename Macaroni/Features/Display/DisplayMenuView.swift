import SwiftUI

struct DisplayMenuView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @EnvironmentObject var preferences: Preferences

    @StateObject private var solarService = SolarBrightnessService()
    @State private var resolutionIndex: Double = 0
    @State private var isEditingResolution: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display name (if multiple displays)
            if displayManager.displays.count > 1 {
                displaySelector
            }

            if let display = displayManager.selectedDisplay {
                // Brightness Control
                brightnessSection(for: display)

                // Resolution Control (handles both native and virtual resolutions seamlessly)
                resolutionSection(for: display)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onAppear {
            solarService.displayManager = displayManager
            if preferences.autoBrightnessEnabled {
                solarService.start()
            }
            updateResolutionIndex()
        }
        .onChange(of: displayManager.displayRefreshToken) { _, _ in
            // Called when displays are refreshed (e.g., after resolution change completes)
            // Small delay to ensure system state is fully updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateResolutionIndex()
            }
        }
        .onChange(of: displayManager.selectedDisplay?.id) { _, _ in
            // Called when user switches between displays
            updateResolutionIndex()
        }
    }

    // MARK: - Display Selector

    private var displaySelector: some View {
        Picker("Display", selection: Binding(
            get: { displayManager.selectedDisplay?.id ?? 0 },
            set: { id in
                if let display = displayManager.displays.first(where: { $0.id == id }) {
                    displayManager.selectDisplay(display)
                    updateResolutionIndex()
                }
            }
        )) {
            ForEach(displayManager.displays) { display in
                Text(display.name)
                    .tag(display.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    // MARK: - Brightness Section

    private func brightnessSection(for display: Display) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with percentage and auto toggle
            HStack {
                Text("Brightness")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()

                if display.supportsDDC {
                    HStack(alignment: .center, spacing: 6) {
                        // Brightness percentage
                        Text("\(Int(displayManager.brightness * 100))%")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        // Auto brightness toggle as icon button
                        Button {
                            preferences.autoBrightnessEnabled.toggle()
                        } label: {
                            Image(systemName: preferences.autoBrightnessEnabled ? "a.circle.fill" : "a.circle")
                                .font(.system(size: 12))
                                .foregroundColor(preferences.autoBrightnessEnabled ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(preferences.autoBrightnessEnabled ? "Auto brightness: On" : "Auto brightness: Off")
                    }
                }
            }

            // Slider
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if display.supportsDDC {
                    Slider(value: $displayManager.brightness, in: 0...1)
                        .controlSize(.small)
                } else {
                    Slider(value: .constant(1.0), in: 0...1)
                        .controlSize(.small)
                        .disabled(true)
                        .opacity(0.5)
                }

                Image(systemName: "sun.max")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // DDC unavailable message
            if !display.supportsDDC {
                Text("DDC/CI unavailable - use monitor controls")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    // MARK: - Resolution Section

    private func resolutionSection(for display: Display) -> some View {
        let resolutions = availableResolutions(for: display)

        return VStack(alignment: .leading, spacing: 8) {
            // Header - show current resolution
            HStack {
                Text("Resolution")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !resolutions.isEmpty {
                    let index = Int(resolutionIndex.rounded())
                    let safeIndex = min(max(index, 0), resolutions.count - 1)
                    let res = resolutions[safeIndex]
                    Text("\(String(res.width))x\(String(res.height))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            // Slider
            if !resolutions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Slider(
                        value: $resolutionIndex,
                        in: 0...Double(max(0, resolutions.count - 1)),
                        step: 1,
                        onEditingChanged: { editing in
                            isEditingResolution = editing
                            if !editing {
                                let index = Int(resolutionIndex.rounded())
                                let safeIndex = min(max(index, 0), resolutions.count - 1)
                                let selectedRes = resolutions[safeIndex]
                                displayManager.setResolutionOption(selectedRes, for: display)
                            }
                        }
                    )
                    .controlSize(.small)

                    Image(systemName: "rectangle.expand.vertical")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Resolution labels
                HStack {
                    if let smallest = resolutions.first {
                        Text("\(smallest.height)p")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Spacer()
                    if let largest = resolutions.last {
                        Text("\(largest.height)p")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Get available resolutions for a display
    /// For external displays, offers virtual resolutions for crisp HiDPI scaling
    /// Only includes resolutions matching the display's native aspect ratio
    private func availableResolutions(for display: Display) -> [ResolutionOption] {
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
            // Generate resolutions matching the display's aspect ratio
            // For 16:9: width = height * 16/9
            // For 16:10: width = height * 16/10

            let virtualOptions: [(Int, Int)]

            // Check if display is 16:9 or 16:10 (within tolerance)
            let is16by9 = abs(nativeAspect - 16.0/9.0) < 0.02
            let is16by10 = abs(nativeAspect - 16.0/10.0) < 0.02

            if is16by9 {
                // 16:9 resolutions from 576p to 1440p
                virtualOptions = [
                    (1024, 576),   // 576p
                    (1152, 648),   // 648p
                    (1280, 720),   // 720p HD
                    (1366, 768),   // 768p (common laptop)
                    (1600, 900),   // 900p HD+
                    (1792, 1008),  // 1008p
                    (1920, 1080),  // 1080p Full HD
                    (2048, 1152),  // 1152p
                    (2560, 1440),  // 1440p QHD
                ]
            } else if is16by10 {
                // 16:10 resolutions
                virtualOptions = [
                    (1280, 800),   // WXGA
                    (1440, 900),   // WXGA+
                    (1680, 1050),  // WSXGA+
                    (1920, 1200),  // WUXGA
                    (2560, 1600),  // WQXGA
                ]
            } else {
                // Fallback to common resolutions
                virtualOptions = [
                    (1280, 720),
                    (1600, 900),
                    (1920, 1080),
                ]
            }

            for (w, h) in virtualOptions {
                // Only add if meets minimum height
                guard h >= minHeight else { continue }
                // Don't add if it matches native resolution exactly (will add native below)
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

    private func updateResolutionIndex() {
        guard let display = displayManager.selectedDisplay else { return }
        guard !isEditingResolution else { return }

        let resolutions = availableResolutions(for: display)
        guard !resolutions.isEmpty else {
            resolutionIndex = 0
            return
        }

        // Get current logical resolution
        let currentWidth: Int
        let currentHeight: Int

        if displayManager.crispHiDPIActive, let virtualRes = displayManager.currentVirtualResolution {
            // Virtual display active - use virtual resolution's logical size
            currentWidth = virtualRes.logicalWidth
            currentHeight = virtualRes.logicalHeight
        } else if let currentMode = display.currentMode {
            currentWidth = currentMode.width
            currentHeight = currentMode.height
        } else {
            resolutionIndex = 0
            return
        }

        // Find matching resolution
        if let index = resolutions.firstIndex(where: { $0.width == currentWidth && $0.height == currentHeight }) {
            resolutionIndex = Double(index)
        } else {
            // Find closest
            let currentArea = currentWidth * currentHeight
            var closestIndex = 0
            var closestDiff = Int.max
            for (index, res) in resolutions.enumerated() {
                let diff = abs(res.width * res.height - currentArea)
                if diff < closestDiff {
                    closestDiff = diff
                    closestIndex = index
                }
            }
            resolutionIndex = Double(closestIndex)
        }
    }
}

#Preview {
    DisplayMenuView()
        .environmentObject(DisplayManager())
        .environmentObject(Preferences.shared)
        .frame(width: 280)
}
