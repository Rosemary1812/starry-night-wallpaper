import AppKit
import CoreText

extension AppDelegate {
    func writeViewSnapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw failure("View snapshot failed")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw failure("PNG encoding failed")
        }
        try data.write(to: url)
    }

    func verifyGallery() {
        guard let output = verificationOutput else { return }
        AppLanguage.verificationLanguage = AppLanguage.current
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fputs("\(error)\n", stderr); exit(1) }
        let savedLanguage = AppLanguage.current
        var scenes: [(String, AppLanguage, Artwork, NSSize, NSAppearance.Name)] = [
            ("StarryNight-zh-hans-wide-light", .zhHans, .cypresses, NSSize(width: 1200, height: 760), .aqua),
            ("StarryNight-zh-hant-wide-light", .zhHant, .rhone, NSSize(width: 1200, height: 760), .aqua),
            ("StarryNight-en-narrow-light", .en, .wheatStacks, NSSize(width: 760, height: 620), .aqua),
            ("StarryNight-en-wide-light", .en, .rhone, NSSize(width: 1200, height: 760), .aqua),
            ("StarryNight-zh-hant-narrow-light", .zhHant, .wheatStacks, NSSize(width: 760, height: 620), .aqua),
            ("StarryNight-zh-hans-narrow-light", .zhHans, .rhone, NSSize(width: 760, height: 620), .aqua),
            ("breakpoint-999", .en, .wheatStacks, NSSize(width: 999, height: 620), .aqua),
            ("breakpoint-1000", .en, .wheatStacks, NSSize(width: 1000, height: 620), .aqua),
            ("starry-night", .zhHans, .starryNight, NSSize(width: 1080, height: 760), .aqua),
            ("water-lilies-light", .en, .waterLilies, NSSize(width: 1080, height: 760), .aqua)
        ]
        for scene in scenes.prefix(6) {
            scenes.append((scene.0.replacingOccurrences(of: "-light", with: "-dark"), scene.1, scene.2, scene.3, .darkAqua))
        }
        let represented = Set(scenes.map { $0.2.rawValue })
        for artwork in Artwork.allCases where !represented.contains(artwork.rawValue) {
            scenes.append(("\(artwork.filename)-light", .zhHans, artwork, NSSize(width: 1080, height: 760), .aqua))
            scenes.append(("\(artwork.filename)-dark-narrow", .en, artwork, NSSize(width: 820, height: 650), .darkAqua))
        }
        let adjustmentOnly = ProcessInfo.processInfo.environment["STARRY_VERIFY_ADJUSTMENTS_ONLY"] == "1"
        if adjustmentOnly { scenes = [scenes[2]] }
        guard Set(Artwork.allCases.map { $0.shortcutLabel }).count == Artwork.allCases.count,
              Artwork.allCases.allSatisfy({ $0.shortcutKey.count == 1 }) else {
            fputs("Incomplete gallery or invalid artwork shortcuts\n", stderr); exit(1)
        }
        var index = 0
        var reports: [[String: Any]] = []
        func prepare() {
            let scene = scenes[index]
            AppLanguage.current = scene.1
            applyLocalization()
            window.appearance = NSAppearance(named: scene.4)
            window.setContentSize(scene.3)
            window.center()
            changeArtwork(to: scene.2)
            window.contentView?.layoutSubtreeIfNeeded()
            redraw()
        }
        prepare()
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [self] timer in
            do {
                let scene = scenes[index]
                guard engine.artwork == scene.2,
                      artworkTitle.stringValue == scene.2.name,
                      artworkDetails.stringValue == scene.2.metadata else {
                    throw failure("Artwork selection did not update the gallery")
                }
                let titleFont = artworkTitle.font!
                let expectedTitleFont: String
                switch scene.1 {
                case .zhHans: expectedTitleFont = "STSongti-SC-Regular"
                case .zhHant: expectedTitleFont = "STSongti-TC-Regular"
                default: expectedTitleFont = "SourceSerif4Variable-Roman"
                }
                let brandVariations = CTFontCopyVariation(brandLabel.font! as CTFont) as? [NSNumber: NSNumber]
                guard brandLabel.stringValue == "StarryNight", window.title == "StarryNight",
                      brandLabel.font!.fontName.hasPrefix("SourceSerif4Variable-Roman"),
                      brandVariations?[NSNumber(value: 0x77676874)]?.intValue == 500,
                      titleFont.fontName.hasPrefix(expectedTitleFont) else {
                    throw failure("Brand or regional font failed to load: \(brandLabel.font!), \(titleFont)")
                }
                let characters = Array(artworkTitle.stringValue.utf16)
                var glyphs = [CGGlyph](repeating: 0, count: characters.count)
                guard CTFontGetGlyphsForCharacters(titleFont as CTFont, characters, &glyphs, characters.count) else {
                    throw failure("Title font is missing glyphs: \(artworkTitle.stringValue)")
                }
                let content = window.contentView!
                let views: [(String, NSView)] = [("carousel", carousel), ("preview", preview), ("title", artworkTitle),
                    ("artist", artworkDetails), ("status", statusLabel), ("thumbnails", thumbnailRail),
                    ("previous", previousButton), ("next", nextButton),
                    ("apply", desktopButton), ("adjust", adjustButton), ("more", moreButton)]
                var geometry: [[String: Any]] = []
                for (name, view) in views {
                    let frame = view.convert(view.bounds, to: content)
                    guard frame.width > 0, frame.height > 0 else { throw failure("Empty frame: \(name)") }
                    geometry.append(["id": name, "x": frame.minX, "y": frame.minY,
                        "width": frame.width, "height": frame.height,
                        "insideWindow": content.bounds.contains(frame), "ambiguous": view.hasAmbiguousLayout])
                }
                let previewFrame = preview.convert(preview.bounds, to: content)
                let carouselFrame = carousel.convert(carousel.bounds, to: content)
                guard !preview.hasAmbiguousLayout, !carousel.hasAmbiguousLayout,
                      content.bounds.contains(previewFrame), content.bounds.intersects(carouselFrame) else {
                    throw failure("Preview or carousel has invalid layout: preview=\(previewFrame) carousel=\(carouselFrame) content=\(content.bounds) ambiguous=\(preview.hasAmbiguousLayout),\(carousel.hasAmbiguousLayout)")
                }
                let screenshot = output.appendingPathComponent("\(scene.0).png")
                for (name, view) in views {
                    guard content.bounds.contains(view.convert(view.bounds, to: content)) else {
                        throw failure("View falls outside the window: \(name)")
                    }
                }
                let titleFrame = artworkTitle.convert(artworkTitle.bounds, to: content)
                let metadataFrame = artworkDetails.convert(artworkDetails.bounds, to: content)
                guard !titleFrame.intersects(previewFrame), !titleFrame.intersects(desktopButton.convert(desktopButton.bounds, to: content)) else {
                    throw failure("Title overlaps the painting or controls")
                }
                if let exhibition = content as? ExhibitionLayoutView, exhibition.usesSidebar {
                    guard titleFrame.minX > previewFrame.maxX, abs(metadataFrame.minY - previewFrame.minY) < 1 else {
                        throw failure("Sidebar caption is not aligned with the painting bottom")
                    }
                } else {
                    guard titleFrame.maxY < previewFrame.minY, abs(titleFrame.minX - 28) < 1 else {
                        throw failure("Narrow caption did not move below the painting and align left")
                    }
                }
                guard moreButton.frame.minX >= adjustButton.frame.maxX,
                      desktopButton.frame.minX >= moreButton.frame.maxX,
                      adjustButton.frame.minY == moreButton.frame.minY,
                      moreButton.frame.minY == desktopButton.frame.minY,
                      [desktopButton!, adjustButton!, moreButton!].allSatisfy({
                          $0.controlSize == .regular && $0.frame.width >= ceil($0.intrinsicContentSize.width)
                      }),
                      moreButton.title.isEmpty, moreButton.imagePosition == .imageOnly,
                      moreButton.accessibilityLabel() == L10n.tr("menu.auxiliary"),
                      abs(metadataFrame.minY - desktopButton.frame.maxY - 24) < 1,
                      titleFrame.minY >= metadataFrame.maxY + 7,
                      statusLabel.frame.height == 36,
                      statusLabel.frame.maxY < desktopButton.frame.minY,
                      thumbnailRail.buttons.count == Artwork.allCases.count else {
                    throw failure("Controls or thumbnail navigation do not form the expected groups")
                }
                for label in [artworkTitle!, artworkDetails!, statusLabel!, brandLabel!] {
                    let textBounds = (label.stringValue as NSString).boundingRect(
                        with: NSSize(width: label.bounds.width - 4, height: 1000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: label.font!])
                    guard textBounds.height <= label.bounds.height + 2 else {
                        throw failure("Label is clipped: \(label.stringValue) text=\(textBounds) field=\(label.bounds)")
                    }
                }
                try writeViewSnapshot(content, to: screenshot)
                let captureMode = "appkit-cacheDisplay-offscreen"
                reports.append(["scene": scene.0, "language": scene.1.rawValue, "artwork": scene.2.filename, "width": content.bounds.width,
                    "height": content.bounds.height, "coordinates": "AppKit points, bottom-left origin", "capture": captureMode,
                    "brandFont": brandLabel.font!.fontName, "brandWeight": 500, "titleFont": titleFont.fontName,
                    "titleGlyphCoverage": true, "views": geometry])
                index += 1
                if index == scenes.count {
                    try verifyAdjustmentPanels(output: output)
                    speedSlider.doubleValue = 0.75
                    strengthSlider.doubleValue = 0.8
                    changeValues()
                    guard animation.speed == 0.75, animation.strength == 0.8,
                          speedLabel.stringValue == "0.75×", strengthLabel.stringValue == "80%" else {
                        throw failure("Slider values did not reach the live preview")
                    }
                    setArtworkSelectionEnabled(false)
                    guard !carousel.selectionEnabled else { throw failure("Busy selection is still enabled") }
                    setArtworkSelectionEnabled(true)
                    guard carousel.selectionEnabled else { throw failure("Selection did not recover") }
                    let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: output.appendingPathComponent("layout.json"))
                    AppLanguage.current = savedLanguage
                    print("PASS: gallery selection, live slider values, busy recovery; \(scenes.count) captured scenes")
                    timer.invalidate()
                    if adjustmentOnly { NSApp.terminate(nil); return }
                    try verifyCarouselFrames(output: output, savedLanguage: savedLanguage)
                } else { prepare() }
            } catch {
                AppLanguage.current = savedLanguage
                fputs("UI verification failed: \(error)\n", stderr)
                timer.invalidate()
                exit(1)
            }
        }
    }

    func verifyAdjustmentPanels(output: URL) throws {
        for language in [AppLanguage.zhHans, .zhHant, .en] {
            AppLanguage.current = language
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let panel = makeAdjustmentView()
                panel.appearance = NSAppearance(named: appearance)
                panel.setFrameSize(panel.fittingSize)
                panel.layoutSubtreeIfNeeded()
                func checkLabels(_ view: NSView) throws {
                    if let label = view as? NSTextField, !label.stringValue.isEmpty {
                        guard label.frame.width >= min(100, label.intrinsicContentSize.width),
                              panel.bounds.contains(label.convert(label.bounds, to: panel)) else {
                            throw failure("Adjustment label clipped: \(label.stringValue)")
                        }
                    }
                    for child in view.subviews { try checkLabels(child) }
                }
                try checkLabels(panel)
                let tone = appearance == .aqua ? "light" : "dark"
                try writeViewSnapshot(panel, to: output.appendingPathComponent("StarryNight-adjustments-\(language.rawValue)-\(tone).png"))
            }
        }
    }

    func verifyCarouselFrames(output: URL, savedLanguage: AppLanguage) throws {
        let frames = output.appendingPathComponent("motion-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        AppLanguage.current = .en
        applyLocalization()
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1200, height: 760))
        changeArtwork(to: .rhone)
        carousel.usesAutomaticMotionClock = false
        carousel.reduceMotionOverride = false
        let originalTitle = artworkTitle.stringValue
        var trace: [[String: Any]] = []
        let center = carousel.convert(NSPoint(x: carousel.bounds.midX, y: carousel.bounds.midY), to: nil)
        func mouse(_ type: NSEvent.EventType, x: CGFloat, frame: Int) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: center.x + x, y: center.y),
                modifierFlags: [], timestamp: Double(frame) / 60, windowNumber: window.windowNumber,
                context: nil, eventNumber: frame, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: carousel.mouseDown(with: event)
            case .leftMouseDragged: carousel.mouseDragged(with: event)
            default: carousel.mouseUp(with: event)
            }
        }
        func arrow(_ right: Bool, frame: Int) {
            let key = right ? "\u{F703}" : "\u{F702}"
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: Double(frame) / 60, windowNumber: window.windowNumber, context: nil,
                characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: right ? 124 : 123)!
            carousel.keyDown(with: event)
        }
        for frame in 0..<210 {
            if frame == 6 { mouse(.leftMouseDown, x: 0, frame: frame) }
            if (7...24).contains(frame) { mouse(.leftMouseDragged, x: -CGFloat(frame - 6) * 18, frame: frame) }
            if frame == 25 { mouse(.leftMouseUp, x: -324, frame: frame) }
            if frame == 34 { mouse(.leftMouseDown, x: 0, frame: frame) }
            if (35...51).contains(frame) { mouse(.leftMouseDragged, x: CGFloat(frame - 34) * 18, frame: frame) }
            if frame == 52 { mouse(.leftMouseUp, x: 306, frame: frame) }
            if [94, 101, 107].contains(frame) { arrow(true, frame: frame) }
            if [114, 120].contains(frame) { arrow(false, frame: frame) }
            if frame == 156 { arrow(false, frame: frame) }
            if frame == 24 && artworkTitle.stringValue != originalTitle {
                throw failure("Metadata changed during the drag")
            }
            carousel.advanceMotion(by: 1.0 / 60)
            trace.append(["frame": frame, "seconds": Double(frame) / 60,
                "position": carousel.motion.position, "velocity": carousel.motion.velocity,
                "target": carousel.motion.target, "phase": String(describing: carousel.motion.phase),
                "selected": engine.artwork.filename])
            if frame.isMultiple(of: 2) {
                try writeViewSnapshot(window.contentView!, to: frames.appendingPathComponent(String(format: "%04d.png", frame / 2)))
            }
        }
        guard carousel.motion.phase == .idle, carousel.motion.target == engine.artwork.rawValue else {
            throw failure("Interrupted input did not settle on the selected artwork")
        }
        selectThumbnail(thumbnailRail.buttons[Artwork.waterLilies.rawValue])
        for _ in 0..<120 { carousel.advanceMotion(by: 1.0 / 60) }
        guard engine.artwork == .waterLilies else { throw failure("Thumbnail selection did not reach the carousel") }
        selectNext()
        for _ in 0..<120 { carousel.advanceMotion(by: 1.0 / 60) }
        guard engine.artwork == .wheatStacks else { throw failure("Next arrow did not navigate") }
        selectPrevious()
        for _ in 0..<120 { carousel.advanceMotion(by: 1.0 / 60) }
        guard engine.artwork == .waterLilies else { throw failure("Previous arrow did not navigate") }
        carousel.reduceMotionOverride = true
        arrow(true, frame: 210)
        guard carousel.motion.phase == .idle else { throw failure("Reduced motion left a spring running") }
        try writeViewSnapshot(window.contentView!, to: output.appendingPathComponent("reduced-motion-keyboard-focus.png"))
        carousel.reduceMotionOverride = nil
        carousel.usesAutomaticMotionClock = true
        let report: [String: Any] = ["capture": "AppKit cacheDisplay, offscreen native NSView",
            "input": "Synthetic NSEvent delivered to AppKit handlers; not physical mouse or screen recording",
            "clock": "Production spring advanced at deterministic 60 Hz; 105 PNG frames sampled at 30 Hz",
            "metal": "Static artwork fallback in snapshots; live Metal pixels are not captured", "frames": trace]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("motion-trace.json"))
        AppLanguage.current = savedLanguage
        print("PASS: 210 continuous simulation frames; drag, interrupted reversal, repeated keys, stable metadata, reduced motion")
        carousel.reduceMotionOverride = false
        arrow(true, frame: 211)
        guard !desktopButton.isEnabled else { throw failure("Apply remained active during motion") }
        applyLocalization()
        guard desktopButton.isEnabled, !carouselMoving, carousel.motion.phase == .idle else {
            throw failure("Localization interrupted motion without restoring controls")
        }
        arrow(true, frame: 212)
        let started = ProcessInfo.processInfo.systemUptime
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] timer in
            if carousel.motion.phase == .idle {
                guard desktopButton.isEnabled, !carouselMoving else {
                    fputs("Live clock did not restore controls\n", stderr); exit(1)
                }
                timer.invalidate()
                print("PASS: production run-loop animation timer settles and restores controls")
                NSApp.terminate(nil)
            } else if ProcessInfo.processInfo.systemUptime - started > 3 {
                fputs("Live clock failed to settle\n", stderr); exit(1)
            }
        }
    }
}
