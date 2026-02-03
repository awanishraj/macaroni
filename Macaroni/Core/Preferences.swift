import Foundation
import SwiftUI
import Combine

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case temperature = "temperature"
    case volume = "volume"
    case iconOnly = "iconOnly"

    var displayName: String {
        switch self {
        case .temperature: return "Temperature"
        case .volume: return "Volume"
        case .iconOnly: return "Icon Only"
        }
    }
}

enum CameraRotation: Int, CaseIterable, Codable {
    case none = 0
    case rotate90 = 90
    case rotate180 = 180
    case rotate270 = 270

    var displayName: String {
        switch self {
        case .none: return "0°"
        case .rotate90: return "90°"
        case .rotate180: return "180°"
        case .rotate270: return "270°"
        }
    }

    var next: CameraRotation {
        switch self {
        case .none: return .rotate90
        case .rotate90: return .rotate180
        case .rotate180: return .rotate270
        case .rotate270: return .none
        }
    }
}

enum FrameStyle: String, CaseIterable, Codable {
    case none = "none"
    case roundedCorners = "roundedCorners"
    case polaroid = "polaroid"
    case neonBorder = "neonBorder"
    case vintage = "vintage"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .roundedCorners: return "Rounded Corners"
        case .polaroid: return "Polaroid"
        case .neonBorder: return "Neon Border"
        case .vintage: return "Vintage"
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: - Display Preferences

    @Published var autoBrightnessEnabled: Bool {
        didSet { defaults.set(autoBrightnessEnabled, forKey: Keys.autoBrightnessEnabled) }
    }

    @Published var dayBrightness: Double {
        didSet { defaults.set(dayBrightness, forKey: Keys.dayBrightness) }
    }

    @Published var nightBrightness: Double {
        didSet { defaults.set(nightBrightness, forKey: Keys.nightBrightness) }
    }

    @Published var selectedDisplayID: CGDirectDisplayID? {
        didSet {
            if let id = selectedDisplayID {
                defaults.set(Int(id), forKey: Keys.selectedDisplayID)
            } else {
                defaults.removeObject(forKey: Keys.selectedDisplayID)
            }
        }
    }

    @Published var crispHiDPIEnabled: Bool {
        didSet { defaults.set(crispHiDPIEnabled, forKey: Keys.crispHiDPIEnabled) }
    }

    @Published var crispHiDPIResolution: String {
        didSet { defaults.set(crispHiDPIResolution, forKey: Keys.crispHiDPIResolution) }
    }

    // MARK: - Audio Preferences

    @Published var selectedAudioDeviceUID: String? {
        didSet { defaults.set(selectedAudioDeviceUID, forKey: Keys.selectedAudioDeviceUID) }
    }

    // MARK: - Camera Preferences

    @Published var cameraRotation: CameraRotation {
        didSet { defaults.set(cameraRotation.rawValue, forKey: Keys.cameraRotation) }
    }

    @Published var horizontalFlip: Bool {
        didSet { defaults.set(horizontalFlip, forKey: Keys.horizontalFlip) }
    }

    @Published var verticalFlip: Bool {
        didSet { defaults.set(verticalFlip, forKey: Keys.verticalFlip) }
    }

    @Published var frameStyle: FrameStyle {
        didSet { defaults.set(frameStyle.rawValue, forKey: Keys.frameStyle) }
    }

    @Published var selectedCameraID: String? {
        didSet { defaults.set(selectedCameraID, forKey: Keys.selectedCameraID) }
    }

    // MARK: - Fan Control Preferences

    @Published var fanControlEnabled: Bool {
        didSet { defaults.set(fanControlEnabled, forKey: Keys.fanControlEnabled) }
    }

    @Published var triggerTemperature: Double {
        didSet { defaults.set(triggerTemperature, forKey: Keys.triggerTemperature) }
    }

    // MARK: - Menubar Preferences

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Keys.menuBarDisplayMode) }
    }

    // MARK: - Keys

    private enum Keys {
        static let autoBrightnessEnabled = "autoBrightnessEnabled"
        static let dayBrightness = "dayBrightness"
        static let nightBrightness = "nightBrightness"
        static let selectedDisplayID = "selectedDisplayID"
        static let crispHiDPIEnabled = "crispHiDPIEnabled"
        static let crispHiDPIResolution = "crispHiDPIResolution"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let cameraRotation = "cameraRotation"
        static let horizontalFlip = "horizontalFlip"
        static let verticalFlip = "verticalFlip"
        static let frameStyle = "frameStyle"
        static let selectedCameraID = "selectedCameraID"
        static let fanControlEnabled = "fanControlEnabled"
        static let triggerTemperature = "triggerTemperature"
        static let menuBarDisplayMode = "menuBarDisplayMode"
    }

    // MARK: - Initialization

    private init() {
        // Display defaults
        self.autoBrightnessEnabled = defaults.bool(forKey: Keys.autoBrightnessEnabled)
        self.dayBrightness = defaults.object(forKey: Keys.dayBrightness) as? Double ?? 1.0
        self.nightBrightness = defaults.object(forKey: Keys.nightBrightness) as? Double ?? 0.5

        if let displayID = defaults.object(forKey: Keys.selectedDisplayID) as? Int {
            self.selectedDisplayID = CGDirectDisplayID(displayID)
        } else {
            self.selectedDisplayID = nil
        }

        self.crispHiDPIEnabled = defaults.bool(forKey: Keys.crispHiDPIEnabled)
        self.crispHiDPIResolution = defaults.string(forKey: Keys.crispHiDPIResolution) ?? "res1080p"

        // Audio defaults
        self.selectedAudioDeviceUID = defaults.string(forKey: Keys.selectedAudioDeviceUID)

        // Camera defaults
        let rotationRaw = defaults.integer(forKey: Keys.cameraRotation)
        self.cameraRotation = CameraRotation(rawValue: rotationRaw) ?? .none
        self.horizontalFlip = defaults.bool(forKey: Keys.horizontalFlip)
        self.verticalFlip = defaults.bool(forKey: Keys.verticalFlip)

        let frameStyleRaw = defaults.string(forKey: Keys.frameStyle) ?? FrameStyle.none.rawValue
        self.frameStyle = FrameStyle(rawValue: frameStyleRaw) ?? .none
        self.selectedCameraID = defaults.string(forKey: Keys.selectedCameraID)

        // Fan control defaults
        self.fanControlEnabled = defaults.bool(forKey: Keys.fanControlEnabled)
        self.triggerTemperature = defaults.object(forKey: Keys.triggerTemperature) as? Double ?? 70.0

        // Menubar defaults
        let menuBarModeRaw = defaults.string(forKey: Keys.menuBarDisplayMode) ?? MenuBarDisplayMode.iconOnly.rawValue
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: menuBarModeRaw) ?? .iconOnly
    }
}
