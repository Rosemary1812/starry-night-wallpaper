import AppKit
import ImageIO

enum GalleryStyle {
    static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.90, alpha: 1)
            : NSColor(calibratedWhite: 0.07, alpha: 1)
    }
    static let surface = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.14, alpha: 1)
            : NSColor(calibratedWhite: 0.97, alpha: 1)
    }
    static let canvas = NSColor(calibratedWhite: 0.12, alpha: 1)
    static let primaryAction = NSColor(calibratedWhite: 0.07, alpha: 1)

    static func text(_ string: String, size: CGFloat = 14, color: NSColor = .labelColor) -> NSTextField {
        let text = NSTextField(wrappingLabelWithString: string)
        text.font = .systemFont(ofSize: size)
        text.textColor = color
        text.setContentCompressionResistancePriority(.required, for: .vertical)
        return text
    }

    static func column(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }
}

final class GallerySurface: NSView {
    let color: NSColor
    let radius: CGFloat
    init(color: NSColor, radius: CGFloat = 0) {
        self.color = color
        self.radius = radius
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

final class ArtworkCard: NSButton {
    let artwork: Artwork
    let thumbnail: NSImage
    override var isFlipped: Bool { true }
    init(artwork: Artwork, resources: URL, target: AnyObject, action: Selector) throws {
        self.artwork = artwork
        let url = resources.appendingPathComponent("\(artwork.filename).jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480
              ] as CFDictionary) else { throw failure("无法生成画作缩略图。") }
        let cropped = try Engine.crop(image, artwork: artwork)
        thumbnail = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = artwork.title
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .none
        keyEquivalent = artwork.shortcutKey
        keyEquivalentModifierMask = artwork.shortcutUsesOption ? [.option, .command] : [.command]
        toolTip = "\(artwork.title) · \(artwork.shortcutLabel)"
        setAccessibilityLabel(artwork.title)
        setAccessibilityHelp("选择画作并预览动效")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 156),
            heightAnchor.constraint(equalToConstant: 128)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        if selected || isHighlighted {
            GalleryStyle.accent.withAlphaComponent(selected ? 0.09 : 0.05).setFill()
            outline.fill()
        }
        if selected || window?.firstResponder === self {
            GalleryStyle.accent.withAlphaComponent(isEnabled ? 1 : 0.4).setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
        }
        let rect = NSRect(x: 8, y: 8, width: bounds.width - 16, height: 70)
        let imageAspect = thumbnail.size.width / thumbnail.size.height
        var source = NSRect(origin: .zero, size: thumbnail.size)
        if imageAspect > rect.width / rect.height {
            source.size.width = thumbnail.size.height * rect.width / rect.height
            source.origin.x = (thumbnail.size.width - source.width) / 2
        } else {
            source.size.height = thumbnail.size.width * rect.height / rect.width
            source.origin.y = (thumbnail.size.height - source.height) / 2
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).addClip()
        thumbnail.draw(in: rect, from: source, operation: .sourceOver,
            fraction: isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let name = artwork.shortName as NSString
        name.draw(in: NSRect(x: 9, y: 84, width: bounds.width - 18, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular),
            .foregroundColor: NSColor.labelColor
        ])
        (artwork.artist as NSString).draw(in: NSRect(x: 9, y: 105, width: bounds.width - 18, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
}
