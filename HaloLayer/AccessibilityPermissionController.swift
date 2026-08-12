// AccessibilityPermissionController.swift
// Checks and requests Accessibility permission for HaloLayer.

import ApplicationServices
import Foundation

enum AccessibilityPermission {
    case granted
    case denied
    case unknown
}

final class AccessibilityPermissionController {

    // MARK: — State

    private(set) var currentStatus: AccessibilityPermission = .unknown

    var onStatusChange: ((AccessibilityPermission) -> Void)?

    // MARK: — Public API

    /// Check whether the current process has Accessibility permission.
    func checkPermission() -> AccessibilityPermission {
        if AXIsProcessTrusted() {
            if currentStatus != .granted {
                currentStatus = .granted
                onStatusChange?(.granted)
            }
            return .granted
        } else {
            if currentStatus != .denied {
                currentStatus = .denied
                onStatusChange?(.denied)
            }
            return .denied
        }
    }

    /// Request Accessibility permission with a system prompt.
    func requestPermission() {
        let options: [CFString: Any] = [
            "AXTrustedCheckOptionPrompt" as CFString: true
        ]
        let granted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if granted {
            currentStatus = .granted
            onStatusChange?(.granted)
        } else {
            currentStatus = .denied
            onStatusChange?(.denied)
        }
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        // Try to open directly via AppleScript
        let script = """
        tell application "System Preferences"
            set active pane to id "com.apple.preference.security"
            reveal anchor "Privacy_Accessibility" of pane "com.apple.preference.security"
            activate
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script as String) {
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Returns a user-facing message about the current permission state.
    func statusMessage() -> String {
        switch currentStatus {
        case .granted:
            return "✓ Accessibility permission granted"
        case .denied:
            return "Accessibility permission required — tap to open settings"
        case .unknown:
            return "Checking permissions…"
        }
    }
}