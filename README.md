<h1 align="center">
  <img src="logo.png" width="80" height="80" alt="Macaroni Logo"><br>
  Macaroni
</h1>

<p align="center">
  <em>A unified menubar utility for Mac Mini power users</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Ready-brightgreen.svg" alt="Apple Silicon">
</p>

---

## Why Macaroni?

Mac Mini users often juggle multiple utilities: one for display brightness, another for audio, a third for fan control. **Macaroni** combines them all into a single, elegant menubar app.

- **All-in-one**: Display, audio, camera, and fan control in one place
- **Native**: Built with SwiftUI, feels right at home on macOS
- **Lightweight**: Runs quietly in your menubar
- **Apple Silicon optimized**: Full support for M1/M2/M3/M4 chips

---

## Features

### Display Control
- **Hardware brightness** via DDC/CI for external monitors
- **Auto brightness** based on sunrise/sunset times
- **HiDPI resolution switching** with smart mode filtering
- Keyboard shortcuts for quick adjustments

### Audio Control
- **Volume slider** with live percentage display
- **Mute toggle** with visual feedback
- Global keyboard shortcuts

### Camera
- **Quick preview** popover from menubar
- **Rotation transforms**: 0°, 90°, 180°, 270°
- **Flip controls**: Horizontal and vertical mirroring
- Virtual camera output for video apps (coming soon)

### Fan Control *(Apple Silicon)*
- **Real-time CPU temperature** monitoring
- **Proportional fan curve**: Smooth scaling based on temperature
- **Configurable trigger**: Set your preferred threshold
- Safe defaults with automatic mode fallback

---

## Quick Start

### Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1/M2/M3/M4) for fan control
- External display with DDC/CI support for brightness control

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/macaroni.git
cd macaroni

# Generate Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate

# Open and build
open Macaroni.xcodeproj
```

### Fan Control Setup

The fan control feature requires a privileged helper for SMC access:

```bash
# Build the helper from Xcode, then install:
sudo cp build/Debug/MacaroniFanHelper /Library/PrivilegedHelperTools/com.macaroni.fanhelper
sudo cp MacaroniFanHelper/com.macaroni.fanhelper.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.macaroni.fanhelper.plist
```

---

## Keyboard Shortcuts

Configure in Settings. Suggested defaults:

| Action | Shortcut |
|--------|----------|
| Brightness Up | `⌥⌘↑` |
| Brightness Down | `⌥⌘↓` |
| Volume Up | `⌥⌘]` |
| Volume Down | `⌥⌘[` |
| Toggle Mute | `⌥⌘M` |
| Camera Preview | `⌥⌘P` |
| Cycle Rotation | `⌥⌘R` |

---

## Project Structure

```
Macaroni/
├── Macaroni/
│   ├── App/                    # App entry point & lifecycle
│   ├── Features/
│   │   ├── Display/            # DDC brightness, resolution, auto-brightness
│   │   ├── Audio/              # Volume control via CoreAudio
│   │   ├── Camera/             # AVFoundation capture & processing
│   │   └── FanControl/         # SMC temperature & fan speed
│   ├── UI/                     # SwiftUI views & components
│   └── Core/                   # Preferences, shortcuts, utilities
├── MacaroniCameraExtension/    # CMIOExtension virtual camera
├── MacaroniFanHelper/          # Privileged helper for SMC writes
└── Resources/                  # Assets & icons
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey handling |
| [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) | CoreAudio wrapper |
| [Solar](https://github.com/ceeK/Solar) | Sunrise/sunset calculation |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) | Login item management |

---

## Technical Notes

### DDC/CI Brightness
Uses IOKit's `IOAVService` on Apple Silicon for I2C communication with external monitors. Supports VCP code `0x10` for brightness control.

### Temperature Reading
Reads CPU/SoC temperature via `IOHIDEventSystem` private API. Monitors sensors containing "cpu", "soc", "die", or "pmgr" and reports the maximum.

### Fan Control
Communicates with SMC via privileged XPC helper. Supports both Apple Silicon (`F0Md` key) and Intel (`FS!` key) forced mode mechanisms. Auto-detects data format (Float32 vs FPE2).

---

## Contributing

Contributions are welcome! Please read through the codebase and feel free to submit PRs for:

- Bug fixes
- New features
- Documentation improvements
- UI/UX enhancements

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with SwiftUI for macOS</sub>
</p>
