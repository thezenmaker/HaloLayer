// OverlayWindowController.swift
// Manages the transparent overlay window that draws file-size labels.

import Cocoa
import Foundation

final class OverlayWindowController {

    // MARK: — State
    private var overlayWindow: NSWindow?
    private var overlayContentView: NSView?
    private var labelViews: [OverlayLabelView] = []
    private var badgeViews: [FolderCountBadgeView] = []
    private var cachedScrollTranslation = CGVector.zero

    var isVisible: Bool { overlayWindow?.isVisible ?? false }

    /// Whether a global AppKit screen point is inside the Finder icon viewport
    /// currently covered by HaloLayer.
    func contains(screenPoint: CGPoint) -> Bool {
        guard let window = overlayWindow, window.isVisible else { return false }
        return window.frame.contains(screenPoint)
    }

    /// Move the cached overlay geometry in lockstep with Finder's scroll
    /// gesture. The authoritative Accessibility mapping replaces these frames
    /// after momentum settles.
    func translateCachedContent(by delta: CGVector) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard overlayWindow?.isVisible == true,
              delta.dx != 0 || delta.dy != 0 else { return }

        cachedScrollTranslation.dx += delta.dx
        cachedScrollTranslation.dy += delta.dy

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayContentView?.layer?.setAffineTransform(
            CGAffineTransform(
                translationX: cachedScrollTranslation.dx,
                y: cachedScrollTranslation.dy
            )
        )
        CATransaction.commit()
    }

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

        // AppKit view mutations must stay on the main thread. Moving these
        // operations through a private queue caused intermittent one-frame
        // stale/partial overlay draws while Finder was navigating.
        dispatchPrecondition(condition: .onQueue(.main))

        // The incoming Accessibility frames are authoritative. Clear the
        // temporary scroll transform in the same transaction in which those
        // frames are installed so reconciliation never animates or trails.
        cachedScrollTranslation = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayContentView?.layer?.setAffineTransform(.identity)

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
                if let overlayContentView {
                    view.attach(to: overlayContentView)
                }
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
                overlayContentView?.addSubview(view)
                badgeViews.append(view)
            }
            view.frame = appKitGlobalFrame(
                fromAccessibilityFrame: badge.frame
            ).offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
            view.countText = badge.countText
            view.isHidden = false
        }

        CATransaction.commit()

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
        dispatchPrecondition(condition: .onQueue(.main))
        labelViews.forEach { $0.removeFromSuperview() }
        labelViews.removeAll()
        badgeViews.forEach { $0.removeFromSuperview() }
        badgeViews.removeAll()
        cachedScrollTranslation = .zero
        overlayContentView?.layer?.setAffineTransform(.identity)
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

        let content = NSView(frame: win.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        win.contentView?.addSubview(content)

        overlayWindow = win
        overlayContentView = content
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
