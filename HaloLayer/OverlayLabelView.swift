// OverlayLabelView.swift
// Renders a single file-size label beneath a Finder item.

import Cocoa
import Foundation

final class OverlayLabelView: NSView {
    /// Adjust this value to change metadata character spacing.
    /// Examples: `0` = system default, `0.3` = looser, `-0.2` = tighter.
    static let metadataLetterSpacing: CGFloat = -0.5

    var sizeText: String = "" {
        didSet { updateText() }
    }
    var detailText: String = "" {
        didSet { updateText() }
    }
    var registeredLabel: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
    }

    func attach(to window: NSWindow) {
        window.contentView?.addSubview(self, positioned: .below, relativeTo: nil)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let displayText: String
        if !sizeText.isEmpty && !detailText.isEmpty {
            displayText = "\(sizeText) · \(detailText)"
        } else {
            displayText = sizeText.isEmpty ? detailText : sizeText
        }
        var fontSize: CGFloat = 11
        var attributes = textAttributes(fontSize: fontSize)
        var textSize = displayText.size(withAttributes: attributes)
        let availableWidth = max(0, bounds.width - 4)
        while textSize.width > availableWidth && fontSize > 8 {
            fontSize -= 0.5
            attributes = textAttributes(fontSize: fontSize)
            textSize = displayText.size(withAttributes: attributes)
        }
        // Draw from the measured glyph width, not a text-field alignment
        // rectangle, so every length is mathematically centered on the icon.
        displayText.draw(
            at: NSPoint(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2
            ),
            withAttributes: attributes
        )
    }

    private func textAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: Self.metadataLetterSpacing
        ]
    }

    override func mouseDown(with event: NSEvent) {
        // Click-through: ignore all mouse events
    }

    override func rightMouseDown(with event: NSEvent) {
        // Ignore context menu triggers
    }

    private func updateText() {
        needsDisplay = true
    }

    // Override to prevent focus / activation
    override var acceptsFirstResponder: Bool { false }
}
