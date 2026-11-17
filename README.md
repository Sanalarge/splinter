# Splinter

A lightweight mouse remapper for macOS, built with SwiftUI. Works with standard
USB and Bluetooth mice across brands, with English and Turkish interfaces.

**macOS 14 Sonoma or later · Apple Silicon and Intel · Apache-2.0 licensed**

## Features

- Remap left, right, middle, back, forward and additional buttons up to button 32.
- Assign navigation, tab controls, desktop actions, editing commands or custom shortcuts.
- Give wheel tilt separate tap and hold actions, with adjustable horizontal scrolling.
- Apply mappings to all mice or a selected model; exclude individual applications.
- Inspect incoming events in Live Test and optionally launch at login.
- Enable compatibility for receivers that send Ctrl+Left/Right instead of side-button events.

## Install

1. Download `Splinter-<version>-universal.zip` from [Releases](https://github.com/Sanalarge/splinter/releases/latest).
2. Extract it and move `Splinter.app` to Applications.
3. Open Splinter and enable **Accessibility** and **Input Monitoring** in
   **System Settings → Privacy & Security**.
4. Choose a button and its action. Use **Live Test** to check the input.

Release packages contain both Apple Silicon and Intel code. They are ad-hoc
signed, without Apple notarization. macOS may block the first launch; after
verifying the download, use **Privacy & Security → Open Anyway** if offered.
Updates can require permission approval again. SHA-256 checksums accompany each release.

Choose **Settings → Language** to switch between English, Türkçe and the system language.
If left click is remapped, hold **⌥ Option** for a normal click. Clicks inside
Splinter's settings window always work normally.

## Compatibility

Splinter handles mouse events exposed by macOS. Vendor-specific buttons that do
not produce standard events need manufacturer support. Wheel tilt requires
discrete horizontal scroll events; continuous trackpad gestures pass through.

Ctrl+arrow compatibility is opt-in. A receiver's keyboard interface is accepted
only when it shares the same physical USB device as a matching mouse. A real
keyboard using that same receiver can also have its Ctrl+arrow shortcuts remapped.
Model selection applies to every connected mouse reporting the same vendor,
product and name.

## Build

Install Xcode Command Line Tools, then run:

```sh
git clone https://github.com/Sanalarge/splinter.git
cd splinter
./build.sh --adhoc --universal
open build/Splinter.app
```

No third-party runtime dependencies. For stable local signing, tests, the CLI
and release maintenance, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy and security

Input processing stays on your Mac. Splinter has no telemetry or network
service. Settings are stored locally; the diagnostic event log stays in memory
unless you explicitly copy it. Diagnostic output can contain key names,
shortcuts and device names; review it before sharing.

Report vulnerabilities through [private security reporting](https://github.com/Sanalarge/splinter/security/advisories/new).
Contributions are welcome through pull requests; see [CONTRIBUTING.md](CONTRIBUTING.md)
and [SECURITY.md](SECURITY.md).
