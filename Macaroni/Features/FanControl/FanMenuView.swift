import SwiftUI
import Combine

// MARK: - Rotating Fan Icon

/// Smoothly rotating fan icon
/// Max speed: 0.25 rotations/second at 100%, scales linearly
struct RotatingFanIcon: View {
    let speedPercent: Int

    @StateObject private var rotationState = FanRotationState()

    var body: some View {
        Image(systemName: "fan.fill")
            .font(.system(size: 12))
            .foregroundColor(speedPercent > 0 ? .accentColor : .secondary)
            .rotationEffect(.degrees(rotationState.angle))
            .onChange(of: speedPercent) { _, newValue in
                rotationState.speedPercent = newValue
            }
            .onAppear {
                rotationState.speedPercent = speedPercent
                rotationState.start()
            }
            .onDisappear {
                rotationState.stop()
            }
    }
}

/// Manages continuous fan rotation with smooth speed transitions
private class FanRotationState: ObservableObject {
    @Published var angle: Double = 0
    var speedPercent: Int = 0

    private var displayLink: CVDisplayLink?
    private var lastTime: CFTimeInterval = 0

    // 1 rotation per second at 100% = 360 degrees per second
    private var degreesPerSecond: Double {
        guard speedPercent > 0 else { return 0 }
        return (Double(speedPercent) / 100.0) * 360.0
    }

    func start() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let userInfo = userInfo else { return kCVReturnError }
            let state = Unmanaged<FanRotationState>.fromOpaque(userInfo).takeUnretainedValue()
            let currentTime = CFAbsoluteTimeGetCurrent()

            if state.lastTime > 0 {
                let delta = currentTime - state.lastTime
                let increment = delta * state.degreesPerSecond

                DispatchQueue.main.async {
                    state.angle += increment
                }
            }

            state.lastTime = currentTime
            return kCVReturnSuccess
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, userInfo)
        CVDisplayLinkStart(displayLink)

        self.displayLink = displayLink
        self.lastTime = CFAbsoluteTimeGetCurrent()
    }

    func stop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    deinit {
        stop()
    }
}

struct FanMenuView: View {
    @EnvironmentObject var thermalService: ThermalService
    @EnvironmentObject var fanController: FanCurveController
    @EnvironmentObject var preferences: Preferences

    @State private var isInstallingHelper = false
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !thermalService.isAvailable {
                unavailableView
            } else {
                // Current Temperature Display
                temperatureSection

                // Target Temperature Control (always shown)
                targetTemperatureSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .onAppear {
            fanController.start(with: thermalService)
        }
        .onDisappear {
            fanController.stopControl()
        }
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("Fan control requires Apple Silicon")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Temperature Section

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Current Temp")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()

                // Current temperature display with fan icon on right
                if let temp = thermalService.cpuTemperature {
                    HStack(spacing: 6) {
                        Text("\(Int(temp))°C")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(temperatureColor(temp))
                            .monospacedDigit()

                        // Show fan icon always - rotating when active, static when off
                        if preferences.fanControlEnabled && fanController.helperInstalled {
                            RotatingFanIcon(speedPercent: fanController.currentFanSpeed)
                        } else {
                            Image(systemName: "fan.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Reading...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            // Temperature bar with icons
            HStack(spacing: 10) {
                Image(systemName: "thermometer.snowflake")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                temperatureBar

                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var temperatureBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let temp = thermalService.cpuTemperature ?? 40
            let triggerTemp = preferences.triggerTemperature

            // Normalize: 30°C = 0, 100°C = 1
            let normalizedTemp = min(max((temp - 30) / 70, 0), 1)
            let normalizedTrigger = min(max((triggerTemp - 30) / 70, 0), 1)

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))

                // Temperature fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(temperatureColor(temp))
                    .frame(width: max(0, width * normalizedTemp))

                // Trigger marker
                Rectangle()
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 2, height: 8)
                    .offset(x: width * normalizedTrigger - 1)
            }
        }
        .frame(height: 6)
    }

    private func temperatureColor(_ temp: Double) -> Color {
        let trigger = preferences.triggerTemperature
        if temp < trigger { return .green }
        if temp < trigger + 5 { return .yellow }
        if temp < trigger + 10 { return .orange }
        return .red
    }

    private func installHelper() {
        isInstallingHelper = true
        installError = nil

        FanHelperInstaller.shared.install { success, error in
            isInstallingHelper = false

            if success {
                // Refresh helper status
                fanController.checkHelper()
            } else if let error = error {
                installError = error
            }
        }
    }

    // MARK: - Target Temperature Section

    private var targetTemperatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with enable toggle
            HStack {
                Text("Target Temp")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()

                HStack(spacing: 6) {
                    Text("\(Int(preferences.triggerTemperature))°C")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .monospacedDigit()

                    // Enable toggle
                    Button {
                        preferences.fanControlEnabled.toggle()
                    } label: {
                        Image(systemName: preferences.fanControlEnabled ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 12))
                            .foregroundColor(preferences.fanControlEnabled ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(preferences.fanControlEnabled ? "Fan control: On" : "Fan control: Off")
                }
            }

            // Target temperature slider
            HStack(spacing: 10) {
                Text("30°")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Slider(value: $preferences.triggerTemperature, in: 30...90, step: 1)
                    .controlSize(.small)
                    .disabled(!preferences.fanControlEnabled)
                    .onChange(of: preferences.triggerTemperature) { _, newValue in
                        fanController.triggerTemperature = newValue
                    }

                Text("90°")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .opacity(preferences.fanControlEnabled ? 1.0 : 0.5)

            // Helper install prompt (only shown when needed)
            if preferences.fanControlEnabled && !fanController.helperInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("Helper required for fan control")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        installHelper()
                    } label: {
                        HStack(spacing: 4) {
                            if isInstallingHelper {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 10))
                            }
                            Text(isInstallingHelper ? "Installing..." : "Install Helper")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isInstallingHelper)

                    if let error = installError {
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
        }
    }
}

#Preview {
    FanMenuView()
        .environmentObject(ThermalService())
        .environmentObject(FanCurveController())
        .environmentObject(Preferences.shared)
        .frame(width: 280)
}
