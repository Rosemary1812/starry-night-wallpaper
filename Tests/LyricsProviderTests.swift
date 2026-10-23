import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FakeLyricsRequest: LyricsRequest {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}

private final class FakeLyricsTransport: LyricsHTTPTransport {
    var requests: [URLRequest] = []
    var limits: [Int] = []
    var completion: ((Result<LyricsHTTPResponse, Error>) -> Void)?
    var immediate: Result<LyricsHTTPResponse, Error>?
    var duplicateImmediate = false
    let token = FakeLyricsRequest()

    func send(_ request: URLRequest, maximumResponseBytes: Int,
              completion: @escaping (Result<LyricsHTTPResponse, Error>) -> Void) -> LyricsRequest {
        requests.append(request)
        limits.append(maximumResponseBytes)
        self.completion = completion
        if let immediate = immediate {
            completion(immediate)
            if duplicateImmediate { completion(immediate) }
        }
        return token
    }
}

/// Exercises real URLSession delegate delivery and streaming limits without
/// accessing the network or requesting any copyrighted lyrics.
private final class StubLyricsURLProtocol: URLProtocol {
    static var status = 200
    static var headers = [String: String]()
    static var chunks = [Data]()
    static var shouldFinish = true
    static var started: DispatchSemaphore?
    static var stopped: DispatchSemaphore?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for data in Self.chunks { client?.urlProtocol(self, didLoad: data) }
        Self.started?.signal()
        if Self.shouldFinish { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.stopped?.signal() }
}

@main enum LyricsProviderTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            checks += 1
        }
        let track = MusicTrack(id: "local-only-id", title: "Cloud Lights (Live)", artist: "The Example",
                               album: "Evening Sessions", duration: 180.25)
        // Invented test lyrics, never retrieved from a third party.
        let lrc = "[00:00.00]Test line one\n[00:02.50]Test line two"
        let base: [String: Any] = ["id": 7, "trackName": track.title, "artistName": track.artist,
                                  "albumName": track.album, "duration": track.duration,
                                  "instrumental": false, "syncedLyrics": lrc]
        func payload(_ changes: [String: Any] = [:], status: Int = 200,
                     headers: [String: String] = [:], url: URL = LRCLIBProvider.endpoint) throws -> LyricsHTTPResponse {
            let values = base.merging(changes) { _, replacement in replacement }
            return LyricsHTTPResponse(data: try JSONSerialization.data(withJSONObject: values),
                response: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
        func outcome(_ changes: [String: Any] = [:]) throws -> LyricsFetchOutcome {
            try LRCLIBProvider.outcome(for: payload(changes), track: track)
        }
        func fails(_ expected: LRCLIBError, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected \(expected)") }
            catch { check(error as? LRCLIBError == expected, "specific failure \(expected)") }
        }

        let exact = try outcome()
        check(exact == .found(LyricsMatch(lrc: lrc, providerID: 7)), "exact synchronized match")
        let normalized = try outcome(["trackName": "  CLOUD  LIGHTS (LIVE) \n", "artistName": "the example"])
        check(normalized == exact, "conservative case and whitespace normalization")
        check(LRCLIBProvider.normalizedMetadata("Cafe\u{301}") == LRCLIBProvider.normalizedMetadata("CAFÉ"), "canonical Unicode")
        check(LRCLIBProvider.normalizedMetadata("Beyoncé") != LRCLIBProvider.normalizedMetadata("Beyonce"), "diacritics retained")
        for changes: [String: Any] in [
            ["trackName": "Cloud Lights"], ["trackName": "Cloud Lights (Remastered)"],
            ["trackName": "Cloud Lights Live"], ["artistName": "The Example feat. Guest"],
            ["artistName": "Other Artist"], ["albumName": "Evening Sessions (Deluxe)"],
            ["trackName": NSNull()], ["artistName": ""], ["albumName": "   "],
            ["albumName": NSNull()], ["duration": NSNull()], ["duration": 0], ["id": 0],
            ["duration": track.duration + 2.001], ["duration": track.duration - 2.001]
        ] {
            let rejected = try outcome(changes)
            check(rejected == .rejected, "mismatched or incomplete metadata rejected")
        }
        let upper = try outcome(["duration": track.duration + 2])
        let lower = try outcome(["duration": track.duration - 2])
        check(upper == exact && lower == exact, "two-second duration boundaries inclusive")
        for duration in [Double.nan, Double.infinity, -Double.infinity] {
            let record = LRCLIBRecord(id: 7, trackName: track.title, artistName: track.artist,
                                     albumName: track.album, duration: duration,
                                     instrumental: false, syncedLyrics: lrc)
            check(!LRCLIBProvider.strictlyMatches(record, track: track), "nonfinite remote duration rejected")
        }
        let instrumental = try outcome(["instrumental": true, "syncedLyrics": NSNull()])
        check(instrumental == .instrumental, "instrumental distinct")
        let mismatchedInstrumental = try outcome(["instrumental": true, "albumName": "Wrong album"])
        check(mismatchedInstrumental == .rejected, "metadata validated before instrumental")
        for value: Any in [NSNull(), "", "  \n", "Untimed test lyrics", "[ar:Test]\n[00:70]Bad stamp", "[00:00]  "] {
            let untimed = try outcome(["syncedLyrics": value])
            check(untimed == .noTimedLyrics, "only meaningful parsed timed lines accepted")
        }
        let outsideDuration = try outcome(["syncedLyrics": "[09:00]Wrong duration"])
        check(outsideDuration == .rejected, "timing outside track rejected")
        let huge = LyricsHTTPResponse(data: Data(repeating: 0, count: LRCLIBProvider.maximumResponseBytes + 1),
                                     response: try payload().response)
        fails(.responseTooLarge) { _ = try LRCLIBProvider.outcome(for: huge, track: track) }
        let malformed = LyricsHTTPResponse(data: Data("not json".utf8), response: try payload().response)
        fails(.invalidResponse) { _ = try LRCLIBProvider.outcome(for: malformed, track: track) }
        fails(.invalidResponse) { _ = try LRCLIBProvider.outcome(for: payload(["instrumental": "no"]), track: track) }
        let missing = try LRCLIBProvider.outcome(for: payload(status: 404), track: track)
        check(missing == .notFound, "404 distinct from service error")
        for status in [301, 302, 307, 308] {
            fails(.redirectNotAllowed) { _ = try LRCLIBProvider.outcome(for: payload(status: status), track: track) }
        }
        fails(.rateLimited(retryAfter: 123)) {
            _ = try LRCLIBProvider.outcome(for: payload(status: 429, headers: ["Retry-After": "123"]), track: track)
        }
        fails(.rateLimited(retryAfter: 60)) { _ = try LRCLIBProvider.outcome(for: payload(status: 429), track: track) }
        fails(.http(status: 503, retryAfter: 1)) {
            _ = try LRCLIBProvider.outcome(for: payload(status: 503, headers: ["Retry-After": "1"]), track: track)
        }
        for status in [400, 401, 403, 500, 204] {
            fails(.http(status: status, retryAfter: nil)) { _ = try LRCLIBProvider.outcome(for: payload(status: status), track: track) }
        }
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        check(LRCLIBProvider.retryAfter("Tue, 14 Nov 2023 22:15:20 GMT", now: clock) == 120, "HTTP-date retry delay")
        check(LRCLIBProvider.retryAfter("Tue, 14 Nov 2023 22:11:20 GMT", now: clock) == 0, "past retry date")
        for value in ["-1", "NaN", "infinity", "1.5", "not a date", ""] {
            check(LRCLIBProvider.retryAfter(value, now: clock) == nil, "invalid Retry-After ignored")
        }

        let special = MusicTrack(id: "NEVER-SEND-ID", title: "A+B & C? #音乐", artist: "D/E", album: "F=G", duration: 123.456)
        let request = try LRCLIBProvider.makeRequest(for: special)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        check(query.count == 4, "only necessary metadata transmitted")
        check(query.first { $0.name == "track_name" }?.value == special.title, "metadata query escaped")
        check(request.url!.absoluteString.contains("%2B"), "literal plus encoded for form-query decoding")
        check(!request.url!.absoluteString.contains(special.id), "Music persistent ID never transmitted")
        check(request.httpMethod == "GET" && request.httpBody == nil, "read-only GET")
        check(request.value(forHTTPHeaderField: "User-Agent") == LRCLIBProvider.userAgent, "app User-Agent")
        check(request.value(forHTTPHeaderField: "Authorization") == nil, "no API key or auth")
        check(!request.httpShouldHandleCookies && request.timeoutInterval == 12, "request privacy and timeout")
        for duration in [0, -1, Double.nan, Double.infinity, 0.99, 3600.01] {
            let invalid = MusicTrack(id: "x", title: "Title", artist: "Artist", album: "Album", duration: duration)
            fails(.invalidMetadata) { _ = try LRCLIBProvider.makeRequest(for: invalid) }
        }
        let missingAlbum = MusicTrack(id: "x", title: "Title", artist: "Artist", album: " \n", duration: 100)
        fails(.invalidMetadata) { _ = try LRCLIBProvider.makeRequest(for: missingAlbum) }
        for invalid in [MusicTrack(id: "x", title: "", artist: "Artist", album: "Album", duration: 100),
                        MusicTrack(id: "x", title: "Title", artist: " \n", album: "Album", duration: 100),
                        MusicTrack(id: "x", title: String(repeating: "x", count: 4097), artist: "Artist", album: "Album", duration: 100)] {
            fails(.invalidMetadata) { _ = try LRCLIBProvider.makeRequest(for: invalid) }
        }
        for url in ["http://lrclib.net/api/get", "https://evil.test/api/get", "https://lrclib.net/api/search",
                    "https://user:password@lrclib.net/api/get", "https://lrclib.net:8080/api/get", "https://lrclib.net/api/get#fragment"] {
            check(!LRCLIBProvider.isAllowedURL(URL(string: url)!), "destination constraint")
        }
        fails(.invalidResponse) {
            _ = try LRCLIBProvider.outcome(for: payload(url: URL(string: "https://evil.test/api/get")!), track: track)
        }

        let configuration = LRCLIBURLSessionTransport.sessionConfiguration()
        check(configuration.urlCache == nil, "no HTTP disk or memory cache")
        check(configuration.httpCookieStorage == nil && !configuration.httpShouldSetCookies, "no cookie storage")
        check(configuration.urlCredentialStorage == nil, "no shared credentials")
        check(configuration.timeoutIntervalForRequest == 12 && configuration.timeoutIntervalForResource == 15, "bounded timeouts")

        let callbackQueue = DispatchQueue(label: "LyricsProviderTests.callback")
        let key = DispatchSpecificKey<String>()
        callbackQueue.setSpecific(key: key, value: "callback")
        let fake = FakeLyricsTransport()
        fake.immediate = .success(try payload())
        fake.duplicateImmediate = true
        let provider = LRCLIBProvider(transport: fake, callbackQueue: callbackQueue)
        var callbacks = 0
        callbackQueue.sync {
            provider.fetch(for: track) { result in
                precondition(DispatchQueue.getSpecific(key: key) == "callback", "configured callback queue")
                precondition(try! result.get() == exact)
                callbacks += 1
            }
            check(callbacks == 0, "completion never synchronous even for immediate transport")
        }
        callbackQueue.sync {}
        check(callbacks == 1, "duplicate transport completion suppressed")
        check(fake.requests.count == 1 && fake.limits == [LRCLIBProvider.maximumResponseBytes], "one bounded request; no search fallback")
        let invalidFake = FakeLyricsTransport()
        let invalidProvider = LRCLIBProvider(transport: invalidFake, callbackQueue: callbackQueue)
        let invalidDone = DispatchSemaphore(value: 0)
        invalidProvider.fetch(for: missingAlbum) { result in
            if case .failure(let error) = result { precondition(error as? LRCLIBError == .invalidMetadata) }
            else { preconditionFailure("Missing album accepted") }
            invalidDone.signal()
        }
        check(invalidDone.wait(timeout: .now() + 2) == .success && invalidFake.requests.isEmpty, "invalid metadata performs no network request")
        let cancelledFake = FakeLyricsTransport()
        let cancelledProvider = LRCLIBProvider(transport: cancelledFake, callbackQueue: callbackQueue)
        let cancelled = cancelledProvider.fetch(for: track) { _ in callbacks += 1 }
        cancelled.cancel()
        check(cancelledFake.token.cancelled, "cancellation reaches transport")
        cancelledFake.completion?(.success(try payload()))
        callbackQueue.sync {}
        check(callbacks == 1, "late cancelled response ignored")
        callbackQueue.suspend()
        let queued = provider.fetch(for: track) { _ in callbacks += 1 }
        queued.cancel()
        callbackQueue.resume()
        callbackQueue.sync {}
        check(callbacks == 1, "cancellation also suppresses queued completion")
        let errorFake = FakeLyricsTransport()
        errorFake.immediate = .failure(URLError(.timedOut))
        let errorProvider = LRCLIBProvider(transport: errorFake, callbackQueue: callbackQueue)
        let errorDone = DispatchSemaphore(value: 0)
        errorProvider.fetch(for: track) { result in
            if case .failure(let error) = result { precondition((error as? URLError)?.code == .timedOut) }
            else { preconditionFailure("Network error hidden") }
            errorDone.signal()
        }
        check(errorDone.wait(timeout: .now() + 2) == .success, "transport errors preserved")

        // Real URLSession delegate path, entirely intercepted by URLProtocol.
        let transport = LRCLIBURLSessionTransport(protocolClasses: [StubLyricsURLProtocol.self])
        func transportResult(limit: Int) -> Result<LyricsHTTPResponse, Error> {
            let done = DispatchSemaphore(value: 0)
            var result: Result<LyricsHTTPResponse, Error>?
            let task = transport.send(request, maximumResponseBytes: limit) {
                result = $0
                done.signal()
            }
            precondition(done.wait(timeout: .now() + 5) == .success, "Stub URLSession timed out")
            withExtendedLifetime(task) {}
            return result!
        }
        StubLyricsURLProtocol.chunks = [Data("first".utf8), Data("second".utf8)]
        let combined = try transportResult(limit: 11).get()
        check(String(data: combined.data, encoding: .utf8) == "firstsecond", "streamed response collected")
        fails(.responseTooLarge) { _ = try transportResult(limit: 10).get() }
        StubLyricsURLProtocol.headers = ["Content-Length": "1000"]
        StubLyricsURLProtocol.chunks = []
        fails(.responseTooLarge) { _ = try transportResult(limit: 10).get() }
        StubLyricsURLProtocol.headers = [:]
        StubLyricsURLProtocol.chunks = []
        StubLyricsURLProtocol.shouldFinish = false
        StubLyricsURLProtocol.started = DispatchSemaphore(value: 0)
        StubLyricsURLProtocol.stopped = DispatchSemaphore(value: 0)
        let cancelDone = DispatchSemaphore(value: 0)
        let inFlight = transport.send(request, maximumResponseBytes: 100) { result in
            if case .failure(let error) = result { precondition((error as? URLError)?.code == .cancelled) }
            else { preconditionFailure("Cancellation succeeded") }
            cancelDone.signal()
        }
        check(StubLyricsURLProtocol.started!.wait(timeout: .now() + 5) == .success, "in-flight request started")
        inFlight.cancel()
        check(cancelDone.wait(timeout: .now() + 2) == .success, "in-flight cancellation completes once")
        check(StubLyricsURLProtocol.stopped!.wait(timeout: .now() + 5) == .success, "URLSession request actually stopped")
        print("PASS: \(checks) lyrics provider checks (offline; no live service requests)")
    }
}
