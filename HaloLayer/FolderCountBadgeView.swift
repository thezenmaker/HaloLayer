import Cocoa

final class FolderCountBadgeView: NSView {
    var countText = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()

        let fontSize: CGFloat = countText.count > 3 ? 8 : 10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.windowBackgroundColor
        ]
        let textSize = countText.size(withAttributes: attributes)
        countText.draw(
            at: NSPoint(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2
            ),
            withAttributes: attributes
        )
    }

    override var acceptsFirstResponder: Bool { false }
}
