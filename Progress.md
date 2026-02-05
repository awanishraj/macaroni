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

### Display Module ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Hardware brightness (DDC/CI) | ✅ Complete | Works via IOAVService on Apple Silicon |
| Auto brightness (solar) | ✅ Complete | Uses sunrise/sunset with smooth transitions |
| Resolution switching | ✅ Complete | Shows HiDPI + native modes only |
| HiDPI labels | ✅ Complete | Shows HiDPI/Native/Scaled indicators |
| Keyboard shortcuts | ✅ Complete | Brightness up/down configurable |
| Crisp HiDPI scaling | ✅ Complete | Via CGVirtualDisplay API |

**Crisp HiDPI Scaling:** Implemented using the private `CGVirtualDisplay` API to create virtual displays for crisp text rendering on external monitors.

---

### Audio Module ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Volume slider | ✅ Complete | Real-time control |
| Mute toggle | ✅ Complete | Visual feedback in UI |
| Keyboard shortcuts | ✅ Complete | Volume up/down/mute |
| Device selection | ✅ Complete | Dropdown with volume capability indicator |
| Menu bar icon | ✅ Complete | Dynamic icon based on volume level |
| Software volume proxy | ✅ Complete | HAL plugin for monitors without volume control |

**Menu Bar Volume Icon:** Shows appropriate SF Symbol based on volume level:
- `speaker.slash.fill` - Muted or 0%
- `speaker.wave.1.fill` - Low volume (<33%)
- `speaker.wave.2.fill` - Medium volume (33-66%)
- `speaker.wave.3.fill` - High volume (>66%)

---

### Camera Module ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Camera enumeration | ✅ Complete | Lists all cameras, filters out virtual camera |
| Live preview | ✅ Complete | Shows Macaroni Camera output in menu |
| Rotation transforms | ✅ Complete | Counter-clockwise, clockwise via icons |
| Horizontal flip | ✅ Complete | Toggle via icon button |
| Frame overlays | ❌ Not implemented | Future: rounded corners, polaroid, neon, vintage |
| Virtual camera output | ✅ Complete | CMIOExtension with sink/source streams |
| Placeholder frames | ✅ Complete | Dual text (normal + mirrored) when camera OFF |
| Extension updates | ✅ Complete | Update button + restart prompt |

**Virtual Camera Implementation:**
- CMIOExtension with fixed UUIDs (OBS-style architecture)
- Sink stream receives frames from main app via CoreMediaIO
- Source stream outputs to apps like Zoom, Photo Booth, FaceTime
- Auto-reconnect logic for robust connection handling
- Aspect-fill scaling (crops to fill 1920x1080 output)
- Placeholder frames with dual text for apps that flip video
- Seamless extension updates with restart prompt

---

### Fan Control Module ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Temperature reading | ✅ Complete | IOHIDEventSystem, M1-M4 support |
| Fan speed reading | ✅ Complete | Via privileged helper |
| Manual fan control | ✅ Complete | Set target RPM via slider |
| Proportional curve | ✅ Complete | Linear 10%/°C above trigger |
| Auto/Manual mode toggle | ✅ Complete | Preference-synced |
| Helper installation | ✅ Complete | XPC LaunchDaemon |
| M4 Mac Mini support | ✅ Complete | Float32 format, F0Md key |

---

### Settings Module ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Menu Icon picker | ✅ Complete | Icon-only segmented control (logo/volume/temp) |
| Launch at Login | ✅ Complete | Toggle via LaunchAtLogin package |
| Quit Macaroni | ✅ Complete | Clean app termination |

**Simplified Settings UI:** Clean three-item layout with icon-based menu bar mode picker.

---

### UI/UX ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Menubar icon | ✅ Complete | Custom macaroni logo or dynamic icons |
| Tabbed menu sections | ✅ Complete | Display, Audio, Camera, Fan, Settings |
| Consistent design language | ✅ Complete | 12pt labels, proper spacing |
| Dark mode support | ✅ Complete | Template icons adapt |

---

## Architecture Summary

```
Macaroni.app
├── Main App
│   ├── Display (DDCService, SolarBrightnessService, DisplayManager)
│   ├── Audio (AudioManager via SimplyCoreAudio)
│   ├── Camera (CameraManager, FrameProcessor, CMIOSinkSender, VirtualCameraPreview)
│   ├── FanControl (ThermalService, FanCurveController)
│   └── UI (MainMenuView, Settings)
├── MacaroniFanHelper (Privileged XPC daemon for SMC)
└── MacaroniCameraExtension (CMIOExtension virtual camera)
```

---

## Code Quality

**v1.0 Code Review Completed:**
- ✅ No debug logging or print statements
- ✅ No commented-out code blocks
- ✅ No unused imports or dead code
- ✅ Force unwraps fixed or verified safe
- ✅ Error handling with proper logging
- ✅ Consistent coding patterns

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| KeyboardShortcuts | 2.4.0 | Global hotkey handling |
| SimplyCoreAudio | 4.1.1 | CoreAudio wrapper |
| Solar | 3.0.1 | Sunrise/sunset calculation |
| LaunchAtLogin | 1.1.0 | Login item management |

---

## Build System

- **Makefile** - `make run` for kill → clean → build → launch
- **XcodeGen** - `project.yml` generates Xcode project
- **Targets:** Macaroni (app), MacaroniFanHelper (helper), MacaroniCameraExtension (extension)

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

### Fan Control
- [Stats](https://github.com/exelban/stats) - SMC/temperature patterns
- [Mac Fan Control](https://crystalidea.com/macs-fan-control) - Reference app

### Camera
- [OBS](https://github.com/obsproject/obs-studio) - CMIOExtension reference

---

## Version History

### v1.0 (February 2026)
- Initial release
- All core features complete
- Code review passed
