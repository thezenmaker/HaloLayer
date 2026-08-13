# Changelog

All notable HaloLayer changes will be documented here.

## 0.1.2 — 2026-08-13

- Ensured the setup assistant appears automatically after HaloLayer is allowed and launched.
- Versioned onboarding completion so users of earlier previews see the corrected guide once.
- Replaced the legacy Settings AppleScript with the native Accessibility deep link and fallback.
- Restored the setup assistant to the foreground as soon as Accessibility access is granted.

## 0.1.1 — 2026-08-13

- Added a guided first-launch assistant for non-developer installation.
- Added live Accessibility permission detection and one-click Finder opening.
- Fixed the Xcode target so folder badges are included in normal Release builds.
- Preserved macOS 14 compatibility in Finder viewport grouping.
- Repaired and enabled the complete unit test suite.

## 0.1.0 — 2026-08-13

- Renamed the complete application and bundle identity to HaloLayer.
- Unified metadata and folder-count badges in the main application overlay.
- Added public-ready project documentation and MIT licensing.
- Added independent size, resolution, and folder-badge controls.
- Added image and video dimensions in Finder Icon View.
- Improved overlay clipping, scrolling, navigation transitions, and window ordering.
