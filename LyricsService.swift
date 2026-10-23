import Foundation

// Display state contains no network error bodies or URLs (which may contain metadata).
enum LyricsLoadStatus: String {
    case idle, imported, automatic, demo, lookingUp, automaticOff
    case notFound, instrumental, noTimedLyrics, rejected, unavailable, missingMetadata
}

struct LyricsServiceSnapshot {
    let identity: String?
    let document: LyricsDocument?
    let offset: TimeInterval
    let status: LyricsLoadStatus
    let storageWarning: Bool
}

private enum LyricsServiceError: LocalizedError {
    case trackChanged, invalidDocument
    var errorDescription: String? {
        switch self {
        case .trackChanged: return "The current track changed. Import again for the new track."
        case .invalidDocument: return "No valid synchronized lyrics were found."
        }
    }
}

// Queue-confined coordinator. Neither the Music polling queue nor AppKit performs disk/network I/O.
// Every selection, toggle and import invalidates stale request completions before they can be saved.
final class LyricsService {
    private struct Cached {
        var document: LyricsDocument?
        var offset: TimeInterval = 0
        var status: LyricsLoadStatus = .idle
        var retryAfter: Date?
        var storageWarning = false
    }
    private let queue = DispatchQueue(label: "local.starrynight.lyrics", qos: .utility)
    private let callbackQueue: DispatchQueue
    private let store: LyricsStore?
    private let provider: LyricsProviding
    private let minimumInterval: TimeInterval
    private let debounce: TimeInterval
    private let now: () -> Date
    private var track: MusicTrack?
    private var automatic = false
    private var enabled = false
    private var generation: UInt64 = 0
    private var request: LyricsRequest?
    private var scheduled: DispatchWorkItem?
    private var nextRequestAt = Date.distantPast
    private var providerCooldownUntil = Date.distantPast
    private var restoredProviderCooldown = false
    private var cache: [String: Cached] = [:]
    private var providerStorageWarning = false
    var onChange: ((LyricsServiceSnapshot) -> Void)?

    init(store: LyricsStore?, provider: LyricsProviding = LRCLIBProvider(),
         callbackQueue: DispatchQueue = .main, minimumInterval: TimeInterval = 2,
         debounce: TimeInterval = 0.5, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.provider = provider
        self.callbackQueue = callbackQueue
        self.minimumInterval = max(0, minimumInterval)
        self.debounce = max(0, debounce)
        self.now = now
    }

    func select(_ selected: MusicTrack?, enabled: Bool, automatic: Bool) {
        queue.async {
            guard self.track?.lyricsIdentity != selected?.lyricsIdentity || self.enabled != enabled || self.automatic != automatic else { return }
            self.invalidate()
            self.track = selected
            self.enabled = enabled
            self.automatic = automatic
            guard enabled, let selected else { self.publish(); return }
            if !self.restoredProviderCooldown {
                self.restoredProviderCooldown = true
                self.providerCooldownUntil = self.store?.providerRetryAfter() ?? .distantPast
                self.nextRequestAt = max(self.nextRequestAt, self.providerCooldownUntil)
            }
            self.restore(selected)
            self.resolve(selected)
        }
    }

    func importLyrics(_ lrc: String, for selected: MusicTrack,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            guard self.enabled, self.track?.lyricsIdentity == selected.lyricsIdentity else {
                self.callbackQueue.async { completion(.failure(LyricsServiceError.trackChanged)) }; return
            }
            let document = LyricsDocument(lrc: lrc)
            guard lrc.utf8.count <= 2_000_000, !document.lines.isEmpty else {
                self.callbackQueue.async { completion(.failure(LyricsServiceError.invalidDocument)) }; return
            }
            self.invalidate()
            let key = selected.lyricsIdentity
            let offset = self.cache[key]?.offset ?? 0
            self.cache[key] = Cached(document: document, offset: offset, status: .imported)
            do {
                _ = try self.store?.saveLyrics(lrc, for: selected, origin: .imported, providerID: nil)
                self.refreshStorageWarning(selected)
            } catch { self.cache[key]?.storageWarning = true }
            self.publish()
            self.callbackQueue.async { completion(.success(())) }
        }
    }

    // Original timing-demo text is deliberately session-only and never poisons the disk cache.
    func useSessionDocument(_ document: LyricsDocument, for selected: MusicTrack) {
        queue.async {
            guard self.enabled, self.track?.lyricsIdentity == selected.lyricsIdentity else { return }
            self.invalidate()
            self.cache[selected.lyricsIdentity] = Cached(document: document, offset: self.cache[selected.lyricsIdentity]?.offset ?? 0, status: .demo)
            self.publish()
        }
    }

    func setOffset(_ offset: TimeInterval, for selected: MusicTrack) {
        queue.async {
            guard offset.isFinite, self.enabled, self.track?.lyricsIdentity == selected.lyricsIdentity else { return }
            let value = min(10, max(-10, offset))
            var cached = self.cache[selected.lyricsIdentity] ?? Cached()
            cached.offset = value
            self.cache[selected.lyricsIdentity] = cached
            do {
                _ = try self.store?.setOffset(value, for: selected)
                self.refreshStorageWarning(selected)
            } catch { self.cache[selected.lyricsIdentity]?.storageWarning = true }
            self.publish()
        }
    }

    private func invalidate() {
        generation &+= 1
        scheduled?.cancel(); scheduled = nil
        request?.cancel(); request = nil
    }

    private func restore(_ selected: MusicTrack) {
        let key = selected.lyricsIdentity
        guard cache[key] == nil else { return }
        if let stored = store?.record(for: selected) {
            let document = stored.lrc.map(LyricsDocument.init(lrc:))
            let usable = document?.lines.isEmpty == false ? document : nil
            let status: LyricsLoadStatus = usable != nil ? (stored.origin == .imported ? .imported : .automatic) :
                (stored.negativeReason.flatMap(LyricsLoadStatus.init(rawValue:)) ?? .idle)
            cache[key] = Cached(document: usable, offset: stored.offset, status: status, retryAfter: stored.retryAfter)
        } else { cache[key] = Cached() }
        // Disk remains the persistent cache; bound the process-local working set.
        if cache.count > 64 {
            for old in Array(cache.keys) where old != key && cache.count > 64 { cache.removeValue(forKey: old) }
        }
    }

    private func resolve(_ selected: MusicTrack) {
        let key = selected.lyricsIdentity
        guard enabled, track?.lyricsIdentity == key else { return }
        if cache[key]?.document != nil { publish(); return }
        guard automatic else { publish(); return }
        guard LRCLIBProvider.hasUsableMetadata(selected) else {
            cache[key]?.status = .missingMetadata; publish(); return
        }
        if let retry = cache[key]?.retryAfter, retry > now() {
            publish()
            schedule(selected, delay: retry.timeIntervalSince(now()))
            return
        }
        cache[key]?.status = providerCooldownUntil > now() ? .unavailable : .lookingUp
        publish()
        schedule(selected, delay: max(debounce, nextRequestAt.timeIntervalSince(now())))
    }

    private func schedule(_ selected: MusicTrack, delay: TimeInterval) {
        scheduled?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.enabled, self.automatic,
                  self.track?.lyricsIdentity == selected.lyricsIdentity else { return }
            self.beginLookup(selected, token: token)
        }
        scheduled = work
        queue.asyncAfter(deadline: .now() + min(86400, max(0, delay)), execute: work)
    }

    private func beginLookup(_ selected: MusicTrack, token: UInt64) {
        // Long deadlines are scheduled in bounded chunks, without shortening a provider's Retry-After.
        if let retry = cache[selected.lyricsIdentity]?.retryAfter, retry > now() {
            schedule(selected, delay: retry.timeIntervalSince(now())); return
        }
        // Expiry can wake during another track's rate limit; never bypass that limit.
        if nextRequestAt > now() {
            if providerCooldownUntil > now() { cache[selected.lyricsIdentity]?.status = .unavailable; publish() }
            schedule(selected, delay: nextRequestAt.timeIntervalSince(now())); return
        }
        let key = selected.lyricsIdentity
        guard cache[key]?.document == nil else { publish(); return }
        cache[key]?.status = .lookingUp
        publish()
        nextRequestAt = now().addingTimeInterval(minimumInterval)
        request = provider.fetch(for: selected) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                // A response may already have been delivered when selection cancels
                // its request. Honor a known provider cooldown even for stale songs;
                // never accept their lyrics or change the new song's display state.
                if case .failure(let error) = result,
                   let retry = (error as? LRCLIBError)?.retryAfter, retry.isFinite {
                    self.applyProviderCooldown(retry)
                }
                guard self.generation == token, self.enabled, self.automatic,
                      self.track?.lyricsIdentity == key, self.cache[key]?.document == nil else { return }
                self.request = nil
                switch result {
                case .success(.found(let match)):
                    let document = LyricsDocument(lrc: match.lrc)
                    guard !document.lines.isEmpty else { self.fail(selected, status: .noTimedLyrics, delay: 3600); return }
                    var cached = self.cache[key] ?? Cached()
                    cached.document = document; cached.status = .automatic; cached.retryAfter = nil
                    do {
                        if let saved = try self.store?.saveLyrics(match.lrc, for: selected, origin: .lrclib, providerID: match.providerID),
                           saved.origin == .imported, let lrc = saved.lrc {
                            cached.document = LyricsDocument(lrc: lrc); cached.status = .imported; cached.offset = saved.offset
                        }
                        cached.storageWarning = false
                    } catch { cached.storageWarning = true }
                    self.cache[key] = cached
                    if !cached.storageWarning { self.refreshStorageWarning(selected) }
                    self.publish()
                case .success(let outcome):
                    let status: LyricsLoadStatus
                    switch outcome {
                    case .notFound: status = .notFound
                    case .instrumental: status = .instrumental
                    case .noTimedLyrics: status = .noTimedLyrics
                    case .rejected: status = .rejected
                    case .found: return
                    }
                    self.fail(selected, status: status, delay: status == .instrumental ? 86400 : 3600)
                case .failure(let error):
                    let delay = max(60, (error as? LRCLIBError)?.retryAfter ?? 60)
                    // A provider rate limit applies globally, not just to this song.
                    self.applyProviderCooldown(delay)
                    self.fail(selected, status: .unavailable, delay: delay)
                }
            }
        }
    }

    private func applyProviderCooldown(_ delay: TimeInterval) {
        guard delay.isFinite else { return }
        let deadline = now().addingTimeInterval(max(60, delay))
        providerCooldownUntil = max(providerCooldownUntil, deadline)
        nextRequestAt = max(nextRequestAt, providerCooldownUntil)
        do { try store?.saveProviderRetryAfter(providerCooldownUntil); providerStorageWarning = false }
        catch { providerStorageWarning = true }
    }

    private func fail(_ selected: MusicTrack, status: LyricsLoadStatus, delay: TimeInterval) {
        let retry = now().addingTimeInterval(delay)
        cache[selected.lyricsIdentity]?.status = status
        cache[selected.lyricsIdentity]?.retryAfter = retry
        do {
            try store?.saveNegative(for: selected, reason: status.rawValue, retryAfter: retry)
            refreshStorageWarning(selected)
        } catch { cache[selected.lyricsIdentity]?.storageWarning = true }
        publish()
        schedule(selected, delay: delay)
    }

    private func refreshStorageWarning(_ selected: MusicTrack) {
        let key = selected.lyricsIdentity
        guard let cached = cache[key] else { return }
        guard let stored = store?.record(for: selected) else {
            cache[key]?.storageWarning = cached.document != nil || cached.offset != 0 || cached.retryAfter != nil
            return
        }
        let lyricsSaved = cached.status == .demo || cached.document == nil ||
            stored.lrc.map { LyricsDocument(lrc: $0).lines == cached.document?.lines } == true
        let originSaved = cached.status != .imported && cached.status != .automatic ||
            stored.origin == (cached.status == .imported ? .imported : .lrclib)
        let negativeSaved = cached.retryAfter == nil || (stored.retryAfter.map {
            abs($0.timeIntervalSince(cached.retryAfter!)) < 0.002
        } == true && stored.negativeReason == cached.status.rawValue)
        cache[key]?.storageWarning = !lyricsSaved || !originSaved || stored.offset != cached.offset || !negativeSaved
    }

    private func publish() {
        let key = enabled ? track?.lyricsIdentity : nil
        let current = key.flatMap { cache[$0] }
        let snapshot = LyricsServiceSnapshot(identity: key, document: current?.document,
            offset: current?.offset ?? 0,
            status: key != nil && current?.document == nil && !automatic ? .automaticOff : current?.status ?? .idle,
            storageWarning: store == nil || (providerStorageWarning && providerCooldownUntil > now()) || current?.storageWarning == true)
        callbackQueue.async { [weak self] in self?.onChange?(snapshot) }
    }
}
