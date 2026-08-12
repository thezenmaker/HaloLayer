# Manual Test Matrix — HaloLayer

## Test environment

- **OS:** macOS 26.5.2 (Sequoia)
- **Xcode:** 16.x / Swift 6.1
- **Display:** Primary display (Retina), secondary display (if available)
- **Finder:** Icon View, all icon sizes

---

## Test 1: Basic overlay display

| Step | Action | Expected | Result |
|---|---|---|---|
| 1.1 | Grant Accessibility permission | HaloLayer shows ✓ in status bar | |
| 1.2 | Open a Finder window in Icon View | Size labels appear beneath visible files | |
| 1.3 | Verify each label shows correct file size | Format: `428 KB`, `12.6 MB`, `1.2 GB` | |
| 1.4 | Open a folder with images | Size labels match Finder's file sizes | |
| 1.5 | Open a folder with PDFs | Size labels match Finder's file sizes | |
| 1.6 | Open a folder with ZIP files | Size labels match Finder's file sizes | |
| 1.7 | Toggle Finder's Show Item Info | Size sits directly below filename or native info, whichever is lower | |

## Test 2: Light and dark mode

| Step | Action | Expected | Result |
|---|---|---|---|
| 2.1 | Switch to Light Mode | Labels visible with appropriate contrast | |
| 2.2 | Switch to Dark Mode | Labels visible with appropriate contrast | |
| 2.3 | Toggle between modes | Labels update color accordingly | |

## Test 3: Retina display

| Step | Action | Expected | Result |
|---|---|---|---|
| 3.1 | Open a folder on Retina display | Labels render crisply, no pixelation | |
| 3.2 | Change icon size (small → large) | Labels reposition correctly | |
| 3.3 | Change display scaling | Labels remain sharp | |

## Test 4: Scrolling

| Step | Action | Expected | Result |
|---|---|---|---|
| 4.1 | Scroll down in a large folder | Labels follow the correct files | |
| 4.2 | Scroll rapidly | Labels hide during scroll, appear when stable | |
| 4.3 | Scroll to the bottom | Labels at bottom are correct | |
| 4.4 | Horizontal scroll (if applicable) | Labels stay with correct files | |
| 4.5 | Scroll items beneath the toolbar/header | Labels are clipped at the icon-view viewport edge | |

## Test 5: Resizing and icon size

| Step | Action | Expected | Result |
|---|---|---|---|
| 5.1 | Resize the Finder window | Labels realign with file icons | |
| 5.2 | Change icon size (View → Icon Size → Small/Large) | Labels reposition correctly | |
| 5.3 | Toggle between icon sizes | Labels update smoothly | |

## Test 6: Sorting and renaming

| Step | Action | Expected | Result |
|---|---|---|---|
| 6.1 | Sort by name (A→Z, Z→A) | Labels follow correct files | |
| 6.2 | Sort by date | Labels follow correct files | |
| 6.3 | Sort by size | Labels follow correct files | |
| 6.4 | Rename a file | Label updates to new position | |
| 6.5 | Drag a file to a new position | Label follows the file | |

## Test 7: File operations

| Step | Action | Expected | Result |
|---|---|---|---|
| 7.1 | Copy a file into the folder | New label appears for the copied file | |
| 7.2 | Delete a file | Label disappears | |
| 7.3 | Move a file into the folder | Label appears at the new location | |
| 7.4 | Move a file out of the folder | Label disappears | |

## Test 8: Finder interaction

| Step | Action | Expected | Result |
|---|---|---|---|
| 8.1 | Click on a file (through overlay) | File is selected normally | |
| 8.2 | Click and drag a file | File is dragged normally | |
| 8.3 | Open context menu (right-click) | Context menu appears normally | |
| 8.4 | Open a file (double-click) | File opens normally | |
| 8.5 | Quick Look (Spacebar) | Quick Look appears normally | |
| 8.6 | Select all (⌘A) | All files selected normally | |
| 8.7 | Multi-select (⌘Click) | Multi-select works normally | |

## Test 9: Overlay toggle

| Step | Action | Expected | Result |
|---|---|---|---|
| 9.1 | Toggle off via menu-bar | All labels disappear | |
| 9.2 | Toggle on via menu-bar | Labels reappear | |
| 9.3 | Toggle off while Finder is not frontmost | No effect | |
| 9.4 | Toggle on, then switch to another app | Labels hide | |
| 9.5 | Switch back to Finder | Labels reappear | |

## Test 10: Finder window state

| Step | Action | Expected | Result |
|---|---|---|---|
| 10.1 | Close the Finder window | Labels disappear | |
| 10.2 | Open a new Finder window | Labels appear in new window | |
| 10.3 | Open multiple Finder windows | Labels appear only in frontmost | |
| 10.4 | Minimize the Finder window | Labels hide | |
| 10.5 | Restore the minimized window | Labels reappear | |

## Test 11: Unsupported view

| Step | Action | Expected | Result |
|---|---|---|---|
| 11.1 | Switch Finder to List View | Labels disappear | |
| 11.2 | Switch Finder to Column View | Labels disappear | |
| 11.3 | Switch Finder back to Icon View | Labels reappear | |

## Test 12: Special file types

| Step | Action | Expected | Result |
|---|---|---|---|
| 12.1 | Folder | No size shown (or `—`) | |
| 12.2 | Application (.app) | Size shown correctly | |
| 12.3 | Alias (.alias) | Size shown correctly | |
| 12.4 | Symbolic link (.symlink) | Size shown correctly | |
| 12.5 | Hidden file (.hidden) | Size shown correctly | |
| 12.6 | Video file (.mov, .mp4) | Size shown correctly | |
| 12.7 | PDF file | Size shown correctly | |

## Test 13: Edge cases

| Step | Action | Expected | Result |
|---|---|---|---|
| 13.1 | Long filenames | Labels don't overlap | |
| 13.2 | Emoji filenames | Labels render correctly | |
| 13.3 | CJK filenames | Labels render correctly | |
| 13.4 | Identical prefixes | Ambiguous files: no label shown | |
| 13.5 | Empty folder | No labels shown | |
| 13.6 | Folder with 100+ files | Labels render for visible items only | |
| 13.7 | Truncated names (e.g., "Screen Shot 2026") | Ambiguous: no label shown | |

## Test 14: Multi-monitor

| Step | Action | Expected | Result |
|---|---|---|---|
| 14.1 | Open Finder on secondary display | Labels appear correctly | |
| 14.2 | Drag Finder window between displays | Labels follow correctly | |
| 14.3 | Different display resolutions | Labels render correctly on each | |

## Test 15: Permission denial

| Step | Action | Expected | Result |
|---|---|---|---|
| 15.1 | Revoke Accessibility permission | Labels disappear | |
| 15.2 | Status bar shows "permission required" | Tapping opens settings | |
| 15.3 | Grant permission after revoking | Labels reappear | |

## Test 16: Performance

| Step | Action | Expected | Result |
|---|---|---|---|
| 16.1 | Open a folder with 50 files | No Finder lag | |
| 16.2 | Scroll rapidly | No noticeable performance impact | |
| 16.3 | Change icon size 10 times | Smooth, no stutter | |
| 16.4 | CPU usage while idle | Minimal (< 2%) | |

## Test 17: Folder count badges

| Step | Action | Expected | Result |
|---|---|---|---|
| 17.1 | Enable Folder badges from the HaloLayer menu | Badges appear without enabling a Finder extension | |
| 17.2 | Open a folder containing child folders | Each visible child folder has a circular immediate-item-count badge | |
| 17.3 | Add a file inside a visible child folder | Its badge count updates | |
| 17.4 | Delete a file inside a visible child folder | Its badge count updates | |
| 17.5 | Scroll new folders onscreen | Badges are requested only as folders become visible | |

---

## Summary

| Category | Tests | Passed | Failed | Notes |
|---|---|---|---|---|
| Basic display | 6 | | | |
| Light/Dark mode | 3 | | | |
| Retina display | 3 | | | |
| Scrolling | 4 | | | |
| Resizing & icon size | 3 | | | |
| Sorting & renaming | 5 | | | |
| File operations | 4 | | | |
| Finder interaction | 7 | | | |
| Overlay toggle | 5 | | | |
| Finder window state | 5 | | | |
| Unsupported view | 3 | | | |
| Special file types | 7 | | | |
| Edge cases | 7 | | | |
| Multi-monitor | 3 | | | |
| Permission denial | 3 | | | |
| Performance | 4 | | | |
| **Total** | **65** | | | |
