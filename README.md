<div align="center">

# HaloLayer

**The missing metadata layer for Finder.**

File sizes, image and video dimensions, folder sizes, and subtle item-count badges—placed directly in Finder Icon View.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License MIT](https://img.shields.io/badge/License-MIT-63D391)](LICENSE)
[![Status Preview](https://img.shields.io/badge/Status-Preview-8B7CF6)](#project-status)

[Website preview](https://zenmaker-website-git-agent-halolayer-product-page-zenmaker.vercel.app/halolayer) · [Install](#installation) · [Privacy](#privacy-and-permissions) · [Contribute](CONTRIBUTING.md)

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

Everything runs locally. HaloLayer does not require an account, analytics, or a visit to a website.

## Installation

HaloLayer is not yet signed or notarized with a paid Apple Developer certificate. Choose the path that fits you.

### For developers — build with free Xcode

You only need a Mac, Xcode, and a free Apple ID.

```bash
git clone https://github.com/thezenmaker/HaloLayer.git
cd HaloLayer
open HaloLayer.xcodeproj
```

In Xcode, select the **HaloLayer** scheme and press **Run**. If Xcode asks for a team, choose your Personal Team under **Signing & Capabilities**. A paid Apple Developer membership is not required for a local build.

### For normal users — unsigned release build

When a preview build is attached to [GitHub Releases](https://github.com/thezenmaker/HaloLayer/releases), download `HaloLayer.app.zip`, unzip it, and move `HaloLayer.app` to Applications.

Because the app is unsigned and not notarized, macOS may block the first launch. If—and only if—you downloaded it from this official repository, open **System Settings → Privacy & Security**, find the HaloLayer message, and choose **Open Anyway**. This approves this app only; do not disable Gatekeeper globally.

> No release is promised until a build has been manually verified. Building from source is the recommended preview path today.

## First launch

1. Open HaloLayer; its status indicator appears in the menu bar.
2. Grant **Accessibility** access when requested so HaloLayer can locate visible Finder icons.
3. Allow Finder automation if macOS asks; this lets HaloLayer identify the open folder and view mode.
4. Open a Finder window in **Icon View** and use the menu-bar toggles to choose what appears.

After replacing or rebuilding the app, macOS may treat it as a new binary and ask you to re-enable Accessibility access.

## Privacy and permissions

HaloLayer reads Finder window geometry and local file metadata solely to draw its overlays. It does not upload filenames, metadata, or usage data. The app uses:

- **Accessibility** to read visible Finder item positions
- **Finder automation** to identify the active folder and confirm Icon View
- **Local filesystem metadata** to calculate sizes, dimensions, and folder counts

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

HaloLayer is an early preview. Finder's Accessibility hierarchy is not a public overlay API and can change between macOS versions. Icon View is the supported layout; List, Column, and Gallery views are intentionally left untouched.

## About

Built by [Johanna Zhou / ZenMaker](https://zenmaker.io)—designing tools that make complexity feel simple.

HaloLayer remains fully functional without visiting the website.

## More tools

Explore more work from [ZenMaker](https://zenmaker.io).

## License

HaloLayer is available under the [MIT License](LICENSE).
