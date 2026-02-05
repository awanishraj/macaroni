import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

@main
struct MacaroniApp: App {
    @StateObject private var displayManager = DisplayManager()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var thermalService = ThermalService()
    @StateObject private var fanCurveController = FanCurveController()
    @StateObject private var preferences = Preferences.shared
    @StateObject private var systemExtensionManager = SystemExtensionManager.shared

    init() {
        // Register keyboard shortcuts
        ShortcutManager.shared.registerShortcuts()

        // System extensions activation - uncomment when SIP is disabled
        // SystemExtensionManager.shared.activateAllExtensions()
    }

    var body: some Scene {
        MenuBarExtra {
            MainMenuView()
                .environmentObject(displayManager)
                .environmentObject(audioManager)
                .environmentObject(cameraManager)
                .environmentObject(thermalService)
                .environmentObject(fanCurveController)
                .environmentObject(preferences)
        } label: {
            MenuBarLabel()
                .environmentObject(thermalService)
                .environmentObject(audioManager)
                .environmentObject(preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var thermalService: ThermalService
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var preferences: Preferences

    private var volumeIconName: String {
        if audioManager.isMuted || audioManager.volume == 0 {
            return "speaker.slash.fill"
        } else if audioManager.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if audioManager.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        switch preferences.menuBarDisplayMode {
        case .temperature:
            if let temp = thermalService.cpuTemperature {
                Text("\(Int(temp))°")
            } else {
                Image("MenuBarIcon")
            }
        case .volume:
            Image(systemName: volumeIconName)
        case .iconOnly:
            Image("MenuBarIcon")
        }
    }
}
