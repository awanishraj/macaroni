# Claude Code Instructions for Macaroni

This file provides context and guidelines for Claude Code when working on this codebase.

## Project Overview

Macaroni is a macOS menubar utility that combines display, audio, camera, and fan control into a single app. It replaces 5 separate utilities (BetterDisplay, SoundSource, Hand Mirror, OBS Virtual Camera, Mac Fan Control) with one native SwiftUI app targeting macOS 14+ on Apple Silicon.

## Architecture

```
Macaroni.app
├── Main App (Macaroni/)
│   ├── App/           → MacaroniApp.swift, MenuBarLabel
│   ├── Features/
│   │   ├── Display/   → DDCService, SolarBrightnessService, VirtualDisplayService
│   │   ├── Audio/     → AudioManager (SimplyCoreAudio)
│   │   ├── Camera/    → CameraManager, FrameProcessor, CMIOSinkSender
│   │   └── FanControl/→ ThermalService, FanCurveController
│   ├── UI/            → MainMenuView, SettingsMenuView
│   └── Core/          → Preferences, ShortcutManager, SystemExtensionManager
│
├── MacaroniFanHelper/ → Privileged XPC daemon for SMC writes
│
└── MacaroniCameraExtension/ → CMIOExtension virtual camera
```

### Main App (Macaroni/)

- **App/**: Entry point using `MenuBarExtra` for menubar-only UI
- **Features/**: Four main modules (Display, Audio, Camera, FanControl)
- **UI/**: SwiftUI views with tabbed sections
- **Core/**: Preferences, shortcuts, system extension management

### Fan Helper (MacaroniFanHelper/)

Privileged XPC service for SMC writes. Runs as a LaunchDaemon with root privileges.

- `SMCWriteService.swift`: Low-level SMC communication
- `main.swift`: XPC listener and `FanHelperProtocol` implementation
- Supports both Apple Silicon (F0Md key, Float32) and Intel (FS! key, FPE2)

### Camera Extension (MacaroniCameraExtension/)

CMIOExtension providing virtual camera output. Fully implemented with:

- `ExtensionProvider.swift`: Main entry point, reads UUIDs from Info.plist
- `ExtensionDeviceSource.swift`: Device with sink/source streams, placeholder generation
- `ExtensionStreamSource.swift`: Source stream for apps to read from
- `ExtensionSinkSource.swift`: Sink stream receiving frames from main app

**Key UUIDs** (must match in Info.plist, CMIOSinkSender, SystemExtensionManager):
- Device: `A8D7B8AA-65AD-4D21-9C42-F3D7A8D7B8AA`
- Source: `B9E8C9BB-76BE-4E32-AD53-04E8B9E8C9BB`
- Sink: `C0F9D0CC-87CF-4F43-BE64-05F9C0F9D0CC`

## Key Technical Details

### DDC/CI (Display Brightness)
- Uses `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` for Apple Silicon
- VCP code `0x10` for brightness control
- Service cache maintains display ID → IOAVService mapping

### Virtual Camera
- CMIOExtension with OBS-style sink/source architecture
- Main app sends frames via `CMIOSinkSender` using CoreMediaIO APIs
- Placeholder frames shown when camera OFF (dual text: normal + mirrored)
- Extension updates require app restart (macOS caches CMIO devices per-process)

### Temperature Reading
- Uses private `IOHIDEventSystem` API via `dlsym`
- Filters sensors by name: "cpu", "soc", "die", "pmgr"
- Returns maximum temperature from matched sensors

### Fan Control
- Privileged helper at `/Library/PrivilegedHelperTools/com.macaroni.fanhelper`
- XPC protocol: `FanHelperProtocol`
- SMC keys: `F0Ac` (actual), `F0Mn/F0Mx` (min/max), `F0Tg` (target), `F0Md` (mode)

### Menu Bar Display
- Three modes: Icon only, Volume (dynamic icon), Temperature
- Volume icon changes based on level: slash (muted), wave.1/2/3.fill

## Build System

### Makefile Commands
```bash
make run    # Kill → Clean → Build → Launch (recommended)
make build  # Build only
make clean  # Clean build artifacts
make kill   # Kill running instances
```

### Project Generation
```bash
xcodegen generate  # Regenerate Xcode project from project.yml
```

### Targets
- `Macaroni` - Main app
- `MacaroniFanHelper` - Privileged helper (requires separate installation)
- `MacaroniCameraExtension` - System extension (embedded in app)

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| KeyboardShortcuts | 2.4.0 | Global hotkeys |
| SimplyCoreAudio | 4.1.1 | Audio device control |
| Solar | 3.0.1 | Sunrise/sunset calculation |
| LaunchAtLogin | 1.1.0 | Login item management |

## Code Style

- Use `os.log` Logger for logging, not print statements
- No debug logging to files in production code
- Follow Swift naming conventions
- Use proper access control (private/internal/public)
- Guard against force unwraps where possible
- Handle errors with logging, don't silently ignore

## Common Tasks

### Building and Running
```bash
make run  # Recommended: kills old instance, clean builds, launches
```

### Bumping Extension Version
When changing camera extension code:
1. Edit `MacaroniCameraExtension/Info.plist`
2. Increment `CFBundleVersion`
3. `make run`
4. Click "Update" in Camera tab, then "Restart Now"

### Testing Virtual Camera
1. Run Macaroni
2. Activate extension if needed (Camera tab → Activate)
3. Open Photo Booth → Select "Macaroni Camera"
4. Toggle camera ON/OFF in Macaroni to test placeholder vs live feed

### Debugging Fan Control
```bash
# Check helper installation
ls -la /Library/PrivilegedHelperTools/com.macaroni.fanhelper

# Check daemon status
sudo launchctl list | grep macaroni

# View helper logs
log show --predicate 'subsystem == "com.macaroni.fanhelper"' --last 5m
```

### Debugging Camera Extension
```bash
# View extension logs
log show --predicate 'subsystem == "com.macaroni.camera"' --last 5m
```

## File Locations

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project definition |
| `Makefile` | Build automation |
| `Progress.md` | Development progress tracking |
| `CLAUDE.md` | This file - AI assistant context |

## Important Notes

- **Extension Updates**: macOS caches CMIO devices per-process. After updating the camera extension, the app must restart for changes to take effect.
- **Hardcoded UUIDs**: Camera device/stream UUIDs are intentionally hardcoded and must match across Info.plist, CMIOSinkSender.swift, and SystemExtensionManager.swift.
- **No Sandboxing**: App is not sandboxed to allow IOKit access for DDC/CI and SMC communication.
