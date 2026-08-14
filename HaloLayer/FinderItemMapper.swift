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
    let url: URL
    let sizeText: String
    let detailText: String
    let position: CGPoint  // screen coordinates for label origin
    let frame: CGRect      // bounding rect
    let viewportFrame: CGRect?

    init(
        url: URL,
        sizeText: String,
        detailText: String = "",
        position: CGPoint,
        frame: CGRect,
        viewportFrame: CGRect? = nil
    ) {
        self.url = url
        self.sizeText = sizeText
        self.detailText = detailText
        self.position = position
        self.frame = frame
        self.viewportFrame = viewportFrame
    }
}

struct FolderCountBadge {
    let url: URL
    let countText: String
    let frame: CGRect
    let viewportFrame: CGRect
}

struct FinderItemLayout {
    let url: URL
    let frame: CGRect
    let metadataBottomY: CGFloat
    let viewportFrame: CGRect
    let isDirectory: Bool

}

struct FinderLayoutSnapshot {
    let items: [FinderItemLayout]
    let viewportFrame: CGRect

}

struct FinderOverlayContent {
    let labels: [OverlayLabel]
    let folderBadges: [FolderCountBadge]
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

    /// Perform the expensive Accessibility traversal once. Labels and badges
    /// are derived from this immutable geometry snapshot without touching AX.
    func mapVisibleLayout(
        folderURL: URL,
        windowID: Int64,
        windowFrame: CGRect,
        permissionController: AccessibilityPermissionController
    ) -> FinderLayoutSnapshot? {
        guard permissionController.checkPermission() == .granted else { return nil }

        // Get Finder process
        guard let finderApp = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.finder" }
        ) else {
            return nil
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
            return nil
        }

        // Find the matching window
        guard let targetWindow = findTargetWindow(
            windows: windowsArray,
            windowID: windowID,
            folderURL: folderURL,
            windowFrame: windowFrame
        ) else {
            return nil
        }

        // Finder's hierarchy varies between macOS releases. Walk the window
        // recursively and keep elements that resolve to files in this folder.
        let items = collectFileItems(from: targetWindow, folderURL: folderURL)
        guard let viewportFrame = items.first?.viewportFrame else { return nil }
        return FinderLayoutSnapshot(items: items, viewportFrame: viewportFrame)
    }

    /// Build render data from cached geometry and cache-only metadata lookups.
    /// This method does no AX traversal and no filesystem or media I/O.
    func overlayContent(
        from snapshot: FinderLayoutSnapshot,
        showSize: Bool,
        showResolution: Bool,
        showFolderCounts: Bool
    ) -> FinderOverlayContent {
        let provider = FileMetadataProvider.shared
        let labels: [OverlayLabel] = (showSize || showResolution)
            ? snapshot.items.compactMap { item in
                let sizeLookup = showSize
                    ? provider.cachedFormattedSize(
                        at: item.url,
                        isDirectory: item.isDirectory
                    )
                    : .hit("")
                let resolutionLookup = showResolution && !item.isDirectory
                    ? provider.cachedFormattedPixelDimensions(at: item.url)
                    : .hit("")
                let sizeText = sizeLookup.value ?? ""
                let detailText = resolutionLookup.value ?? ""

                let labelHeight: CGFloat = 16
                let spacing: CGFloat = 2
                // Reserve the final width before resolution metadata arrives,
                // preventing the centered label from shifting when populated.
                let labelWidth: CGFloat = showResolution
                    ? min(max(item.frame.width + 48, 112), 120)
                    : min(max(item.frame.width + 32, 96), 112)
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

                guard item.viewportFrame.contains(labelFrame) else { return nil }

                return OverlayLabel(
                    url: item.url,
                    sizeText: sizeText,
                    detailText: detailText,
                    position: item.frame.origin,
                    frame: labelFrame,
                    viewportFrame: item.viewportFrame
                )
            }
            : []

        let badges: [FolderCountBadge] = showFolderCounts
            ? snapshot.items.compactMap { item in
                guard item.isDirectory else { return nil }
                let countLookup = provider.cachedFolderItemCount(at: item.url)
                guard countLookup.isCached, let text = countLookup.value else {
                    return nil
                }
                let diameter: CGFloat = text.count > 3 ? 26 : 22
                let badgeFrame = CGRect(
                    x: item.frame.maxX - diameter * 0.72,
                    y: item.frame.maxY - diameter * 0.82,
                    width: diameter,
                    height: diameter
                )
                guard item.viewportFrame.contains(badgeFrame) else { return nil }
                return FolderCountBadge(
                    url: item.url,
                    countText: text,
                    frame: badgeFrame,
                    viewportFrame: item.viewportFrame
                )
            }
            : []

        return FinderOverlayContent(labels: labels, folderBadges: badges)
    }

    /// Compatibility path used by diagnostics. Production rendering uses the
    /// progressive cache-only `overlayContent` pipeline above.
    func mapVisibleItems(
        folderURL: URL,
        windowID: Int64,
        windowFrame: CGRect,
        showSize: Bool = true,
        showResolution: Bool = true,
        permissionController: AccessibilityPermissionController
    ) -> [OverlayLabel] {
        guard let snapshot = mapVisibleLayout(
            folderURL: folderURL,
            windowID: windowID,
            windowFrame: windowFrame,
            permissionController: permissionController
        ) else { return [] }
        for item in snapshot.items {
            if showSize {
                _ = FileMetadataProvider.shared.formattedSize(
                    at: item.url,
                    isDirectory: item.isDirectory
                )
            }
            if showResolution {
                _ = FileMetadataProvider.shared.formattedPixelDimensions(at: item.url)
            }
        }
        return overlayContent(
            from: snapshot,
            showSize: showSize,
            showResolution: showResolution,
            showFolderCounts: false
        ).labels
    }

    func mapVisibleFolderBadges(
        folderURL: URL,
        windowID: Int64,
        windowFrame: CGRect,
        permissionController: AccessibilityPermissionController
    ) -> [FolderCountBadge] {
        guard let snapshot = mapVisibleLayout(
            folderURL: folderURL,
            windowID: windowID,
            windowFrame: windowFrame,
            permissionController: permissionController
        ) else { return [] }
        for item in snapshot.items where item.isDirectory {
            _ = FileMetadataProvider.shared.formattedFolderItemCount(at: item.url)
        }
        return overlayContent(
            from: snapshot,
            showSize: false,
            showResolution: false,
            showFolderCounts: true
        ).folderBadges
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

    private func collectFileItems(from root: AXUIElement, folderURL: URL) -> [FinderItemLayout] {
        let folderPath = folderURL.standardizedFileURL.path
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        let urlsByName = Dictionary(uniqueKeysWithValues: contents.map {
            ($0.lastPathComponent, $0)
        })

        var bestItemByPath: [String: (item: FinderItemLayout, area: CGFloat)] = [:]
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
                let isDirectory = (try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) == true
                let item = FinderItemLayout(
                    url: url,
                    frame: frame,
                    metadataBottomY: textBottom ?? frame.maxY,
                    viewportFrame: currentViewport,
                    isDirectory: isDirectory
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
