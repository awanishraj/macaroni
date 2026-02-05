# Macaroni - Development Progress

*Last updated: February 5, 2026*

## Vision

Macaroni aims to be the **all-in-one menubar utility** for Mac Mini power users, combining:
- Display control (brightness, resolution)
- Audio control (volume, device selection)
- Camera control (preview, transforms, virtual camera)
- Fan control (temperature monitoring, custom curves)

The goal is to replace multiple single-purpose utilities with one cohesive, native macOS app.

---

## Feature Status

### Display Module

| Feature | Status | Notes |
|---------|--------|-------|
| Hardware brightness (DDC/CI) | ✅ Complete | Works via IOAVService on Apple Silicon |
| Auto brightness (solar) | ✅ Complete | Uses sunrise/sunset with smooth transitions |
| Resolution switching | ✅ Complete | Shows HiDPI + native modes only |
| HiDPI labels | ✅ Complete | Shows HiDPI/Native/Scaled indicators |
| Keyboard shortcuts | ✅ Complete | Brightness up/down configurable |
| **Crisp HiDPI scaling** | ✅ Complete | Via CGVirtualDisplay API, brightness fix applied |

**Crisp HiDPI Scaling:** Implemented using the private `CGVirtualDisplay` API to create virtual displays for crisp text rendering on external monitors. Features:
- Creates virtual display at 2x resolution (e.g., 3840x2160 for 1080p HiDPI)
- Mirrors virtual display to physical display
- macOS performs supersampling for crisp text
- Supports 576p through 1440p HiDPI modes (aspect-ratio aware)
- DDC brightness control works correctly during mirroring (uses physical display ID from IOAVService cache)
- Limitations: 60Hz max, no HDR/HDCP support

Files added:
- `CGVirtualDisplay.h` - Private API declarations
- `VirtualDisplayService.swift` - Virtual display lifecycle
- `DisplayMirrorService.swift` - Display mirroring control
- Updated `DisplayMenuView.swift` with UI controls

---

### Audio Module

| Feature | Status | Notes |
|---------|--------|-------|
| Volume slider | ✅ Complete | Real-time percentage display |
| Mute toggle | ✅ Complete | Visual feedback in UI |
| Keyboard shortcuts | ✅ Complete | Volume up/down/mute |
| Device selection | ✅ Complete | Dropdown menu with volume capability indicator |
| **Software volume proxy** | ✅ Complete | HAL plugin (proxy-audio-device) for monitors without volume control |

---

### Camera Module

| Feature | Status | Notes |
|---------|--------|-------|
| Camera enumeration | ✅ Complete | Lists all cameras, filters out virtual camera |
| Live preview | ✅ Complete | Shows Macaroni Camera output in menu |
| Rotation transforms | ✅ Complete | Counter-clockwise, clockwise via icons |
| Horizontal flip | ✅ Complete | Toggle via icon button |
| Frame overlays | ✅ Complete | Rounded corners, polaroid, neon, vintage |
| **Virtual camera output** | ✅ Complete | CMIOExtension with sink/source streams |
| **Placeholder frames** | ✅ Complete | Shows "Turn on camera" when camera OFF |
| **Extension updates** | ✅ Complete | Update button + restart prompt |

**Virtual Camera Implementation:**
- CMIOExtension with fixed UUIDs (OBS-style architecture)
- Sink stream receives frames from main app via CoreMediaIO
- Source stream outputs to apps like Zoom, Photo Booth, FaceTime
- Auto-reconnect logic for robust connection handling
- Aspect-fill scaling (crops to fill 1920x1080 output)
- System extension auto-detection on app launch
- Placeholder frames with dual text (normal + mirrored) for apps that flip video
- Seamless extension updates with restart prompt (macOS caches CMIO devices per-process)

---

### Fan Control Module

| Feature | Status | Notes |
|---------|--------|-------|
| Temperature reading | ✅ Complete | IOHIDEventSystem, M1-M4 support |
| Fan speed reading | ✅ Complete | Via privileged helper |
| Manual fan control | ✅ Complete | Set target RPM via slider |
| Proportional curve | ✅ Complete | Linear 10%/°C above trigger |
| Auto/Manual mode toggle | ✅ Complete | Preference-synced |
| Helper installation | ✅ Complete | XPC LaunchDaemon |
| M4 Mac Mini support | ✅ Complete | Float32 format, F0Md key |

**Fully functional** - Robust temperature monitoring and fan speed control.

---

### Settings Module

| Feature | Status | Notes |
|---------|--------|-------|
| Menubar display mode | ✅ Complete | Temp, volume, or icon only |
| Launch at login | ✅ Complete | Via LaunchAtLogin package |
| Keyboard shortcuts config | ⚠️ Partial | UI present, needs window |
| About section | ✅ Complete | Minimal version footer |

---

### UI/UX

| Feature | Status | Notes |
|---------|--------|-------|
| Menubar icon | ✅ Complete | Custom macaroni logo |
| Tabbed menu sections | ✅ Complete | Display, Audio, Camera, Fan, Settings |
| Consistent design language | ✅ Complete | 12pt headers, 11pt body, icons |
| Dark mode support | ✅ Complete | Template icon adapts |

---

## Architecture Summary

```
Macaroni.app
├── Main App
│   ├── Display (DDCService, SolarBrightnessService, DisplayManager)
│   ├── Audio (AudioManager via SimplyCoreAudio)
│   ├── Camera (CameraManager, FrameProcessor, CMIOSinkSender, VirtualCameraPreview)
│   └── FanControl (ThermalService, FanCurveController)
├── MacaroniFanHelper (Privileged XPC daemon for SMC)
└── MacaroniCameraExtension (CMIOExtension virtual camera with placeholder support)
```

---

## Technical Debt

1. **Keyboard shortcuts window** - Currently just a placeholder button

---

## Next Steps (Priority Order)

1. **Keyboard Shortcuts Window** - Proper settings window for configuring hotkeys
2. **Polish & Release** - DMG packaging, notarization, GitHub release

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| KeyboardShortcuts | Latest | Global hotkey handling |
| SimplyCoreAudio | Latest | CoreAudio wrapper |
| Solar | Latest | Sunrise/sunset calculation |
| LaunchAtLogin | Latest | Login item management |

---

## Build Requirements

- macOS 14 Sonoma SDK
- Xcode 15+
- XcodeGen (for project generation)
- Apple Developer account (for signing extensions)

---

## References

### Display
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) - DDC/CI reference
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) - HiDPI scaling reference
- [one-key-hidpi](https://github.com/xzhih/one-key-hidpi) - Display override plists

### Fan Control
- [Stats](https://github.com/exelban/stats) - SMC/temperature patterns
- [Mac Fan Control](https://crystalidea.com/macs-fan-control) - Reference app

### Camera
- [OBS](https://github.com/obsproject/obs-studio) - CMIOExtension reference

---

## Contact

For questions or contributions, please open an issue on GitHub.
