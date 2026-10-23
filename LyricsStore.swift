import Foundation

enum LyricsOrigin: String, Codable {
    case imported, lrclib
}

struct LyricsStoredRecord: Codable, Equatable {
    let lrc: String?
    let origin: LyricsOrigin?
    let providerID: Int?
    let offset: TimeInterval
    let negativeReason: String?
    /// A negative result suppresses automatic lookup only while this is in the future.
    /// Expired deadlines remain readable, so reading the cache never mutates the disk.
    let retryAfter: Date?
}

extension MusicTrack {
    /// Exact recording identity, not a search-normalized title. Length prefixes avoid
    /// delimiter collisions; duration's IEEE-754 representation is locale-independent.
    /// Keep this version stable across launches and releases unless the schema changes.
    var lyricsIdentity: String {
        let fields = [id, title, artist, album, String(duration.bitPattern, radix: 16)]
        return "recording-v1|" + fields.map { "\($0.utf8.count):\($0)" }.joined()
    }
}

enum LyricsStoreError: LocalizedError {
    case invalidDirectory, invalidIdentity, invalidOffset, invalidLyrics
    case invalidProviderID, invalidNegativeResult, invalidStoredRecord
    case recordTooLarge, capacityExceeded

    var errorDescription: String? {
        switch self {
        case .invalidDirectory: return "The lyrics storage directory is not available."
        case .invalidIdentity: return "The recording metadata cannot be stored."
        case .invalidOffset: return "The lyrics timing offset is outside the supported range."
        case .invalidLyrics: return "The lyrics are empty or exceed the supported size."
        case .invalidProviderID: return "The lyrics provider identifier is invalid."
        case .invalidNegativeResult: return "The lyrics retry information is invalid."
        case .invalidStoredRecord: return "The saved lyrics record is invalid or uses a newer format."
        case .recordTooLarge: return "The encoded lyrics record exceeds the supported size."
        case .capacityExceeded: return "The lyrics storage limit has been reached."
        }
    }
}

/// A local, offline store. All access to a directory must be confined to the same
/// serial queue, including access through other LyricsStore instances. Atomic file
/// replacement prevents partial records, not simultaneous read/modify/write races.
///
/// Production callers supply a dedicated directory in the app's Application Support
/// directory; tests supply temporary directories. This type never uses UserDefaults,
/// Music's library, the working directory, or a network service. Lyrics and recording
/// metadata are never logged. Recording files are UTF-8 JSON containing unchanged
/// LRC. A separate bounded provider cooldown contains no recording metadata.
final class LyricsStore {
    static let maximumLRCBytes = 2_000_000
    static let maximumRecordBytes = 4_194_304
    static let maximumStorageBytes = 67_108_864
    static let maximumRecordCount = 4_096
    static let maximumOffset: TimeInterval = 10
    static let maximumProviderCooldownBytes = 1_024
    private static let maximumIdentityBytes = 65_536
    private static let maximumReasonBytes = 512
    private static let schemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let identity: String
        let record: LyricsStoredRecord
    }

    private struct ProviderCooldown: Codable {
        let schemaVersion: Int
        let retryAfter: Date
    }

    private let directory: URL
    private let files = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) throws {
        guard directory.isFileURL else { throw LyricsStoreError.invalidDirectory }
        self.directory = directory.standardizedFileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        try files.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let attributes = try files.attributesOfItem(atPath: self.directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw LyricsStoreError.invalidDirectory
        }
    }

    /// Corrupt, oversized, unsupported and inaccessible records are cache misses.
    /// Reads leave such files untouched. Mutations throw rather than silently destroy
    /// an unreadable record (which could have contained a user's manual import).
    func record(for track: MusicTrack) -> LyricsStoredRecord? {
        try? read(for: track)
    }

    /// LRCLIB's Retry-After applies to the provider, not just the current recording.
    /// Like per-record deadlines, an expired deadline remains readable and must not
    /// suppress requests. Corrupt/unsupported data is left untouched and reads nil.
    func providerRetryAfter() -> Date? {
        try? readProviderRetryAfter()
    }

    /// Never shorten a previously saved provider cooldown. This dedicated, at most
    /// 1 KiB file is separate from the lyrics-record budget so a full lyrics cache
    /// cannot prevent persisting a rate limit. Failed reads or writes propagate.
    func saveProviderRetryAfter(_ deadline: Date) throws {
        guard deadline.timeIntervalSince1970.isFinite else {
            throw LyricsStoreError.invalidNegativeResult
        }
        if let previous = try readProviderRetryAfter(), previous >= deadline { return }
        let data = try encoder.encode(ProviderCooldown(schemaVersion: Self.schemaVersion,
                                                       retryAfter: deadline))
        guard data.count <= Self.maximumProviderCooldownBytes else {
            throw LyricsStoreError.recordTooLarge
        }
        try data.write(to: providerCooldownURL, options: .atomic)
    }

    @discardableResult
    func saveLyrics(_ lrc: String, for track: MusicTrack, origin: LyricsOrigin,
                    providerID: Int?) throws -> LyricsStoredRecord {
        let previous = try read(for: track)
        // A late response cannot replace a manual choice, even after restarting.
        if previous?.origin == .imported && origin == .lrclib { return previous! }
        let record = LyricsStoredRecord(lrc: lrc, origin: origin, providerID: providerID,
                                        offset: previous?.offset ?? 0,
                                        negativeReason: nil, retryAfter: nil)
        try write(record, for: track)
        return record
    }

    @discardableResult
    func setOffset(_ offset: TimeInterval, for track: MusicTrack) throws -> LyricsStoredRecord {
        let previous = try read(for: track)
        let record = LyricsStoredRecord(lrc: previous?.lrc, origin: previous?.origin,
                                        providerID: previous?.providerID, offset: offset,
                                        negativeReason: previous?.negativeReason,
                                        retryAfter: previous?.retryAfter)
        try write(record, for: track)
        return record
    }

    func saveNegative(for track: MusicTrack, reason: String, retryAfter: Date) throws {
        let previous = try read(for: track)
        // A failed refresh is not allowed to erase usable offline lyrics.
        guard previous?.lrc == nil else { return }
        let record = LyricsStoredRecord(lrc: nil, origin: nil, providerID: nil,
                                        offset: previous?.offset ?? 0,
                                        negativeReason: reason, retryAfter: retryAfter)
        try write(record, for: track)
    }

    private func identity(for track: MusicTrack) throws -> String {
        guard track.duration.isFinite, track.duration >= 0,
              [track.id, track.title, track.artist, track.album].allSatisfy({
                  $0.utf8.count <= Self.maximumIdentityBytes
              }) else { throw LyricsStoreError.invalidIdentity }
        let identity = track.lyricsIdentity
        guard identity.utf8.count <= Self.maximumIdentityBytes else {
            throw LyricsStoreError.invalidIdentity
        }
        return identity
    }

    private func fileURL(for identity: String) -> URL {
        directory.appendingPathComponent("lyrics-" + LyricsSHA256.hex(identity.utf8) + ".json")
    }

    private var providerCooldownURL: URL {
        directory.appendingPathComponent("lrclib-cooldown.json")
    }

    private func readProviderRetryAfter() throws -> Date? {
        guard let data = try readData(at: providerCooldownURL,
                                      maximumBytes: Self.maximumProviderCooldownBytes) else { return nil }
        let cooldown: ProviderCooldown
        do { cooldown = try decoder.decode(ProviderCooldown.self, from: data) }
        catch { throw LyricsStoreError.invalidStoredRecord }
        guard cooldown.schemaVersion == Self.schemaVersion,
              cooldown.retryAfter.timeIntervalSince1970.isFinite else {
            throw LyricsStoreError.invalidStoredRecord
        }
        return cooldown.retryAfter
    }

    private func read(for track: MusicTrack) throws -> LyricsStoredRecord? {
        let identity = try identity(for: track)
        let url = fileURL(for: identity)
        guard let data = try readData(at: url, maximumBytes: Self.maximumRecordBytes) else { return nil }
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw LyricsStoreError.invalidStoredRecord }
        guard envelope.schemaVersion == Self.schemaVersion,
              // Compare bytes, not String's canonical-equivalence comparison.
              envelope.identity.utf8.elementsEqual(identity.utf8) else {
            throw LyricsStoreError.invalidStoredRecord
        }
        do { try validate(envelope.record) }
        catch { throw LyricsStoreError.invalidStoredRecord }
        return envelope.record
    }

    private func readData(at url: URL, maximumBytes: Int) throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try files.attributesOfItem(atPath: url.path)
        } catch let error as NSError {
            let isCocoaMissing = error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let isPOSIXMissing = [error, underlying].compactMap { $0 }.contains {
                $0.domain == NSPOSIXErrorDomain && $0.code == 2 // ENOENT only, never permission errors.
            }
            if isCocoaMissing || isPOSIXMissing { return nil }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0, size.int64Value <= Int64(maximumBytes) else {
            throw LyricsStoreError.invalidStoredRecord
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the actual read as well as checking size, even if a file grows.
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw LyricsStoreError.invalidStoredRecord
        }
        return data
    }

    private func validate(_ record: LyricsStoredRecord) throws {
        guard record.offset.isFinite, abs(record.offset) <= Self.maximumOffset else {
            throw LyricsStoreError.invalidOffset
        }
        if let lrc = record.lrc {
            guard !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  lrc.utf8.count <= Self.maximumLRCBytes, record.origin != nil else {
                throw LyricsStoreError.invalidLyrics
            }
            guard record.negativeReason == nil, record.retryAfter == nil else {
                throw LyricsStoreError.invalidNegativeResult
            }
        } else if record.origin != nil || record.providerID != nil {
            throw LyricsStoreError.invalidLyrics
        }
        if let providerID = record.providerID {
            guard providerID > 0, record.origin == .lrclib else {
                throw LyricsStoreError.invalidProviderID
            }
        }
        if let reason = record.negativeReason, let deadline = record.retryAfter {
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reason.utf8.count <= Self.maximumReasonBytes,
                  deadline.timeIntervalSince1970.isFinite else {
                throw LyricsStoreError.invalidNegativeResult
            }
        } else if record.negativeReason != nil || record.retryAfter != nil {
            throw LyricsStoreError.invalidNegativeResult
        }
    }

    private func write(_ record: LyricsStoredRecord, for track: MusicTrack) throws {
        try validate(record)
        let identity = try identity(for: track)
        let url = fileURL(for: identity)
        let data = try encoder.encode(Envelope(schemaVersion: Self.schemaVersion,
                                               identity: identity, record: record))
        guard data.count <= Self.maximumRecordBytes else { throw LyricsStoreError.recordTooLarge }
        try checkCapacity(replacing: url, withByteCount: data.count)
        // One atomic replacement keeps lyrics, provenance, offset and retry state in
        // sync. Validation/capacity/I/O failure never reports a successful save.
        try data.write(to: url, options: .atomic)
    }

    private func checkCapacity(replacing target: URL, withByteCount bytes: Int) throws {
        var count = 1
        var size = Int64(bytes)
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            // Enumeration can resolve /var to /private/var on macOS. Both URLs
            // belong to this directory, so compare basenames to exclude the
            // replaced entry without counting it twice at the capacity limit.
            guard name.hasPrefix("lyrics-"), name.hasSuffix(".json"), name != target.lastPathComponent else { continue }
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let storedSize = attributes[.size] as? NSNumber, storedSize.int64Value >= 0 else {
                throw LyricsStoreError.invalidStoredRecord
            }
            count += 1
            let additional = storedSize.int64Value
            guard additional <= Int64(Self.maximumStorageBytes),
                  size <= Int64(Self.maximumStorageBytes) - additional else {
                throw LyricsStoreError.capacityExceeded
            }
            size += additional
            guard count <= Self.maximumRecordCount else { throw LyricsStoreError.capacityExceeded }
        }
    }
}

/// SHA-256 is used only for portable, deterministic, filename-safe indexing. Exact
/// identity validation above is still mandatory. No CryptoKit/package dependency is
/// required, so the storage tests also run with Foundation on Linux.
private enum LyricsSHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hex(_ input: String.UTF8View) -> String {
        var bytes = Array(input)
        let bits = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bits >> shift))
        }
        var hash: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var words = [UInt32](repeating: 0, count: 64)
        func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value >> count) | (value << (32 - count))
        }
        for start in stride(from: 0, to: bytes.count, by: 64) {
            for index in 0..<16 {
                let p = start + index * 4
                words[index] = (UInt32(bytes[p]) << 24) | (UInt32(bytes[p + 1]) << 16)
                    | (UInt32(bytes[p + 2]) << 8) | UInt32(bytes[p + 3])
            }
            for index in 16..<64 {
                let a = words[index - 15], b = words[index - 2]
                let s0 = rotate(a, 7) ^ rotate(a, 18) ^ (a >> 3)
                let s1 = rotate(b, 17) ^ rotate(b, 19) ^ (b >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for index in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choice = (e & f) ^ (~e & g)
                let first = h &+ s1 &+ choice &+ constants[index] &+ words[index]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                h = g; g = f; f = e; e = d &+ first
                d = c; c = b; b = a; a = first &+ s0 &+ majority
            }
            hash = zip(hash, [a, b, c, d, e, f, g, h]).map { $0 &+ $1 }
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }
}
