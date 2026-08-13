# Changelog

All notable HaloLayer changes will be documented here.

## 0.1.1 — 2026-08-13

- Added a guided first-launch assistant for non-developer installation.
- Ensured the setup assistant appears automatically after HaloLayer is allowed and launched.
- Replaced the legacy Settings AppleScript with the native Accessibility deep link and fallback.
- Marked both setup actions as complete as the user finishes them and removed the redundant toggle step.
- Used the macOS accent blue for enabled menu toggles and the active halo icon.
- Added live Accessibility permission detection and one-click Finder opening.
- Fixed the Xcode target so folder badges are included in normal Release builds.
- Preserved macOS 14 compatibility in Finder viewport grouping.
- Repaired and enabled the complete unit test suite.
- Added an **Open Privacy & Security** download shortcut to simplify Gatekeeper approval.
- Made first-run guide presentation reliable after Gatekeeper approval and automatic only once.
- Made Finder-step completion and the **Finish Setup** button respond immediately.
- Preserved layer toggles between launches and kept enabled switches visibly blue.
- Added a ready-made DMG for normal-user installation without Xcode.
- Presented onboarding once per internal build so retained preview preferences cannot suppress a newly corrected guide.
- Disabled automatic menu-item validation so saved enabled switches remain interactive and blue after relaunching.
- Replaced native menu switches with deterministic controls whose enabled state is always system blue.
- Replaced the unreliable Privacy & Security web location with a native macOS preference-pane link.

## 0.1.0 — 2026-08-13

- Renamed the complete application and bundle identity to HaloLayer.
- Unified metadata and folder-count badges in the main application overlay.
- Added public-ready project documentation and MIT licensing.
- Added independent size, resolution, and folder-badge controls.
- Added image and video dimensions in Finder Icon View.
- Improved overlay clipping, scrolling, navigation transitions, and window ordering.
