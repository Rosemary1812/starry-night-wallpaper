import AppKit

struct LyricsObservation {
    let state: PlaybackState
    let position: TimeInterval?
    let sampledAt: TimeInterval
    let lines: [String]
    let visibleWindows: Int
}

// Opt-in native acceptance runner. It controls only the already selected Music track.
final class LyricsLiveVerification {
    private let controller: DesktopLyricsController
    private let source = MusicPlaybackSource()
    private var rows: [[String: Any]] = []

    init(controller: DesktopLyricsController) { self.controller = controller }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LyricsLiveVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    func run(lrc: URL?, document suppliedDocument: LyricsDocument? = nil, output: URL, expectedTitle: String,
             exitWhenFinished: Bool = true, completion: @escaping (Bool) -> Void = { _ in }) {
        if !controller.enabled { controller.toggle() }
        DispatchQueue.global(qos: .userInitiated).async {
            var volume: Int32?
            var original: (MusicTrack, Double)?
            var failure: String?
            do {
                let document = try suppliedDocument ?? LyricsDocument(lrc: String(contentsOf: lrc!, encoding: .utf8))
                try self.require(!document.lines.isEmpty, "No timed lyrics")
                let initial = self.source.sample()
                guard case .track(let track, let position, _) = initial else {
                    throw NSError(domain: "LyricsLiveVerification", code: 3, userInfo: [NSLocalizedDescriptionKey: "Music has no readable track or permission: \(initial)"])
                }
                try self.require(track.title == expectedTitle, "Unexpected Music track; no playback changes made")
                original = (track, position)
                volume = try MusicAppleEvents.get("pVol").int32Value
                try MusicAppleEvents.set("pVol", to: 0)
                try MusicAppleEvents.playback(false)
                DispatchQueue.main.sync { self.controller.installVerificationDocument(document, trackID: track.id) }
                let targets = [0.0, 47.0, 120.0, 12.0, 88.9, 89.2, 170.0, 70.0, 220.0, 44.5, 44.9]
                    .filter { $0 < track.duration - 2 }
                for playing in [false, true] {
                    for target in targets {
                        try self.verifyTarget(target, playing: playing, track: track, document: document)
                    }
                }
                // A rapid series of seeks must converge to the final position.
                try self.checkIdentity(track)
                try MusicAppleEvents.playback(false)
                for position in [180.0, 20.0, 140.0, 50.0] { try MusicAppleEvents.set("pPos", to: position) }
                try self.waitForTarget(50, playing: false, track: track, document: document,
                                       started: ProcessInfo.processInfo.systemUptime, label: "rapid-seeks")
                let before = DispatchQueue.main.sync { self.controller.verificationObservation() }
                Thread.sleep(forTimeInterval: 0.8)
                let after = DispatchQueue.main.sync { self.controller.verificationObservation() }
                try self.require(before.position == after.position && before.lines == after.lines, "Paused lyrics drifted")
                self.rows.append(["case": "pause-hold", "seconds": 0.8, "pass": true])
                try self.verifyTarget(74, playing: false, track: track, document: document)
                try DispatchQueue.main.sync { try self.controller.captureVerification(output.appendingPathComponent("native-window")) }
            } catch { failure = error.localizedDescription }

            // Do not seek a new track if the user changed Music while verification was running.
            if let (track, position) = original,
               case .track(let current, _, _) = self.source.sample(), current.id == track.id {
                do { try MusicAppleEvents.playback(false); try MusicAppleEvents.set("pPos", to: position) }
                catch { failure = (failure ?? "") + " Restore position failed: \(error.localizedDescription)" }
            }
            if let volume {
                do { try MusicAppleEvents.set("pVol", to: Double(volume)) }
                catch { failure = (failure ?? "") + " Restore volume failed: \(error.localizedDescription)" }
            }
            let report: [String: Any] = [
                "pass": failure == nil, "failure": failure ?? "", "cases": self.rows,
                "track": expectedTitle, "method": "Live public Music Apple Events seeking; real controller polling and NSTextField contents. Not a physical UI drag or an audio alignment measurement.",
                "cleanup": "Restored original track position when still same track, restored volume, left playback paused."
            ]
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("live-report.json"))
            } catch { failure = error.localizedDescription }
            if let failure { fputs("FAIL: \(failure)\n", stderr) }
            else { print("PASS: \(self.rows.count) native Music acceptance cases") }
            let succeeded = failure == nil
            DispatchQueue.main.async {
                completion(succeeded)
                if exitWhenFinished { if succeeded { NSApp.terminate(nil) } else { exit(1) } }
            }
        }
    }

    private func checkIdentity(_ track: MusicTrack) throws {
        guard case .track(let current, _, _) = source.sample(), current.id == track.id else {
            throw NSError(domain: "LyricsLiveVerification", code: 4, userInfo: [NSLocalizedDescriptionKey: "Track changed during acceptance; stopped"])
        }
    }

    private func verifyTarget(_ target: Double, playing: Bool, track: MusicTrack, document: LyricsDocument) throws {
        try checkIdentity(track)
        if case .track(_, _, let currentPlaying) = source.sample(), currentPlaying != playing {
            try MusicAppleEvents.playback(playing)
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            var matched = false
            while ProcessInfo.processInfo.systemUptime < deadline {
                if case .track(_, _, let actualPlaying) = source.sample(), actualPlaying == playing { matched = true; break }
                Thread.sleep(forTimeInterval: 0.03)
            }
            try require(matched, "Music did not enter requested playback state")
        }
        try MusicAppleEvents.set("pPos", to: target)
        try waitForTarget(target, playing: playing, track: track, document: document,
                          started: ProcessInfo.processInfo.systemUptime, label: playing ? "playing-seek" : "paused-seek")
    }

    private func waitForTarget(_ target: Double, playing: Bool, track: MusicTrack, document: LyricsDocument,
                               started: Double, label: String) throws {
        var last: [String: Any] = [:]
        while ProcessInfo.processInfo.systemUptime - started < 4 {
            let observation = DispatchQueue.main.sync { controller.verificationObservation() }
            if case .track(let observedTrack, let raw, let observedPlaying) = observation.state,
               observedTrack.id == track.id, observedPlaying == playing, observation.sampledAt >= started,
               let position = observation.position {
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let expectedPosition = target + (playing ? elapsed : 0)
                let error = abs(position - expectedPosition)
                // Linear reference selection, independent of the production binary search.
                let index = document.lines.lastIndex(where: { $0.time <= position }) ?? -1
                let expected = [index - 1, index, index + 1].map {
                    document.lines.indices.contains($0) ? document.lines[$0].text : ""
                }
                let intendedIndex = document.lines.lastIndex(where: { $0.time <= expectedPosition }) ?? -1
                last = ["rawPosition": raw, "timelinePosition": position, "positionErrorSeconds": error,
                        "rowIndex": index, "intendedRowIndex": intendedIndex,
                        "visibleWindows": observation.visibleWindows, "renderedRowsMatch": observation.lines == expected]
                if error < (playing ? 0.4 : 0.01) && index == intendedIndex && observation.lines == expected && observation.visibleWindows > 0 {
                    rows.append(["case": label, "target": target, "rawPosition": raw,
                                 "timelinePosition": position, "convergenceSeconds": elapsed,
                                 "positionErrorSeconds": error, "rowIndex": index, "pass": true])
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        rows.append(["case": label, "target": target, "pass": false, "lastObservation": last])
        throw NSError(domain: "LyricsLiveVerification", code: 5, userInfo: [NSLocalizedDescriptionKey: "Did not converge: \(label) at \(target)s"])
    }
}
