// FinderItemMapper.swift
// Maps visible Finder items to their file URLs and screen frames using the Accessibility API.

import ApplicationServices
import Cocoa
import Foundation

/// A single mapped file item with URL, name, and screen position.
struct MappedFileItem {
    let url: URL
    let name: String
    let frame: CGRect
    let confidence: Confidence  // How confident we are about the URL match
}

enum Confidence: Comparable {
    case certain
    case probable
    case ambiguous

    static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        switch (lhs, rhs) {
        case (.certain, .certain): return false
        case (.certain, _): return false
        case (_, .certain): return true
        case (.probable, .probable): return false
        case (.probable, _): return false
        case (_, .probable): return true
        case (.ambiguous, .ambiguous): return false
        default: return true
        }
    }
}

struct OverlayLabel {
    let sizeText: String
    let detailText: String
    let position: CGPoint  // screen coordinates for label origin
    let frame: CGRect      // bounding rect
    let viewportFrame: CGRect?

    init(
        sizeText: String,
        detailText: String = "",
        position: CGPoint,
        frame: CGRect,
        viewportFrame: CGRect? = nil
    ) {
        self.sizeText = sizeText
        self.detailText = detailText
        self.position = position
        self.frame = frame
        self.viewportFrame = viewportFrame
    }
}

struct FolderCountBadge {
    let countText: String
    let frame: CGRect
    let viewportFrame: CGRect
}

private struct AXMappedItem {
    let element: AXUIElement
    let url: URL
    let frame: CGRect
    let metadataBottomY: CGFloat
    let viewportFrame: CGRect
}

private struct ViewportKey: Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ frame: CGRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
    }
}

final class FinderItemMapper {
    // MARK: — Public API

    /// Map visible Finder items to their URLs and frames.
    /// Returns an array of MappedFileItems with their screen positions.
    /// The overlay labels (size text + position) are computed from the frames.
    func mapVisibleItems(
        folderURL: URL,
        windowID: Int64,
        windowFrame: CGRect,
        showSize: Bool = true,
        showResolution: Bool = true,
        permissionController: AccessibilityPermissionController
    ) -> [OverlayLabel] {

        guard permissionController.checkPermission() == .granted else {
            return []
        }

        // Get Finder process
        guard let finderApp = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        ) else {
            return []
        }

        let finderPID = finderApp.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()

        // Get Finder AX element
        var appCFType: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide, "AXApplication" as CFString, &appCFType
        )
        var finderAX: AXUIElement
        if let gotApp = appCFType as! AXUIElement?, appResult == .success {
            finderAX = gotApp
        } else {
            finderAX = AXUIElementCreateApplication(finderPID)
        }

        // Get windows
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            finderAX, "AXWindows" as CFString, &windowsValue
        ) == .success,
        let windowsArray = windowsValue as? [AXUIElement] else {
            return []
        }

        // Find the matching window
        guard let targetWindow = findTargetWindow(
            windows: windowsArray,
            windowID: windowID,
            folderURL: folderURL,
            windowFrame: windowFrame
        ) else {
            return []
        }

        // Finder's hierarchy varies between macOS releases. Walk the window
        // recursively and keep elements that resolve to files in this folder.
        let fileItems = collectFileItems(from: targetWindow, folderURL: folderURL)

        // Map each file item to its URL and compute overlay position
        let overlayLabels = fileItems.compactMap { item -> OverlayLabel? in
            // Get file size
            let sizeText = showSize
                ? (FileMetadataProvider.shared.formattedSize(at: item.url) ?? "—")
                : ""
            let detailText = showResolution
                ? (FileMetadataProvider.shared.formattedPixelDimensions(at: item.url) ?? "")
                : ""
            guard !sizeText.isEmpty || !detailText.isEmpty else { return nil }

            // The deepest visible text descendant is either the filename or
            // Finder's optional native item-info line. Place HaloLayer directly
            // beneath whichever one Finder is currently drawing.
            let labelHeight: CGFloat = 16
            let spacing: CGFloat = 2
            // Image dimensions need substantially more room than a byte count.
            // Keep the row centered on the Finder item, but give the resolution
            // enough width that values such as “2,906 × 4,484” are not clipped.
            let labelWidth: CGFloat
            if detailText.isEmpty {
                labelWidth = min(max(item.frame.width + 32, 96), 112)
            } else {
                labelWidth = min(max(item.frame.width + 48, 112), 120)
            }
            let unclampedX = item.frame.midX - (labelWidth / 2)
            let labelX = min(
                max(unclampedX, item.viewportFrame.minX),
                item.viewportFrame.maxX - labelWidth
            )

            let labelFrame = CGRect(
                x: labelX,
                y: item.metadataBottomY + spacing,
                width: labelWidth,
                height: labelHeight
            )

            // Do not draw partial labels at the viewport edges. They will
            // appear on the next refresh once fully scrolled into view.
            guard item.viewportFrame.contains(labelFrame) else { return nil }

            return OverlayLabel(
                sizeText: sizeText,
                detailText: detailText,
                position: item.frame.origin,
                frame: labelFrame,
                viewportFrame: item.viewportFrame
            )
        }

        return overlayLabels
    }

    func mapVisibleFolderBadges(
        folderURL: URL,
        windowID: Int64,
        windowFrame: CGRect,
        permissionController: AccessibilityPermissionController
    ) -> [FolderCountBadge] {
        guard permissionController.checkPermission() == .granted,
              let finderApp = NSWorkspace.shared.runningApplications.first(
                where: { $0.bundleIdentifier == "com.apple.finder" }
              ) else { return [] }

        let finderAX = AXUIElementCreateApplication(finderApp.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            finderAX, kAXWindowsAttribute as CFString, &windowsValue
        ) == .success,
        let windows = windowsValue as? [AXUIElement],
        let targetWindow = findTargetWindow(
            windows: windows,
            windowID: windowID,
            folderURL: folderURL,
            windowFrame: windowFrame
        ) else { return [] }

        return collectFileItems(from: targetWindow, folderURL: folderURL).compactMap { item in
            guard (try? item.url.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true else { return nil }

            let count = (try? FileManager.default.contentsOfDirectory(
                at: item.url,
                includingPropertiesForKeys: nil,
                options: []
            ).count) ?? 0
            let text = count > 999 ? "999+" : String(count)
            let diameter: CGFloat = text.count > 3 ? 26 : 22
            let badgeFrame = CGRect(
                x: item.frame.maxX - diameter * 0.72,
                y: item.frame.maxY - diameter * 0.82,
                width: diameter,
                height: diameter
            )
            guard item.viewportFrame.contains(badgeFrame) else { return nil }
            return FolderCountBadge(
                countText: text,
                frame: badgeFrame,
                viewportFrame: item.viewportFrame
            )
        }
    }

    // MARK: — Private helpers

    private func findTargetWindow(
        windows: [AXUIElement],
        windowID: Int64,
        folderURL: URL,
        windowFrame: CGRect
    ) -> AXUIElement? {
        var firstStandardWindow: AXUIElement?
        var closestWindow: (element: AXUIElement, distance: CGFloat)?
        for window in windows {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXRole" as CFString, &roleValue)
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXSubrole" as CFString, &subroleValue)
            var hiddenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXHidden" as CFString, &hiddenValue)

            let role = roleValue as? String ?? ""
            let subrole = subroleValue as? String ?? ""
            let hidden = (hiddenValue as? Bool) ?? false

            if role == "AXWindow" && subrole == "AXStandardWindow" && !hidden {
                if firstStandardWindow == nil { firstStandardWindow = window }

                if let axFrame = getFrame(window) {
                    let distance = abs(axFrame.minX - windowFrame.minX) +
                        abs(axFrame.minY - windowFrame.minY) +
                        abs(axFrame.width - windowFrame.width) +
                        abs(axFrame.height - windowFrame.height)
                    if closestWindow == nil || distance < closestWindow!.distance {
                        closestWindow = (window, distance)
                    }
                }

                var documentValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    window,
                    kAXDocumentAttribute as CFString,
                    &documentValue
                ) == .success,
                let document = documentValue as? String {
                    let windowURL = URL(string: document)?.isFileURL == true
                        ? URL(string: document)!
                        : URL(fileURLWithPath: document)
                    if windowURL.standardizedFileURL == folderURL.standardizedFileURL {
                        return window
                    }
                }
            }
        }
        // AppleScript and Accessibility use the same top-left screen geometry
        // for Finder window bounds. A small tolerance handles title-bar rounding.
        if let closestWindow, closestWindow.distance < 12 {
            return closestWindow.element
        }
        return firstStandardWindow
    }

    private func collectFileItems(from root: AXUIElement, folderURL: URL) -> [AXMappedItem] {
        let folderPath = folderURL.standardizedFileURL.path
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        let urlsByName = Dictionary(uniqueKeysWithValues: contents.map {
            ($0.lastPathComponent, $0)
        })

        var bestItemByPath: [String: (item: AXMappedItem, area: CGFloat)] = [:]
        var visitedCount = 0

        func visit(_ element: AXUIElement, depth: Int, viewport: CGRect?) {
            guard depth <= 12, visitedCount < 5_000 else { return }
            visitedCount += 1

            let role = stringAttribute("AXRole", from: element)
            let elementFrame = getFrame(element)
            let currentViewport: CGRect?
            if role == "AXScrollArea", let elementFrame, !elementFrame.isEmpty {
                currentViewport = elementFrame
            } else {
                currentViewport = viewport
            }

            if let url = resolveURL(
                from: element,
                folderURL: folderURL,
                urlsByName: urlsByName
            ), url.deletingLastPathComponent().standardizedFileURL.path == folderPath,
               let frame = elementFrame, !frame.isEmpty,
               let currentViewport,
               currentViewport.intersects(frame) {
                let path = url.standardizedFileURL.path
                let area = frame.width * frame.height
                let textBottom = deepestTextBottom(
                    in: element,
                    fileName: url.lastPathComponent,
                    limitedTo: currentViewport
                )
                let item = AXMappedItem(
                    element: element,
                    url: url,
                    frame: frame,
                    metadataBottomY: textBottom ?? frame.maxY,
                    viewportFrame: currentViewport
                )
                if bestItemByPath[path] == nil || area > bestItemByPath[path]!.area {
                    bestItemByPath[path] = (item, area)
                }
            }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, "AXChildren" as CFString, &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] else { return }

            for child in children {
                visit(child, depth: depth + 1, viewport: currentViewport)
            }
        }

        visit(root, depth: 0, viewport: nil)
        let items = bestItemByPath.values.map(\.item)

        // A Finder window can contain several scroll areas (sidebar, preview,
        // file grid). The icon-view viewport is the one containing the largest
        // number of resolved children from the current folder.
        let itemsByViewport = Dictionary(grouping: items) {
            ViewportKey($0.viewportFrame)
        }
        return itemsByViewport.values.max { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            let lhsArea = (lhs.first?.viewportFrame.width ?? 0) *
                (lhs.first?.viewportFrame.height ?? 0)
            let rhsArea = (rhs.first?.viewportFrame.width ?? 0) *
                (rhs.first?.viewportFrame.height ?? 0)
            return lhsArea < rhsArea
        } ?? []
    }

    private func deepestTextBottom(
        in root: AXUIElement,
        fileName: String,
        limitedTo viewport: CGRect
    ) -> CGFloat? {
        var deepest: CGFloat?
        var visitedCount = 0

        func visit(_ element: AXUIElement, depth: Int) {
            guard depth <= 6, visitedCount < 250 else { return }
            visitedCount += 1

            let role = stringAttribute("AXRole", from: element)
            if (role == "AXStaticText" || role == "AXTextField"),
               let frame = getFrame(element),
               !frame.isEmpty, viewport.intersects(frame) {
                deepest = max(deepest ?? frame.maxY, frame.maxY)
            }

            // macOS 26 exposes Icon View files as AXImage nodes, but does not
            // expose Finder's drawn filename/item-info lines as AXStaticText.
            // The image title is "filename, native metadata" when item info is
            // visible, so reproduce Finder's one/two-line filename layout and
            // reserve the native line only when that suffix is present.
            if role == "AXImage", let iconFrame = getFrame(element),
               !iconFrame.isEmpty, viewport.intersects(iconFrame) {
                let accessibilityTitle = stringAttribute("AXTitle", from: element)
                let hasNativeInfo = accessibilityTitle.hasPrefix(fileName + ",")
                let filenameLines = estimatedFilenameLineCount(fileName)
                let nativeInfoLines = hasNativeInfo ? 1 : 0
                let textTop = iconFrame.maxY + 4
                let estimatedBottom = textTop +
                    CGFloat(filenameLines + nativeInfoLines) * 16
                deepest = max(deepest ?? estimatedBottom, estimatedBottom)
            }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, "AXChildren" as CFString, &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] else { return }
            for child in children { visit(child, depth: depth + 1) }
        }

        visit(root, depth: 0)
        return deepest
    }

    private func estimatedFilenameLineCount(_ fileName: String) -> Int {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let bounds = (fileName as NSString).boundingRect(
            with: NSSize(width: 104, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return min(2, max(1, Int(ceil(bounds.height / 16))))
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value as? String ?? ""
    }

    private func resolveURL(
        from axItem: AXUIElement,
        folderURL: URL,
        urlsByName: [String: URL]? = nil
    ) -> URL? {
        // Primary: try AXURL attribute
        var urlValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axItem, "AXURL" as CFString, &urlValue)
        if let url = urlValue as? URL {
            return url
        }
        if let urlString = urlValue as? String,
           let url = URL(string: urlString), url.isFileURL {
            return url
        }

        // Fallback: try AXTitle and match by filename in the folder
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axItem, "AXTitle" as CFString, &titleValue)
        guard let title = titleValue as? String, !title.isEmpty else {
            return nil
        }

        // Also try AXName
        var nameValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axItem, "AXName" as CFString, &nameValue)
        let name = (nameValue as? String)?.isEmpty == false ? (nameValue as? String) ?? "" : title

        if let urlsByName {
            return urlsByName[name] ?? urlsByName[title]
        }

        let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return contents?.first {
            $0.lastPathComponent == name || $0.lastPathComponent == title
        }
    }

    private func getFrame(_ axItem: AXUIElement) -> CGRect? {
        var frameValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axItem, "AXFrame" as CFString, &frameValue)
        guard let axv = frameValue as! AXValue? else { return nil }

        var rect = CGRect.zero
        if AXValueGetValue(axv, .cgRect, &rect) {
            return rect
        }
        return nil
    }

}
