# Macaroni - Development Progress

*Last updated: January 2026*

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
| **Crisp HiDPI scaling** | ❌ Blocked | Requires CGVirtualDisplay private API |

**Roadblock:** True crisp 1080p on a 2560x1440 display requires creating virtual displays with the undocumented `CGVirtualDisplay` API (used by BetterDisplay, Sidecar, AirPlay). This involves:
- Creating a virtual display at 3840x2160
- Mirroring it to the physical 2560x1440 display
- macOS handles the downscaling (crisp supersampling)

Research completed; implementation requires adding Objective-C bridging header and special entitlements.

---

### Audio Module

| Feature | Status | Notes |
|---------|--------|-------|
| Volume slider | ✅ Complete | Real-time percentage display |
| Mute toggle | ✅ Complete | Visual feedback in UI |
| Keyboard shortcuts | ✅ Complete | Volume up/down/mute |
| Device selection | ⚠️ Partial | UI present, needs testing |
| **Virtual audio device** | ❌ Not started | Would require DriverKit audio extension |

---

### Camera Module

| Feature | Status | Notes |
|---------|--------|-------|
| Camera enumeration | ✅ Complete | Lists all available cameras |
| Quick preview popover | ✅ Complete | Click menubar to show/hide |
| Rotation transforms | ✅ Complete | 0°, 90°, 180°, 270° |
| Flip controls | ✅ Complete | Horizontal and vertical |
| Frame overlays | ⚠️ Partial | Infrastructure ready, frames not bundled |
| **Virtual camera output** | ❌ Blocked | CMIOExtension scaffolded but not functional |

**Roadblock:** Virtual camera requires:
- Properly signing the CMIOExtension
- System Extension approval workflow
- Frame passing from main app to extension

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

**Fully functional** - Fan control is the most complete module.

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
│   ├── Camera (CameraManager, FrameProcessor)
│   └── FanControl (ThermalService, FanCurveController)
├── MacaroniFanHelper (Privileged XPC daemon for SMC)
└── MacaroniCameraExtension (CMIOExtension - not functional)
```

---

## Technical Debt

1. **Camera extension not functional** - Needs signing, entitlements, frame passing
2. **Keyboard shortcuts window** - Currently just a placeholder button
3. **Display device selection** - Works but UI could be cleaner
4. **Frame overlays** - Code ready but no bundled PNG frames
5. **HiDPI virtual display** - Research done, implementation deferred

---

## Next Steps (Priority Order)

1. **Virtual Camera** - Get CMIOExtension working for video call apps
2. **HiDPI Scaling** - Implement CGVirtualDisplay for crisp external display scaling
3. **Keyboard Shortcuts Window** - Proper settings window for configuring hotkeys
4. **Frame Overlays** - Bundle artistic frames for camera preview
5. **Polish & Release** - DMG packaging, notarization, GitHub release

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
