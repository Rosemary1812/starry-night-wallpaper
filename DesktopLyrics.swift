import AppKit

private final class LyricsWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LyricsView: NSView {
    private var labels: [NSTextField] = []
    private var rendered: [String] = []
    var displayedLines: [String] { labels.map(\.stringValue) }
    var largeText = false

    override func draw(_ dirtyRect: NSRect) {
        let colors = [NSColor.clear, NSColor.black.withAlphaComponent(0.30), NSColor.clear]
        NSGradient(colors: colors)?.draw(in: bounds.insetBy(dx: 18, dy: 0), angle: 90)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for _ in 0..<3 {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: 23, weight: .medium)
            label.textColor = .white
            label.wantsLayer = true
            label.shadow = NSShadow()
            label.shadow?.shadowColor = NSColor.black
            label.shadow?.shadowBlurRadius = 8
            labels.append(label)
            addSubview(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ lines: [String]) {
        guard rendered != lines else { return }
        rendered = lines
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, label) in labels.enumerated() {
            label.stringValue = lines[index]
            let size: CGFloat = index == 1 ? (largeText ? 36 : 28) : (largeText ? 24 : 19)
            label.font = .systemFont(ofSize: size, weight: index == 1 ? .medium : .regular)
            let textWidth = bounds.width - 56
            let measured = (lines[index] as NSString).boundingRect(
                with: NSSize(width: textWidth - 6, height: 94),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: label.font!])
            let textHeight = min(94, ceil(measured.height) + 6)
            let centerY = bounds.midY + CGFloat(1 - index) * 94
            let target = NSRect(x: 28, y: centerY - textHeight / 2, width: textWidth, height: textHeight)
            label.frame = target.offsetBy(dx: 0, dy: reduce ? 0 : -8)
            label.alphaValue = reduce ? (index == 1 ? 1 : 0.38) : 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduce ? 0 : 0.20
                label.animator().frame = target
                label.animator().alphaValue = index == 1 ? 1 : 0.38
            }
        }
    }
}

final class DesktopLyricsController: NSObject {
    private let source: PlaybackSource
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



    init(source: PlaybackSource = MusicPlaybackSource()) {
        self.source = source
        super.init()
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
        let root = NSMenuItem(title: "Desktop Lyrics (Prototype)", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        root.submenu = menu
        let toggle = NSMenuItem(title: "Enable Desktop Lyrics", action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItems.append(toggle)
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
                self.sampledAt = ended
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
                status = "\(playing ? "Playing" : "Paused"): \(track.title) · \(documents[track.id] == nil ? "Import an LRC" : "LRC loaded")"
            }
        }
        toggleItems.forEach { $0.state = enabled ? .on : .off }
        importItems.forEach { $0.isEnabled = canImport }
        for item in appearanceItems {
            if item.tag == 1 { item.state = centerPlacement ? .on : .off }
            if item.tag == 2 { item.state = centerPlacement ? .off : .on }
            if item.tag == 3 { item.state = largeText ? .on : .off }
            if item.tag >= 4 { item.isEnabled = canImport }
        }
        if case .track(let track, _, _) = timeline.state, enabled {
            let offset = offsets[track.id] ?? 0
            if offset != 0 { status += String(format: " · timing %+.2f s", offset) }
        }
        statusItems.forEach { $0.title = status }
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
        let offset = offsets[track.id] ?? 0
        offsets[track.id] = sender.tag == 6 ? 0 : min(10, max(-10, offset + (sender.tag == 4 ? 0.25 : -0.25)))
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
        documents[track.id] = LyricsDocument(lrc: lrc)
        updateMenu()
        render()
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
        panel.message = "Choose synchronized lyrics for \(track.title) — \(track.artist). Stored for this session only."
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
        guard enabled, case .track(let current, _, _) = timeline.state, current.id == track.id else {
            showError("The current track changed. Import again for the new track.")
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let document = LyricsDocument(lrc: try String(contentsOf: url, encoding: .utf8))
            guard !document.lines.isEmpty else { showError("No valid LRC timestamps found."); return }
            let version = generation
            queue.async { [weak self] in
                guard let self else { return }
                let fresh = self.source.sample()
                DispatchQueue.main.async {
                    guard self.enabled, self.generation == version,
                          case .track(let latest, _, _) = fresh, latest.id == track.id else {
                        self.showError("Music changed or became unavailable. Import again for the current track.")
                        return
                    }
                    self.timeline.calibrate(fresh, at: ProcessInfo.processInfo.systemUptime)
                    self.documents[track.id] = document
                    self.updateMenu()
                    self.render()
                }
            }
        } catch { showError("Could not read UTF-8 LRC: \(error.localizedDescription)") }
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
              let document = documents[track.id], let position = timeline.position(at: ProcessInfo.processInfo.systemUptime) else {
            windows.forEach { $0.orderOut(nil) }
            return
        }
        let index = document.index(at: position + (offsets[track.id] ?? 0)) ?? -1
        let text = [index - 1, index, index + 1].map { document.lines.indices.contains($0) ? document.lines[$0].text : "" }
        for window in windows {
            (window.contentView as? LyricsView)?.render(text)
            if !window.isVisible { window.orderFrontRegardless() }
        }
    }

    @objc private func sleep() {
        sleeping = true
        generation += 1
        windows.forEach { $0.orderOut(nil) }
    }
    @objc private func wake() {
        sleeping = false
        timeline.calibrate(.notRunning, at: ProcessInfo.processInfo.systemUptime)
        screensChanged()
        poll()
    }
    @objc private func spaceChanged() { render() }

    func installVerificationDocument(_ document: LyricsDocument, trackID: String) {
        documents[trackID] = document
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
        let track = MusicTrack(id: "fixture", title: "Local fixture", artist: "Prototype", album: "", duration: 30)
        enabled = true
        documents[track.id] = LyricsDocument(lrc: "[00:00]Previous fixture line\n[00:01]Current fixture line\n[00:20]Next fixture line")
        timeline.calibrate(.track(track, position: 2, playing: true), at: ProcessInfo.processInfo.systemUptime)
        screensChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                var report = "Native AppKit fixture check; no Music/Automation or wallpaper verification.\n"
                precondition(self.windows.count == NSScreen.screens.count && !self.windows.isEmpty)
                for (index, window) in self.windows.enumerated() {
                    precondition(window.isVisible && window.ignoresMouseEvents && !window.canBecomeKey && !window.isOpaque)
                    let view = window.contentView!
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("overlay-\(index).png"))
                    report += "screen \(index): visible=\(window.isVisible), clickThrough=\(window.ignoresMouseEvents), level=\(window.level.rawValue), frame=\(window.frame)\n"
                }
                try report.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            } catch { fputs("Lyrics smoke failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
        }
    }
}
