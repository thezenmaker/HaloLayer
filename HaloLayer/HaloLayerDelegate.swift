// HaloLayerDelegate.swift
// AppState + MenuBar status item — the main orchestration layer.

import Cocoa
import Foundation

final class HaloLayerDelegate: NSObject, NSApplicationDelegate {

    // MARK: — Core components
    private let permissionController = AccessibilityPermissionController()
    private let contextMonitor = FinderContextMonitor()
    private let itemMapper = FinderItemMapper()
    private let overlayController = OverlayWindowController()

    // MARK: — Menu bar
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var sizeSwitch: NSSwitch!
    private var resolutionSwitch: NSSwitch!
    private var folderCountSwitch: NSSwitch!
    private var quitMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    private var gettingStartedController: GettingStartedWindowController?

    // MARK: — State
    private var isFileSizeEnabled: Bool = true
    private var isResolutionEnabled: Bool = true
    private var isFolderCountsEnabled: Bool = false
    private var refreshTimer: Timer?
    private var navigationRetryWorkItem: DispatchWorkItem?
    private let refreshInterval: TimeInterval = 1.0 / 30.0
    private let navigationSettleDelay: TimeInterval = 0.016
    private let fileSizePreferenceKey = "fileSizeEnabled"
    private let resolutionPreferenceKey = "fileResolutionEnabled"
    private let folderCountsPreferenceKey = "folderCountLayerEnabled"
    private let completedGuideKey = "didCompleteGettingStarted"
    private let presentedGuideKey = "didPresentGettingStarted"
    private let legacyCompletedGuideVersionKey = "didCompleteGettingStartedVersion"

    // MARK: — NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissionController.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusBar()
                self?.contextMonitor.refresh()
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

        sizeSwitch = NSSwitch(frame: NSRect(x: 130, y: 9, width: 40, height: 24))
        sizeSwitch.controlSize = .mini
        sizeSwitch.target = self
        sizeSwitch.action = #selector(toggleFileSize(_:))
        row.addSubview(sizeSwitch)

        let resolutionLabel = NSTextField(labelWithString: "Resolution")
        resolutionLabel.font = NSFont.systemFont(ofSize: 12)
        resolutionLabel.textColor = .secondaryLabelColor
        resolutionLabel.frame = NSRect(x: 181, y: 12, width: 64, height: 18)
        row.addSubview(resolutionLabel)

        resolutionSwitch = NSSwitch(frame: NSRect(x: 270, y: 9, width: 40, height: 24))
        resolutionSwitch.controlSize = .mini
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
        title.frame = NSRect(x: 14, y: 10, width: 180, height: 18)
        row.addSubview(title)

        folderCountSwitch = NSSwitch(frame: NSRect(x: 270, y: 7, width: 40, height: 24))
        folderCountSwitch.controlSize = .mini
        folderCountSwitch.target = self
        folderCountSwitch.action = #selector(toggleFolderCounts(_:))
        row.addSubview(folderCountSwitch)

        item.view = row
        item.isEnabled = true
        return item
    }

    private func updateStatusBar() {
        sizeSwitch?.state = isFileSizeEnabled ? .on : .off
        resolutionSwitch?.state = isResolutionEnabled ? .on : .off
        folderCountSwitch?.state = isFolderCountsEnabled ? .on : .off

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
        migrateLegacyGuideCompletionIfNeeded(defaults)
        guard !defaults.bool(forKey: presentedGuideKey) else {
            return
        }
        showGettingStarted()
        defaults.set(true, forKey: presentedGuideKey)
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
                  !UserDefaults.standard.bool(forKey: self.completedGuideKey),
                  self.gettingStartedController?.window?.isVisible == true else { return }
            self.bringGettingStartedToFront()
        }
    }

    private func migrateLegacyGuideCompletionIfNeeded(_ defaults: UserDefaults) {
        guard defaults.object(forKey: presentedGuideKey) == nil else { return }
        if defaults.bool(forKey: completedGuideKey)
            || defaults.integer(forKey: legacyCompletedGuideVersionKey) >= 2 {
            defaults.set(true, forKey: presentedGuideKey)
            defaults.set(true, forKey: completedGuideKey)
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
                    UserDefaults.standard.set(true, forKey: self.presentedGuideKey)
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

    @objc private func toggleFileSize(_ sender: NSSwitch) {
        isFileSizeEnabled = sender.state == .on
        UserDefaults.standard.set(isFileSizeEnabled, forKey: fileSizePreferenceKey)
        updateStatusBar()
        refreshForLayerChange()
    }

    @objc private func toggleResolution(_ sender: NSSwitch) {
        isResolutionEnabled = sender.state == .on
        UserDefaults.standard.set(isResolutionEnabled, forKey: resolutionPreferenceKey)
        updateStatusBar()
        refreshForLayerChange()
    }

    @objc private func toggleFolderCounts(_ sender: NSSwitch) {
        isFolderCountsEnabled = sender.state == .on
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
