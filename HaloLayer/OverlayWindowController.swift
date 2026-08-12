// OverlayWindowController.swift
// Manages the transparent overlay window that draws file-size labels.

import Cocoa
import Foundation

final class OverlayWindowController {

    // MARK: — State
    private var overlayWindow: NSWindow?
    private var labelViews: [OverlayLabelView] = []
    private var badgeViews: [FolderCountBadgeView] = []
    private let overlayDispatchQueue = DispatchQueue(
        label: "com.korwerk.halolayer.file-metadata-layer",
        qos: .userInteractive
    )

    var isVisible: Bool { overlayWindow?.isVisible ?? false }

    // MARK: — Public API

    /// Show or update the overlay with the given labels.
    func update(
        over windowFrame: CGRect,
        labels: [OverlayLabel],
        folderBadges: [FolderCountBadge]
    ) {
        guard let viewportFrame = labels.first?.viewportFrame ?? folderBadges.first?.viewportFrame else {
            hide()
            return
        }

        let appKitViewportFrame = appKitGlobalFrame(fromAccessibilityFrame: viewportFrame)

        // Create window if needed
        if overlayWindow == nil {
            createOverlayWindow(frame: appKitViewportFrame)
        }

        guard let window = overlayWindow else { return }
        window.setFrame(appKitViewportFrame, display: false)

        // Update labels
        overlayDispatchQueue.sync {
            // Remove excess views
            while labelViews.count > labels.count {
                let removed = labelViews.removeLast()
                removed.removeFromSuperview()
            }

            // Add or update views
            for (i, label) in labels.enumerated() {
                let view: OverlayLabelView
                if i < labelViews.count {
                    view = labelViews[i]
                } else {
                    view = OverlayLabelView()
                    view.registeredLabel = label.sizeText
                    view.attach(to: window)
                    labelViews.append(view)
                }

                view.frame = appKitGlobalFrame(fromAccessibilityFrame: label.frame).offsetBy(
                    dx: -window.frame.minX,
                    dy: -window.frame.minY
                )
                view.sizeText = label.sizeText
                view.detailText = label.detailText
                view.isHidden = false
            }

            while badgeViews.count > folderBadges.count {
                badgeViews.removeLast().removeFromSuperview()
            }
            for (i, badge) in folderBadges.enumerated() {
                let view: FolderCountBadgeView
                if i < badgeViews.count {
                    view = badgeViews[i]
                } else {
                    view = FolderCountBadgeView()
                    window.contentView?.addSubview(view)
                    badgeViews.append(view)
                }
                view.frame = appKitGlobalFrame(
                    fromAccessibilityFrame: badge.frame
                ).offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
                view.countText = badge.countText
                view.isHidden = false
            }
        }

        // Keep HaloLayer immediately above this Finder content window—not at
        // a global high level. Finder dialogs and Get Info windows then remain
        // naturally above the overlay.
        if let finderWindowNumber = matchingFinderWindowNumber(for: windowFrame) {
            window.order(.above, relativeTo: finderWindowNumber)
        } else if !window.isVisible {
            window.orderFront(nil)
        }
    }

    /// Hide the overlay.
    func hide() {
        overlayDispatchQueue.sync {
            labelViews.forEach { $0.removeFromSuperview() }
            labelViews.removeAll()
            badgeViews.forEach { $0.removeFromSuperview() }
            badgeViews.removeAll()
        }
        overlayWindow?.orderOut(self)
    }

    // MARK: — Private

    private func createOverlayWindow(frame: CGRect) {
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        win.level = .normal
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.isOpaque = false
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.alphaValue = 1.0
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.masksToBounds = true

        overlayWindow = win
    }

    private func matchingFinderWindowNumber(for targetFrame: CGRect) -> Int? {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }),
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var closest: (number: Int, distance: CGFloat)?
        for info in windowInfo {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == finder.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(
                    dictionaryRepresentation: bounds as CFDictionary
                  ) else { continue }

            let distance = abs(frame.minX - targetFrame.minX) +
                abs(frame.minY - targetFrame.minY) +
                abs(frame.width - targetFrame.width) +
                abs(frame.height - targetFrame.height)
            if closest == nil || distance < closest!.distance {
                closest = (number, distance)
            }
        }
        return closest?.distance ?? .greatestFiniteMagnitude < 16
            ? closest?.number
            : nil
    }

    /// Accessibility uses a top-left global origin; AppKit window content uses
    /// a bottom-left origin relative to the overlay window.
    private func appKitGlobalFrame(fromAccessibilityFrame frame: CGRect) -> CGRect {
        let primaryScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: primaryScreenTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
