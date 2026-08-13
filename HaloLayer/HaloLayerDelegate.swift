// HaloLayerDelegate.swift
// AppState + MenuBar status item — the main orchestration layer.

import Cocoa
import Foundation
import QuartzCore

enum FinderScrollMotion {
    /// Precise trackpad deltas are already measured in points. Traditional
    /// wheel events are line based, so approximate AppKit's line movement.
    static func contentTranslation(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseDeltas: Bool
    ) -> CGVector {
        let multiplier: CGFloat = hasPreciseDeltas ? 1 : 10
        return CGVector(
            dx: deltaX * multiplier,
            dy: deltaY * multiplier
        )
    }
}

enum GettingStartedPresentationPolicy {
    static func shouldPresent(
        isCompleted: Bool,
        presentedThisLaunch: Bool
    ) -> Bool {
        !isCompleted && !presentedThisLaunch
    }
}

final class HaloLayerDelegate: NSObject, NSApplicationDelegate {

    // MARK: — Core components
    private let permissionController = AccessibilityPermissionController()
    private let contextMonitor = FinderContextMonitor()
    private let itemMapper = FinderItemMapper()
    private let overlayController = OverlayWindowController()

    // MARK: — Menu bar
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var sizeSwitch: AlwaysBlueToggle!
    private var resolutionSwitch: AlwaysBlueToggle!
    private var folderCountSwitch: AlwaysBlueToggle!
    private var quitMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var gettingStartedController: GettingStartedWindowController?

    // MARK: — State
    private var isFileSizeEnabled: Bool = true
    private var isResolutionEnabled: Bool = true
    private var isFolderCountsEnabled: Bool = false
    private var refreshTimer: Timer?
    private var scrollEventMonitor: Any?
    private var scrollDisplayLink: CADisplayLink?
    private var pendingScrollTranslation = CGVector.zero
    private var isTrackingFinderScroll = false
    private var lastScrollEventTime: CFTimeInterval = 0
    private var navigationRetryWorkItem: DispatchWorkItem?
    private var presentedGuideThisLaunch = false
    // Navigation/content changes do not need display-rate AX tree scans. Live
    // scrolling has its own display-link path below.
    private let refreshInterval: TimeInterval = 1.0 / 8.0
    private let navigationSettleDelay: TimeInterval = 0.016
    private let scrollSettleDelay: CFTimeInterval = 0.085
    private let fileSizePreferenceKey = "fileSizeEnabled"
    private let resolutionPreferenceKey = "fileResolutionEnabled"
    private let folderCountsPreferenceKey = "folderCountLayerEnabled"
    private let completedGuideKey = "didCompleteGettingStarted"

    // MARK: — NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissionController.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateStatusBar()
                self.contextMonitor.refresh()
                if status == .granted,
                   !UserDefaults.standard.bool(forKey: self.completedGuideKey) {
                    self.showGettingStarted()
                    self.presentedGuideThisLaunch = true
                }
            }
        }

        restoreFeaturePreferences()

        // Setup menu bar
        setupStatusBar()
        _ = permissionController.checkPermission()
        presentInitialGuideWhenReady()

        // Setup context monitor
        contextMonitor.onContextChange = { [weak self] context in
            self?.performOnMain { [weak self] in
                self?.handleFinderContext(context)
            }
        }

        contextMonitor.onStateChange = { [weak self] state in
            self?.performOnMain { [weak self] in
                self?.handleFinderState(state)
            }
        }

        // Set up periodic refresh when overlay is enabled
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true,
            block: { [weak self] _ in
                self?.performRefresh()
            }
        )
        refreshTimer?.tolerance = 0.003

        setupFinderScrollTracking()

        contextMonitor.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Menu-bar app, no windows
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        showGettingStartedIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        if let scrollEventMonitor {
            NSEvent.removeMonitor(scrollEventMonitor)
        }
        scrollDisplayLink?.invalidate()
        navigationRetryWorkItem?.cancel()
        overlayController.hide()
    }

    // MARK: — Menu bar setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItem.button?.image = makeHaloStatusImage()

        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false
        statusMenu.addItem(makeMetadataToggleRow())
        statusMenu.addItem(makeFolderToggleRow())

        permissionMenuItem = statusMenu.addItem(
            withTitle: "Checking permissions…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionMenuItem.target = self

        statusMenu.addItem(NSMenuItem.separator())

        let gettingStartedItem = statusMenu.addItem(
            withTitle: "Getting Started…",
            action: #selector(showGettingStarted),
            keyEquivalent: ""
        )
        gettingStartedItem.target = self

        quitMenuItem = statusMenu.addItem(
            withTitle: "Quit HaloLayer",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self

        statusItem.menu = statusMenu
        updateStatusBar()
    }

    private func makeMetadataToggleRow() -> NSMenuItem {
        let item = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 42))

        let title = NSTextField(labelWithString: "Metadata")
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.frame = NSRect(x: 14, y: 12, width: 82, height: 18)
        row.addSubview(title)

        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.font = NSFont.systemFont(ofSize: 12)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 100, y: 12, width: 30, height: 18)
        row.addSubview(sizeLabel)

        sizeSwitch = AlwaysBlueToggle(frame: NSRect(x: 134, y: 12, width: 32, height: 18))
        sizeSwitch.target = self
        sizeSwitch.action = #selector(toggleFileSize(_:))
        row.addSubview(sizeSwitch)

        let resolutionLabel = NSTextField(labelWithString: "Resolution")
        resolutionLabel.font = NSFont.systemFont(ofSize: 12)
        resolutionLabel.textColor = .secondaryLabelColor
        resolutionLabel.frame = NSRect(x: 181, y: 12, width: 64, height: 18)
        row.addSubview(resolutionLabel)

        resolutionSwitch = AlwaysBlueToggle(frame: NSRect(x: 274, y: 12, width: 32, height: 18))
        resolutionSwitch.target = self
        resolutionSwitch.action = #selector(toggleResolution(_:))
        row.addSubview(resolutionSwitch)

        item.view = row
        item.isEnabled = true
        return item
    }

    private func makeFolderToggleRow() -> NSMenuItem {
        let item = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 38))

        let title = NSTextField(labelWithString: "Folder badges")
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.sizeToFit()
        title.frame.origin = NSPoint(x: 14, y: 10)
        row.addSubview(title)

        folderCountSwitch = AlwaysBlueToggle(
            frame: NSRect(
                x: ceil(title.frame.maxX + 12),
                y: 10,
                width: 32,
                height: 18
            )
        )
        folderCountSwitch.target = self
        folderCountSwitch.action = #selector(toggleFolderCounts(_:))
        row.addSubview(folderCountSwitch)

        item.view = row
        item.isEnabled = true
        return item
    }

    private func updateStatusBar() {
        sizeSwitch?.isOn = isFileSizeEnabled
        resolutionSwitch?.isOn = isResolutionEnabled
        folderCountSwitch?.isOn = isFolderCountsEnabled
        sizeSwitch?.isEnabled = true
        resolutionSwitch?.isEnabled = true
        folderCountSwitch?.isEnabled = true

        let permMessage = permissionController.statusMessage()
        let permissionGranted = permissionController.checkPermission() == .granted
        permissionMenuItem.title = permissionGranted
            ? "Accessibility permission granted"
            : permMessage
        permissionMenuItem.state = permissionGranted ? .on : .off
        permissionMenuItem.isEnabled = !permissionGranted

        // Update status item button icon/text
        if let button = statusItem.button {
            button.image = makeHaloStatusImage()
            button.contentTintColor = nil
            button.toolTip = "HaloLayer — " + permMessage
        }
    }

    private func makeHaloStatusImage() -> NSImage? {
        guard let image = NSImage(named: "HaloLayerMenuIcon")?.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
    }

    // MARK: — Getting started

    private func showGettingStartedIfNeeded() {
        let defaults = UserDefaults.standard
        guard GettingStartedPresentationPolicy.shouldPresent(
            isCompleted: defaults.bool(forKey: completedGuideKey),
            presentedThisLaunch: presentedGuideThisLaunch
        ) else { return }
        showGettingStarted()
        presentedGuideThisLaunch = true
    }

    private func presentInitialGuideWhenReady() {
        DispatchQueue.main.async { [weak self] in
            self?.showGettingStartedIfNeeded()
        }

        // Gatekeeper can finish handing focus back a moment after launch.
        // Reassert the already-visible first-run window once, without ever
        // presenting the guide again on later launches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self,
                  self.presentedGuideThisLaunch,
                  self.gettingStartedController?.window?.isVisible == true else { return }
            self.bringGettingStartedToFront()
        }
    }

    private func bringGettingStartedToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        gettingStartedController?.window?.makeKeyAndOrderFront(nil)
        gettingStartedController?.window?.orderFrontRegardless()
    }

    @objc private func showGettingStarted() {
        if gettingStartedController == nil {
            gettingStartedController = GettingStartedWindowController(
                permissionController: permissionController,
                onCompletion: { [weak self] in
                    guard let self else { return }
                    self.updateStatusBar()
                    self.refreshForLayerChange()
                }
            )
        }
        gettingStartedController?.showWindow(nil)
        gettingStartedController?.window?.center()
        bringGettingStartedToFront()
    }

    // MARK: — Menu actions

    @objc private func toggleFileSize(_ sender: NSControl) {
        guard let sender = sender as? AlwaysBlueToggle else { return }
        isFileSizeEnabled = sender.isOn
        UserDefaults.standard.set(isFileSizeEnabled, forKey: fileSizePreferenceKey)
        updateStatusBar()
        refreshForLayerChange()
    }

    @objc private func toggleResolution(_ sender: NSControl) {
        guard let sender = sender as? AlwaysBlueToggle else { return }
        isResolutionEnabled = sender.isOn
        UserDefaults.standard.set(isResolutionEnabled, forKey: resolutionPreferenceKey)
        updateStatusBar()
        refreshForLayerChange()
    }

    @objc private func toggleFolderCounts(_ sender: NSControl) {
        guard let sender = sender as? AlwaysBlueToggle else { return }
        isFolderCountsEnabled = sender.isOn
        UserDefaults.standard.set(
            isFolderCountsEnabled,
            forKey: folderCountsPreferenceKey
        )
        updateStatusBar()
        refreshForLayerChange()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionController.openAccessibilitySettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: — Finder context handling

    private func handleFinderContext(_ context: FinderContext?) {
        guard let context = context, metadataLayerEnabled || isFolderCountsEnabled else {
            if overlayController.isVisible {
                overlayController.hide()
            }
            return
        }

        // A folder-change callback arrives before Finder has necessarily
        // replaced its icon-view Accessibility children. The state handler
        // has already hidden the old overlay and scheduled a frame-boundary
        // retry, so never draw from this transient hierarchy.
        guard contextMonitor.state != .folderChanged else { return }

        renderOverlay(for: context)
    }

    private func renderOverlay(for context: FinderContext) {

        // Check if Icon View
        if !contextMonitor.isIconView() {
            overlayController.hide()
            return
        }

        // Map visible items
        let labels = metadataLayerEnabled ? itemMapper.mapVisibleItems(
            folderURL: context.folderURL, windowID: context.windowID,
            windowFrame: context.windowFrame,
            showSize: isFileSizeEnabled,
            showResolution: isResolutionEnabled,
            permissionController: permissionController
        ) : []
        let badges = isFolderCountsEnabled ? itemMapper.mapVisibleFolderBadges(
            folderURL: context.folderURL, windowID: context.windowID,
            windowFrame: context.windowFrame,
            permissionController: permissionController
        ) : []

        // Only update if labels changed (non-empty from mapper = new data)
        if !labels.isEmpty || !badges.isEmpty {
            overlayController.update(
                over: context.windowFrame,
                labels: labels,
                folderBadges: badges
            )
        } else {
            overlayController.hide()
        }
    }

    private func handleFinderState(_ state: FinderContextState) {
        switch state {
        case .idle:
            navigationRetryWorkItem?.cancel()
            overlayController.hide()
        case .monitoring:
            // Labels will be updated by the refresh timer
            break
        case .folderChanged:
            // Never leave the previous folder's geometry on screen while the
            // new Finder hierarchy is still settling.
            overlayController.hide()
            scheduleNavigationRefresh()
        case .viewUnsupported:
            navigationRetryWorkItem?.cancel()
            overlayController.hide()
        }
    }

    private func scheduleNavigationRefresh() {
        navigationRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.contextMonitor.refresh()
            guard self.contextMonitor.state == .monitoring,
                  let context = self.contextMonitor.currentContext else { return }
            self.renderOverlay(for: context)
        }
        navigationRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + navigationSettleDelay,
            execute: workItem
        )
    }

    // MARK: — Refresh cycle

    private func performRefresh() {
        guard metadataLayerEnabled || isFolderCountsEnabled else {
            if overlayController.isVisible {
                overlayController.hide()
            }
            return
        }

        // During a trackpad/wheel gesture the cached views follow the event
        // deltas at display cadence. Re-running AppleScript and traversing the
        // Finder AX hierarchy here would reintroduce the visible trailing lag.
        guard !isTrackingFinderScroll else { return }

        // Finder navigation does not activate a new application, and workspace
        // activation notifications can occasionally be coalesced. Refresh the
        // front window context as part of the existing polling cycle.
        contextMonitor.refresh()

        // handleFinderState(.folderChanged) hid the stale geometry
        // synchronously and scheduled a retry after Finder's next frame.
        guard contextMonitor.state != .folderChanged else { return }

        guard contextMonitor.state != .idle,
              let context = contextMonitor.currentContext else {
            if overlayController.isVisible {
                overlayController.hide()
            }
            return
        }

        renderOverlay(for: context)
    }

    // MARK: — Display-synchronous Finder scrolling

    private func setupFinderScrollTracking() {
        scrollEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .scrollWheel
        ) { [weak self] event in
            let delta = FinderScrollMotion.contentTranslation(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                hasPreciseDeltas: event.hasPreciseScrollingDeltas
            )
            let pointerLocation = NSEvent.mouseLocation

            DispatchQueue.main.async { [weak self] in
                self?.handleFinderScrollEvent(
                    translation: delta,
                    pointerLocation: pointerLocation
                )
            }
        }

        guard let screen = NSScreen.main else { return }
        let displayLink = screen.displayLink(
            target: self,
            selector: #selector(handleScrollDisplayLink(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        displayLink.isPaused = true
        scrollDisplayLink = displayLink
    }

    private func handleFinderScrollEvent(
        translation: CGVector,
        pointerLocation: CGPoint
    ) {
        guard translation.dx != 0 || translation.dy != 0,
              contextMonitor.isFinderActive,
              overlayController.contains(screenPoint: pointerLocation) else { return }

        pendingScrollTranslation.dx += translation.dx
        pendingScrollTranslation.dy += translation.dy
        lastScrollEventTime = CACurrentMediaTime()
        isTrackingFinderScroll = true
        scrollDisplayLink?.isPaused = false
    }

    @objc private func handleScrollDisplayLink(_ displayLink: CADisplayLink) {
        dispatchPrecondition(condition: .onQueue(.main))

        let translation = pendingScrollTranslation
        pendingScrollTranslation = .zero
        overlayController.translateCachedContent(by: translation)

        guard isTrackingFinderScroll,
              CACurrentMediaTime() - lastScrollEventTime >= scrollSettleDelay else {
            return
        }

        // Momentum has settled. Replace the translated cache with Finder's
        // authoritative current frames before returning to normal polling.
        isTrackingFinderScroll = false
        displayLink.isPaused = true
        contextMonitor.refresh()
        guard contextMonitor.state == .monitoring,
              let context = contextMonitor.currentContext else {
            overlayController.hide()
            return
        }
        renderOverlay(for: context)
    }

    // MARK: — Layer preferences

    private func restoreFeaturePreferences() {
        let defaults = UserDefaults.standard
        isFileSizeEnabled = defaults.object(forKey: fileSizePreferenceKey) == nil
            ? true : defaults.bool(forKey: fileSizePreferenceKey)
        isResolutionEnabled = defaults.object(forKey: resolutionPreferenceKey) == nil
            ? true : defaults.bool(forKey: resolutionPreferenceKey)

        if defaults.object(forKey: folderCountsPreferenceKey) == nil {
            isFolderCountsEnabled = true
        } else {
            isFolderCountsEnabled = defaults.bool(forKey: folderCountsPreferenceKey)
        }
    }

    private var metadataLayerEnabled: Bool {
        isFileSizeEnabled || isResolutionEnabled
    }

    private func refreshForLayerChange() {
        if metadataLayerEnabled || isFolderCountsEnabled {
            contextMonitor.refresh()
            performRefresh()
        } else {
            overlayController.hide()
        }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

}

private final class AlwaysBlueToggle: NSControl {
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()

    var isOn = false {
        didSet {
            updateAppearance()
            setAccessibilityValue(isOn ? 1 : 0)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        trackLayer.cornerRadius = frameRect.height / 2
        layer?.addSublayer(trackLayer)

        knobLayer.backgroundColor = NSColor.white.cgColor
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.18
        knobLayer.shadowRadius = 1
        knobLayer.shadowOffset = NSSize(width: 0, height: -0.5)
        layer?.addSublayer(knobLayer)

        setAccessibilityRole(.checkBox)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        isOn.toggle()
        sendAction(action, to: target)
        return true
    }

    private func updateAppearance() {
        let trackFrame = bounds.insetBy(dx: 0, dy: 1)
        let knobSize = trackFrame.height - 4
        let knobX = isOn
            ? trackFrame.maxX - knobSize - 2
            : trackFrame.minX + 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = trackFrame
        trackLayer.cornerRadius = trackFrame.height / 2
        trackLayer.backgroundColor = (
            isOn ? NSColor.systemBlue : NSColor.systemGray
        ).cgColor
        knobLayer.frame = NSRect(
            x: knobX,
            y: trackFrame.minY + 2,
            width: knobSize,
            height: knobSize
        )
        knobLayer.cornerRadius = knobSize / 2
        CATransaction.commit()
    }
}
