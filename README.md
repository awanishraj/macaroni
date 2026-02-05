<h1 align="center">
  <img src="logo.png" width="100" height="100" alt="Macaroni Logo"><br>
  Macaroni
</h1>

<p align="center">
  <strong>All-in-one Mac utility. Cooked al dente.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/Apple%20Silicon-M1%20to%20M4-brightgreen.svg" alt="Apple Silicon">
</p>

---

## What is Macaroni?

Macaroni is a **free, open-source macOS menubar utility** that combines the functionality of five separate apps into one lightweight, native application:

| Instead of... | You get... |
|---------------|------------|
| **BetterDisplay** ($18) | Crisp text on external monitors, brightness without buttons |
| **SoundSource** ($39) | Unlock volume control on external speakers |
| **Hand Mirror** ($8) | Quick camera check before video calls |
| **OBS Virtual Camera** | Transform your camera feed—rotate, flip, mirror |
| **Mac Fan Control** | Custom fan curves to prevent thermal throttling |

**One simple app. Just the features you need, none of the bloat. Free and open source.**

---

## Features

### 🖥️ Display Control

<img src="Screenshots/Display.png" width="350" align="right" alt="Display Control">

**The problem:** External monitors don't respond to Mac's brightness keys. You're stuck fumbling with tiny buttons on your monitor every time the lighting changes.

**The solution:** Macaroni lets you control your monitor's brightness with a simple slider—no more reaching behind your display. It also makes text crisp and sharp on external monitors, fixing the blurry scaling that plagues many setups.

- Adjust brightness without touching your monitor
- Auto brightness that follows sunrise/sunset
- Crisp, sharp text on external displays (HiDPI scaling)
- Quick resolution switching

<br clear="right"/>

---

### 🔊 Audio Control

<img src="Screenshots/Audio.png" width="350" align="right" alt="Audio Control">

**The problem:** Monitor speakers connected via HDMI or DisplayPort ignore your Mac's volume keys. You're stuck at full blast or have to press buttons on the speaker.

**The solution:** Macaroni gives you a volume slider that works with any audio device—even ones that don't normally support software volume control.

- Volume slider that works with any output device
- Quick device switching
- Dynamic menubar icon showing current volume level
- Mute toggle

<br clear="right"/>

---

### 📷 Camera Preview & Virtual Camera

<img src="Screenshots/Camera.png" width="350" align="right" alt="Camera">

**The problem:** You want to check how you look before joining a video call, but that means opening Photo Booth. And if you want to flip or rotate your camera, you need OBS.

**The solution:** One click in your menubar shows a live camera preview. Macaroni also creates a virtual camera that any app can use—Zoom, Meet, FaceTime—with rotation and flip built right in.

- Quick camera check from the menubar
- Virtual camera output works in any video app
- Rotate and flip your camera feed

<br clear="right"/>

---

### 🌡️ Fan Control

<img src="Screenshots/Fans.png" width="350" align="right" alt="Fan Control">

**The problem:** Mac Mini runs hot under load, and macOS's conservative fan curves prioritize silence over cooling.

**The solution:** Macaroni reads CPU temperature in real-time and lets you set a custom fan curve with your preferred trigger temperature. Keep your Mac cool during heavy workloads.

- Real-time CPU temperature monitoring
- Custom fan curves with configurable trigger
- Manual RPM control via slider
- Animated fan icon showing current speed
- Full M1/M2/M3/M4 support

<br clear="right"/>

---

### ⚙️ Settings

<img src="Screenshots/Settings.png" width="350" align="right" alt="Settings">

**Simple, focused settings.** Choose what to show in your menubar: the Macaroni icon, a dynamic volume indicator, or the current CPU temperature. Enable launch at login with one click.

- Menu icon picker (logo, volume, or temperature)
- Launch at Login toggle
- Quit Macaroni

<br clear="right"/>

---

## Installation

### Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1/M2/M3/M4) for fan control
- Most external monitors support brightness control (works over HDMI, DisplayPort, USB-C)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/awanishraj/macaroni.git
cd macaroni

# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build and run
make run
```

### Virtual Camera Setup

The virtual camera requires approving a system extension:

1. Run Macaroni
2. Go to Camera tab → Click "Activate" on Virtual Camera
3. Approve in System Settings → Privacy & Security → Extensions
4. Restart Macaroni when prompted

### Fan Control Setup

Fan control requires installing a privileged helper:

1. Go to Fan tab
2. Click "Install Helper"
3. Enter your password when prompted
4. The helper runs as a LaunchDaemon with minimal privileges

---

## Architecture

```
Macaroni.app
├── Main App (SwiftUI)
│   ├── Display   → DDCService, SolarBrightnessService, VirtualDisplayService
│   ├── Audio     → AudioManager (SimplyCoreAudio)
│   ├── Camera    → CameraManager, FrameProcessor, CMIOSinkSender
│   └── Fan       → ThermalService, FanCurveController
│
├── MacaroniFanHelper (Privileged XPC Service)
│   └── SMC read/write for fan control
│
└── MacaroniCameraExtension (CMIOExtension)
    └── Virtual camera with sink/source streams
```

---

## How It Works

### Display Brightness
Communicates directly with your monitor's hardware using the DDC/CI protocol (the same way your monitor's own buttons work). This means real brightness adjustment—not a software overlay that washes out colors.

### Virtual Camera
Creates a system-level virtual camera that appears in any app's camera selection. Macaroni captures your real camera, applies your chosen transforms, and outputs the result as "Macaroni Camera".

### Fan Control
Uses a privileged helper to communicate directly with your Mac's fan controller. You can set custom temperature triggers or manually control fan speed when you need extra cooling.

### Temperature Reading
Reads your Mac's thermal sensors and reports the CPU temperature in real-time. Works on all Apple Silicon Macs (M1 through M4).

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey handling |
| [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) | CoreAudio device management |
| [Solar](https://github.com/ceeK/Solar) | Sunrise/sunset calculation |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) | Login item management |

---

## Acknowledgments

Macaroni was built by studying and learning from these excellent open-source projects:

- [MonitorControl](https://github.com/MonitorControl/MonitorControl) - Display brightness control
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) - HiDPI scaling
- [OBS Studio](https://github.com/obsproject/obs-studio) - Virtual camera architecture
- [Stats](https://github.com/exelban/stats) - Temperature and fan monitoring

---

## SIP Configuration (Apple Silicon)

Some features require reduced System Integrity Protection. This is a one-time setup.

### Part A: Recovery Mode

1. **Shut down** your Mac completely (Apple menu → Shut Down)
2. **Enter Recovery Mode**: Press and hold Power button until "Loading startup options" appears
3. **Open Startup Security Utility**: Click Options → Continue → Utilities menu → Startup Security Utility
4. **Set Reduced Security**:
   - Select your startup disk
   - Click "Security Policy..."
   - Select "Reduced Security"
   - Check "Allow user management of kernel extensions from identified developers"
   - Click OK and authenticate
5. **Open Terminal**: Utilities menu → Terminal
6. **Run**:
   ```bash
   csrutil enable --without kext --without debug
   ```
7. **Restart**: Type `reboot` and press Enter

### Part B: After Reboot

8. Open Terminal (Applications → Utilities → Terminal)
9. Enable system extension developer mode:
   ```bash
   systemextensionsctl developer on
   ```
10. Verify with `csrutil status` — should show "enabled" with kext and debug exceptions

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Made with ❤️ for Mac users who want fewer menubar icons</sub>
</p>
