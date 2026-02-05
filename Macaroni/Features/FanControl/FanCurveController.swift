import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "FanCurveController")

/// Fan control mode
enum FanControlMode: String, CaseIterable, Codable {
    case automatic = "automatic"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .automatic: return "Auto (System)"
        case .manual: return "Custom Curve"
        }
    }
}

/// Controls fan speed based on temperature using a proportional curve
final class FanCurveController: ObservableObject {
    @Published var mode: FanControlMode = .automatic
    @Published var triggerTemperature: Double = 70.0  // °C
    @Published private(set) var currentFanSpeed: Int = 0  // 0-100%
    @Published private(set) var targetFanSpeed: Int = 0
    @Published private(set) var fanRPM: Int?
    @Published private(set) var minRPM: Int = 1000
    @Published private(set) var maxRPM: Int = 6000
    @Published private(set) var helperInstalled: Bool = false

    private var thermalService: ThermalService?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // XPC connection to privileged helper
    private var helperConnection: NSXPCConnection?
    private var isHelperInstalled: Bool = false

    // Fan curve parameters
    private let curveSlope: Double = 10.0  // 10% per degree above trigger

    init() {
        loadPreferences()
        checkHelperInstallation()
    }

    /// Public method to refresh helper installation status
    func checkHelper() {
        checkHelperInstallation()
    }

    deinit {
        stopControl()
    }

    // MARK: - Public API

    func start(with thermalService: ThermalService) {
        self.thermalService = thermalService

        // Subscribe to temperature changes
        thermalService.$cpuTemperature
            .compactMap { $0 }
            .sink { [weak self] temperature in
                self?.updateFanSpeed(for: temperature)
            }
            .store(in: &cancellables)

        // Subscribe to fanControlEnabled preference
        Preferences.shared.$fanControlEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.mode = .manual
                } else {
                    self?.resetToAutomatic()
                }
            }
            .store(in: &cancellables)

        // Set initial mode based on preference
        if Preferences.shared.fanControlEnabled {
            mode = .manual
        }

        // Read initial fan state
        readCurrentFanState()

        // Start update timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.readCurrentFanState()
        }
    }

    func stopControl() {
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()

        // Reset to automatic mode
        if mode == .manual {
            resetToAutomatic()
        }
    }

    func setManualFanSpeed(_ percent: Int) {
        let clampedPercent = max(0, min(100, percent))
        targetFanSpeed = clampedPercent
        applyFanSpeed(clampedPercent)
    }

    func resetToAutomatic() {
        mode = .automatic
        disableForcedMode()
    }

    // MARK: - Fan Curve Calculation

    private func updateFanSpeed(for temperature: Double) {
        guard mode == .manual else { return }
        guard Preferences.shared.fanControlEnabled else { return }

        let newTargetSpeed = calculateFanSpeed(for: temperature)

        if newTargetSpeed != targetFanSpeed {
            targetFanSpeed = newTargetSpeed
            applyFanSpeed(newTargetSpeed)
        }
    }

    /// Calculate fan speed percentage based on temperature
    /// Uses simple proportional curve:
    /// - Below trigger: 0%
    /// - 1° above trigger: 10%
    /// - 10° above trigger: 100%
    private func calculateFanSpeed(for temperature: Double) -> Int {
        let trigger = Preferences.shared.triggerTemperature

        if temperature <= trigger {
            return 0
        }

        let degreesAbove = temperature - trigger
        let percent = degreesAbove * curveSlope

        return Int(max(0, min(100, percent)))
    }

    // MARK: - Helper Communication

    private func checkHelperInstallation() {
        let helperPath = "/Library/PrivilegedHelperTools/com.macaroni.fanhelper"
        let plistPath = "/Library/LaunchDaemons/com.macaroni.fanhelper.plist"
        isHelperInstalled = FileManager.default.fileExists(atPath: helperPath) &&
                           FileManager.default.fileExists(atPath: plistPath)
        helperInstalled = isHelperInstalled
    }

    private func connectToHelper() {
        guard isHelperInstalled else { return }

        helperConnection = NSXPCConnection(
            machServiceName: "com.macaroni.fanhelper",
            options: .privileged
        )

        helperConnection?.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)

        helperConnection?.invalidationHandler = { [weak self] in
            self?.helperConnection = nil
        }

        helperConnection?.resume()
    }

    private func getHelperProxy() -> FanHelperProtocol? {
        if helperConnection == nil {
            connectToHelper()
        }

        return helperConnection?.remoteObjectProxyWithErrorHandler { error in
            logger.error("XPC connection error: \(error.localizedDescription)")
        } as? FanHelperProtocol
    }

    // MARK: - SMC Fan Control

    private func readCurrentFanState() {
        guard let helper = getHelperProxy() else { return }

        helper.getFanSpeed { [weak self] rpmNumber, minRPM, maxRPM in
            DispatchQueue.main.async {
                let rpm = rpmNumber?.intValue
                self?.fanRPM = rpm
                self?.minRPM = minRPM
                self?.maxRPM = maxRPM

                if let rpm = rpm, maxRPM > minRPM {
                    self?.currentFanSpeed = Int((Double(rpm - minRPM) / Double(maxRPM - minRPM)) * 100)
                }
            }
        }
    }

    private func applyFanSpeed(_ percent: Int) {
        guard let helper = getHelperProxy() else { return }

        helper.enableForcedMode { success in
            guard success else { return }

            let targetRPM = self.minRPM + Int((Double(percent) / 100.0) * Double(self.maxRPM - self.minRPM))

            helper.setFanSpeed(targetRPM) { success in
                if success {
                    DispatchQueue.main.async {
                        self.currentFanSpeed = percent
                    }
                }
            }
        }
    }

    private func disableForcedMode() {
        guard let helper = getHelperProxy() else { return }
        helper.disableForcedMode { _ in }
    }

    // MARK: - Preferences

    private func loadPreferences() {
        triggerTemperature = Preferences.shared.triggerTemperature
    }

    func savePreferences() {
        Preferences.shared.triggerTemperature = triggerTemperature
    }
}

// MARK: - Fan Helper Protocol

@objc protocol FanHelperProtocol {
    func getFanSpeed(reply: @escaping (NSNumber?, Int, Int) -> Void)
    func setFanSpeed(_ rpm: Int, reply: @escaping (Bool) -> Void)
    func enableForcedMode(reply: @escaping (Bool) -> Void)
    func disableForcedMode(reply: @escaping (Bool) -> Void)
    func getAllFanInfo(reply: @escaping ([[String: Any]]) -> Void)
    func checkAuthorization(reply: @escaping (Bool) -> Void)
}
