import Foundation

@main enum LyricsCoreTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            checks += 1
        }
        let fixture = try String(contentsOfFile: "Tests/Fixtures/prototype.lrc", encoding: .utf8)
        let lyrics = LyricsDocument(lrc: fixture)
        check(lyrics.lines.map(\.time) == [0, 2, 4, 6], "fraction, offset, repeated stamps")
        check(lyrics.index(at: -1) == nil, "before first")
        check(lyrics.index(at: 0) == 0, "exact first")
        check(lyrics.index(at: 3.99) == 1, "between lines")
        check(lyrics.index(at: 6) == 3, "exact last")
        check(lyrics.index(at: 1000) == 3, "after last")
        check(lyrics.index(at: .nan) == nil, "invalid time")
        check(LyricsDocument(lrc: "[ar:test]\n[00:61]bad\n[abc]bad").lines.isEmpty, "metadata and malformed stamps")
        check(LyricsDocument(lrc: "[00:01.2]a\n[00:01.23]b\n[00:01.234]c").lines.map(\.time) == [1.2, 1.23, 1.234], "fraction widths")
        let duplicate = LyricsDocument(lrc: "[00:02]late\n[00:01]a\n[00:01]b")
        check(duplicate.lines.map(\.text) == ["a", "b", "late"], "stable sort")
        check(duplicate.index(at: 1) == 1, "last duplicate wins")
        check(LyricsDocument(lrc: "[offset:+500]\n[00:00]a").lines.first?.time == 0.5, "positive offset")
        check(LyricsDocument(lrc: "[00:00]\r\n[00:02]你好 🎵").lines.last?.text == "你好 🎵", "unicode and CRLF")
        let a = MusicTrack(id: "a", title: "A", artist: "", album: "", duration: 100)
        let b = MusicTrack(id: "b", title: "B", artist: "", album: "", duration: 50)
        var timeline = PlaybackTimeline()
        check(timeline.position(at: 0) == nil, "initial")
        timeline.calibrate(.track(a, position: 5, playing: true), at: 100)
        check(timeline.position(at: 102) == 7, "monotonic progression")
        check(timeline.position(at: 99) == 5, "clock backward guard")
        check(timeline.position(at: 1000) == 100, "duration bound")
        timeline.calibrate(.track(a, position: 7, playing: false), at: 102)
        check(timeline.position(at: 110) == 7, "pause freeze")
        timeline.calibrate(.track(a, position: 7, playing: true), at: 110)
        check(timeline.position(at: 111) == 8, "resume")
        timeline.calibrate(.track(a, position: 70, playing: true), at: 111)
        check(timeline.position(at: 112) == 71, "forward seek")
        timeline.calibrate(.track(a, position: 2, playing: false), at: 112)
        check(timeline.position(at: 114) == 2, "paused backward seek")
        timeline.calibrate(.track(b, position: 0, playing: true), at: 114)
        check(timeline.position(at: 115) == 1, "track switch")
        for state: PlaybackState in [.notRunning, .noTrack, .denied, .failed("timeout")] {
            timeline.calibrate(state, at: 116)
            check(timeline.position(at: 120) == nil && timeline.state == state, "unavailable clears anchor")
        }
        // Scrub in both directions across every boundary, including repeated stamps.
        for document in [lyrics, duplicate] {
            let points = document.lines.flatMap { [$0.time - 0.001, $0.time, $0.time + 0.001] }
            for point in points + points.reversed() {
                let reference = document.lines.lastIndex { $0.time <= point }
                check(document.index(at: point) == reference, "scrub boundary matches linear reference")
                timeline.calibrate(.track(a, position: max(0, point), playing: false), at: 100)
                check(timeline.position(at: 105) == max(0, point), "paused seek stays at selected time")
            }
        }
        print("PASS: \(checks) lyrics checks")
    }
}
