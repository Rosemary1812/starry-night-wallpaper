import AppKit

extension AppDelegate {
    func verifyGallery() {
        guard let output = verificationOutput else { return }
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fputs("\(error)\n", stderr); exit(1) }
        let scenes: [(String, Artwork, NSSize, NSAppearance.Name)] = [
            ("light-wide", .cypresses, NSSize(width: 1120, height: 790), .aqua),
            ("light-narrow", .wheatStacks, NSSize(width: 940, height: 728), .aqua),
            ("dark-wide", .rhone, NSSize(width: 1120, height: 790), .darkAqua),
            ("dark-narrow", .waterLilies, NSSize(width: 940, height: 728), .darkAqua),
            ("starry-night", .starryNight, NSSize(width: 1120, height: 790), .aqua)
        ]
        var index = 0
        var reports: [[String: Any]] = []
        func prepare() {
            let scene = scenes[index]
            window.appearance = NSAppearance(named: scene.3)
            window.setContentSize(scene.2)
            window.center()
            changeArtwork(artworkCards[scene.1.rawValue])
            window.contentView?.layoutSubtreeIfNeeded()
            redraw()
        }
        prepare()
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [self] timer in
            do {
                let scene = scenes[index]
                guard engine.artwork == scene.1,
                      artworkCards.filter({ $0.state == .on }).count == 1,
                      artworkTitle.stringValue == scene.1.name else {
                    throw failure("Artwork selection did not update the gallery")
                }
                let content = window.contentView!
                let views: [(String, NSView)] = [("preview", preview), ("title", artworkTitle),
                    ("speed", speedSlider), ("amplitude", strengthSlider),
                    ("apply", desktopButton), ("export", exportButton)]
                var geometry: [[String: Any]] = []
                for (name, view) in views {
                    let frame = view.convert(view.bounds, to: content)
                    guard frame.width > 0, frame.height > 0 else { throw failure("Empty frame: \(name)") }
                    geometry.append(["id": name, "x": frame.minX, "y": frame.minY,
                        "width": frame.width, "height": frame.height,
                        "insideWindow": content.bounds.contains(frame), "ambiguous": view.hasAmbiguousLayout])
                }
                guard !preview.hasAmbiguousLayout, content.bounds.contains(preview.convert(preview.bounds, to: content)) else {
                    throw failure("Preview has invalid layout")
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("\(scene.0).png").path]
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw failure("Window capture failed") }
                reports.append(["scene": scene.0, "artwork": scene.1.filename, "width": content.bounds.width,
                    "height": content.bounds.height, "coordinates": "AppKit points, bottom-left origin", "views": geometry])
                index += 1
                if index == scenes.count {
                    speedSlider.doubleValue = 0.75
                    strengthSlider.doubleValue = 0.8
                    changeValues()
                    guard animation.speed == 0.75, animation.strength == 0.8,
                          speedLabel.stringValue == "0.75×", strengthLabel.stringValue == "80%" else {
                        throw failure("Slider values did not reach the live preview")
                    }
                    setArtworkSelectionEnabled(false)
                    guard artworkCards.allSatisfy({ !$0.isEnabled }) else { throw failure("Busy selection is still enabled") }
                    setArtworkSelectionEnabled(true)
                    guard artworkCards.allSatisfy({ $0.isEnabled }) else { throw failure("Selection did not recover") }
                    let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: output.appendingPathComponent("layout.json"))
                    print("PASS: gallery selection, live slider values, busy recovery; \(scenes.count) captured scenes")
                    timer.invalidate()
                    NSApp.terminate(nil)
                } else { prepare() }
            } catch {
                fputs("UI verification failed: \(error)\n", stderr)
                timer.invalidate()
                exit(1)
            }
        }
    }
}
