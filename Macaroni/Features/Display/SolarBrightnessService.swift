import Foundation
import CoreLocation
import Solar
import Combine
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "SolarBrightnessService")

/// Service for automatic brightness adjustment based on sunrise/sunset and civil twilight times.
///
/// Uses a smooth ease-in-out curve during twilight transitions for natural-feeling brightness changes.
/// Civil twilight (sun 6° below horizon) marks when there's enough natural light for outdoor activities.
final class SolarBrightnessService: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentPhase: SolarPhase = .morning
    @Published private(set) var targetBrightness: Double = 1.0
    @Published private(set) var dawn: Date?        // Civil twilight start (morning)
    @Published private(set) var sunrise: Date?
    @Published private(set) var solarNoon: Date?   // Peak daylight
    @Published private(set) var sunset: Date?
    @Published private(set) var dusk: Date?        // Civil twilight end (evening)
    @Published private(set) var locationStatus: LocationStatus = .unknown

    // MARK: - Types

    enum SolarPhase: Equatable {
        case night
        case dawn           // Civil twilight → sunrise
        case morning        // Sunrise → solar noon
        case afternoon      // Solar noon → sunset
        case dusk           // Sunset → civil twilight end

        var description: String {
            switch self {
            case .night: return "Night"
            case .dawn: return "Dawn"
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .dusk: return "Dusk"
            }
        }

        var isDaytime: Bool {
            switch self {
            case .morning, .afternoon: return true
            case .night, .dawn, .dusk: return false
            }
        }
    }

    enum LocationStatus {
        case unknown
        case authorized
        case denied
        case notDetermined
    }

    // MARK: - Configuration

    /// Minimum transition duration if civil twilight is too short (30 minutes)
    private let minimumTransitionDuration: TimeInterval = 1800

    /// Current brightness levels from Preferences (0.0 to 1.0)
    private var dayBrightness: Double { Preferences.shared.dayBrightness }
    private var nightBrightness: Double { Preferences.shared.nightBrightness }

    // MARK: - Private State

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    weak var displayManager: DisplayManager?

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        setupPreferenceBindings()
    }

    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Public API

    func start() {
        let status = locationManager.authorizationStatus
        if status == .authorized || status == .authorizedAlways {
            // Already authorized - request location and start updates
            locationManager.requestLocation()
            if currentLocation != nil {
                startUpdating()
            }
        } else if status == .notDetermined {
            // Need to request authorization
            locationManager.requestWhenInUseAuthorization()
        }
        // If denied, we'll use default location in didFailWithError
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Private Methods

    private func setupPreferenceBindings() {
        Preferences.shared.$autoBrightnessEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.start()
                    // If we already have location, immediately apply brightness
                    if self.currentLocation != nil {
                        self.updateSolarTimes()
                        self.updateBrightness()
                    }
                } else {
                    self.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func startUpdating() {
        updateSolarTimes()
        updateBrightness()

        // Update every 30 seconds for smooth transitions
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateBrightness()
        }
    }

    private func updateSolarTimes() {
        guard let location = currentLocation else { return }

        let solar = Solar(for: Date(), coordinate: location.coordinate)

        // Civil twilight times - when sun is 6° below horizon
        dawn = solar?.civilSunrise
        sunrise = solar?.sunrise
        sunset = solar?.sunset
        dusk = solar?.civilSunset

        // Calculate solar noon as midpoint between sunrise and sunset
        if let sr = sunrise, let ss = sunset {
            let midpoint = sr.timeIntervalSince1970 + (ss.timeIntervalSince1970 - sr.timeIntervalSince1970) / 2
            solarNoon = Date(timeIntervalSince1970: midpoint)
        } else {
            solarNoon = nil
        }

        logger.info("Solar times - Dawn: \(self.formatTime(self.dawn)), Sunrise: \(self.formatTime(self.sunrise)), Noon: \(self.formatTime(self.solarNoon)), Sunset: \(self.formatTime(self.sunset)), Dusk: \(self.formatTime(self.dusk))")
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "nil" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func updateBrightness() {
        guard currentLocation != nil else { return }
        guard Preferences.shared.autoBrightnessEnabled else { return }

        let (phase, brightness) = calculateBrightness(at: Date())

        currentPhase = phase
        targetBrightness = brightness

        // Use setAutoBrightness to avoid disabling auto mode
        displayManager?.setAutoBrightness(brightness)

        logger.debug("Brightness updated - Phase: \(phase.description), Brightness: \(Int(brightness * 100))%")
    }

    /// Calculates brightness using a bell curve centered on solar noon.
    ///
    /// The brightness follows natural daylight intensity throughout the day:
    /// ```
    /// Night (50%) ──[dawn]── Rising ──[sunrise]── Morning ──[noon: 100%]── Afternoon ──[sunset]── Falling ──[dusk]── Night (50%)
    /// ```
    ///
    /// The curve uses cosine interpolation for smooth, natural transitions:
    /// - Peak brightness (100%) at solar noon
    /// - Minimum brightness (50%) during night
    /// - Gradual rise from dawn through morning
    /// - Gradual fall from afternoon through dusk
    private func calculateBrightness(at now: Date) -> (SolarPhase, Double) {
        guard let dawn = self.dawn,
              let sunrise = self.sunrise,
              let solarNoon = self.solarNoon,
              let sunset = self.sunset,
              let dusk = self.dusk else {
            // No solar data - default to midpoint brightness
            let midBrightness = (dayBrightness + nightBrightness) / 2
            return (.morning, midBrightness)
        }

        // Ensure minimum transition durations
        let dawnDuration = max(sunrise.timeIntervalSince(dawn), minimumTransitionDuration)
        let duskDuration = max(dusk.timeIntervalSince(sunset), minimumTransitionDuration)
        let effectiveDawn = sunrise.addingTimeInterval(-dawnDuration)
        let effectiveDusk = sunset.addingTimeInterval(duskDuration)

        if now < effectiveDawn {
            // Night - before dawn
            return (.night, nightBrightness)

        } else if now < sunrise {
            // Dawn - transitioning from night toward day
            // Brightness rises from nightBrightness toward ~75% at sunrise
            let t = now.timeIntervalSince(effectiveDawn) / dawnDuration
            let dawnPeakBrightness = nightBrightness + (dayBrightness - nightBrightness) * 0.5
            let brightness = nightBrightness + (dawnPeakBrightness - nightBrightness) * easeInOut(t)
            return (.dawn, brightness)

        } else if now < solarNoon {
            // Morning - rising toward peak at solar noon
            // Brightness rises from ~75% at sunrise to 100% at solar noon
            let morningDuration = solarNoon.timeIntervalSince(sunrise)
            let t = now.timeIntervalSince(sunrise) / morningDuration
            let sunriseBrightness = nightBrightness + (dayBrightness - nightBrightness) * 0.5
            let brightness = sunriseBrightness + (dayBrightness - sunriseBrightness) * easeInOut(t)
            return (.morning, brightness)

        } else if now < sunset {
            // Afternoon - falling from peak toward sunset
            // Brightness falls from 100% at solar noon to ~75% at sunset
            let afternoonDuration = sunset.timeIntervalSince(solarNoon)
            let t = now.timeIntervalSince(solarNoon) / afternoonDuration
            let sunsetBrightness = nightBrightness + (dayBrightness - nightBrightness) * 0.5
            let brightness = dayBrightness - (dayBrightness - sunsetBrightness) * easeInOut(t)
            return (.afternoon, brightness)

        } else if now < effectiveDusk {
            // Dusk - transitioning from day toward night
            // Brightness falls from ~75% at sunset toward nightBrightness
            let t = now.timeIntervalSince(sunset) / duskDuration
            let duskStartBrightness = nightBrightness + (dayBrightness - nightBrightness) * 0.5
            let brightness = duskStartBrightness - (duskStartBrightness - nightBrightness) * easeInOut(t)
            return (.dusk, brightness)

        } else {
            // Night - after dusk
            return (.night, nightBrightness)
        }
    }

    /// Cosine ease-in-out function for smooth transitions.
    ///
    /// - Parameter t: Linear progress from 0.0 to 1.0
    /// - Returns: Eased progress with smooth acceleration/deceleration
    ///
    /// The curve starts slow, accelerates through the middle, and slows at the end.
    /// This mimics natural light changes during twilight.
    private func easeInOut(_ t: Double) -> Double {
        let clampedT = max(0, min(1, t))
        return (1 - cos(.pi * clampedT)) / 2
    }
}

// MARK: - CLLocationManagerDelegate

extension SolarBrightnessService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            locationStatus = .authorized
            manager.requestLocation()
        case .denied, .restricted:
            locationStatus = .denied
        case .notDetermined:
            locationStatus = .notDetermined
        @unknown default:
            locationStatus = .unknown
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        currentLocation = location
        updateSolarTimes()
        startUpdating()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("Location error: \(error.localizedDescription)")

        // Use a default location if location services fail
        // Default to a reasonable mid-latitude location
        currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)  // San Francisco
        updateSolarTimes()
        startUpdating()
    }
}
