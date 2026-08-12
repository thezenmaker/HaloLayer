// FinderContextMonitor.swift
// Detects Finder activation/deactivation, tracks the frontmost Finder window and folder.

import ApplicationServices
import Cocoa
import Foundation

struct FinderContext {
    let folderURL: URL
    let windowID: Int64
    let windowFrame: CGRect
}

enum FinderContextState {
    case idle                    // No Finder window
    case monitoring              // Tracking Finder
    case folderChanged           // Folder changed since last check
    case viewUnsupported         // Not Icon View
}

final class FinderContextMonitor {

    // MARK: — State

    private var previousFolderURL: URL?
    private var previousWindowID: Int64?
    public var currentContext: FinderContext?

    private let workspace = NSWorkspace.shared
    private let notificationCenter = NSWorkspace.shared.notificationCenter

    // MARK: — Callbacks

    var onContextChange: ((FinderContext?) -> Void)?
    var onStateChange: ((FinderContextState) -> Void)?

    var state: FinderContextState = .idle {
        didSet { onStateChange?(state) }
    }

    var currentFolder: URL? { currentContext?.folderURL }

    // MARK: — Lifecycle

    init() {
        // Observe application activation
        notificationCenter.addObserver(
            self,
            selector: #selector(handleFrontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Observe launch/termination
        notificationCenter.addObserver(
            self,
            selector: #selector(handleFinderLaunched),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleFinderTerminated),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    /// Refresh immediately instead of waiting for Finder to be re-activated.
    func refresh() {
        handleFinderActivation(
            workspace.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        )
    }

    // MARK: — Private

    @objc private func handleFrontmostApplicationChanged(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handleFinderActivation(app.bundleIdentifier == "com.apple.finder")
    }

    @objc private func handleFinderLaunched(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handleFinderActivation(app.bundleIdentifier == "com.apple.finder")
    }

    @objc private func handleFinderTerminated(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == "com.apple.finder" {
            currentContext = nil
            previousFolderURL = nil
            previousWindowID = nil
            state = .idle
            onContextChange?(nil)
        }
    }

    private func handleFinderActivation(_ isActive: Bool) {
        if !isActive {
            currentContext = nil
            previousFolderURL = nil
            previousWindowID = nil
            state = .idle
            onContextChange?(nil)
            return
        }

        // Finder is frontmost — try to get the frontmost Finder window
        if let context = getFrontmostFinderContext() {
            let changed = previousWindowID != context.windowID ||
                previousFolderURL != context.folderURL

            currentContext = context
            previousFolderURL = context.folderURL
            previousWindowID = context.windowID
            if changed {
                state = .folderChanged
                onContextChange?(context)
            } else {
                state = .monitoring
            }
        } else {
            currentContext = nil
            previousFolderURL = nil
            previousWindowID = nil
            state = .idle
            onContextChange?(nil)
        }
    }

    /// Get the focused Finder window through Accessibility. Keeping context
    /// discovery uses Finder Automation for the folder URL because Finder's
    /// AXDocument attribute returns `noValue` on current macOS releases.
    private func getFrontmostFinderContext() -> FinderContext? {
        if let context = automationFinderContext() { return context }

        // Keep the Accessibility fallback for Finder variants that do expose
        // AXDocument, even though stock Finder currently does not.
        guard let finder = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else {
            return nil
        }

        guard let focusedWindow = activeWindow(for: finder) else { return nil }

        guard let folderURL = documentURL(for: focusedWindow),
              let windowFrame = frame(of: focusedWindow) else { return nil }

        return FinderContext(
            folderURL: folderURL,
            windowID: Int64(folderURL.standardizedFileURL.path.hashValue),
            windowFrame: windowFrame
        )
    }

    /// Icon view exposes nested AXList/AXImage items; list and column views
    /// expose AXOutline/AXTable containers. Inspect the focused window rather
    /// than asking Finder through Apple Events.
    func isIconView() -> Bool {
        let scriptText = """
        tell application "Finder"
            try
                return (current view of front Finder window is icon view)
            on error
                return false
            end try
        end tell
        """
        var scriptError: NSDictionary?
        if let script = NSAppleScript(source: scriptText),
           let value = script.executeAndReturnError(&scriptError).stringValue {
            return value == "true"
        }

        guard let finder = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return false }

        guard let focusedWindow = activeWindow(for: finder) else { return false }

        var sawIconImage = false
        var sawListContainer = false
        var visited = 0

        func visit(_ element: AXUIElement, depth: Int) {
            guard depth <= 10, visited < 3_000, !sawListContainer else { return }
            visited += 1

            let role = stringAttribute(kAXRoleAttribute, from: element)
            if role == "AXOutline" || role == "AXTable" {
                sawListContainer = true
                return
            }
            if role == "AXImage" {
                sawIconImage = true
            }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] else { return }
            for child in children { visit(child, depth: depth + 1) }
        }

        visit(focusedWindow, depth: 0)
        return sawIconImage && !sawListContainer
    }

    private func automationFinderContext() -> FinderContext? {
        let scriptText = """
        tell application "Finder"
            try
                set finderWindow to front Finder window
                set folderPath to POSIX path of (target of finderWindow as alias)
                set {x1, y1, x2, y2} to bounds of finderWindow
                return folderPath & "|" & (id of finderWindow as string) & "|" & (x1 as string) & "|" & (y1 as string) & "|" & (x2 as string) & "|" & (y2 as string)
            on error
                return "ERROR"
            end try
        end tell
        """

        var scriptError: NSDictionary?
        guard let script = NSAppleScript(source: scriptText),
              let result = script.executeAndReturnError(&scriptError).stringValue else {
            return nil
        }

        let parts = result.components(separatedBy: "|")
        guard parts.count == 6,
              let windowID = Int64(parts[1]),
              let x1 = Double(parts[2]),
              let y1 = Double(parts[3]),
              let x2 = Double(parts[4]),
              let y2 = Double(parts[5]) else { return nil }

        return FinderContext(
            folderURL: URL(fileURLWithPath: parts[0]).standardizedFileURL,
            windowID: windowID,
            windowFrame: CGRect(
                x: x1,
                y: y1,
                width: x2 - x1,
                height: y2 - y1
            )
        )
    }

    private func documentURL(for window: AXUIElement) -> URL? {
        var documentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXDocumentAttribute as CFString,
            &documentValue
        ) == .success else { return nil }

        if let url = documentValue as? URL { return url.standardizedFileURL }
        guard let value = documentValue as? String else { return nil }
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL
        }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private func activeWindow(for finder: NSRunningApplication) -> AXUIElement? {
        let finderElement = AXUIElementCreateApplication(finder.processIdentifier)

        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var windowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                finderElement, attribute as CFString, &windowValue
            ) == .success,
            let window = windowValue as! AXUIElement?,
            documentURL(for: window) != nil {
                return window
            }
        }

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            finderElement, kAXWindowsAttribute as CFString, &windowsValue
        ) == .success,
        let windows = windowsValue as? [AXUIElement] else { return nil }

        return windows.first { window in
            stringAttribute(kAXRoleAttribute, from: window) == "AXWindow" &&
            stringAttribute(kAXSubroleAttribute, from: window) == "AXStandardWindow" &&
            documentURL(for: window) != nil
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeValue
        ) == .success,
        let positionAX = positionValue as! AXValue?,
        let sizeAX = sizeValue as! AXValue? else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value
        ) == .success else { return "" }
        return value as? String ?? ""
    }
}
