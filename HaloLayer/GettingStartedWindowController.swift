import AppKit

final class GettingStartedWindowController: NSWindowController, NSWindowDelegate {
    private let permissionController: AccessibilityPermissionController
    private let permissionBadge = NSTextField(labelWithString: "1")
    private let permissionStatus = NSTextField(labelWithString: "Checking…")
    private let permissionButton = NSButton(title: "Allow Accessibility", target: nil, action: nil)
    private let finderButton = NSButton(title: "Open Finder", target: nil, action: nil)
    private let doneButton = NSButton(title: "Open Finder and Finish", target: nil, action: nil)
    private var permissionPollTimer: Timer?

    private let didRequestPermissionKey = "didRequestAccessibilityPermission"

    init(permissionController: AccessibilityPermissionController) {
        self.permissionController = permissionController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set up HaloLayer"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)
        window.delegate = self
        buildInterface()
        refreshPermissionStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshPermissionStatus()
        startPermissionPolling()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        stopPermissionPolling()
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let logo = NSImageView()
        logo.image = NSImage(named: "HaloLayerLogo") ?? NSApplication.shared.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Let’s make Finder more useful")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: "HaloLayer needs one macOS permission. We’ll guide you through it, then open Finder for you.")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let header = NSStackView(views: [logo, title, subtitle])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 10

        let privacyIcon = NSImageView(image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) ?? NSImage())
        privacyIcon.contentTintColor = .secondaryLabelColor
        privacyIcon.translatesAutoresizingMaskIntoConstraints = false

        let privacyText = NSTextField(wrappingLabelWithString: "Your files stay on this Mac. HaloLayer does not send file names, folder paths, contents, or usage data anywhere.")
        privacyText.font = .systemFont(ofSize: 12, weight: .medium)
        privacyText.textColor = .secondaryLabelColor
        privacyText.maximumNumberOfLines = 2

        let privacyNotice = NSStackView(views: [privacyIcon, privacyText])
        privacyNotice.orientation = .horizontal
        privacyNotice.alignment = .centerY
        privacyNotice.spacing = 12
        privacyNotice.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        privacyNotice.wantsLayer = true
        privacyNotice.layer?.cornerRadius = 10
        privacyNotice.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        styleStepBadge(permissionBadge)
        permissionStatus.font = .systemFont(ofSize: 12, weight: .medium)
        permissionStatus.textColor = .secondaryLabelColor
        permissionButton.target = self
        permissionButton.action = #selector(handleAccessibilityPermission)
        permissionButton.bezelStyle = .rounded

        let permissionActions = NSStackView(views: [permissionStatus, permissionButton])
        permissionActions.orientation = .horizontal
        permissionActions.alignment = .centerY
        permissionActions.spacing = 12

        finderButton.target = self
        finderButton.action = #selector(openFinder)
        finderButton.bezelStyle = .rounded

        let steps = NSStackView(views: [
            makeStep(
                badge: permissionBadge,
                title: "Allow Accessibility",
                detail: "This lets HaloLayer locate visible Finder icons so metadata appears in the right place.",
                accessory: permissionActions
            ),
            makeStep(
                number: "2",
                title: "Open Finder",
                detail: "If macOS asks for Finder access, choose Allow. Switch Finder to Icon View to see HaloLayer.",
                accessory: finderButton
            ),
            makeStep(
                number: "3",
                title: "Choose what you see",
                detail: "Click the halo in the menu bar to toggle file size, resolution, and folder badges independently."
            )
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 12
        steps.distribution = .fillEqually

        doneButton.target = self
        doneButton.action = #selector(finish)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .large

        let laterButton = NSButton(title: "Set Up Later", target: self, action: #selector(setUpLater))
        laterButton.bezelStyle = .rounded

        let finalActions = NSStackView(views: [laterButton, doneButton])
        finalActions.orientation = .horizontal
        finalActions.alignment = .centerY
        finalActions.spacing = 14

        let help = NSTextField(labelWithString: "You can reopen this guide anytime from the halo menu.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.alignment = .center

        let root = NSStackView(views: [header, privacyNotice, steps, finalActions, help])
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 68),
            logo.heightAnchor.constraint(equalToConstant: 68),
            subtitle.widthAnchor.constraint(equalToConstant: 470),
            privacyIcon.widthAnchor.constraint(equalToConstant: 24),
            privacyIcon.heightAnchor.constraint(equalToConstant: 24),
            privacyNotice.widthAnchor.constraint(equalToConstant: 550),
            steps.widthAnchor.constraint(equalToConstant: 550),
            doneButton.widthAnchor.constraint(equalToConstant: 210),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
            root.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            root.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            root.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    private func makeStep(
        number: String,
        title: String,
        detail: String,
        accessory: NSView? = nil
    ) -> NSView {
        let badge = NSTextField(labelWithString: number)
        styleStepBadge(badge)
        return makeStep(badge: badge, title: title, detail: detail, accessory: accessory)
    }

    private func makeStep(
        badge: NSTextField,
        title: String,
        detail: String,
        accessory: NSView? = nil
    ) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: detail)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 2

        var textViews: [NSView] = [heading, body]
        if let accessory { textViews.append(accessory) }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5

        let row = NSStackView(views: [badge, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        row.wantsLayer = true
        row.layer?.cornerRadius = 12
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 32),
            badge.heightAnchor.constraint(equalToConstant: 32),
            row.widthAnchor.constraint(equalToConstant: 550)
        ])
        return row
    }

    private func styleStepBadge(_ badge: NSTextField) {
        badge.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        badge.alignment = .center
        badge.textColor = .labelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 16
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.separatorColor.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
        permissionPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionStatus() {
        let granted = permissionController.checkPermission() == .granted
        permissionStatus.stringValue = granted ? "Granted" : "Required"
        permissionStatus.textColor = granted ? .systemGreen : .secondaryLabelColor
        permissionBadge.stringValue = granted ? "✓" : "1"
        permissionBadge.textColor = granted ? .systemGreen : .labelColor
        permissionBadge.layer?.borderColor = (granted ? NSColor.systemGreen : NSColor.separatorColor).cgColor
        permissionButton.isHidden = granted
        finderButton.isEnabled = granted
        doneButton.isEnabled = granted

        if !granted {
            let hasRequested = UserDefaults.standard.bool(forKey: didRequestPermissionKey)
            permissionButton.title = hasRequested ? "Open System Settings" : "Allow Accessibility"
        }
    }

    @objc private func handleAccessibilityPermission() {
        guard permissionController.checkPermission() != .granted else { return }

        if UserDefaults.standard.bool(forKey: didRequestPermissionKey) {
            AccessibilityPermissionController.openAccessibilitySettings()
        } else {
            UserDefaults.standard.set(true, forKey: didRequestPermissionKey)
            permissionController.requestPermission()
        }
        refreshPermissionStatus()
    }

    @objc private func openFinder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    @objc private func finish() {
        guard permissionController.checkPermission() == .granted else { return }
        UserDefaults.standard.set(true, forKey: "didCompleteGettingStarted")
        openFinder()
        window?.close()
    }

    @objc private func setUpLater() {
        window?.close()
    }
}
