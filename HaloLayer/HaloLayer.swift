// HaloLayer — Finder Size Overlay for macOS
// A menu-bar utility that overlays file-size labels beneath visible files in Finder Icon View.
// Uses the macOS Accessibility API to map visible Finder items to screen coordinates.

import AppKit
import Foundation

// MARK: — Main entry point

@main
struct HaloLayerApp {
    static func main() {
        // Diagnostic / spike mode
        if CommandLine.arguments.contains("--spike") || CommandLine.arguments.contains("--diagnostic") {
            SpikeDiagnostic.run()
            exit(0)
        }

        // Normal menu-bar app
        let delegate = HaloLayerDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
