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
        VStack(alignment: .leading, spacing: 12) {
            // Menu Icon
            HStack {
                Text("Menu Icon")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)

                Spacer()

                Picker("", selection: $preferences.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName)
                            .frame(width: 50)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            // Launch at Login
            HStack {
                Text("Launch at Login")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)

                Spacer()

                LaunchAtLogin.Toggle("")
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            // Quit Macaroni
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Macaroni")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    MainMenuView()
        .environmentObject(DisplayManager())
        .environmentObject(AudioManager())
        .environmentObject(CameraManager())
        .environmentObject(ThermalService())
        .environmentObject(FanCurveController())
        .environmentObject(Preferences.shared)
}
