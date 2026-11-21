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
        for url in ["http://lrclib.net/api/get", "https://evil.test/api/get", "https://lrclib.net/api/publish",
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
        check(fake.requests.count == 1 && fake.limits == [LRCLIBProvider.maximumResponseBytes], "an exact match makes one bounded request")
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

        // Search fallback: the same song filed under another release.
        check(LRCLIBProvider.isAllowedURL(LRCLIBProvider.searchEndpoint), "search endpoint allowed")
        check(!LRCLIBProvider.isAllowedURL(LRCLIBProvider.searchEndpoint, endpoint: LRCLIBProvider.endpoint) &&
              !LRCLIBProvider.isAllowedURL(LRCLIBProvider.endpoint, endpoint: LRCLIBProvider.searchEndpoint),
              "a response must come from the endpoint that was asked")
        let searchRequest = try LRCLIBProvider.makeSearchRequest(for: special)
        let searchQuery = URLComponents(url: searchRequest.url!, resolvingAgainstBaseURL: false)!.queryItems!
        check(searchRequest.url!.path == "/api/search" && searchQuery.map(\.name) == ["track_name", "artist_name"],
              "search sends title and artist only")
        check(!searchRequest.url!.absoluteString.contains(special.id) && searchRequest.httpMethod == "GET" &&
              searchRequest.value(forHTTPHeaderField: "Authorization") == nil, "search is the same read-only request")
        check(LRCLIBProvider.looseMetadata("Cloud Lights (Live)") == LRCLIBProvider.looseMetadata("cloud  lights - LIVE"),
              "punctuation around a version label ignored")
        check(LRCLIBProvider.looseMetadata("A & B") == LRCLIBProvider.looseMetadata("A, B"), "artist separators ignored")
        check(LRCLIBProvider.looseMetadata("Cloud Lights (Live)") != LRCLIBProvider.looseMetadata("Cloud Lights"),
              "the version label itself still counts")
        check(LRCLIBProvider.looseMetadata("Beyoncé") != LRCLIBProvider.looseMetadata("Beyonce") &&
              LRCLIBProvider.looseMetadata("音乐！") == "音乐" && LRCLIBProvider.looseMetadata("?!") == "",
              "letters of any script kept; diacritics retained")
        func found(_ changes: [[String: Any]], status: Int = 200, otherwise: LyricsFetchOutcome = .notFound,
                   raw: Data? = nil) throws -> LyricsFetchOutcome {
            let records = changes.map { base.merging($0) { _, replacement in replacement } }
            let response = HTTPURLResponse(url: LRCLIBProvider.searchEndpoint, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            return try LRCLIBProvider.searchOutcome(
                for: LyricsHTTPResponse(data: try raw ?? JSONSerialization.data(withJSONObject: records), response: response),
                track: track, otherwise: otherwise)
        }
        let other = "[00:01.00]Another release"
        let otherAlbum = try found([["id": 8, "albumName": "Evening Sessions - Single", "syncedLyrics": other]])
        check(otherAlbum == .found(LyricsMatch(lrc: other, providerID: 8)), "another release of the same song accepted")
        let punctuation = try found([["id": 9, "trackName": "Cloud Lights - Live", "artistName": "THE EXAMPLE",
                                      "albumName": NSNull(), "syncedLyrics": other]])
        check(punctuation == .found(LyricsMatch(lrc: other, providerID: 9)), "title punctuation and missing album tolerated")
        for changes: [String: Any] in [
            ["trackName": "Cloud Lights"], ["trackName": "Cloud Lights (Remastered)"], ["artistName": "Other Artist"],
            ["artistName": "The Example feat. Guest"], ["duration": track.duration + 2.001], ["duration": NSNull()],
            ["id": 0], ["trackName": NSNull()], ["instrumental": true], ["syncedLyrics": NSNull()],
            ["syncedLyrics": "Untimed test lyrics"], ["syncedLyrics": "[09:00]Wrong duration"]
        ] {
            let kept = try found([changes], otherwise: .rejected)
            check(kept == .rejected, "a different song, version or untimed record keeps the exact outcome")
        }
        let ranked = try found([
            ["id": 30, "albumName": "Other", "duration": track.duration + 1.5, "syncedLyrics": "[00:01.00]Far"],
            ["id": 31, "albumName": "Other", "duration": track.duration + 0.5, "syncedLyrics": "[00:01.00]Near"],
            ["id": 32, "albumName": "evening sessions!", "duration": track.duration + 2, "syncedLyrics": "[00:01.00]Album"],
            ["id": 33, "trackName": "Something Else", "syncedLyrics": "[00:01.00]Wrong"]
        ])
        check(ranked == .found(LyricsMatch(lrc: "[00:01.00]Album", providerID: 32)), "same album preferred")
        let nearest = try found([
            ["id": 41, "albumName": "Other", "duration": track.duration + 1.5, "syncedLyrics": "[00:01.00]Far"],
            ["id": 40, "albumName": "Other", "duration": track.duration - 0.5, "syncedLyrics": "[00:01.00]Near"],
            ["id": 39, "albumName": "Third", "duration": track.duration + 0.5, "syncedLyrics": "[00:01.00]Tie"]
        ])
        check(nearest == .found(LyricsMatch(lrc: "[00:01.00]Tie", providerID: 39)), "then nearest duration, then lowest ID")
        let lossy = try found([], raw: Data("[{\"id\":\"bad\"},\(String(data: try JSONSerialization.data(withJSONObject: base.merging(["albumName": "Other"]) { _, new in new }), encoding: .utf8)!)]".utf8))
        check(lossy == exact, "a malformed record does not hide the others")
        let empty = try found([], otherwise: .noTimedLyrics)
        let absent = try found([], status: 404, otherwise: .rejected)
        check(empty == .noTimedLyrics && absent == .rejected, "no candidates keeps the exact outcome")
        fails(.invalidResponse) { _ = try found([], raw: Data("{}".utf8)) }
        fails(.rateLimited(retryAfter: 60)) { _ = try found([], status: 429) }
        fails(.http(status: 500, retryAfter: nil)) { _ = try found([], status: 500) }
        fails(.invalidResponse) {
            _ = try LRCLIBProvider.searchOutcome(for: payload(), track: track, otherwise: .notFound)
        }
        check(LRCLIBProvider.searchesAfter(.notFound) && LRCLIBProvider.searchesAfter(.rejected) &&
              LRCLIBProvider.searchesAfter(.noTimedLyrics) && !LRCLIBProvider.searchesAfter(.instrumental) &&
              !LRCLIBProvider.searchesAfter(exact), "only a miss searches")

        // Two-step fetch through an injected transport.
        final class ScriptedTransport: LyricsHTTPTransport {
            var replies: [Result<LyricsHTTPResponse, Error>]
            var requests: [URLRequest] = []
            var limits: [Int] = []
            var tokens: [FakeLyricsRequest] = []
            var pending: ((Result<LyricsHTTPResponse, Error>) -> Void)?
            var repeats = 1
            init(_ replies: [Result<LyricsHTTPResponse, Error>]) { self.replies = replies }
            func send(_ request: URLRequest, maximumResponseBytes: Int,
                      completion: @escaping (Result<LyricsHTTPResponse, Error>) -> Void) -> LyricsRequest {
                requests.append(request); limits.append(maximumResponseBytes)
                let token = FakeLyricsRequest(); tokens.append(token)
                if replies.isEmpty { pending = completion }
                else { let reply = replies.removeFirst(); for _ in 0..<repeats { completion(reply) } }
                return token
            }
        }
        func searchPayload(_ records: [[String: Any]], status: Int = 200) throws -> LyricsHTTPResponse {
            LyricsHTTPResponse(data: try JSONSerialization.data(withJSONObject: records.map { base.merging($0) { _, new in new } }),
                response: HTTPURLResponse(url: LRCLIBProvider.searchEndpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        func run(_ scripted: ScriptedTransport) -> Result<LyricsFetchOutcome, Error>? {
            var result: Result<LyricsFetchOutcome, Error>?
            var count = 0
            LRCLIBProvider(transport: scripted, callbackQueue: callbackQueue).fetch(for: track) { result = $0; count += 1 }
            callbackQueue.sync {}
            precondition(count <= 1, "completion delivered more than once")
            return result
        }
        let single = [["id": 8, "albumName": "Evening Sessions - Single", "syncedLyrics": other]]
        for first in [try payload(status: 404), try payload(["albumName": "Wrong album"]), try payload(["syncedLyrics": NSNull()])] {
            let scripted = ScriptedTransport([.success(first), .success(try searchPayload(single))])
            scripted.repeats = 2
            let result = run(scripted)
            check((try? result?.get()) == otherAlbum, "a miss falls back to the search result")
            check(scripted.requests.map { $0.url!.path } == ["/api/get", "/api/search"] &&
                  scripted.limits == [LRCLIBProvider.maximumResponseBytes, LRCLIBProvider.maximumSearchResponseBytes],
                  "exactly one search, even if the transport completes twice")
        }
        let instrumentalOnly = ScriptedTransport([.success(try payload(["instrumental": true, "syncedLyrics": NSNull()]))])
        check((try? run(instrumentalOnly)?.get()) == .instrumental && instrumentalOnly.requests.count == 1, "an instrumental does not search")
        let nothing = ScriptedTransport([.success(try payload(status: 404)), .success(try searchPayload([]))])
        check((try? run(nothing)?.get()) == .notFound, "an empty search stays not found")
        let oversized = ScriptedTransport([.success(try payload(["albumName": "Wrong album"])), .failure(LRCLIBError.responseTooLarge)])
        check((try? run(oversized)?.get()) == .rejected, "an oversized search keeps the exact outcome")
        let limited = ScriptedTransport([.success(try payload(status: 404)), .success(try searchPayload([], status: 429))])
        if case .failure(let error)? = run(limited) { check(error as? LRCLIBError == .rateLimited(retryAfter: 60), "search rate limit reported") }
        else { preconditionFailure("search rate limit hidden") }
        let offline = ScriptedTransport([.success(try payload(status: 404)), .failure(URLError(.timedOut))])
        if case .failure(let error)? = run(offline) { check((error as? URLError)?.code == .timedOut, "search transport error reported") }
        else { preconditionFailure("search transport error hidden") }
        let slow = ScriptedTransport([.success(try payload(status: 404))])
        var late = 0
        let slowFetch = LRCLIBProvider(transport: slow, callbackQueue: callbackQueue).fetch(for: track) { _ in late += 1 }
        check(slow.requests.count == 2 && slow.pending != nil, "search in flight")
        slowFetch.cancel()
        check(slow.tokens[1].cancelled, "cancellation reaches the search request")
        slow.pending?(.success(try searchPayload(single)))
        callbackQueue.sync {}
        check(late == 0, "late cancelled search ignored")

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
