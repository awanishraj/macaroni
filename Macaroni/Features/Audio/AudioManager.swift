import Foundation
import SimplyCoreAudio
import Combine
import os.log

private let logger = Logger(subsystem: "com.macaroni.app", category: "AudioManager")

/// Represents an audio output device
struct AudioDevice: Identifiable, Hashable {
    let id: String  // UID
    let name: String
    let isDefault: Bool
    var volume: Float
    var isMuted: Bool
    let supportsVolumeControl: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages audio output devices and volume control
final class AudioManager: ObservableObject {
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var selectedDevice: AudioDevice?

    @Published var volume: Float = 0.5 {
        didSet {
            if !isUpdatingFromExternal {
                setVolume(volume)
            }
        }
    }
    @Published var isMuted: Bool = false {
        didSet {
            if !isUpdatingFromExternal {
                setMuted(isMuted)
            }
        }
    }

    private let simplyCA = SimplyCoreAudio()
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingFromExternal = false

    init() {
        setupDevices()
        setupNotifications()
        setupShortcutHandlers()
    }

    // MARK: - Public API

    func refreshDevices() {
        setupDevices()
    }

    func selectDevice(_ device: AudioDevice) {
        guard let scaDevice = simplyCA.allOutputDevices.first(where: { $0.uid == device.id }) else {
            return
        }

        // Set as default output device
        scaDevice.isDefaultOutputDevice = true

        selectedDevice = device
        Preferences.shared.selectedAudioDeviceUID = device.id

        // Update volume from new device
        updateVolumeFromDevice()
    }

    func setVolume(_ value: Float) {
        guard let device = selectedDevice,
              let scaDevice = simplyCA.allOutputDevices.first(where: { $0.uid == device.id }) else {
            return
        }

        let clampedValue = max(0, min(1, value))

        // Set volume using virtual main volume if available
        if scaDevice.canSetVirtualMainVolume(scope: .output) {
            scaDevice.setVirtualMainVolume(clampedValue, scope: .output)
        }

        // Fallback: set on individual stereo channels (1 = left, 2 = right for stereo devices)
        if scaDevice.canSetVolume(channel: 1, scope: .output) {
            scaDevice.setVolume(clampedValue, channel: 1, scope: .output)
        }
        if scaDevice.canSetVolume(channel: 2, scope: .output) {
            scaDevice.setVolume(clampedValue, channel: 2, scope: .output)
        }

        // Also try channel 0 (master)
        if scaDevice.canSetVolume(channel: 0, scope: .output) {
            scaDevice.setVolume(clampedValue, channel: 0, scope: .output)
        }

        // Update local state
        if let index = outputDevices.firstIndex(where: { $0.id == device.id }) {
            outputDevices[index].volume = clampedValue
            selectedDevice = outputDevices[index]
        }
    }

    func setMuted(_ muted: Bool) {
        guard let device = selectedDevice,
              let scaDevice = simplyCA.allOutputDevices.first(where: { $0.uid == device.id }) else {
            return
        }

        // Try main channel mute
        if scaDevice.canMute(channel: 0, scope: .output) {
            scaDevice.setMute(muted, channel: 0, scope: .output)
        }

        // Update local state
        if let index = outputDevices.firstIndex(where: { $0.id == device.id }) {
            outputDevices[index].isMuted = muted
            selectedDevice = outputDevices[index]
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Shortcut Handlers

    private func setupShortcutHandlers() {
        NotificationCenter.default.publisher(for: .volumeUp)
            .sink { [weak self] _ in
                self?.adjustVolume(by: 0.1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .volumeDown)
            .sink { [weak self] _ in
                self?.adjustVolume(by: -0.1)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleMute)
            .sink { [weak self] _ in
                self?.toggleMute()
            }
            .store(in: &cancellables)
    }

    private func adjustVolume(by delta: Float) {
        volume = max(0, min(1, volume + delta))
    }

    // MARK: - Private Methods

    private func setupDevices() {
        let devices = simplyCA.allOutputDevices.compactMap { device -> AudioDevice? in
            guard let uid = device.uid else { return nil }
            let name = device.name ?? "Unknown Device"

            let volume = device.virtualMainVolume(scope: .output) ?? 0.5
            let muted = device.isMuted(channel: 0, scope: .output) ?? false
            let isDefault = device.isDefaultOutputDevice

            // Check if device supports any form of volume control
            let canSetVirtualMain = device.canSetVirtualMainVolume(scope: .output)
            let canSetCh0 = device.canSetVolume(channel: 0, scope: .output)
            let canSetCh1 = device.canSetVolume(channel: 1, scope: .output)
            let canSetCh2 = device.canSetVolume(channel: 2, scope: .output)
            let supportsVolume = canSetVirtualMain || canSetCh0 || canSetCh1 || canSetCh2

            return AudioDevice(
                id: uid,
                name: name,
                isDefault: isDefault,
                volume: volume,
                isMuted: muted,
                supportsVolumeControl: supportsVolume
            )
        }

        outputDevices = devices

        // Select default device or restore saved preference
        if let savedUID = Preferences.shared.selectedAudioDeviceUID,
           let savedDevice = devices.first(where: { $0.id == savedUID }) {
            selectedDevice = savedDevice
        } else {
            selectedDevice = devices.first { $0.isDefault } ?? devices.first
        }

        // Update volume from selected device
        updateVolumeFromDevice()
    }

    private func setupNotifications() {
        // Device list changes
        NotificationCenter.default.addObserver(
            forName: .deviceListChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupDevices()
        }

        // Default device changes
        NotificationCenter.default.addObserver(
            forName: .defaultOutputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDefaultDeviceChange()
        }

        // Volume changes (event-based, no polling needed)
        NotificationCenter.default.addObserver(
            forName: .deviceVolumeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVolumeFromDevice()
        }

        // Mute state changes
        NotificationCenter.default.addObserver(
            forName: .deviceMuteDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVolumeFromDevice()
        }
    }

    private func handleDefaultDeviceChange() {
        guard let defaultDevice = simplyCA.defaultOutputDevice,
              let uid = defaultDevice.uid else {
            return
        }

        if let device = outputDevices.first(where: { $0.id == uid }) {
            selectedDevice = device
            updateVolumeFromDevice()
        }
    }

    private func updateVolumeFromDevice() {
        guard let device = selectedDevice,
              let scaDevice = simplyCA.allOutputDevices.first(where: { $0.uid == device.id }) else {
            return
        }

        let deviceVolume = scaDevice.virtualMainVolume(scope: .output) ?? volume
        let deviceMuted = scaDevice.isMuted(channel: 0, scope: .output) ?? isMuted

        isUpdatingFromExternal = true
        volume = deviceVolume
        isMuted = deviceMuted
        isUpdatingFromExternal = false
    }
}
