import AppKit

final class GettingStartedWindowController: NSWindowController {
    private let permissionController: AccessibilityPermissionController
    private let permissionStatus = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)

    init(permissionController: AccessibilityPermissionController) {
        self.permissionController = permissionController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to HaloLayer"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)
        buildInterface()
        refreshPermissionStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshPermissionStatus()
        super.showWindow(sender)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let logo = NSImageView()
        logo.image = NSImage(named: "HaloLayerLogo") ?? NSApplication.shared.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "HaloLayer is ready")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: "Three quick steps, then the details you need will appear directly in Finder Icon View.")
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let header = NSStackView(views: [logo, title, subtitle])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 10

        permissionStatus.font = .systemFont(ofSize: 12, weight: .medium)
        permissionStatus.textColor = .secondaryLabelColor
        permissionButton.target = self
        permissionButton.action = #selector(openAccessibilitySettings)
        permissionButton.bezelStyle = .rounded

        let permissionActions = NSStackView(views: [permissionStatus, permissionButton])
        permissionActions.orientation = .horizontal
        permissionActions.alignment = .centerY
        permissionActions.spacing = 12

        let steps = NSStackView(views: [
            makeStep(
                number: "1",
                title: "Allow Accessibility",
                detail: "HaloLayer uses this permission only to locate visible Finder icons.",
                accessory: permissionActions
            ),
            makeStep(
                number: "2",
                title: "Allow Finder access",
                detail: "Choose Allow if macOS asks. This lets HaloLayer identify the open folder and view mode."
            ),
            makeStep(
                number: "3",
                title: "Open Finder in Icon View",
                detail: "Use the halo in the menu bar to turn file size, resolution, and folder badges on or off."
            )
        ])
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 12
        steps.distribution = .fillEqually

        let doneButton = NSButton(title: "Start using HaloLayer", target: self, action: #selector(finish))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .large

        let help = NSTextField(labelWithString: "You can reopen this guide anytime from the halo menu.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.alignment = .center

        let root = NSStackView(views: [header, steps, doneButton, help])
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 22
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 76),
            logo.heightAnchor.constraint(equalToConstant: 76),
            subtitle.widthAnchor.constraint(equalToConstant: 440),
            steps.widthAnchor.constraint(equalToConstant: 520),
            doneButton.widthAnchor.constraint(equalToConstant: 220),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
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
        badge.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        badge.alignment = .center
        badge.textColor = .labelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 16
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.separatorColor.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false

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
        text.spacing = 4

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
            row.widthAnchor.constraint(equalToConstant: 520)
        ])
        return row
    }

    private func refreshPermissionStatus() {
        let granted = permissionController.checkPermission() == .granted
        permissionStatus.stringValue = granted ? "Granted" : "Not granted yet"
        permissionStatus.textColor = granted ? .systemGreen : .secondaryLabelColor
        permissionButton.isHidden = granted
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionController.openAccessibilitySettings()
    }

    @objc private func finish() {
        UserDefaults.standard.set(true, forKey: "didCompleteGettingStarted")
        window?.close()
    }
}
