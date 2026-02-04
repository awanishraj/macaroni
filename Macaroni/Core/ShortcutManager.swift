import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    // Display shortcuts
    static let brightnessUp = Self("brightnessUp")
    static let brightnessDown = Self("brightnessDown")
    static let toggleResolution = Self("toggleResolution")

    // Audio shortcuts
    static let volumeUp = Self("volumeUp")
    static let volumeDown = Self("volumeDown")
    static let toggleMute = Self("toggleMute")

    // Camera shortcuts
    static let togglePreview = Self("togglePreview")
    static let cycleRotation = Self("cycleRotation")
}

final class ShortcutManager {
    static let shared = ShortcutManager()

    private init() {
        setupDefaultShortcuts()
    }

    /// Set default shortcuts (only if not already configured by user)
    private func setupDefaultShortcuts() {
        // Brightness: Ctrl + = (up), Ctrl + - (down)
        if KeyboardShortcuts.getShortcut(for: .brightnessUp) == nil {
            KeyboardShortcuts.setShortcut(.init(.equal, modifiers: .control), for: .brightnessUp)
        }
        if KeyboardShortcuts.getShortcut(for: .brightnessDown) == nil {
            KeyboardShortcuts.setShortcut(.init(.minus, modifiers: .control), for: .brightnessDown)
        }
    }

    func registerShortcuts() {
        // Display shortcuts
        KeyboardShortcuts.onKeyUp(for: .brightnessUp) { [weak self] in
            self?.handleBrightnessUp()
        }

        KeyboardShortcuts.onKeyUp(for: .brightnessDown) { [weak self] in
            self?.handleBrightnessDown()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleResolution) { [weak self] in
            self?.handleToggleResolution()
        }

        // Audio shortcuts
        KeyboardShortcuts.onKeyUp(for: .volumeUp) { [weak self] in
            self?.handleVolumeUp()
        }

        KeyboardShortcuts.onKeyUp(for: .volumeDown) { [weak self] in
            self?.handleVolumeDown()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleMute) { [weak self] in
            self?.handleToggleMute()
        }

        // Camera shortcuts
        KeyboardShortcuts.onKeyUp(for: .togglePreview) { [weak self] in
            self?.handleTogglePreview()
        }

        KeyboardShortcuts.onKeyUp(for: .cycleRotation) { [weak self] in
            self?.handleCycleRotation()
        }
    }

    // MARK: - Display Handlers

    private func handleBrightnessUp() {
        NotificationCenter.default.post(name: .brightnessUp, object: nil)
    }

    private func handleBrightnessDown() {
        NotificationCenter.default.post(name: .brightnessDown, object: nil)
    }

    private func handleToggleResolution() {
        NotificationCenter.default.post(name: .toggleResolution, object: nil)
    }

    // MARK: - Audio Handlers

    private func handleVolumeUp() {
        NotificationCenter.default.post(name: .volumeUp, object: nil)
    }

    private func handleVolumeDown() {
        NotificationCenter.default.post(name: .volumeDown, object: nil)
    }

    private func handleToggleMute() {
        NotificationCenter.default.post(name: .toggleMute, object: nil)
    }

    // MARK: - Camera Handlers

    private func handleTogglePreview() {
        NotificationCenter.default.post(name: .toggleCameraPreview, object: nil)
    }

    private func handleCycleRotation() {
        NotificationCenter.default.post(name: .cycleRotation, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // Display notifications
    static let brightnessUp = Notification.Name("brightnessUp")
    static let brightnessDown = Notification.Name("brightnessDown")
    static let toggleResolution = Notification.Name("toggleResolution")

    // Audio notifications
    static let volumeUp = Notification.Name("volumeUp")
    static let volumeDown = Notification.Name("volumeDown")
    static let toggleMute = Notification.Name("toggleMute")

    // Camera notifications
    static let toggleCameraPreview = Notification.Name("toggleCameraPreview")
    static let cycleRotation = Notification.Name("cycleRotation")
}
