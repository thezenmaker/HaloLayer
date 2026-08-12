import Cocoa

final class FolderCountBadgeView: NSView {
    var countText = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let badgePath = NSBezierPath(
        ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)
    )

    // Fully opaque, lighter gray
    NSColor.systemGray.setFill()
    badgePath.fill()

    // White border
    NSColor.white.setStroke()
    badgePath.lineWidth = 2
    badgePath.stroke()

    let fontSize: CGFloat = countText.count > 3 ? 8 : 10
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
        .foregroundColor: NSColor.white
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
