import SwiftUI
import LaunchAtLogin

struct MainMenuView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var thermalService: ThermalService
    @EnvironmentObject var fanController: FanCurveController
    @EnvironmentObject var preferences: Preferences

    @State private var selectedSection: MenuSection = .display

    enum MenuSection: String, CaseIterable {
        case display = "Display"
        case audio = "Audio"
        case camera = "Camera"
        case fan = "Fan"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .display: return "display"
            case .audio: return "speaker.wave.2"
            case .camera: return "camera"
            case .fan: return "fan"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation tabs
            sectionTabs

            Divider()

            // Content - dynamic height, no scroll
            VStack(alignment: .leading, spacing: 0) {
                switch selectedSection {
                case .display:
                    DisplayMenuView()
                case .audio:
                    AudioMenuView()
                case .camera:
                    CameraMenuView()
                case .fan:
                    FanMenuView()
                case .settings:
                    SettingsMenuView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300)
    }

    // MARK: - Section Tabs

    private var sectionTabs: some View {
        HStack(spacing: 0) {
            ForEach(MenuSection.allCases, id: \.self) { section in
                Button(action: { selectedSection = section }) {
                    Image(systemName: section.icon)
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedSection == section
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .foregroundColor(
                            selectedSection == section
                                ? .accentColor
                                : .secondary
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.rawValue)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

}

// MARK: - Settings Menu View

struct SettingsMenuView: View {
    @EnvironmentObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Menubar Display
            menuBarDisplaySection

            // Launch at Login
            launchAtLoginSection

            // Keyboard Shortcuts
            keyboardShortcutsSection

            // Quit Button
            quitSection

            // Subtle version footer
            versionFooter
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Menubar Display Section

    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Menubar Display")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }

            Picker("Display", selection: $preferences.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
    }

    // MARK: - Launch at Login Section

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Startup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }

            LaunchAtLogin.Toggle {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Launch at Login")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Keyboard Shortcuts Section

    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcuts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }

            Button {
                openShortcutsWindow()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Configure Keyboard Shortcuts")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quit Section

    private var quitSection: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
                Text("Quit Macaroni")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        HStack {
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
            Spacer()
        }
        .padding(.top, 4)
    }

    private func openShortcutsWindow() {
        // Open keyboard shortcuts configuration
        // This would typically open a settings window
    }
}

// MARK: - Keyboard Shortcuts Settings View

struct KeyboardShortcutsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Group {
                ShortcutRow(name: "Brightness Up", shortcut: .brightnessUp)
                ShortcutRow(name: "Brightness Down", shortcut: .brightnessDown)
                ShortcutRow(name: "Volume Up", shortcut: .volumeUp)
                ShortcutRow(name: "Volume Down", shortcut: .volumeDown)
                ShortcutRow(name: "Toggle Mute", shortcut: .toggleMute)
                ShortcutRow(name: "Toggle Camera Preview", shortcut: .togglePreview)
                ShortcutRow(name: "Cycle Camera Rotation", shortcut: .cycleRotation)
            }
        }
        .padding()
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: KeyboardShortcuts.Name

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)

            Spacer()

            KeyboardShortcuts.Recorder(for: shortcut)
        }
    }
}

import KeyboardShortcuts

#Preview {
    MainMenuView()
        .environmentObject(DisplayManager())
        .environmentObject(AudioManager())
        .environmentObject(CameraManager())
        .environmentObject(ThermalService())
        .environmentObject(FanCurveController())
        .environmentObject(Preferences.shared)
}
