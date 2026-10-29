# MacMonitor

A lightweight system monitor for the macOS menu bar, built with Swift and SwiftUI. It lives only in the menu bar: no Dock icon and no regular windows, just a panel that opens from the menu bar item.

- **CPU:** total and per-core usage, with history
- **GPU:** usage and memory in use
- **Temperatures:** CPU, GPU, SoC, SSD and battery (Apple Silicon)
- **Memory:** usage, pressure, compressed and swap
- **Network:** download/upload speed and local IP (hidden by default)
- **Disk:** free space, read and write speed
- **Battery:** charge, time remaining, cycle count and health
- **Processes:** top apps by CPU and by memory
- **Weather:** current conditions, hourly and 7-day forecast via [Open-Meteo](https://open-meteo.com) (no API key needed)
- **Alerts:** notifications for high CPU usage, memory pressure and CPU temperature

Everything is configurable from the gear button in the panel: what shows up in the menu bar, which sections appear in the panel, and two layouts, **Normal** (cards with charts and details) and **Compact** (square tiles that fit without scrolling).

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 14 Sonoma or later
- To build: Xcode or the Command Line Tools (`xcode-select --install`)

## Install

Download `MacMonitor.dmg` from [Releases](https://github.com/lucianogalvao/MacMonitor/releases), open it and drag MacMonitor to Applications.

The app is ad-hoc signed (not notarized by Apple), so macOS blocks it the first time you open it. To allow it, go to **System Settings → Privacy & Security** and click **Open Anyway**. If macOS says the app is damaged, run:

```bash
xattr -dr com.apple.quarantine /Applications/MacMonitor.app
```

## Build

```bash
./build.sh                 # builds build/MacMonitor.app
open build/MacMonitor.app
./make-dmg.sh              # builds build/MacMonitor.dmg (app + Applications shortcut + install notes)
```

The app starts through AppKit (`NSApplication`) instead of a SwiftUI `App`, since a SwiftUI scene would require an empty Settings window. Since the panel never activates the app, it handles ⌘C/⌘V/⌘X/⌘A/⌘Z in the city field and ⌘Q itself (`PanelWindow.performKeyEquivalent`).

The app icon is drawn in code (`Scripts/make-icon.swift`). To regenerate `Resources/AppIcon.icns`, run `Scripts/make-icon.sh`.

## About temperatures

Temperatures are read through IOHID, an internal macOS interface also used by tools like Stats and iStat Menus. It needs no special permissions, but it isn't documented by Apple and may change in future macOS releases. Sensor names vary between chips, so readings are grouped by name prefix. Intel Macs aren't supported, and the temperature card is hidden there.

To list every sensor on a Mac:

```bash
swift Scripts/sensors-probe.swift
```
