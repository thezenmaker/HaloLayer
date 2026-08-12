// HaloLayerDiagnostic.swift
// Feasibility spike diagnostic — runs with --spike flag.
// Maps visible Finder items to their file URLs and screen frames using the Accessibility API.

import Cocoa
import Foundation
import ApplicationServices

enum SpikeDiagnostic {
    static func run() {
        print("═══ HaloLayer Feasibility Spike v0.1.0 ═══")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        step1_checkFinderRunning()
        step2_checkAccessibilityPermission()
        step3_testUnifiedMetadataLayer()
    }

    // MARK: Step 3 — Exercise the production metadata-layer path

    private static func step3_testUnifiedMetadataLayer() {
        print("")
        print("── Step 3: File metadata layer ──")

        let monitor = FinderContextMonitor()
        monitor.refresh()
        guard let context = monitor.currentContext else {
            print("  ✗ No focused Finder folder found through Accessibility")
            return
        }

        print("  ✓ Focused folder: \(context.folderURL.path)")
        guard monitor.isIconView() else {
            print("  ✗ Focused Finder window is not Icon View")
            return
        }
        print("  ✓ Finder view: Icon View")

        let labels = FinderItemMapper().mapVisibleItems(
            folderURL: context.folderURL,
            windowID: context.windowID,
            windowFrame: context.windowFrame,
            permissionController: AccessibilityPermissionController()
        )
        print("  ✓ Visible metadata labels mapped: \(labels.count)")
    }

    private static func errorDescription(for error: AXError) -> String {
        switch error {
        case .success: return "Success"
        case .failure: return "Generic failure"
        case .illegalArgument: return "Illegal argument"
        case .invalidUIElement: return "Invalid UI element"
        case .invalidUIElementObserver: return "Invalid UI element observer"
        case .cannotComplete: return "Cannot complete"
        case .attributeUnsupported: return "Attribute not supported"
        case .actionUnsupported: return "Action not supported"
        case .notificationUnsupported: return "Notification not supported"
        case .notImplemented: return "Not implemented"
        case .notificationAlreadyRegistered: return "Notification already registered"
        case .notificationNotRegistered: return "Notification not registered"
        case .apiDisabled: return "Accessibility API disabled"
        case .noValue: return "No value for attribute"
        case .parameterizedAttributeUnsupported: return "Parameterized attribute not supported"
        case .notEnoughPrecision: return "Not enough precision"
        @unknown default: return "Unknown error (\(error.rawValue))"
        }
    }

    // MARK: Step 1 — Detect if Finder is running

    private static func step1_checkFinderRunning() {
        print("── Step 1: Is Finder running? ──")
        let workspace = NSWorkspace.shared
        let finderApp = workspace.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        )

        if let finderApp = finderApp {
            print("  ✓ Finder is running (PID: \(finderApp.processIdentifier))")
        } else {
            print("  ✗ Finder is NOT running")
            print("  → Cannot proceed without Finder.")
        }
    }

    // MARK: Step 2 — Check Accessibility permission

    private static func step2_checkAccessibilityPermission() {
        print("")
        print("── Step 2: Accessibility permission ──")

        let trusted = AXIsProcessTrusted()
        if trusted {
            print("  ✓ Accessibility permission GRANTED (AXIsProcessTrusted)")
        } else {
            print("  ✗ Accessibility permission DENIED")
            print("  → Open System Settings → Privacy & Security → Accessibility")
            print("  → Add HaloLayer and enable it.")
            print("")

            let promptOptions: [String: Any] = ["AXTrustedCheckOptionPrompt": true]
            let prompted = AXIsProcessTrustedWithOptions(promptOptions as CFDictionary)
            if prompted {
                print("  → Prompt returned: permission now GRANTED")
            } else {
                print("  → Prompt returned: permission still DENIED")
            }
        }
    }

    // MARK: Step 3 — Identify frontmost Finder window

    private static func step3_getFrontmostFinderWindow() {
        print("")
        print("── Step 3: Frontmost Finder window ──")

        let scriptText = """
        tell application "Finder"
            set _window to (window 1 whose class is Finder window and target of it is not missing value)
            set _target to target of _window as alias
            return POSIX path of _target
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: scriptText) {
            let result = appleScript.executeAndReturnError(&error)
            if let folderPath = result.stringValue {
                print("  ✓ Frontmost Finder target: \(folderPath)")
            } else if let errDict = error {
                let desc = errDict["NSLocalizedDescription"] as? String ?? "unknown error"
                print("  ✗ Could not get Finder target: \(desc)")
            }
        }
    }

    // MARK: Step 4 — Map visible Finder items via Accessibility API

    private static func step4_mapVisibleItems() {
        print("")
        print("── Step 4: Accessibility hierarchy inspection ──")

        guard let finderApp = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        ) else {
            print("  ✗ Finder not running")
            return
        }

        let finderPID = finderApp.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()

        var appCFType: CFTypeRef?
        let _ = AXUIElementCopyAttributeValue(
            systemWide, "AXApplication" as CFString, &appCFType
        )
        var app: AXUIElement
        var methodUsed = "AXApplication attribute"
        if let gotApp = appCFType as! AXUIElement? {
            app = gotApp
        } else {
            app = AXUIElementCreateApplication(finderPID)
            methodUsed = "AXUIElementCreateApplication"
        }
        print("  ✓ Got Finder AX element via \(methodUsed) (PID: \(finderPID))")

        var windowsValue: CFTypeRef?
        let winResult = AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &windowsValue)

        if winResult != .success {
            print("  ✗ No AXWindows attribute (error: \(errorDescription(for: winResult)))")
            print("  → Without Accessibility permission, Finder's windows are not accessible.")
            return
        }

        guard let windowsArray = windowsValue as? [AXUIElement] else {
            print("  ✗ AXWindows is not an array")
            return
        }

        print("  → Found \(windowsArray.count) AXWindow elements")

        // Find Finder windows
        var foundWindow: (AXUIElement, String)? = nil
        for (idx, window) in windowsArray.enumerated() {
            var windowRoleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXRole" as CFString, &windowRoleValue)
            var windowSubroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXSubrole" as CFString, &windowSubroleValue)
            var windowNameValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXName" as CFString, &windowNameValue)
            var isHiddenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXHidden" as CFString, &isHiddenValue)

            let role = windowRoleValue as? String ?? "(none)"
            let subrole = windowSubroleValue as? String ?? "(none)"
            let name = windowNameValue as? String ?? "(none)"
            let hidden = (isHiddenValue as? Bool) ?? false

            print("  Window[\(idx)]: role=\(role) subrole=\(subrole) name=\"\(name)\" hidden=\(hidden)")

            if subrole == "AXStandardWindow" && !hidden {
                if foundWindow == nil {
                    foundWindow = (window, name)
                }
            }
        }

        if foundWindow == nil {
            print("  → No Finder windows found via Accessibility")
            return
        }

        let (finderWindow, winName) = foundWindow!
        print("")
        print("  → Using frontmost Finder window: \"\(winName)\"")

        // Get content / scroll areas
        var contentValue: CFTypeRef?
        AXUIElementCopyAttributeValue(finderWindow, "AXContent" as CFString, &contentValue)

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(finderWindow, "AXChildren" as CFString, &childrenValue)

        var allGroups: [AXUIElement] = []
        if let groups = contentValue as? [AXUIElement] {
            allGroups.append(contentsOf: groups)
        }
        if let children = childrenValue as? [AXUIElement] {
            allGroups.append(contentsOf: children)
        }

        var scrollAreas: [AXUIElement] = []
        for group in allGroups {
            var groupRoleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(group, "AXRole" as CFString, &groupRoleValue)
            if groupRoleValue as? String == "AXScrollArea" || groupRoleValue as? String == "AXGroup" {
                scrollAreas.append(group)
            }
        }

        print("  → Found \(scrollAreas.count) scrollable/group areas")

        // Collect file items
        struct FileItem {
            let url: String?
            let name: String
            let frame: CGRect
            let role: String
            let subrole: String
            let iconFrame: CGRect?
            let nameFrame: CGRect?
        }

        var fileItems: [FileItem] = []

        for (_, scrollArea) in scrollAreas.enumerated() {
            var saChildrenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(scrollArea, "AXChildren" as CFString, &saChildrenValue)

            if let iconGroups = saChildrenValue as? [AXUIElement] {
                for (_, iconGroup) in iconGroups.enumerated() {
                    var iconRoleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(iconGroup, "AXRole" as CFString, &iconRoleValue)
                    let roleStr = iconRoleValue as? String ?? ""

                    if roleStr == "AXButton" || roleStr == "AXCell" || roleStr == "AXCheckBox" {
                        var nameVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXTitle" as CFString, &nameVal)
                        let nameStr = nameVal as? String ?? ""

                        var nameLabelVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXName" as CFString, &nameLabelVal)
                        let nameLabelStr = nameLabelVal as? String ?? ""

                        var frameValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXFrame" as CFString, &frameValue)
                        var frameRect = CGRect.zero
                        if let axv = frameValue as! AXValue? {
                            AXValueGetValue(axv, .cgRect, &frameRect)
                        }

                        var urlVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXURL" as CFString, &urlVal)
                        let urlPath = (urlVal as? URL)?.path ?? ""

                        var subroleVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXSubrole" as CFString, &subroleVal)
                        let subroleStr = subroleVal as? String ?? ""

                        var iconFrameRect: CGRect?
                        var iconVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(iconGroup, "AXImage" as CFString, &iconVal)
                        if let icon = iconVal as! AXUIElement? {
                            var iconFrameVal: CFTypeRef?
                            AXUIElementCopyAttributeValue(icon, "AXFrame" as CFString, &iconFrameVal)
                            if let axv = iconFrameVal as! AXValue? {
                                var irect = CGRect.zero
                                AXValueGetValue(axv, .cgRect, &irect)
                                if irect != CGRect.zero {
                                    iconFrameRect = irect
                                }
                            }
                        }

                        var nameLabelFrame: CGRect?
                        if let nameLabelRef = nameLabelVal as! AXUIElement? {
                            var lfVal: CFTypeRef?
                            AXUIElementCopyAttributeValue(nameLabelRef, "AXFrame" as CFString, &lfVal)
                            if let axv = lfVal as! AXValue? {
                                var lrect = CGRect.zero
                                AXValueGetValue(axv, .cgRect, &lrect)
                                if lrect != CGRect.zero {
                                    nameLabelFrame = lrect
                                }
                            }
                        }

                        fileItems.append(FileItem(
                            url: urlPath.isEmpty ? nil : urlPath,
                            name: nameStr.isEmpty ? nameLabelStr : nameStr,
                            frame: frameRect,
                            role: roleStr,
                            subrole: subroleStr,
                            iconFrame: iconFrameRect,
                            nameFrame: nameLabelFrame
                        ))
                    }
                }
            }
        }

        print("")
        print("  → Mapped \(fileItems.count) visible file items from Accessibility API:")
        print("")
        print("  \(String("URL").ljust(44))│ \(String("Name").ljust(32))│ \(String("Frame"))")

        for (_, item) in fileItems.enumerated() {
            let urlStr = item.url ?? "(no URL)"
            let urlCol = urlStr.count > 42 ? String(urlStr.prefix(39)) + "…" : urlStr
            let nameCol = item.name.count > 30 ? String(item.name.prefix(27)) + "…" : item.name

            let frameStr = item.frame != CGRect.zero
                ? String(format: "(%.0f, %.0f) %.0f×%.0f",
                         item.frame.origin.x, item.frame.origin.y,
                         item.frame.width, item.frame.height)
                : "no frame"

            print("  \(urlCol.ljust(44))│ \(nameCol.ljust(32))│ \(frameStr)")
        }

        print("")

        // Feasibility analysis
        print("── Feasibility Analysis ──")

        let itemsWithUrl = fileItems.filter { $0.url != nil }.count
        let itemsWithFrame = fileItems.filter { $0.frame != CGRect.zero }.count
        let itemsWithName = fileItems.filter { !$0.name.isEmpty }.count

        print("  Total visible items: \(fileItems.count)")
        print("  Items with URL attribute: \(itemsWithUrl) / \(fileItems.count)")

        if itemsWithUrl == fileItems.count && fileItems.count > 0 {
            print("  URL matching: FULL — all items have URL (EXCELLENT)")
        } else if itemsWithUrl == 0 {
            print("  URL matching: NONE — cannot map accessibility element to file (BLOCKER)")
        } else {
            print("  URL matching: PARTIAL — \(itemsWithUrl) of \(fileItems.count) items have URL, rest rely on name matching")
        }

        print("  Items with frame: \(itemsWithFrame) / \(fileItems.count)")
        print("  Items with name: \(itemsWithName) / \(fileItems.count)")
        print("")

        if itemsWithUrl == fileItems.count && fileItems.count > 0 {
            print("  ★ Feasibility GATE PASSES ★")
            print("  → All visible items have stable URLs and frames.")
            print("  → Overlay implementation is viable.")
        } else if itemsWithUrl > 0 {
            print("  ⚠ Feasibility GATE PARTIAL")
            let rate = Double(itemsWithUrl) / Double(max(fileItems.count, 1))
            if rate >= 0.8 {
                print("  → Match rate \(String(format: "%.0f%%", rate * 100)) ≥ 80% — GATE PASSES (with name-matching fallback)")
            } else {
                print("  → Match rate \(String(format: "%.0f%%", rate * 100)) < 80% — GATE FAILS")
            }
        } else {
            print("  ✗ Feasibility GATE FAILS")
            print("  → No URL attributes exposed. Cannot reliably map visible items to files.")
            print("  → The MVP must run with Accessibility permission granted.")
        }

        print("")
        print("═══ Spike diagnostic complete. ═══")
    }
}

// MARK: Helpers

extension String {
    func ljust(_ width: Int) -> String {
        let count = self.count
        if count >= width { return self }
        return self + String(repeating: " ", count: width - count)
    }
}
