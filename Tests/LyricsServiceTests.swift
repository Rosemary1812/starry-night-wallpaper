import Foundation

private final class Request: LyricsRequest {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

private final class Provider: LyricsProviding {
    struct Pending {
        let track: MusicTrack
        let request: Request
        let completion: (Result<LyricsFetchOutcome, Error>) -> Void
        let started: Date
    }
    private let condition = NSCondition()
    private var pending: [Pending] = []
    var count: Int { condition.lock(); defer { condition.unlock() }; return pending.count }
    func fetch(for track: MusicTrack, completion: @escaping (Result<LyricsFetchOutcome, Error>) -> Void) -> LyricsRequest {
        let request = Request()
        condition.lock()
        pending.append(Pending(track: track, request: request, completion: completion, started: Date()))
        condition.broadcast(); condition.unlock()
        return request
    }
    func item(_ index: Int) -> Pending {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(4)
        while pending.count <= index {
            precondition(condition.wait(until: deadline), "Timed out waiting for lookup \(index)")
        }
        return pending[index]
    }
}

private final class TestClock {
    private let lock = NSLock()
    private var value = Date()
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value.addTimeInterval(seconds); lock.unlock() }
}

private final class Observations {
    private let condition = NSCondition()
    private var values: [LyricsServiceSnapshot] = []
    func append(_ value: LyricsServiceSnapshot) {
        condition.lock(); values.append(value); condition.broadcast(); condition.unlock()
    }
    func wait(_ predicate: (LyricsServiceSnapshot) -> Bool) -> LyricsServiceSnapshot {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(4)
        while true {
            if let value = values.last(where: predicate) { return value }
            precondition(condition.wait(until: deadline), "Timed out waiting for service state")
        }
    }
    var last: LyricsServiceSnapshot? { condition.lock(); defer { condition.unlock() }; return values.last }
}

@main enum LyricsServiceTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checks += 1
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let a = MusicTrack(id: "A", title: "Morning", artist: "Original", album: "Home", duration: 120)
        let b = MusicTrack(id: "B", title: "Evening", artist: "Original", album: "Home", duration: 130)
        let lrc = "[00:00]Original test words\n[00:10]Another original line"
        let other = "[00:00]Different original words"
        func make(_ folder: String, minimum: Double = 0, debounce: Double = 0) throws -> (LyricsService, Provider, Observations, LyricsStore) {
            let store = try LyricsStore(directory: temporary.appendingPathComponent(folder))
            let provider = Provider(), observations = Observations()
            let service = LyricsService(store: store, provider: provider,
                callbackQueue: DispatchQueue(label: "test.callback.\(folder)"), minimumInterval: minimum, debounce: debounce)
            service.onChange = observations.append
            return (service, provider, observations, store)
        }

        // Consent is a real gate, including repeated 250 ms Music selections.
        let (consent, noNetwork, consentState, _) = try make("consent")
        consent.select(a, enabled: true, automatic: false)
        _ = consentState.wait { $0.status == .automaticOff }
        for _ in 0..<10 { consent.select(a, enabled: true, automatic: false) }
        Thread.sleep(forTimeInterval: 0.04)
        check(noNetwork.count == 0, "No network before opt-in")
        consent.select(a, enabled: true, automatic: true)
        let first = noNetwork.item(0)
        first.completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 1))))
        _ = consentState.wait { $0.status == .automatic }
        for _ in 0..<10 { consent.select(a, enabled: true, automatic: true) }
        Thread.sleep(forTimeInterval: 0.04)
        check(noNetwork.count == 1, "Repeated samples do not redownload")

        // Real cancellation plus stale-result guard. A deliberately bad mock still calls back.
        let (race, racing, raceState, raceStore) = try make("race")
        race.select(a, enabled: true, automatic: true)
        let stale = racing.item(0)
        race.select(b, enabled: true, automatic: true)
        let current = racing.item(1)
        check(stale.request.cancelled, "Changing song cancels request")
        stale.completion(.success(.found(LyricsMatch(lrc: other, providerID: 2))))
        current.completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 3))))
        let selected = raceState.wait { $0.identity == b.lyricsIdentity && $0.status == .automatic }
        check(selected.document?.lines.first?.text == "Original test words", "New song renders its own lyrics")
        check(raceStore.record(for: a) == nil, "Stale song response is not persisted")
        check(raceStore.record(for: b)?.providerID == 3, "Current response persists attribution")

        // A manual import beats an in-flight request and remains authoritative after restart.
        let (manual, importing, manualState, manualStore) = try make("manual")
        manual.select(a, enabled: true, automatic: true)
        let pending = importing.item(0)
        let imported = DispatchSemaphore(value: 0)
        manual.importLyrics(other, for: a) { result in
            if case .failure(let error) = result { preconditionFailure("Import failed: \(error)") }
            imported.signal()
        }
        check(imported.wait(timeout: .now() + 4) == .success, "Import completes")
        pending.completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 4))))
        _ = manualState.wait { $0.status == .imported }
        manual.setOffset(1.25, for: a)
        _ = manualState.wait { $0.offset == 1.25 }
        check(pending.request.cancelled, "Import cancels automatic lookup")
        check(manualStore.record(for: a)?.lrc == other, "Late automatic result cannot overwrite import")
        let reloadedProvider = Provider(), reloadedState = Observations()
        let reloaded = LyricsService(store: try LyricsStore(directory: temporary.appendingPathComponent("manual")), provider: reloadedProvider,
            callbackQueue: DispatchQueue(label: "test.reload"), minimumInterval: 0, debounce: 0)
        reloaded.onChange = reloadedState.append
        reloaded.select(a, enabled: true, automatic: false)
        let offline = reloadedState.wait { $0.status == .imported }
        check(offline.offset == 1.25 && offline.document?.lines.first?.text == "Different original words", "Offline lyrics and per-recording offset survive restart")
        check(reloadedProvider.count == 0, "Offline restore makes no request")

        // Imported bytes for an old track must never attach to the newly selected recording.
        let wrongImport = DispatchSemaphore(value: 0)
        manual.select(b, enabled: true, automatic: false)
        manual.importLyrics(lrc, for: a) { result in
            if case .success = result { preconditionFailure("Wrong-track import succeeded") }
            wrongImport.signal()
        }
        check(wrongImport.wait(timeout: .now() + 4) == .success, "Changed-track import rejected")

        // Persist misses and don't hammer the service on switching away and back or restart.
        let (negative, missing, negativeState, negativeStore) = try make("negative")
        negative.select(a, enabled: true, automatic: true)
        missing.item(0).completion(.success(.notFound))
        _ = negativeState.wait { $0.status == .notFound }
        check(negativeStore.record(for: a)?.retryAfter != nil, "Miss has persistent retry deadline")
        negative.select(nil, enabled: false, automatic: true)
        negative.select(a, enabled: true, automatic: true)
        Thread.sleep(forTimeInterval: 0.05)
        check(missing.count == 1, "Negative cache suppresses repeated lookup")
        let negativeAgain = Provider(), negativeAgainState = Observations()
        let restart = LyricsService(store: try LyricsStore(directory: temporary.appendingPathComponent("negative")), provider: negativeAgain,
            callbackQueue: DispatchQueue(label: "test.negative.restart"), minimumInterval: 0, debounce: 0)
        restart.onChange = negativeAgainState.append
        restart.select(a, enabled: true, automatic: true)
        _ = negativeAgainState.wait { $0.status == .notFound }
        check(negativeAgain.count == 0, "Negative cache survives restart")

        // Expired persistent misses may be looked up again.
        let (expired, retried, expiredState, expiredStore) = try make("expired")
        try expiredStore.saveNegative(for: a, reason: LyricsLoadStatus.notFound.rawValue, retryAfter: Date().addingTimeInterval(-1))
        expired.select(a, enabled: true, automatic: true)
        retried.item(0).completion(.success(.instrumental))
        _ = expiredState.wait { $0.status == .instrumental }
        check(retried.count == 1, "Expired miss retries")

        // Disabling online mode cancels transport and rejects even a malicious late callback.
        let (disable, disabledProvider, disabledState, disabledStore) = try make("disabled")
        disable.select(a, enabled: true, automatic: true)
        let disabledRequest = disabledProvider.item(0)
        disable.select(a, enabled: true, automatic: false)
        _ = disabledState.wait { $0.status == .automaticOff }
        disabledRequest.completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 6))))
        Thread.sleep(forTimeInterval: 0.05)
        check(disabledRequest.request.cancelled && disabledStore.record(for: a) == nil, "Disabled lookup never saves stale results")

        // Global throttle applies across songs, not just repeated requests for one identity.
        let (throttled, throttledProvider, _, _) = try make("throttle", minimum: 0.12)
        throttled.select(a, enabled: true, automatic: true)
        let throttleA = throttledProvider.item(0)
        throttled.select(b, enabled: true, automatic: true)
        let throttleB = throttledProvider.item(1)
        check(throttleB.started.timeIntervalSince(throttleA.started) >= 0.10, "Cross-track global request throttle")

        // Debounce means rapidly skipped tracks send no metadata at all.
        let (debounced, debounceProvider, _, _) = try make("debounce", debounce: 0.1)
        debounced.select(a, enabled: true, automatic: true)
        debounced.select(b, enabled: true, automatic: true)
        check(debounceProvider.item(0).track.id == "B", "Skipped song does not leak metadata")
        check(debounceProvider.count == 1, "One request after rapid track changes")

        let (rate, rateProvider, rateState, rateStore) = try make("rate")
        rate.select(a, enabled: true, automatic: true)
        rateProvider.item(0).completion(.failure(LRCLIBError.rateLimited(retryAfter: 120)))
        _ = rateState.wait { $0.status == .unavailable }
        check((rateStore.record(for: a)?.retryAfter?.timeIntervalSinceNow ?? 0) > 115, "Retry-After persists")
        rate.select(b, enabled: true, automatic: true)
        Thread.sleep(forTimeInterval: 0.05)
        check(rateProvider.count == 1, "Retry-After throttles other songs too")

        let rateRestartProvider = Provider(), rateRestartState = Observations()
        let rateRestart = LyricsService(store: try LyricsStore(directory: temporary.appendingPathComponent("rate")), provider: rateRestartProvider,
            callbackQueue: DispatchQueue(label: "test.rate.restart"), minimumInterval: 0, debounce: 0)
        rateRestart.onChange = rateRestartState.append
        rateRestart.select(b, enabled: true, automatic: true)
        _ = rateRestartState.wait { $0.status == .unavailable }
        Thread.sleep(forTimeInterval: 0.05)
        check(rateRestartProvider.count == 0, "Provider cooldown survives restart on a different song")

        // A callback already dispatched before cancellation may carry a global cooldown.
        // The stale lyric guard must not discard that cooldown along with the old result.
        let (staleRate, staleRateProvider, staleRateState, staleRateStore) = try make("stale-rate", minimum: 0.12)
        staleRate.select(a, enabled: true, automatic: true)
        let oldLimited = staleRateProvider.item(0)
        staleRate.select(b, enabled: true, automatic: true)
        _ = staleRateState.wait { $0.identity == b.lyricsIdentity }
        oldLimited.completion(.failure(LRCLIBError.rateLimited(retryAfter: 120)))
        Thread.sleep(forTimeInterval: 0.18)
        check(staleRateProvider.count == 1, "Stale 429 still protects the provider across track changes")
        check(staleRateStore.record(for: a) == nil, "Stale failure does not write an old-track record")

        let (incomplete, incompleteProvider, incompleteState, _) = try make("incomplete")
        incomplete.select(MusicTrack(id: "x", title: "A", artist: "", album: "", duration: 100), enabled: true, automatic: true)
        _ = incompleteState.wait { $0.status == .missingMetadata }
        check(incompleteProvider.count == 0, "Incomplete recording metadata is never sent")

        // A write failure belongs to that recording and clears only once its data is saved.
        let (recovery, _, recoveryState, recoveryStore) = try make("recovery")
        _ = try recoveryStore.saveLyrics(lrc, for: b, origin: .imported, providerID: nil)
        recovery.select(a, enabled: true, automatic: false)
        _ = recoveryState.wait { $0.identity == a.lyricsIdentity && $0.status == .automaticOff }
        let recoveryDirectory = temporary.appendingPathComponent("recovery")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: recoveryDirectory.path)
        let failedWrite = DispatchSemaphore(value: 0)
        recovery.importLyrics(other, for: a) { _ in failedWrite.signal() }
        check(failedWrite.wait(timeout: .now() + 4) == .success, "Failed disk save keeps imported session lyrics")
        _ = recoveryState.wait { $0.identity == a.lyricsIdentity && $0.status == .imported && $0.storageWarning }
        recovery.select(b, enabled: true, automatic: false)
        let cleanTrack = recoveryState.wait { $0.identity == b.lyricsIdentity && $0.status == .imported }
        check(!cleanTrack.storageWarning, "Other cached tracks don't inherit a save warning")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recoveryDirectory.path)
        recovery.select(a, enabled: true, automatic: false)
        recovery.setOffset(0.5, for: a)
        let offsetOnly = recoveryState.wait { $0.identity == a.lyricsIdentity && $0.offset == 0.5 }
        check(offsetOnly.storageWarning && recoveryStore.record(for: a)?.lrc == nil, "Offset-only recovery cannot falsely mark lyrics saved")
        let savedAgain = DispatchSemaphore(value: 0)
        recovery.importLyrics(other, for: a) { _ in savedAgain.signal() }
        check(savedAgain.wait(timeout: .now() + 4) == .success, "Import can be saved after filesystem recovery")
        _ = recoveryState.wait { $0.identity == a.lyricsIdentity && $0.status == .imported && !$0.storageWarning }
        check(recoveryStore.record(for: a)?.lrc == other, "Successful save clears only the resolved warning")

        // A failed negative-cache write must not taint a later successful automatic save.
        let negativeRecoveryDirectory = temporary.appendingPathComponent("negative-recovery")
        let negativeRecoveryStore = try LyricsStore(directory: negativeRecoveryDirectory)
        let negativeRecoveryProvider = Provider(), negativeRecoveryState = Observations(), clock = TestClock()
        let negativeRecovery = LyricsService(store: negativeRecoveryStore, provider: negativeRecoveryProvider,
            callbackQueue: DispatchQueue(label: "test.negative.recovery"), minimumInterval: 0, debounce: 0, now: clock.now)
        negativeRecovery.onChange = negativeRecoveryState.append
        negativeRecovery.select(a, enabled: true, automatic: true)
        let unavailableWrite = negativeRecoveryProvider.item(0)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: negativeRecoveryDirectory.path)
        unavailableWrite.completion(.success(.notFound))
        _ = negativeRecoveryState.wait { $0.status == .notFound && $0.storageWarning }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: negativeRecoveryDirectory.path)
        clock.advance(3601)
        negativeRecovery.select(nil, enabled: false, automatic: true)
        negativeRecovery.select(a, enabled: true, automatic: true)
        negativeRecoveryProvider.item(1).completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 12))))
        _ = negativeRecoveryState.wait { $0.status == .automatic && !$0.storageWarning }
        check(negativeRecoveryStore.record(for: a)?.lrc == lrc, "Successful automatic recovery clears prior negative-save warning")

        // No storage is a visible degraded mode, not false persistence success.
        let volatileState = Observations(), volatileProvider = Provider()
        let volatile = LyricsService(store: nil, provider: volatileProvider, callbackQueue: DispatchQueue(label: "test.volatile"), minimumInterval: 0, debounce: 0)
        volatile.onChange = volatileState.append
        volatile.select(a, enabled: true, automatic: true)
        volatileProvider.item(0).completion(.success(.found(LyricsMatch(lrc: lrc, providerID: 9))))
        let volatileResult = volatileState.wait { $0.status == .automatic }
        check(volatileResult.document != nil && volatileResult.storageWarning, "Storage failures retain session fallback and visible warning")
        for service in [consent, race, manual, reloaded, negative, restart, expired, disable, throttled, debounced, rate, rateRestart, staleRate, incomplete, recovery, negativeRecovery, volatile] {
            service.select(nil, enabled: false, automatic: false)
        }
        print("PASS: \(checks) lyrics service checks")
    }
}
