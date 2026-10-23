import Foundation

@main enum LyricsStoreTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            checks += 1
        }
        func expectThrow(_ label: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(label) }
            catch { checks += 1 }
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("lyrics-store-tests-" + UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
        func records(in directory: URL) throws -> [URL] {
            try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        }
        func rewrite(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            change(&object)
            try JSONSerialization.data(withJSONObject: object).write(to: url, options: .atomic)
        }
        let track = MusicTrack(id: "A1B2", title: "歌曲 🎵", artist: "Artist", album: "Album", duration: 180.25)
        let automatic = "[ar:Artist]\n[00:01.00]你好 🎵\r\n[00:02.50]second line\n"
        let imported = "[offset:125]\n[00:00.00]My exact version\n"
        let location = folder("persisted")
        let store = try LyricsStore(directory: location)
        check(store.record(for: track) == nil, "missing recording is a cache miss")
        check(track.lyricsIdentity == "recording-v1|4:A1B211:歌曲 🎵6:Artist5:Album16:4066880000000000",
              "identity is stable, byte-length-delimited and independent of randomized Hasher")

        let offsetOnly = try store.setOffset(-1.75, for: track)
        check(offsetOnly.offset == -1.75 && offsetOnly.lrc == nil && offsetOnly.origin == nil,
              "offset can be saved before lyrics exist")
        let offsetReload = try LyricsStore(directory: location)
        check(offsetReload.record(for: track) == offsetOnly, "offset survives a new store instance")
        let saved = try offsetReload.saveLyrics(automatic, for: track, origin: .lrclib, providerID: 123)
        check(saved.offset == -1.75 && saved.lrc == automatic && saved.origin == .lrclib && saved.providerID == 123,
              "automatic lyrics preserve the preexisting offset and provider attribution")
        let reloaded = try LyricsStore(directory: location)
        check(reloaded.record(for: track) == saved, "offline reload preserves every field and exact UTF-8 LRC")
        let initialFiles = try records(in: location)
        check(initialFiles.count == 1, "record fields are persisted together in one file")
        let file = initialFiles[0]
        // SHA-256 cross-checked with Python hashlib, not the implementation under test.
        check(file.lastPathComponent == "lyrics-8c434c4e5137bfc70bd453da4ffb23f8a215f25d7a7206a41df34cf06ab38edf.json",
              "portable SHA-256 filename matches the known digest")
        let encoded = try Data(contentsOf: file)
        check(String(data: encoded, encoding: .utf8) != nil, "stored record is valid UTF-8")

        let changedOffset = try store.setOffset(2.25, for: track)
        check(changedOffset.lrc == automatic && changedOffset.providerID == 123 && changedOffset.offset == 2.25,
              "timing edits do not discard lyrics or attribution")
        let manual = try store.saveLyrics(imported, for: track, origin: .imported, providerID: nil)
        check(manual.offset == 2.25 && manual.origin == .imported && manual.providerID == nil,
              "manual import replaces automatic result while retaining offset")
        let restarted = try LyricsStore(directory: location)
        let late = try restarted.saveLyrics(automatic, for: track, origin: .lrclib, providerID: 999)
        check(late == manual && restarted.record(for: track) == manual,
              "late automatic response never replaces persisted manual import")
        try restarted.saveNegative(for: track, reason: "unavailable", retryAfter: Date().addingTimeInterval(60))
        check(restarted.record(for: track) == manual, "late negative response also cannot erase imported lyrics")
        let updatedImport = try restarted.saveLyrics("[00:00]New manual choice", for: track,
                                                    origin: .imported, providerID: nil)
        check(updatedImport.lrc == "[00:00]New manual choice" && updatedImport.offset == 2.25,
              "a new explicit manual import can replace an older import")

        let variants = [
            MusicTrack(id: "DIFFERENT", title: track.title, artist: track.artist, album: track.album, duration: track.duration),
            MusicTrack(id: track.id, title: track.title + " (Live)", artist: track.artist, album: track.album, duration: track.duration),
            MusicTrack(id: track.id, title: track.title, artist: "Other artist", album: track.album, duration: track.duration),
            MusicTrack(id: track.id, title: track.title, artist: track.artist, album: "Remaster", duration: track.duration),
            MusicTrack(id: track.id, title: track.title, artist: track.artist, album: track.album, duration: 181)
        ]
        for variant in variants {
            check(variant.lyricsIdentity != track.lyricsIdentity, "every recording field participates in identity")
            check(store.record(for: variant) == nil, "metadata edits and alternate versions cannot reuse stored lyrics")
        }
        let delimitersA = MusicTrack(id: "a|b", title: "c", artist: "d", album: "e", duration: 1)
        let delimitersB = MusicTrack(id: "a", title: "b|c", artist: "d", album: "e", duration: 1)
        check(delimitersA.lyricsIdentity != delimitersB.lyricsIdentity, "embedded separators cannot collide")
        let pathTrack = MusicTrack(id: "../../outside", title: "/tmp/escape", artist: "a\nb", album: "x\0y", duration: 5)
        let pathDirectory = folder("safe-path")
        let pathStore = try LyricsStore(directory: pathDirectory)
        try pathStore.setOffset(1, for: pathTrack)
        let pathFiles = try records(in: pathDirectory)
        check(pathFiles.count == 1 &&
              pathFiles[0].deletingLastPathComponent().resolvingSymlinksInPath() == pathDirectory.resolvingSymlinksInPath(),
              "untrusted recording metadata never becomes a path")
        check(pathFiles[0].lastPathComponent.range(of: #"^lyrics-[0-9a-f]{64}\.json$"#, options: .regularExpression) != nil,
              "filename contains only a fixed prefix and hexadecimal digest")

        let negativeDirectory = folder("negative")
        let negative = try LyricsStore(directory: negativeDirectory)
        let future = Date(timeIntervalSince1970: 4_000_000_000.125)
        try negative.setOffset(-0.5, for: track)
        try negative.saveNegative(for: track, reason: "not-found", retryAfter: future)
        let negativeReload = try LyricsStore(directory: negativeDirectory)
        let pending = negativeReload.record(for: track)!
        check(pending.negativeReason == "not-found" && pending.retryAfter == future && pending.offset == -0.5,
              "negative reason, retry deadline and offset survive restart")
        check(pending.lrc == nil && pending.origin == nil && pending.providerID == nil,
              "a negative record never pretends to contain lyrics")
        check(pending.retryAfter! > Date(), "future negative suppresses automatic retries")
        let past = Date(timeIntervalSince1970: 1)
        try negative.saveNegative(for: track, reason: "temporary-error", retryAfter: past)
        let expired = negative.record(for: track)!
        check(expired.retryAfter == past && expired.retryAfter! <= Date(),
              "expired negative remains inspectable but no longer suppresses retries")
        let recovered = try negative.saveLyrics(automatic, for: track, origin: .lrclib, providerID: 44)
        check(recovered.negativeReason == nil && recovered.retryAfter == nil && recovered.offset == -0.5,
              "successful lyrics clear retry state without resetting timing")
        try negative.saveNegative(for: track, reason: "network-error", retryAfter: future)
        check(negative.record(for: track) == recovered, "failed refresh preserves offline automatic lyrics")

        func testInvalidFile(_ name: String, change: (URL) throws -> Void) throws {
            let directory = folder(name)
            let cache = try LyricsStore(directory: directory)
            try cache.saveLyrics(imported, for: track, origin: .imported, providerID: nil)
            let target = try records(in: directory)[0]
            try change(target)
            let invalidBytes = try Data(contentsOf: target)
            check(cache.record(for: track) == nil, "\(name) is a harmless cache miss")
            let afterRead = try Data(contentsOf: target)
            check(afterRead == invalidBytes, "\(name) is preserved on read")
            expectThrow("\(name) cannot be silently overwritten by automatic lyrics") {
                try cache.saveLyrics(automatic, for: track, origin: .lrclib, providerID: 55)
            }
            let afterWrite = try Data(contentsOf: target)
            check(afterWrite == invalidBytes, "\(name) survives a refused write")
        }
        try testInvalidFile("invalid-json") { try Data("{broken".utf8).write(to: $0) }
        try testInvalidFile("empty-file") { try Data().write(to: $0) }
        try testInvalidFile("unknown-schema") { url in
            try rewrite(url) { $0["schemaVersion"] = 999 }
        }
        try testInvalidFile("metadata-mismatch") { url in
            try rewrite(url) { $0["identity"] = variants[0].lyricsIdentity }
        }
        try testInvalidFile("invalid-origin") { url in
            try rewrite(url) { object in
                var record = object["record"] as! [String: Any]
                record["origin"] = "unrecognized-provider"
                object["record"] = record
            }
        }
        try testInvalidFile("invalid-fields") { url in
            try rewrite(url) { object in
                var record = object["record"] as! [String: Any]
                record["offset"] = LyricsStore.maximumOffset + 1
                object["record"] = record
            }
        }
        try testInvalidFile("oversized-file") {
            try Data(repeating: 0x20, count: LyricsStore.maximumRecordBytes + 1).write(to: $0)
        }

        let boundedDirectory = folder("bounded")
        let bounded = try LyricsStore(directory: boundedDirectory)
        let original = try bounded.saveLyrics(automatic, for: track, origin: .lrclib, providerID: 123)
        let boundedFile = try records(in: boundedDirectory)[0]
        let originalBytes = try Data(contentsOf: boundedFile)
        expectThrow("oversized LRC is rejected before replacement") {
            try bounded.saveLyrics(String(repeating: "a", count: LyricsStore.maximumLRCBytes + 1),
                                   for: track, origin: .imported, providerID: nil)
        }
        expectThrow("JSON escaping cannot evade the encoded-record size limit") {
            try bounded.saveLyrics(String(repeating: "\0", count: LyricsStore.maximumLRCBytes),
                                   for: track, origin: .lrclib, providerID: 123)
        }
        for invalid: TimeInterval in [.nan, .infinity, -.infinity, LyricsStore.maximumOffset + 1] {
            expectThrow("invalid timing offset is rejected") { try bounded.setOffset(invalid, for: track) }
        }
        expectThrow("empty lyrics are rejected") {
            try bounded.saveLyrics(" \n", for: track, origin: .lrclib, providerID: 123)
        }
        expectThrow("invalid provider attribution is rejected") {
            try bounded.saveLyrics(imported, for: track, origin: .imported, providerID: 123)
        }
        expectThrow("negative provider ID is rejected") {
            try bounded.saveLyrics(automatic, for: track, origin: .lrclib, providerID: -1)
        }
        check(bounded.record(for: track) == original, "rejected writes preserve the complete previous record")
        let boundedBytes = try Data(contentsOf: boundedFile)
        check(boundedBytes == originalBytes, "rejected writes leave original bytes unchanged")
        let boundedFiles = try files.contentsOfDirectory(atPath: boundedDirectory.path)
        check(boundedFiles.count == 1, "failed validation leaves no partial or temporary files")
        let maxLRC = "[00:00]" + String(repeating: "x", count: LyricsStore.maximumLRCBytes - 7)
        try bounded.saveLyrics(maxLRC, for: track, origin: .lrclib, providerID: nil)
        check(bounded.record(for: track)?.lrc?.utf8.count == LyricsStore.maximumLRCBytes,
              "the exact raw LRC size limit remains writable and readable")
        for index in 0..<10 { try bounded.setOffset(Double(index) / 10, for: track) }
        check(bounded.record(for: track)?.offset == 0.9, "repeated atomic replacements remain readable")
        let finalFiles = try files.contentsOfDirectory(atPath: boundedDirectory.path)
        check(finalFiles.count == 1, "successful atomic replacements leave only the complete destination file")

        let fullDirectory = folder("capacity")
        let full = try LyricsStore(directory: fullDirectory)
        let beforeFull = try full.setOffset(1, for: track)
        let filler = fullDirectory.appendingPathComponent("lyrics-capacity.json")
        check(files.createFile(atPath: filler.path, contents: nil), "capacity fixture created")
        let handle = try FileHandle(forWritingTo: filler)
        try handle.truncate(atOffset: UInt64(LyricsStore.maximumStorageBytes))
        try handle.close()
        expectThrow("aggregate byte cap rejects growth without evicting manual data") {
            try full.setOffset(2, for: track)
        }
        check(full.record(for: track) == beforeFull, "full cache preserves existing offset")

        let crowdedDirectory = folder("record-count")
        let crowded = try LyricsStore(directory: crowdedDirectory)
        try crowded.setOffset(1, for: track)
        for index in 1..<LyricsStore.maximumRecordCount {
            let placeholder = crowdedDirectory.appendingPathComponent("lyrics-placeholder-\(index).json")
            try Data().write(to: placeholder)
        }
        try crowded.setOffset(2, for: track)
        check(crowded.record(for: track)?.offset == 2, "entry limit still allows replacement of an existing record")
        expectThrow("entry count is bounded even for zero-byte entries") {
            try crowded.setOffset(3, for: variants[0])
        }
        check(crowded.record(for: variants[0]) == nil, "entry-count rejection does not create a partial file")

        let permissionsDirectory = folder("permissions")
        let permissions = try LyricsStore(directory: permissionsDirectory)
        let readable = try permissions.setOffset(1, for: track)
        let permissionsFile = try records(in: permissionsDirectory)[0]
        let permissionsBytes = try Data(contentsOf: permissionsFile)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: permissionsFile.path)
        // Root-run test environments may bypass Unix mode bits, so gate this branch
        // on the effective permission rather than claim to have tested a denied read.
        if !files.isReadableFile(atPath: permissionsFile.path) {
            check(permissions.record(for: track) == nil, "unreadable file is a cache miss")
            expectThrow("permission failure cannot silently replace a saved record") {
                try permissions.setOffset(2, for: track)
            }
        }
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: permissionsFile.path)
        let permissionsAfterRead = try Data(contentsOf: permissionsFile)
        check(permissionsAfterRead == permissionsBytes, "denied reads preserve saved bytes")
        try files.setAttributes([.posixPermissions: 0o500], ofItemAtPath: permissionsDirectory.path)
        if !files.isWritableFile(atPath: permissionsDirectory.path) {
            expectThrow("atomic write failure propagates rather than claiming success") {
                try permissions.setOffset(3, for: track)
            }
            check(permissions.record(for: track) == readable, "failed atomic replacement preserves the last complete record")
        }
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: permissionsDirectory.path)

        let symlinkDirectory = folder("symlink")
        let symlink = try LyricsStore(directory: symlinkDirectory)
        try symlink.setOffset(1, for: track)
        let symlinkFile = try records(in: symlinkDirectory)[0]
        let outside = root.appendingPathComponent("outside-record.json")
        try files.moveItem(at: symlinkFile, to: outside)
        let outsideBytes = try Data(contentsOf: outside)
        try files.createSymbolicLink(at: symlinkFile, withDestinationURL: outside)
        check(symlink.record(for: track) == nil, "record symlinks are not followed")
        expectThrow("writes refuse a symlinked record") { try symlink.setOffset(2, for: track) }
        let outsideAfter = try Data(contentsOf: outside)
        check(outsideAfter == outsideBytes, "refused symlink operation leaves its destination untouched")

        let invalidDirectory = folder("not-directory")
        try Data("file".utf8).write(to: invalidDirectory)
        expectThrow("initialization reports directory creation failure") {
            _ = try LyricsStore(directory: invalidDirectory)
        }
        let missingDirectory = folder("removed-directory")
        let missing = try LyricsStore(directory: missingDirectory)
        try files.removeItem(at: missingDirectory)
        expectThrow("I/O failure is not reported as a successful save") {
            try missing.setOffset(1, for: track)
        }
        let invalidTrack = MusicTrack(id: "id", title: "t", artist: "a", album: "b", duration: .nan)
        check(store.record(for: invalidTrack) == nil, "invalid metadata cannot crash a cache read")
        expectThrow("invalid metadata cannot be persisted") { try store.setOffset(1, for: invalidTrack) }
        let enormousTrack = MusicTrack(id: String(repeating: "x", count: 65_537), title: "t", artist: "a", album: "b", duration: 1)
        expectThrow("recording identity size is bounded") { try store.setOffset(1, for: enormousTrack) }
        let negativeOnly = try LyricsStore(directory: folder("invalid-negative"))
        expectThrow("empty negative-cache reason is rejected") {
            try negativeOnly.saveNegative(for: track, reason: " ", retryAfter: future)
        }
        expectThrow("oversized negative-cache reason is rejected") {
            try negativeOnly.saveNegative(for: track, reason: String(repeating: "x", count: 513), retryAfter: future)
        }
        expectThrow("nonfinite negative deadline is rejected") {
            try negativeOnly.saveNegative(for: track, reason: "not-found", retryAfter: Date(timeIntervalSince1970: .infinity))
        }

        let cooldownDirectory = folder("provider-cooldown")
        let cooldown = try LyricsStore(directory: cooldownDirectory)
        check(cooldown.providerRetryAfter() == nil, "missing provider deadline does not suppress requests")
        try cooldown.saveProviderRetryAfter(future)
        let cooldownReload = try LyricsStore(directory: cooldownDirectory)
        check(cooldownReload.providerRetryAfter() == future, "provider deadline survives restart independently of recording")
        let cooldownFiles = try records(in: cooldownDirectory)
        check(cooldownFiles.count == 1 && cooldownFiles[0].lastPathComponent == "lrclib-cooldown.json",
              "provider cooldown uses one dedicated file rather than a recording key")
        let cooldownFile = cooldownFiles[0]
        let cooldownBytes = try Data(contentsOf: cooldownFile)
        let cooldownObject = try JSONSerialization.jsonObject(with: cooldownBytes) as! [String: Any]
        check(Set(cooldownObject.keys) == Set(["schemaVersion", "retryAfter"]),
              "provider cooldown contains no song metadata or lyrics")
        check(cooldownBytes.count <= LyricsStore.maximumProviderCooldownBytes, "provider cooldown has a small bounded representation")
        try cooldownReload.saveProviderRetryAfter(future.addingTimeInterval(-60))
        check(cooldownReload.providerRetryAfter() == future, "older response cannot shorten provider cooldown")
        let unchangedCooldown = try Data(contentsOf: cooldownFile)
        check(unchangedCooldown == cooldownBytes, "older provider deadline does not rewrite persisted bytes")
        let extended = future.addingTimeInterval(120)
        try cooldownReload.saveProviderRetryAfter(extended)
        check(cooldown.providerRetryAfter() == extended, "later response extends provider deadline atomically")
        try cooldown.setOffset(1, for: track)
        try cooldown.saveNegative(for: track, reason: "not-found", retryAfter: past)
        check(cooldown.providerRetryAfter() == extended, "per-record negative never changes provider cooldown")
        check(cooldown.record(for: track)?.retryAfter == past, "provider cooldown does not rewrite per-record retry state")
        for invalid: TimeInterval in [.nan, .infinity, -.infinity] {
            expectThrow("nonfinite provider cooldown is rejected") {
                try cooldown.saveProviderRetryAfter(Date(timeIntervalSince1970: invalid))
            }
        }
        check(cooldown.providerRetryAfter() == extended, "rejected provider deadline preserves previous valid value")
        let expiredProvider = try LyricsStore(directory: folder("expired-provider"))
        try expiredProvider.saveProviderRetryAfter(past)
        check(expiredProvider.providerRetryAfter() == past && expiredProvider.providerRetryAfter()! <= Date(),
              "expired provider cooldown stays readable but no longer suppresses requests")
        try full.saveProviderRetryAfter(future)
        check(full.providerRetryAfter() == future, "full lyrics cache cannot prevent persisting provider rate limit")

        func testInvalidCooldown(_ name: String, change: (URL) throws -> Void) throws {
            let directory = folder("provider-" + name)
            let cache = try LyricsStore(directory: directory)
            try cache.saveProviderRetryAfter(future)
            let target = try records(in: directory)[0]
            try change(target)
            let invalidBytes = try Data(contentsOf: target)
            check(cache.providerRetryAfter() == nil, "\(name) provider data cannot crash cache reads")
            let afterRead = try Data(contentsOf: target)
            check(afterRead == invalidBytes, "\(name) provider data is preserved on read")
            expectThrow("\(name) provider data cannot be silently overwritten") {
                try cache.saveProviderRetryAfter(extended)
            }
            let afterWrite = try Data(contentsOf: target)
            check(afterWrite == invalidBytes, "\(name) provider data survives refused mutation")
        }
        try testInvalidCooldown("corrupt") { try Data("{broken".utf8).write(to: $0) }
        try testInvalidCooldown("unknown-schema") { url in try rewrite(url) { $0["schemaVersion"] = 999 } }
        try testInvalidCooldown("invalid-date") { url in try rewrite(url) { $0["retryAfter"] = "NaN" } }
        try testInvalidCooldown("oversized") {
            try Data(repeating: 0x20, count: LyricsStore.maximumProviderCooldownBytes + 1).write(to: $0)
        }
        let symlinkProviderDirectory = folder("provider-symlink")
        let symlinkProvider = try LyricsStore(directory: symlinkProviderDirectory)
        try symlinkProvider.saveProviderRetryAfter(future)
        let symlinkProviderFile = try records(in: symlinkProviderDirectory)[0]
        let outsideProviderFile = root.appendingPathComponent("outside-provider.json")
        try files.moveItem(at: symlinkProviderFile, to: outsideProviderFile)
        let outsideProviderBytes = try Data(contentsOf: outsideProviderFile)
        try files.createSymbolicLink(at: symlinkProviderFile, withDestinationURL: outsideProviderFile)
        check(symlinkProvider.providerRetryAfter() == nil, "provider cooldown symlinks are not followed")
        expectThrow("provider cooldown write refuses a symlink") { try symlinkProvider.saveProviderRetryAfter(extended) }
        let outsideProviderAfter = try Data(contentsOf: outsideProviderFile)
        check(outsideProviderAfter == outsideProviderBytes, "refused provider write leaves symlink destination untouched")

        print("PASS: \(checks) lyrics storage checks")
    }
}
