import AppKit

private final class LyricsWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LyricsFixtureBackgroundView: NSView {
    let color: NSColor
    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); dirtyRect.fill() }
}

private final class LyricsView: NSView {
    private var labels: [NSTextField] = []
    private var rendered: [String] = []
    var displayedLines: [String] { labels.map(\.stringValue) }
    var largeText = false {
        didSet {
            guard largeText != oldValue else { return }
            styleAndLayoutLines()
        }
    }

    // The wallpaper must remain untouched between glyphs. Never paint a panel,
    // material, gradient, border or view-level shadow behind these labels.
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        for _ in 0..<3 {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.isBordered = false
            label.drawsBackground = false
            label.backgroundColor = .clear
            label.isEditable = false
            label.isSelectable = false
            label.focusRingType = .none
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.cell?.wraps = true
            label.cell?.usesSingleLineMode = false
            labels.append(label)
            addSubview(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        styleAndLayoutLines()
    }

    private func styleAndLayoutLines() {
        guard labels.count == 3 else { return }
        let textWidth = max(1, min(740, bounds.width - 56))
        var heights: [CGFloat] = []
        for (index, label) in labels.enumerated() {
            let current = index == 1
            let size: CGFloat = current ? (largeText ? 38 : 30) : (largeText ? 23 : 18)
            // System typography gives Latin and Chinese their native, compatible
            // font fallbacks instead of substituting an unrelated display face.
            let font = NSFont.systemFont(ofSize: size, weight: current ? .medium : .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = current ? 5 : 3
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(current ? 0.68 : 0.55)
            shadow.shadowBlurRadius = current ? 3 : 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            let string = NSAttributedString(string: label.stringValue, attributes: [
                .font: font,
                .foregroundColor: NSColor(white: 0.98, alpha: 1),
                .kern: current ? 0.45 : 0.3,
                .paragraphStyle: paragraph,
                // Attribute-level shadow follows only the glyphs, not a view.
                .shadow: shadow
            ])
            label.attributedStringValue = string
            let measured = string.boundingRect(
                with: NSSize(width: max(1, textWidth - 6), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let oneLine = ceil(font.ascender - font.descender + font.leading)
            // Reserve two lines at most, with room for glyph shadows. Long CJK
            // text wraps naturally; the field truncates beyond its two-line cap.
            heights.append(min(ceil(measured.height), oneLine * 2 + paragraph.lineSpacing) + 8)
        }
        let gap: CGFloat = largeText ? 16 : 18
        let centerHeight = heights[1]
        let centerBottom = bounds.midY - centerHeight / 2
        let origins = [centerBottom + centerHeight + gap,
                       centerBottom,
                       centerBottom - gap - heights[2]]
        for (index, label) in labels.enumerated() {
            label.frame = NSRect(x: (bounds.width - textWidth) / 2, y: origins[index],
                                 width: textWidth, height: heights[index])
        }
    }

    func render(_ lines: [String], animated: Bool = true) {
        // Keep the display safe for empty and partially populated timelines.
        let normalized = (0..<3).map { lines.indices.contains($0) ? lines[$0] : "" }
        guard rendered != normalized else { return }
        rendered = normalized
        for (index, label) in labels.enumerated() {
            label.stringValue = normalized[index]
        }
        styleAndLayoutLines()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, label) in labels.enumerated() {
            let target: CGFloat = index == 1 ? 1 : 0.52
            if reduceMotion || !animated {
                label.alphaValue = target
            } else {
                // A short opacity settle avoids sliding text or a flashing panel.
                label.alphaValue = target * 0.6
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20
                    label.animator().alphaValue = target
                }
            }
        }
    }
}

final class DesktopLyricsController: NSObject {
    private let source: PlaybackSource
    private let lyricsService: LyricsService
    private var automaticLookup = UserDefaults.standard.bool(forKey: "lyrics.automaticLookup")
    private var automaticItems: [NSMenuItem] = []
    private var lookupStatus: LyricsLoadStatus = .idle
    private var storageWarning = false
    private var verificationMode = false
    private let queue = DispatchQueue(label: "local.starrynight.music-events", qos: .utility)
    private var timeline = PlaybackTimeline()
    private var documents: [String: LyricsDocument] = [:]
    private var windows: [LyricsWindow] = []
    private var pollTimer: Timer?
    private var renderTimer: Timer?
    private var busy = false
    private var generation = 0
    private var sleeping = false
    private(set) var enabled = false
    private var toggleItems: [NSMenuItem] = []
    private var importItems: [NSMenuItem] = []
    private var statusItems: [NSMenuItem] = []
    private var appearanceItems: [NSMenuItem] = []
    private var centerPlacement = !UserDefaults.standard.bool(forKey: "lyrics.lowerPlacement")
    private var largeText = UserDefaults.standard.bool(forKey: "lyrics.largeText")
    private var offsets: [String: TimeInterval] = [:]
    private var sampledAt: TimeInterval = 0
    private var openPanel: NSOpenPanel?



    init(source: PlaybackSource = MusicPlaybackSource(), isolatedVerification: Bool = false,
         storageDirectory: URL? = nil) {
        self.source = source
        let directory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StarryNight/Lyrics-v1", isDirectory: true)
        let store = isolatedVerification ? nil : directory.flatMap { try? LyricsStore(directory: $0) }
        self.lyricsService = LyricsService(store: store)
        super.init()
        if isolatedVerification {
            automaticLookup = false
            centerPlacement = true
            largeText = false
        }
        lyricsService.onChange = { [weak self] snapshot in
            guard let self, !self.verificationMode, self.enabled,
                  case .track(let track, _, _) = self.timeline.state,
                  snapshot.identity == track.lyricsIdentity else { return }
            self.documents.removeAll()
            self.documents[track.lyricsIdentity] = snapshot.document
            self.offsets = [track.lyricsIdentity: snapshot.offset]
            self.lookupStatus = snapshot.status
            self.storageWarning = snapshot.storageWarning
            self.updateMenu()
            self.render()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func menu() -> NSMenuItem {
        // Menus are rebuilt when the app language changes; keep only current items.
        toggleItems.removeAll { $0.menu == nil }
        importItems.removeAll { $0.menu == nil }
        statusItems.removeAll { $0.menu == nil }
        appearanceItems.removeAll { $0.menu == nil }
        automaticItems.removeAll { $0.menu == nil }
        let root = NSMenuItem(title: "Desktop Lyrics", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        root.submenu = menu
        let toggle = NSMenuItem(title: "Enable Desktop Lyrics", action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItems.append(toggle)
        let automatic = NSMenuItem(title: "Automatically Find Lyrics (LRCLIB)…", action: #selector(toggleAutomaticLookup), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
        automaticItems.append(automatic)
        let privacy = NSMenuItem(title: "Online lookup sends song title, artist, album and duration only.", action: nil, keyEquivalent: "")
        privacy.isEnabled = false
        menu.addItem(privacy)
        let load = NSMenuItem(title: "Import LRC for Current Track…", action: #selector(importLRC), keyEquivalent: "")
        load.target = self
        menu.addItem(load)
        importItems.append(load)
        let demo = NSMenuItem(title: "Load Timing Demo (Not Song Lyrics)", action: #selector(loadTimingDemo), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)
        importItems.append(demo)
        menu.addItem(.separator())
        for (title, action, tag) in [
            ("Center on Screen", #selector(changeAppearance(_:)), 1),
            ("Near Bottom", #selector(changeAppearance(_:)), 2),
            ("Larger Text", #selector(changeAppearance(_:)), 3),
            ("Lyrics Earlier by 0.25 s", #selector(adjustTiming(_:)), 4),
            ("Lyrics Later by 0.25 s", #selector(adjustTiming(_:)), 5),
            ("Reset Lyric Timing", #selector(adjustTiming(_:)), 6)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
            appearanceItems.append(item)
        }
        let status = NSMenuItem(title: "Disabled", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusItems.append(status)
        updateMenu()
        return root
    }

    @objc func toggle() {
        enabled.toggle()
        generation += 1
        pollTimer?.invalidate()
        renderTimer?.invalidate()
        timeline.calibrate(.notRunning, at: ProcessInfo.processInfo.systemUptime)
        if enabled {
            screensChanged()
            pollTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
            renderTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.render() }
            RunLoop.main.add(pollTimer!, forMode: .common)
            RunLoop.main.add(renderTimer!, forMode: .common)
            poll()
        } else {
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
        updateLyricsSelection()
        updateMenu()
    }

    private func poll() {
        guard enabled, !sleeping, !busy, timeline.state != .denied else { return }
        busy = true
        let version = generation
        queue.async { [weak self] in
            guard let self else { return }
            let sample = self.source.sample()
            let ended = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                self.busy = false
                guard self.enabled, !self.sleeping, version == self.generation else { return }
                self.timeline.calibrate(sample, at: ended)
                if self.verificationMode, case .track(let track, _, _) = sample,
                   let injected = self.documents[track.id] { self.documents[track.lyricsIdentity] = injected }
                self.sampledAt = ended
                self.updateLyricsSelection()
                self.updateMenu()
                self.render()
            }
        }
    }

    private func updateMenu() {
        var status = "Disabled"
        var canImport = false
        if enabled {
            switch timeline.state {
            case .notRunning: status = "Music is not running"
            case .noTrack: status = "No current Music track"
            case .denied: status = "Automation denied. Allow in System Settings; toggle to retry."
            case .failed(let message): status = message
            case .track(let track, _, let playing):
                canImport = true
                status = "\(playing ? "Playing" : "Paused"): \(track.title) · \(lookupDescription)"
                if storageWarning { status += " · Some lyric data could not be saved" }
            }
        }
        toggleItems.forEach { $0.state = enabled ? .on : .off }
        automaticItems.forEach { $0.state = automaticLookup ? .on : .off }
        importItems.forEach { $0.isEnabled = canImport }
        for item in appearanceItems {
            if item.tag == 1 { item.state = centerPlacement ? .on : .off }
            if item.tag == 2 { item.state = centerPlacement ? .off : .on }
            if item.tag == 3 { item.state = largeText ? .on : .off }
            if item.tag >= 4 { item.isEnabled = canImport }
        }
        if case .track(let track, _, _) = timeline.state, enabled {
            let offset = offsets[track.lyricsIdentity] ?? 0
            if offset != 0 { status += String(format: " · timing %+.2f s", offset) }
        }
        statusItems.forEach { $0.title = status }
    }

    private var lookupDescription: String {
        switch lookupStatus {
        case .idle: return "Waiting for lyrics"
        case .imported: return "Imported LRC"
        case .automatic: return "Lyrics from LRCLIB"
        case .demo: return "Timing demo, not song lyrics"
        case .lookingUp: return "Finding an exact recording match…"
        case .automaticOff: return "Automatic lookup off; import an LRC"
        case .notFound: return "No exact lyrics found; import an LRC"
        case .instrumental: return "Instrumental recording"
        case .noTimedLyrics: return "No synchronized lyrics; import an LRC"
        case .rejected: return "Recording mismatch rejected; import an LRC"
        case .unavailable: return "Lookup unavailable; retrying later, or import an LRC"
        case .missingMetadata: return "Incomplete recording metadata; import an LRC"
        }
    }

    private func updateLyricsSelection() {
        guard !verificationMode else { return }
        let track: MusicTrack?
        if case .track(let current, _, _) = timeline.state { track = current } else { track = nil }
        lyricsService.select(track, enabled: enabled && !sleeping, automatic: automaticLookup)
    }

    @objc private func toggleAutomaticLookup() {
        if !automaticLookup {
            let alert = NSAlert()
            alert.messageText = "Automatically find lyrics with LRCLIB?"
            alert.informativeText = "While Desktop Lyrics is enabled, send only the current song’s title, artist, album and duration to https://lrclib.net. No audio, local files, stored listening history or Music account details are uploaded. Exact recording matches are cached locally for offline use. Imported LRC files always take priority. You can turn this off in this menu."
            alert.addButton(withTitle: "Enable Automatic Lookup")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        automaticLookup.toggle()
        UserDefaults.standard.set(automaticLookup, forKey: "lyrics.automaticLookup")
        updateLyricsSelection()
        updateMenu()
    }

    @objc private func changeAppearance(_ sender: NSMenuItem) {
        if sender.tag == 1 { centerPlacement = true }
        if sender.tag == 2 { centerPlacement = false }
        if sender.tag == 3 { largeText.toggle() }
        UserDefaults.standard.set(!centerPlacement, forKey: "lyrics.lowerPlacement")
        UserDefaults.standard.set(largeText, forKey: "lyrics.largeText")
        screensChanged()
        updateMenu()
    }

    @objc private func adjustTiming(_ sender: NSMenuItem) {
        guard case .track(let track, _, _) = timeline.state else { return }
        let offset = offsets[track.lyricsIdentity] ?? 0
        offsets[track.lyricsIdentity] = sender.tag == 6 ? 0 : min(10, max(-10, offset + (sender.tag == 4 ? 0.25 : -0.25)))
        lyricsService.setOffset(offsets[track.lyricsIdentity] ?? 0, for: track)
        render()
        updateMenu()
    }

    @objc private func loadTimingDemo() {
        guard case .track(let track, _, _) = timeline.state else { return }
        let phrases = ["桌面歌词同步演示", "当前行高亮，前后两行淡出", "暂停音乐，文字也会停下来", "演示文字 · 不是歌曲歌词"]
        var rows: [String] = []
        let duration = Int(min(track.duration, 86_400))
        for seconds in stride(from: 0, through: duration, by: 5) {
            let stamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            let phrase = phrases[(seconds / 5) % phrases.count]
            rows.append("[\(stamp).000]\(phrase) · \(stamp)")
        }
        let lrc = rows.joined(separator: "\n")
        lyricsService.useSessionDocument(LyricsDocument(lrc: lrc), for: track)
    }

    @objc private func importLRC() {
        guard case .track(let track, _, _) = timeline.state else { return }
        if let panel = openPanel { panel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        openPanel = panel
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose synchronized lyrics for \(track.title) — \(track.artist). Imported lyrics take priority and are saved on this Mac."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            self?.openPanel = nil
            guard response == .OK, let url = panel.url else { return }
            self?.loadLRC(at: url, for: track)
        }
    }

    private func loadLRC(at url: URL, for track: MusicTrack) {
        guard url.pathExtension.lowercased() == "lrc" else {
            showError("Choose a file with the .lrc extension.")
            return
        }
        guard enabled, case .track(let current, _, _) = timeline.state, current.lyricsIdentity == track.lyricsIdentity else {
            showError("The current track changed. Import again for the new track.")
            return
        }
        let version = generation
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
                // Bound the read as well as the size check if the selected file grows.
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 2_000_001) ?? Data()
                guard data.count <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
                guard let lrc = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                let fresh = self.source.sample()
                DispatchQueue.main.async {
                    guard self.enabled, !self.sleeping, self.generation == version,
                          case .track(let latest, _, _) = fresh, latest.lyricsIdentity == track.lyricsIdentity else {
                        self.showError("Music changed or became unavailable. Import again for the current track.")
                        return
                    }
                    self.timeline.calibrate(fresh, at: ProcessInfo.processInfo.systemUptime)
                    self.updateLyricsSelection()
                    self.lyricsService.importLyrics(lrc, for: track) { [weak self = self] result in
                        if case .failure(let error) = result { self?.showError(error.localizedDescription) }
                    }
                }
            } catch {
                DispatchQueue.main.async { self.showError("Could not read UTF-8 LRC: \(error.localizedDescription)") }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Desktop Lyrics"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func screensChanged() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard enabled, !sleeping else { return }
        for screen in NSScreen.screens {
            let width = min(820, screen.frame.width - 80)
            let y = centerPlacement ? screen.frame.midY - 150 : screen.frame.minY + 70
            let frame = NSRect(x: screen.frame.midX - width / 2, y: y, width: width, height: 300)
            let window = LyricsWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            let view = LyricsView(frame: NSRect(origin: .zero, size: frame.size))
            view.largeText = largeText
            window.contentView = view
            windows.append(window)
        }
        render()
    }

    private func render() {
        guard enabled, !sleeping else { return }
        guard case .track(let track, _, _) = timeline.state,
              let document = documents[track.lyricsIdentity], let position = timeline.position(at: ProcessInfo.processInfo.systemUptime) else {
            windows.forEach { $0.orderOut(nil) }
            return
        }
        let index = document.index(at: position + (offsets[track.lyricsIdentity] ?? 0)) ?? -1
        let text = [index - 1, index, index + 1].map { document.lines.indices.contains($0) ? document.lines[$0].text : "" }
        for window in windows {
            (window.contentView as? LyricsView)?.render(text)
            if !window.isVisible { window.orderFrontRegardless() }
        }
    }

    @objc private func sleep() {
        sleeping = true
        generation += 1
        lyricsService.select(nil, enabled: false, automatic: automaticLookup)
        windows.forEach { $0.orderOut(nil) }
    }
    @objc private func wake() {
        sleeping = false
        timeline.calibrate(.notRunning, at: ProcessInfo.processInfo.systemUptime)
        updateLyricsSelection()
        screensChanged()
        poll()
    }
    @objc private func spaceChanged() { render() }

    func installVerificationDocument(_ document: LyricsDocument, trackID: String) {
        verificationMode = true
        lyricsService.select(nil, enabled: false, automatic: false)
        if case .track(let track, _, _) = timeline.state, track.id == trackID {
            documents[track.lyricsIdentity] = document
        } else { documents[trackID] = document }
        render()
    }

    func verificationObservation() -> LyricsObservation {
        let position = timeline.position(at: ProcessInfo.processInfo.systemUptime)
        return LyricsObservation(state: timeline.state, position: position, sampledAt: sampledAt,
                                 lines: (windows.first?.contentView as? LyricsView)?.displayedLines ?? [],
                                 visibleWindows: windows.filter(\.isVisible).count)
    }

    func captureVerification(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("overlay-\(index).png"))
        }
    }

    func runSmokeCheck(output: URL) {
        verificationMode = true
        precondition(!automaticLookup, "Smoke checks require isolated, offline initialization")
        let track = MusicTrack(id: "fixture", title: "Local fixture", artist: "Prototype", album: "", duration: 30)
        enabled = true
        documents[track.lyricsIdentity] = LyricsDocument(lrc: "[00:00]Previous fixture line\n[00:01]Current fixture line\n[00:20]Next fixture line")
        timeline.calibrate(.track(track, position: 2, playing: true), at: ProcessInfo.processInfo.systemUptime)
        screensChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                var report = "Native AppKit fixture check; no Music/Automation or wallpaper verification.\n"
                precondition(self.windows.count == NSScreen.screens.count && !self.windows.isEmpty)
                for (index, window) in self.windows.enumerated() {
                    precondition(window.isVisible && window.ignoresMouseEvents && !window.canBecomeKey && !window.isOpaque)
                    precondition(!window.hasShadow && window.backgroundColor.alphaComponent == 0 && window.styleMask == .borderless)
                    let view = window.contentView!
                    precondition((view as? LyricsView)?.displayedLines ==
                                 ["Previous fixture line", "Current fixture line", "Next fixture line"])
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("overlay-\(index).png"))
                    var paintedPixels = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                            if alpha > 0 { paintedPixels += 1 }
                            if x < 20 || y < 20 || x >= bitmap.pixelsWide - 20 || y >= bitmap.pixelsHigh - 20 {
                                precondition(alpha == 0, "Overlay perimeter must be fully transparent")
                            }
                        }
                    }
                    precondition(paintedPixels > 0, "Fixture must actually draw text")
                    report += "screen \(index): visible=\(window.isVisible), clickThrough=\(window.ignoresMouseEvents), shadow=false, transparentPerimeter=20px, paintedPixels=\(paintedPixels), level=\(window.level.rawValue), frame=\(window.frame)\n"
                }
                report += "Background images use native NSWindow/NSView cacheDisplay, not a desktop compositor capture. No Music calls, network requests or persistent lyric store in isolated smoke mode.\n"
                try report.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            } catch { fputs("Lyrics smoke failed: \(error)\n", stderr); exit(1) }
            self.windows.forEach { $0.orderOut(nil) }
            self.captureFixtureBackground(output: output, index: 0)
        }
    }

    private func captureFixtureBackground(output: URL, index: Int) {
        guard index < 4 else { NSApp.terminate(nil); return }
        let light = index % 2 == 1
        let large = index >= 2
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        let window = LyricsWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        let color = light ? NSColor(srgbRed: 0.92, green: 0.91, blue: 0.87, alpha: 1) :
                            NSColor(srgbRed: 0.05, green: 0.08, blue: 0.13, alpha: 1)
        let background = LyricsFixtureBackgroundView(frame: frame, color: color)
        let lyrics = LyricsView(frame: NSRect(x: 90, y: 100, width: 820, height: 300))
        lyrics.largeText = large
        background.addSubview(lyrics)
        window.contentView = background
        lyrics.render(["静静看着远方 · A quiet evening",
                       large ? "这是用于检查中文换行和大号文字的原生测试句子，确认文字之间没有矩形背景" : "夜色很轻，文字浮在风里",
                       "Only the words remain · 只有文字"], animated: false)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            do {
                background.layoutSubtreeIfNeeded()
                let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds)!
                background.cacheDisplay(in: background.bounds, to: bitmap)
                let name = "native-\(light ? "light" : "dark")\(large ? "-large" : "").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
            } catch { fputs("Lyrics fixture capture failed: \(error)\n", stderr); exit(1) }
            window.orderOut(nil)
            self.captureFixtureBackground(output: output, index: index + 1)
        }
    }
}
