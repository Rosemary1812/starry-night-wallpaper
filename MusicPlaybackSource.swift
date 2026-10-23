import AppKit

// Codes come from Music.app/Contents/Resources/com.apple.Music.sdef.
// Address the running PID so a race with quitting Music cannot launch it again.
struct MusicAppleEvents {
    static func code(_ value: String) -> UInt32 {
        precondition(value.utf8.count == 4)
        return value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj "))!
    }

    private static func send(_ eventClass: String, _ eventID: String,
                             object: NSAppleEventDescriptor? = nil, value: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -600)
        }
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
                                          targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
                                          returnID: -1, transactionID: 0)
        if let object { event.setParam(object, forKeyword: code("----")) }
        if let value { event.setParam(value, forKeyword: code("data")) }
        let reply = try event.sendEvent(options: [.waitForReply], timeout: 1.5)
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply.paramDescriptor(forKeyword: code("----")) ?? NSAppleEventDescriptor.null()
    }

    static func get(_ name: String, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try send("core", "getd", object: property(name, of: container))
    }

    static func set(_ name: String, to value: Double) throws {
        _ = try send("core", "setd", object: property(name, of: .null()), value: NSAppleEventDescriptor(double: value))
    }

    static func playback(_ playing: Bool) throws { _ = try send("hook", playing ? "Play" : "Paus") }
}

final class MusicPlaybackSource: PlaybackSource {
    private var cachedTrack: MusicTrack?

    func sample() -> PlaybackState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return .notRunning }
        do {
            let state = try MusicAppleEvents.get("pPlS").enumCodeValue
            if state == MusicAppleEvents.code("kPSS") { return .noTrack }
            let object = try MusicAppleEvents.get("pTrk")
            let persistentID = (try? MusicAppleEvents.get("pPIS", of: object).stringValue) ?? ""
            let track: MusicTrack
            if !persistentID.isEmpty, let cached = cachedTrack, cached.id == persistentID {
                track = cached
            } else {
                let title = try MusicAppleEvents.get("pnam", of: object).stringValue ?? ""
                let artist = try MusicAppleEvents.get("pArt", of: object).stringValue ?? ""
                let album = try MusicAppleEvents.get("pAlb", of: object).stringValue ?? ""
                let duration = try MusicAppleEvents.get("pDur", of: object).doubleValue
                guard duration.isFinite, duration > 0, !title.isEmpty else { return .failed("Incomplete Music track") }
                let id = persistentID.isEmpty ? String(describing: [title, artist, album, String(duration)]) : persistentID
                track = MusicTrack(id: id, title: title, artist: artist, album: album, duration: duration)
                cachedTrack = track
            }
            let position = try MusicAppleEvents.get("pPos").doubleValue
            let finalState = try MusicAppleEvents.get("pPlS").enumCodeValue
            if finalState == MusicAppleEvents.code("kPSS") { return .noTrack }
            if !persistentID.isEmpty {
                let current = try MusicAppleEvents.get("pTrk")
                guard try MusicAppleEvents.get("pPIS", of: current).stringValue == persistentID else { return .noTrack }
            }
            guard position.isFinite else { return .failed("Invalid Music position") }
            return .track(track, position: max(0, position), playing: finalState == MusicAppleEvents.code("kPSP"))
        } catch {
            let code = (error as NSError).code
            if code == -1743 { return .denied }
            if code == -600 { return .notRunning }
            if code == -1728 { return .noTrack }
            return .failed("Music read failed (\(code))")
        }
    }
}
