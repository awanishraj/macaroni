# Claude Code Instructions for Macaroni

This file provides context and guidelines for Claude Code when working on this codebase.

## Project Overview

Macaroni is a macOS menubar utility that combines display, audio, camera, and fan control into a single app. It's built with Swift/SwiftUI and targets macOS 14+ on Apple Silicon Macs.

## Architecture

### Main App (Macaroni/)

- **App/**: Entry point (`MacaroniApp.swift`) using `MenuBarExtra` for menubar-only UI
- **Features/**: Four main modules:
  - `Display/`: DDC/CI brightness, auto-brightness (solar-based), resolution management
  - `Audio/`: CoreAudio volume control via SimplyCoreAudio
  - `Camera/`: AVFoundation capture, frame processing, preview
  - `FanControl/`: IOHIDEventSystem for temperature, XPC helper for fan speed
- **UI/**: SwiftUI views including `MainMenuView` with tabbed sections
- **Core/**: `Preferences` (UserDefaults), `ShortcutManager` (KeyboardShortcuts)

### Fan Helper (MacaroniFanHelper/)

Privileged XPC service for SMC writes. Runs as a LaunchDaemon with root privileges.

- `SMCWriteService.swift`: Low-level SMC communication
- `main.swift`: XPC listener and `FanHelperProtocol` implementation
- Supports both Apple Silicon (F0Md key, Float32 format) and Intel (FS! key, FPE2 format)

### Camera Extension (MacaroniCameraExtension/)

CMIOExtension for virtual camera output. Not yet fully implemented.

## Key Technical Details

### DDC/CI (Display Brightness)
- Uses `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` for Apple Silicon
- VCP code `0x10` for brightness control
- Requires non-sandboxed app for IOKit access

### Temperature Reading
- Uses private `IOHIDEventSystem` API via `dlsym`
- Filters sensors by name containing: "cpu", "soc", "die", "pmgr"
- Returns maximum temperature from matched sensors

### Fan Control
- Requires privileged helper at `/Library/PrivilegedHelperTools/com.macaroni.fanhelper`
- XPC protocol: `FanHelperProtocol` defined in both app and helper
- SMC keys:
  - `F0Ac` - Actual RPM
  - `F0Mn` / `F0Mx` - Min/Max RPM
  - `F0Tg` - Target RPM
  - `F0Md` - Fan mode (Apple Silicon)
  - `FS!` - Forced mode bitmask (Intel)

### Resolution Switching
- Uses `CGDisplayCopyAllDisplayModes` with `kCGDisplayShowDuplicateLowResolutionModes`
- Filters to show only HiDPI modes and native panel resolution
- Avoids showing "scaled" intermediate resolutions that appear blurry

## Build System

- Uses XcodeGen (`project.yml`) to generate Xcode project
- Swift Package Manager for dependencies
- Targets: Macaroni (app), MacaroniFanHelper (helper), MacaroniCameraExtension (extension)

## Dependencies

- `KeyboardShortcuts` - Global hotkeys
- `SimplyCoreAudio` - Audio device control
- `Solar` - Sunrise/sunset calculation
- `LaunchAtLogin` - Login item

## Code Style

- Use `os.log` Logger for logging, not print statements
- Follow Swift naming conventions
- Use proper access control (private/internal/public)
- Add doc comments for public APIs
- Keep views focused and use extracted subviews

## Common Tasks

### Adding a new feature module:
1. Create folder under `Macaroni/Features/`
2. Create Manager/Service class for business logic
3. Create MenuView for UI
4. Add tab/section in `MainMenuView.swift`

### Working with SMC:
1. Test reads first before writes
2. Auto-detect data format (Float32 vs FPE2)
3. Always provide fallback for unknown keys

### Debugging fan control:
1. Check helper installation: `ls -la /Library/PrivilegedHelperTools/com.macaroni.fanhelper`
2. Check daemon status: `sudo launchctl list | grep macaroni`
3. View helper logs: `log show --predicate 'subsystem == "com.macaroni.fanhelper"' --last 5m`

## Known Issues

- Virtual camera extension not fully implemented
- HiDPI scaling for external displays requires private CGVirtualDisplay API (not implemented)
- Audio extension (virtual audio device) not implemented

## Testing

Build and run from Xcode. For fan control testing:
1. Install privileged helper
2. Check temperature readings
3. Test fan speed changes with manual slider
4. Verify automatic curve behavior
