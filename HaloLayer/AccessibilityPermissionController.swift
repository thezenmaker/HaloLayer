// AccessibilityPermissionController.swift
// Checks and requests Accessibility permission for HaloLayer.

import ApplicationServices
import AppKit
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
    @discardableResult
    static func openAccessibilitySettings() -> Bool {
        let destinations = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) {
                return true
            }
        }

        return NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
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
