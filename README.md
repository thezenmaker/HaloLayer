<div align="center">

# HaloLayer

**The missing metadata layer for Finder.**

File sizes, image and video dimensions, folder sizes, and subtle item-count badges—placed directly in Finder Icon View.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License MIT](https://img.shields.io/badge/License-MIT-63D391)](LICENSE)
[![Status Preview](https://img.shields.io/badge/Status-Preview-8B7CF6)](#project-status)

[Website](https://zenmaker.io/halolayer) · [Download app](https://github.com/thezenmaker/HaloLayer/releases/latest) · [Install](#installation) · [Privacy](PRIVACY.md) · [Contribute](CONTRIBUTING.md)

</div>

![HaloLayer showing metadata and a folder-count badge in Finder](docs/halolayer-preview.svg)

HaloLayer is a small native macOS menu-bar utility from [Johanna Zhou / ZenMaker](https://zenmaker.io). It makes Finder's Icon View more informative without turning file browsing into a dashboard—making complexity feel simple.

## What it adds

- File and recursive folder sizes
- Image and video resolution
- Immediate folder-item counts in circular badges
- Independent menu-bar toggles for size, resolution, and folder badges
- Overlay clipping to the active Finder viewport
- Fast position updates while scrolling and automatic hiding behind other windows

Everything runs locally. HaloLayer does not require an account or transmit file names, file contents, folder paths, or usage data.

## Installation

HaloLayer is not yet signed or notarized with a paid Apple Developer certificate. Choose the path that fits you.

### For normal users — download the DMG

Download `HaloLayer-v0.1.1.dmg` from the **Assets** section of the [latest GitHub Release](https://github.com/thezenmaker/HaloLayer/releases/latest), open it, and drag `HaloLayer.app` onto Applications. The DMG also includes a native **Open Privacy & Security** link and a short installation guide. Xcode and an Apple Developer account are not required. This universal preview build supports Apple Silicon and Intel Macs.

> Do not choose GitHub's automatically generated **Source code (zip)** or use **Code → Download ZIP** unless you want the source files. Those downloads do not contain the ready-to-run app.

Because the app is unsigned and not notarized, macOS will probably block the first launch. If—and only if—you downloaded it from this official repository:

1. Open the DMG and drag `HaloLayer.app` onto Applications. This copies the app; it does not automatically open the Applications folder. Double-click Applications if you want to verify the copy, then eject the HaloLayer disk image.
2. Open HaloLayer once and dismiss the macOS warning.
3. Double-click **Open Privacy & Security** included in the download.
4. Find the HaloLayer message and choose **Open Anyway → Open**.

This approves this app only; do not disable Gatekeeper globally. macOS intentionally requires the final confirmation and HaloLayer cannot approve itself before it is allowed to run.

HaloLayer requires Accessibility access to position metadata beside visible Finder icons. The source is public so you can inspect what that permission is used for before installing.

### For developers — build from source with Xcode

You need a Mac with macOS 14 or later and Xcode. A paid Apple Developer membership is not required for a local build.

```bash
git clone https://github.com/thezenmaker/HaloLayer.git
cd HaloLayer
open HaloLayer.xcodeproj
```

In Xcode, select the **HaloLayer** scheme and press **Run**. Xcode can sign the app locally. If it asks for a development team, choose your Personal Team under **Signing & Capabilities**.

## First launch

1. Open HaloLayer; its status indicator appears in the menu bar.
2. Grant **Accessibility** access when requested so HaloLayer can locate visible Finder icons.
3. Allow Finder automation if macOS asks; this lets HaloLayer identify the open folder and view mode.
4. Open a Finder window in **Icon View** and use the menu-bar toggles to choose what appears.

After replacing or rebuilding the app, macOS may treat it as a new binary and ask you to re-enable Accessibility access.

After macOS allows the app and HaloLayer opens, the guided setup assistant appears automatically on the first run. It explains the permission, opens the correct Accessibility settings pane, detects when access is granted, and opens Finder. HaloLayer remembers completion and every layer setting on later launches. You can reopen the guide manually from **Getting Started…** in the halo menu.

## Privacy and permissions

HaloLayer reads Finder window geometry and local file metadata solely to draw its overlays. It does not transmit file names, file contents, folder paths, metadata, or usage data. The app uses:

- **Accessibility** to read visible Finder item positions
- **Finder automation** to identify the active folder and confirm Icon View
- **Local filesystem metadata** to calculate sizes, dimensions, and folder counts

See the complete, plain-language [privacy statement](PRIVACY.md).

## How it works

HaloLayer is one native AppKit application with two coordinated visual layers:

```text
Finder Icon View
      │
      ├── Metadata layer ── size · resolution · recursive folder size
      └── Badge layer ───── immediate folder item count
```

The overlays are click-through, clipped to the active Finder content area, and ordered relative to that Finder window. No Finder Sync extension is embedded.

## Development

The application stays in Swift/AppKit because it integrates directly with macOS Accessibility, Finder automation, ImageIO, and AVFoundation.

```bash
# Build and run tests through Swift Package Manager
swift build
swift test

# Or build the app target with Xcode
xcodebuild -project HaloLayer.xcodeproj -scheme HaloLayer -configuration Debug build
```

See [MANUAL_TESTS.md](MANUAL_TESTS.md) for Finder-specific verification that cannot be covered reliably by unit tests.

## Project status

HaloLayer is an early preview with these current limitations:

- macOS 14 or later is required.
- Icon View is the supported layout; List, Column, and Gallery views are intentionally left untouched.
- Finder's Accessibility hierarchy is not a public overlay API and can change between macOS versions.
- Unsigned builds may require Accessibility permission to be granted again after rebuilding or replacing the app.

## About

Built by [Johanna Zhou / ZenMaker](https://zenmaker.io)—designing tools that make complexity feel simple.

HaloLayer remains fully functional without visiting the website.

HaloLayer is an independent open-source project and is not affiliated with or endorsed by Apple Inc. macOS and Finder are trademarks of Apple Inc.

## More tools

Explore more work from [ZenMaker](https://zenmaker.io).

If HaloLayer is useful to you, consider giving the repository a ⭐.

## License

HaloLayer is available under the [MIT License](LICENSE).
