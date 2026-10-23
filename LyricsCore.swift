import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct LyricsDocument {
    let lines: [LyricLine]

    init(lrc: String) {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]\d)(?:\.(\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let full = lrc as NSString
        let offset = offsetPattern.matches(in: lrc, range: NSRange(location: 0, length: full.length)).last
            .flatMap { Double(full.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var parsed: [LyricLine] = []
        for row in lrc.components(separatedBy: .newlines) {
            let ns = row as NSString
            let matches = stamp.matches(in: row, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(ns.substring(with: match.range(at: 1))),
                      let seconds = Double(ns.substring(with: match.range(at: 2))) else { continue }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 :
                    Double("0." + ns.substring(with: match.range(at: 3))) ?? 0
                let time = (minutes * 60_000 + seconds * 1000 + fraction * 1000 + offset * 1000) / 1000
                if time.isFinite { parsed.append(LyricLine(time: max(0, time), text: text)) }
            }
        }
        lines = parsed.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)
    }

    func index(at position: TimeInterval) -> Int? {
        guard position.isFinite else { return nil }
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

struct MusicTrack: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

enum PlaybackState: Equatable {
    case notRunning, noTrack, denied, failed(String)
    case track(MusicTrack, position: TimeInterval, playing: Bool)
}

protocol PlaybackSource {
    func sample() -> PlaybackState
}

struct PlaybackTimeline {
    private(set) var state: PlaybackState = .notRunning
    private var anchor: TimeInterval = 0

    mutating func calibrate(_ state: PlaybackState, at now: TimeInterval) {
        self.state = state
        anchor = now
    }

    func position(at now: TimeInterval) -> TimeInterval? {
        guard case let .track(track, position, playing) = state else { return nil }
        return min(track.duration, max(0, position + (playing ? max(0, now - anchor) : 0)))
    }
}
