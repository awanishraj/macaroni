import SwiftUI

struct AudioMenuView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Volume Control
            volumeSection

            // Output Device (if multiple devices)
            if audioManager.outputDevices.count > 1 {
                outputDeviceSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Volume Section

    private var supportsVolumeControl: Bool {
        audioManager.selectedDevice?.supportsVolumeControl ?? false
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with percentage and mute toggle
            HStack {
                Text("Volume")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()

                if supportsVolumeControl {
                    HStack(alignment: .center, spacing: 6) {
                        // Volume percentage
                        Text("\(Int(audioManager.volume * 100))%")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        // Mute toggle as icon button
                        Button {
                            audioManager.toggleMute()
                        } label: {
                            Image(systemName: audioManager.isMuted ? "speaker.slash.circle.fill" : "speaker.slash.circle")
                                .font(.system(size: 12))
                                .foregroundColor(audioManager.isMuted ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(audioManager.isMuted ? "Unmute" : "Mute")
                    }
                }
            }

            // Slider
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if supportsVolumeControl {
                    Slider(value: $audioManager.volume, in: 0...1)
                        .controlSize(.small)
                } else {
                    Slider(value: .constant(1.0), in: 0...1)
                        .controlSize(.small)
                        .disabled(true)
                        .opacity(0.5)
                }

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Note: Volume control requires a device that supports software volume
            if !supportsVolumeControl {
                Text("Volume control unavailable for this device")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    // MARK: - Output Device Section

    private var outputDeviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("Output")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            // Device picker - use menu style to avoid overflow with long names
            Picker("Output Device", selection: Binding(
                get: { audioManager.selectedDevice?.id ?? "" },
                set: { id in
                    if let device = audioManager.outputDevices.first(where: { $0.id == id }) {
                        audioManager.selectDevice(device)
                    }
                }
            )) {
                ForEach(audioManager.outputDevices) { device in
                    HStack {
                        Text(device.name)
                        if device.supportsVolumeControl {
                            Spacer()
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(device.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Volume Indicator View

struct VolumeIndicatorView: View {
    let volume: Float
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: volumeIcon)
                .font(.system(size: 10))

            // Volume bars
            HStack(spacing: 1) {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .frame(width: 3, height: CGFloat(4 + index * 2))
                }
            }
        }
        .foregroundColor(isMuted ? .red : .primary)
    }

    private var volumeIcon: String {
        if isMuted {
            return "speaker.slash.fill"
        } else if volume == 0 {
            return "speaker.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / 5.0
        if isMuted {
            return .gray.opacity(0.3)
        } else if volume >= threshold {
            return .primary
        } else {
            return .gray.opacity(0.3)
        }
    }
}

#Preview {
    AudioMenuView()
        .environmentObject(AudioManager())
        .frame(width: 300)
}
