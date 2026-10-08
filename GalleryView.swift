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

    static var artworkTitleFont: NSFont { AppTypography.artworkTitle }

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

final class GalleryActionButton: NSButton {
    var prominent = false

    override var intrinsicContentSize: NSSize {
        let width = title.isEmpty ? 36 : ceil((title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width) + 28
        return NSSize(width: width, height: 36)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let pressed = cell?.isHighlighted == true
        let background: NSColor = prominent
            ? (dark ? NSColor(calibratedWhite: pressed ? 0.75 : 0.90, alpha: 1) : NSColor(calibratedWhite: pressed ? 0.25 : 0.10, alpha: 1))
            : NSColor.labelColor.withAlphaComponent(pressed ? 0.12 : 0.045)
        (isEnabled ? background : background.withAlphaComponent(background.alphaComponent * 0.35)).setFill()
        shape.fill()
        if !prominent {
            NSColor.labelColor.withAlphaComponent(isEnabled ? 0.10 : 0.04).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let foreground = (prominent ? (dark ? NSColor.black : .white) : .labelColor)
            .withAlphaComponent(isEnabled ? 1 : 0.35)
        if title.isEmpty {
            foreground.setFill()
            for offset in [-5.0, 0, 5.0] {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX + offset - 1.25, y: bounds.midY - 1.25, width: 2.5, height: 2.5)).fill()
            }
        } else {
            let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: foreground]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
        if window?.firstResponder === self {
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
            focus.lineWidth = 1
            focus.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
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

protocol ArtworkCarouselDelegate: AnyObject {
    func artworkCarousel(_ carousel: ArtworkCarouselView, didSelect artwork: Artwork)
    func artworkCarousel(_ carousel: ArtworkCarouselView, isMoving: Bool)
}

final class ArtworkCarouselView: NSView {
    weak var delegate: ArtworkCarouselDelegate?
    private let liveView: LiveView
    private var thumbnails: [Artwork: NSImage] = [:]
    private var selectedArtwork: Artwork
    private(set) var motion: CarouselMotion
    private var lastDragPoint: NSPoint?
    private var lastInputTime = 0.0
    private var dragDistance: CGFloat = 0
    private var scrolling = false
    private var keyboardFocus = false
    private var motionTimer: Timer?
    private var lastTick = 0.0
    private var wasMoving = false
    var usesAutomaticMotionClock = true
    var reduceMotionOverride: Bool?
    private var reduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    var selectionEnabled = true {
        didSet {
            if !selectionEnabled { cancelInteraction() }
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    init(resources: URL, liveView: LiveView, selected: Artwork) throws {
        self.liveView = liveView
        self.selectedArtwork = selected
        self.motion = CarouselMotion(index: selected.rawValue, count: Artwork.allCases.count)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for artwork in Artwork.allCases {
            let url = resources.appendingPathComponent("\(artwork.filename).jpg")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 900
                  ] as CFDictionary) else { throw failure(L10n.tr("error.thumbnail")) }
            let cropped = try Engine.crop(image, artwork: artwork)
            thumbnails[artwork] = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        }
        addSubview(liveView)
        liveView.wantsLayer = true
        liveView.layer?.cornerRadius = 4
        liveView.layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(L10n.tr("accessibility.carousel"))
        setAccessibilityHelp(L10n.tr("accessibility.carouselHelp"))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        motionTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func relocalize() {
        setAccessibilityLabel(L10n.tr("accessibility.carousel"))
        setAccessibilityHelp(L10n.tr("accessibility.carouselHelp"))
    }

    func setSelected(_ artwork: Artwork) {
        stopClock()
        selectedArtwork = artwork
        motion.reset(to: artwork.rawValue)
        lastDragPoint = nil
        scrolling = false
        liveView.revealAfterRendering()
        if wasMoving {
            wasMoving = false
            delegate?.artworkCarousel(self, isMoving: false)
        }
        setAccessibilityValue(artwork.title)
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        liveView.frame = cardRect(at: Double(selectedArtwork.rawValue))
    }

    private var cardSpacing: CGFloat {
        centerCardSize.width * (reduceMotion ? 1 : 0.94) + 24
    }

    private var centerCardSize: NSSize {
        let width = min(bounds.width * 0.92, 840, max(1, bounds.height - 26) * 1.62)
        return NSSize(width: width, height: width / 1.62)
    }

    var restingCardFrame: NSRect { cardRect(at: motion.position) }

    func thumbnail(for artwork: Artwork) -> NSImage? { thumbnails[artwork] }

    func select(_ artwork: Artwork) {
        guard selectionEnabled else { return }
        lastDragPoint = nil
        scrolling = false
        motion.settle(to: artwork.rawValue, reduceMotion: reduceMotion)
        startSettling()
    }

    private func cardRect(at index: Double) -> NSRect {
        let size = centerCardSize
        let distance = min(abs(index - motion.position), 1)
        let smoothDistance = distance * distance * (3 - 2 * distance)
        let scale = reduceMotion ? 1 : 1 - smoothDistance * 0.12
        let scaled = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - scaled.width / 2 + CGFloat(index - motion.position) * cardSpacing,
                      y: bounds.midY - scaled.height / 2,
                      width: scaled.width, height: scaled.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let indices = Artwork.allCases.indices.sorted {
            abs(Double($0) - motion.position) > abs(Double($1) - motion.position)
        }
        for index in indices {
            let artwork = Artwork.allCases[index]
            let rect = cardRect(at: Double(index))
            guard rect.intersects(bounds.insetBy(dx: -80, dy: -20)) else { continue }
            drawCardShadow(in: rect)
            if let image = thumbnails[artwork] {
                draw(image, in: rect)
            }
        }
        if keyboardFocus && window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: cardRect(at: Double(motion.target)).insetBy(dx: -4, dy: -4),
                xRadius: 7, yRadius: 7)
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    private func drawCardShadow(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ image: NSImage, in rect: NSRect) {
        var source = NSRect(origin: .zero, size: image.size)
        let imageAspect = image.size.width / image.size.height
        let rectAspect = rect.width / rect.height
        if imageAspect > rectAspect {
            source.size.width = image.size.height * rectAspect
            source.origin.x = (image.size.width - source.width) / 2
        } else {
            source.size.height = image.size.width / rectAspect
            source.origin.y = (image.size.height - source.height) / 2
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard selectionEnabled else { return }
        window?.makeFirstResponder(self)
        keyboardFocus = false
        stopClock()
        motion.beginDrag()
        lastDragPoint = convert(event.locationInWindow, from: nil)
        lastInputTime = event.timestamp
        dragDistance = 0
        synchronizePresentation()
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionEnabled else { return }
        guard let previous = lastDragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - previous.x
        dragDistance += abs(delta)
        motion.drag(by: -Double(delta / cardSpacing), elapsed: event.timestamp - lastInputTime)
        lastDragPoint = point
        lastInputTime = event.timestamp
        synchronizePresentation()
    }

    override func mouseUp(with event: NSEvent) {
        guard selectionEnabled, lastDragPoint != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if dragDistance < 4, let index = Artwork.allCases.indices.min(by: {
            abs(Double($0) - motion.position) < abs(Double($1) - motion.position)
        }).flatMap({ nearest in
            ([nearest] + Artwork.allCases.indices.filter { $0 != nearest }).first {
                cardRect(at: Double($0)).contains(point)
            }
        }) {
            motion.settle(to: index, reduceMotion: reduceMotion)
        } else {
            motion.release(projectVelocity: event.timestamp - lastInputTime < 0.1, reduceMotion: reduceMotion)
        }
        lastDragPoint = nil
        startSettling()
    }

    override func keyDown(with event: NSEvent) {
        guard selectionEnabled else { return }
        keyboardFocus = true
        switch event.specialKey {
        case .leftArrow:
            selectRelative(-1)
        case .rightArrow:
            selectRelative(1)
        default:
            super.keyDown(with: event)
        }
    }

    func selectRelative(_ delta: Int) {
        guard selectionEnabled else { return }
        lastDragPoint = nil
        scrolling = false
        motion.step(by: delta, reduceMotion: reduceMotion)
        startSettling()
    }

    override func scrollWheel(with event: NSEvent) {
        guard selectionEnabled else { return }
        // AppKit momentum events are ignored; the spring owns motion after finger-up.
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaX
        if !scrolling && abs(delta) <= abs(event.scrollingDeltaY) { return }
        keyboardFocus = false
        if !scrolling {
            stopClock()
            motion.beginDrag()
            lastInputTime = event.timestamp - 1.0 / 60
            scrolling = true
        }
        if delta != 0 {
            let points = event.hasPreciseScrollingDeltas ? delta : delta * 12
            motion.drag(by: -Double(points / cardSpacing), elapsed: event.timestamp - lastInputTime)
            lastInputTime = event.timestamp
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.phase.isEmpty {
            scrolling = false
            motion.release(projectVelocity: !event.phase.contains(.cancelled) && event.timestamp - lastInputTime < 0.1,
                reduceMotion: reduceMotion)
            startSettling()
        } else { synchronizePresentation() }
    }

    override func becomeFirstResponder() -> Bool {
        keyboardFocus = NSApp.currentEvent?.type != .leftMouseDown
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        keyboardFocus = false
        cancelInteraction()
        needsDisplay = true
        return true
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard selectionEnabled else { return false }
        selectRelative(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard selectionEnabled else { return false }
        selectRelative(-1)
        return true
    }

    func cancelInteraction() {
        lastDragPoint = nil
        scrolling = false
        if !selectionEnabled {
            setSelected(selectedArtwork)
            synchronizePresentation()
        } else if motion.phase == .dragging {
            motion.release(projectVelocity: false, reduceMotion: reduceMotion)
            startSettling()
        }
    }

    @objc private func motionPreferenceChanged() {
        if reduceMotion && motion.phase == .settling {
            motion.reset(to: motion.target)
            synchronizePresentation()
            stopClock()
        }
        needsDisplay = true
    }

    private func startSettling() {
        synchronizePresentation()
        guard motion.phase == .settling, usesAutomaticMotionClock, motionTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            advanceMotion(by: now - lastTick)
            lastTick = now
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func advanceMotion(by elapsed: Double) {
        motion.advance(by: elapsed)
        synchronizePresentation()
        if motion.phase == .idle { stopClock() }
    }

    private func stopClock() {
        motionTimer?.invalidate()
        motionTimer = nil
    }

    private func synchronizePresentation() {
        let moving = motion.phase != .idle
        if moving && !wasMoving { liveView.concealForTransition() }
        if !moving {
            let artwork = Artwork.allCases[motion.target]
            if artwork != selectedArtwork { delegate?.artworkCarousel(self, didSelect: artwork) }
        }
        if moving != wasMoving {
            wasMoving = moving
            delegate?.artworkCarousel(self, isMoving: moving)
            if !moving { liveView.revealAfterRendering() }
        }
        needsDisplay = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

final class ArtworkThumbnailRail: NSView {
    let buttons: [NSButton]
    var selectedIndex = 0 {
        didSet {
            for button in buttons { button.alphaValue = button.tag == selectedIndex ? 1 : 0.55 }
            needsDisplay = true
        }
    }

    init(carousel: ArtworkCarouselView, target: AnyObject, action: Selector) {
        buttons = Artwork.allCases.map { artwork in
            let button = NSButton(image: carousel.thumbnail(for: artwork) ?? NSImage(), target: target, action: action)
            button.tag = artwork.rawValue
            button.keyEquivalent = artwork.shortcutKey
            button.keyEquivalentModifierMask = artwork.shortcutUsesOption ? [.option, .command] : [.command]
            button.isBordered = false
            button.imageScaling = .scaleProportionallyUpOrDown
            button.setButtonType(.momentaryChange)
            button.toolTip = artwork.title
            button.setAccessibilityLabel(artwork.title)
            return button
        }
        super.init(frame: .zero)
        for button in buttons { addSubview(button) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let gap: CGFloat = 7
        let width = min(42, (bounds.width - gap * CGFloat(buttons.count - 1)) / CGFloat(buttons.count))
        let total = width * CGFloat(buttons.count) + gap * CGFloat(buttons.count - 1)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: (bounds.width - total) / 2 + CGFloat(index) * (width + gap),
                y: 7, width: width, height: 28)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard buttons.indices.contains(selectedIndex) else { return }
        let selected = buttons[selectedIndex].frame
        NSColor.labelColor.withAlphaComponent(0.65).setFill()
        NSRect(x: selected.minX + 4, y: 2, width: selected.width - 8, height: 1).fill()
    }

    func relocalize() {
        for button in buttons {
            let artwork = Artwork.allCases[button.tag]
            button.toolTip = artwork.title
            button.setAccessibilityLabel(artwork.title)
        }
    }
}

final class ExhibitionLayoutView: NSView {
    let carousel: ArtworkCarouselView
    let title: NSTextField
    let artist: NSTextField
    let status: NSTextField
    let primary: NSButton
    let secondary: NSButton
    let more: NSButton
    let brand: NSTextField
    let count: NSTextField
    let previous: NSButton
    let next: NSButton
    let thumbnails: ArtworkThumbnailRail
    var usesSidebar: Bool { bounds.width >= 1000 }

    init(carousel: ArtworkCarouselView, title: NSTextField, artist: NSTextField, status: NSTextField,
         primary: NSButton, secondary: NSButton, more: NSButton, brand: NSTextField, count: NSTextField,
         previous: NSButton, next: NSButton, thumbnails: ArtworkThumbnailRail) {
        self.carousel = carousel
        self.title = title
        self.artist = artist
        self.status = status
        self.primary = primary
        self.secondary = secondary
        self.more = more
        self.brand = brand
        self.count = count
        self.previous = previous
        self.next = next
        self.thumbnails = thumbnails
        super.init(frame: .zero)
        for view in [carousel, title, artist, status, primary, secondary, more, brand, count, previous, next, thumbnails] {
            addSubview(view)
        }
        carousel.wantsLayer = true
        carousel.layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        GalleryStyle.surface.setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    private func textHeight(_ label: NSTextField, width: CGFloat) -> CGFloat {
        ceil((label.stringValue as NSString).boundingRect(
            with: NSSize(width: max(1, width - 4), height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font!]).height) + 4
    }

    override func layout() {
        super.layout()
        let margin: CGFloat = 28
        let available = bounds.width - margin * 2
        brand.frame = NSRect(x: margin, y: bounds.height - 43, width: available * 0.6, height: 28)
        count.frame = NSRect(x: bounds.width - margin - 180, y: bounds.height - 39, width: 180, height: 20)
        count.alignment = .right
        let arrowWidth: CGFloat = 28
        let buttonGap: CGFloat = 10
        let secondaryWidth = ceil(secondary.intrinsicContentSize.width)
        let moreWidth = max(26, ceil(more.intrinsicContentSize.width))
        let primaryWidth = ceil(primary.intrinsicContentSize.width)
        let actionWidth = secondaryWidth + moreWidth + primaryWidth + buttonGap * 2
        let actionHeight = max(28, ceil([secondary, more, primary].map { $0.intrinsicContentSize.height }.max() ?? 28))
        let statusHeight: CGFloat = 36
        func placeActions(x: CGFloat, y: CGFloat) {
            secondary.frame = NSRect(x: x, y: y, width: secondaryWidth, height: actionHeight)
            more.frame = NSRect(x: secondary.frame.maxX + buttonGap, y: y, width: moreWidth, height: actionHeight)
            primary.frame = NSRect(x: more.frame.maxX + buttonGap, y: y, width: primaryWidth, height: actionHeight)
        }
        if usesSidebar {
            let infoWidth = max(actionWidth, min(280, max(238, available * 0.245)))
            let gap: CGFloat = 36
            let stageWidth = available - infoWidth - gap
            carousel.frame = NSRect(x: margin + arrowWidth, y: 150,
                width: stageWidth - 2 * arrowWidth, height: max(280, bounds.height - 210))
            carousel.needsLayout = true
            carousel.layoutSubtreeIfNeeded()
            let painting = carousel.convert(carousel.restingCardFrame, to: self)
            let infoX = margin + stageWidth + gap
            let titleHeight = textHeight(title, width: infoWidth)
            let artistHeight = textHeight(artist, width: infoWidth)
            artist.frame = NSRect(x: infoX, y: painting.minY, width: infoWidth, height: artistHeight)
            title.frame = NSRect(x: infoX, y: artist.frame.maxY + 8, width: infoWidth, height: titleHeight)
            placeActions(x: infoX, y: artist.frame.minY - 24 - actionHeight)
            status.frame = NSRect(x: infoX, y: primary.frame.minY - statusHeight - 8,
                width: infoWidth, height: statusHeight)
            thumbnails.frame = NSRect(x: margin + arrowWidth, y: painting.minY - 58,
                width: stageWidth - 2 * arrowWidth, height: 36)
            previous.frame = NSRect(x: margin - 2, y: painting.midY - 16, width: arrowWidth, height: 32)
            next.frame = NSRect(x: margin + stageWidth - arrowWidth + 2, y: painting.midY - 16, width: arrowWidth, height: 32)
        } else {
            let titleHeight = textHeight(title, width: available)
            let artistHeight = textHeight(artist, width: available)
            status.frame = NSRect(x: margin, y: 24, width: available, height: statusHeight)
            let actionY = status.frame.maxY + 8
            placeActions(x: margin, y: actionY)
            artist.frame = NSRect(x: margin, y: primary.frame.maxY + 24, width: available, height: artistHeight)
            title.frame = NSRect(x: margin, y: artist.frame.maxY + 8, width: available, height: titleHeight)
            thumbnails.frame = NSRect(x: margin + arrowWidth, y: title.frame.maxY + 16,
                width: available - 2 * arrowWidth, height: 36)
            let stageY = thumbnails.frame.maxY + 12
            carousel.frame = NSRect(x: margin + arrowWidth, y: stageY,
                width: available - 2 * arrowWidth, height: max(180, bounds.height - 60 - stageY))
            carousel.needsLayout = true
            carousel.layoutSubtreeIfNeeded()
            let painting = carousel.convert(carousel.restingCardFrame, to: self)
            previous.frame = NSRect(x: margin - 2, y: painting.midY - 16, width: arrowWidth, height: 32)
            next.frame = NSRect(x: bounds.width - margin - arrowWidth + 2, y: painting.midY - 16, width: arrowWidth, height: 32)
        }
        thumbnails.needsLayout = true
        thumbnails.layoutSubtreeIfNeeded()
    }
}
