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

                // Resolution Control
                resolutionSection(for: display)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        let hidpiModes = sortedUniqueModes(for: display)

        return VStack(alignment: .leading, spacing: 8) {
            // Header - show logical resolution (like BetterDisplay)
            HStack {
                Text("Resolution")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !hidpiModes.isEmpty {
                    let index = Int(resolutionIndex.rounded())
                    let safeIndex = min(max(index, 0), hidpiModes.count - 1)
                    let mode = hidpiModes[safeIndex]
                    // Show logical resolution with HiDPI/Native indicator
                    HStack(spacing: 4) {
                        Text("\(mode.width)x\(mode.height)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        // Show mode type: HiDPI (sharp), Native (sharp), or Scaled (blurry)
                        if mode.isHiDPI {
                            Text("HiDPI")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.blue.opacity(0.8))
                        } else if isNativeResolution(mode, for: display) {
                            Text("Native")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.green.opacity(0.8))
                        } else {
                            Text("Scaled")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }
                }
            }

            // Slider
            if !hidpiModes.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Slider(
                        value: $resolutionIndex,
                        in: 0...Double(max(0, hidpiModes.count - 1)),
                        step: 1,
                        onEditingChanged: { editing in
                            isEditingResolution = editing
                            // Only apply resolution change when user releases the slider
                            if !editing {
                                let index = Int(resolutionIndex.rounded())
                                let safeIndex = min(max(index, 0), hidpiModes.count - 1)
                                let selectedMode = hidpiModes[safeIndex]
                                // Only change if different from current (compare logical dimensions)
                                if let currentMode = display.currentMode {
                                    if selectedMode.width != currentMode.width ||
                                       selectedMode.height != currentMode.height {
                                        displayManager.setResolution(selectedMode)
                                    }
                                } else {
                                    displayManager.setResolution(selectedMode)
                                }
                            }
                        }
                    )
                    .controlSize(.small)

                    Image(systemName: "rectangle.expand.vertical")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Resolution labels - show logical dimensions (like BetterDisplay)
                // Array is sorted smallest first, so first = left label, last = right label
                HStack {
                    if let smallest = hidpiModes.first {
                        Text("\(smallest.width)x\(smallest.height)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Spacer()
                    if let largest = hidpiModes.last {
                        Text("\(largest.width)x\(largest.height)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            } else {
                Text("No HiDPI modes available")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    // MARK: - Helpers

    /// Check if a mode matches the display's native panel resolution (1:1 pixel mapping)
    private func isNativeResolution(_ mode: DisplayMode, for display: Display) -> Bool {
        // Native resolution = logical resolution equals pixel resolution (no scaling)
        // AND it's the display's maximum resolution
        guard !mode.isHiDPI else { return false }
        guard mode.width == mode.pixelWidth && mode.height == mode.pixelHeight else { return false }

        // Check if this is the display's max native resolution
        let maxNative = display.availableModes
            .filter { !$0.isHiDPI && $0.width == $0.pixelWidth }
            .max { $0.width * $0.height < $1.width * $1.height }

        return maxNative?.width == mode.width && maxNative?.height == mode.height
    }

    private func sortedUniqueModes(for display: Display) -> [DisplayMode] {
        // Get native panel resolution (highest non-HiDPI resolution)
        let maxNativeMode = display.availableModes
            .filter { !$0.isHiDPI && $0.width == $0.pixelWidth }
            .max { $0.width * $0.height < $1.width * $1.height }

        let nativeAspect: Double
        if let maxNative = maxNativeMode {
            nativeAspect = Double(maxNative.width) / Double(maxNative.height)
        } else {
            nativeAspect = 16.0 / 9.0
        }

        var unique: [String: DisplayMode] = [:]

        // Add all HiDPI modes with matching aspect ratio (these are SHARP)
        let hidpiModes = display.availableModes.filter { $0.isHiDPI }
        for mode in hidpiModes {
            let modeAspect = Double(mode.width) / Double(mode.height)
            let aspectDiff = abs(modeAspect - nativeAspect) / nativeAspect
            guard aspectDiff < 0.02 else { continue }

            let key = "\(mode.width)x\(mode.height)-hidpi"
            if let existing = unique[key] {
                if mode.refreshRate > existing.refreshRate {
                    unique[key] = mode
                }
            } else {
                unique[key] = mode
            }
        }

        // Add ONLY the native panel resolution (this is SHARP - 1:1 pixel mapping)
        // Skip intermediate scaled resolutions as they are BLURRY
        if let nativeMode = maxNativeMode {
            let key = "\(nativeMode.width)x\(nativeMode.height)-native"
            // Find the highest refresh rate version
            let bestNative = display.availableModes
                .filter { !$0.isHiDPI && $0.width == nativeMode.width && $0.height == nativeMode.height }
                .max { $0.refreshRate < $1.refreshRate }
            if let best = bestNative {
                unique[key] = best
            }
        }

        // Sort by logical resolution (smallest first for slider: left=small/large UI, right=large/small UI)
        return unique.values.sorted { ($0.width * $0.height) < ($1.width * $1.height) }
    }

    private func updateResolutionIndex() {
        guard let display = displayManager.selectedDisplay else { return }
        // Don't update while user is actively sliding
        guard !isEditingResolution else { return }

        let modes = sortedUniqueModes(for: display)
        guard !modes.isEmpty else {
            resolutionIndex = 0
            return
        }

        guard let currentMode = display.currentMode else {
            resolutionIndex = 0
            return
        }

        // Match by logical dimensions (what BetterDisplay shows)
        if let index = modes.firstIndex(where: {
            $0.width == currentMode.width &&
            $0.height == currentMode.height
        }) {
            resolutionIndex = Double(index)
        } else {
            // If current mode is not in HiDPI list, find the closest by logical area
            let currentArea = currentMode.width * currentMode.height
            var closestIndex = 0
            var closestDiff = Int.max

            for (index, mode) in modes.enumerated() {
                let diff = abs(mode.width * mode.height - currentArea)
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
