import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol LyricsRequest {
    func cancel()
}

protocol LyricsProviding {
    @discardableResult
    func fetch(for track: MusicTrack,
               completion: @escaping (Result<LyricsFetchOutcome, Error>) -> Void) -> LyricsRequest
}

struct LyricsMatch: Equatable {
    let lrc: String
    let providerID: Int
}

enum LyricsFetchOutcome: Equatable {
    case found(LyricsMatch), notFound, instrumental, noTimedLyrics, rejected
}

enum LRCLIBError: Error, Equatable {
    case invalidMetadata, invalidResponse, responseTooLarge, redirectNotAllowed
    case rateLimited(retryAfter: TimeInterval)
    case http(status: Int, retryAfter: TimeInterval?)

    /// The coordinator, not the provider, owns retries and global throttling.
    var retryAfter: TimeInterval? {
        switch self {
        case .rateLimited(let delay): return delay
        case .http(_, let delay): return delay
        default: return nil
        }
    }
}

struct LyricsHTTPResponse {
    let data: Data
    let response: HTTPURLResponse
}

/// Injectable to keep tests independent of the live service.
protocol LyricsHTTPTransport {
    @discardableResult
    func send(_ request: URLRequest, maximumResponseBytes: Int,
              completion: @escaping (Result<LyricsHTTPResponse, Error>) -> Void) -> LyricsRequest
}

struct LRCLIBRecord: Decodable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let instrumental: Bool
    let syncedLyrics: String?
}

/// Read-only, no-key lookup. No search, upload, authentication or automatic retry.
/// Official contract: https://github.com/tranxuanthang/lrclib/blob/main/server/src/routes/get_lyrics_by_metadata.rs
final class LRCLIBProvider: LyricsProviding {
    static let endpoint = URL(string: "https://lrclib.net/api/get")!
    static let maximumResponseBytes = 1_048_576
    static let timeout: TimeInterval = 12
    static let userAgent = "StarryNight/0.3.0 (https://github.com/Rosemary1812/starry-night-wallpaper)"
    static let durationTolerance: TimeInterval = 2

    private let transport: LyricsHTTPTransport
    private let callbackQueue: DispatchQueue
    private let now: () -> Date

    /// Completion is always asynchronous on callbackQueue (main by default),
    /// at most once. Cancellation suppresses callbacks not already executing.
    /// The transport and all parsing run off the main queue in production.
    init(transport: LyricsHTTPTransport = LRCLIBURLSessionTransport(),
         callbackQueue: DispatchQueue = .main, now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.callbackQueue = callbackQueue
        self.now = now
    }

    @discardableResult
    func fetch(for track: MusicTrack,
               completion: @escaping (Result<LyricsFetchOutcome, Error>) -> Void) -> LyricsRequest {
        let task = LyricsFetchTask(queue: callbackQueue, completion: completion)
        let request: URLRequest
        do { request = try Self.makeRequest(for: track) }
        catch {
            task.finish(.failure(error))
            return task
        }
        let clock = now
        let underlying = transport.send(request, maximumResponseBytes: Self.maximumResponseBytes) { result in
            let mapped = result.flatMap { response -> Result<LyricsFetchOutcome, Error> in
                do { return .success(try Self.outcome(for: response, track: track, now: clock())) }
                catch { return .failure(error) }
            }
            task.finish(mapped)
        }
        task.install(underlying)
        return task
    }

    /// Only canonical Unicode, case and whitespace normalization. In particular,
    /// punctuation, diacritics, featuring credits and live/remaster labels survive.
    static func normalizedMetadata(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
    }

    static func hasUsableMetadata(_ track: MusicTrack) -> Bool {
        // The official endpoint accepts duration in this range. Do not send
        // incomplete metadata or substitute a guessed duration/album.
        track.duration.isFinite && (1...3600).contains(track.duration) &&
            [track.title, track.artist, track.album].allSatisfy {
                !normalizedMetadata($0).isEmpty && $0.utf8.count <= 4096
            }
    }

    static func makeRequest(for track: MusicTrack) throws -> URLRequest {
        guard hasUsableMetadata(track) else { throw LRCLIBError.invalidMetadata }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(track.duration))
        ]
        // application/x-www-form-urlencoded servers interpret a literal '+'
        // as a space, even though URLComponents permits it in query values.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw LRCLIBError.invalidMetadata }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func strictlyMatches(_ record: LRCLIBRecord, track: MusicTrack) -> Bool {
        guard hasUsableMetadata(track), record.id > 0,
              let title = record.trackName, let artist = record.artistName,
              let album = record.albumName, let duration = record.duration,
              duration.isFinite, duration > 0,
              abs(duration - track.duration) <= durationTolerance else { return false }
        return zip([title, artist, album], [track.title, track.artist, track.album]).allSatisfy {
            let remote = normalizedMetadata($0.0)
            return !remote.isEmpty && remote == normalizedMetadata($0.1)
        }
    }

    static func outcome(for payload: LyricsHTTPResponse, track: MusicTrack,
                        now: Date = Date()) throws -> LyricsFetchOutcome {
        guard payload.data.count <= maximumResponseBytes else { throw LRCLIBError.responseTooLarge }
        // Recheck the destination even for injected transports.
        guard let url = payload.response.url, isAllowedURL(url) else { throw LRCLIBError.invalidResponse }
        let status = payload.response.statusCode
        let retry = retryAfter(payload.response.value(forHTTPHeaderField: "Retry-After"), now: now)
        if status == 404 { return .notFound }
        if status == 429 { throw LRCLIBError.rateLimited(retryAfter: retry ?? 60) }
        if (300...399).contains(status) { throw LRCLIBError.redirectNotAllowed }
        guard status == 200 else { throw LRCLIBError.http(status: status, retryAfter: retry) }
        let record: LRCLIBRecord
        do { record = try JSONDecoder().decode(LRCLIBRecord.self, from: payload.data) }
        catch { throw LRCLIBError.invalidResponse }
        guard strictlyMatches(record, track: track) else { return .rejected }
        if record.instrumental { return .instrumental }
        guard let lrc = record.syncedLyrics,
              !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noTimedLyrics }
        let document = LyricsDocument(lrc: lrc)
        guard document.lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return .noTimedLyrics }
        guard document.lines.count <= 20_000,
              document.lines.allSatisfy({ $0.time.isFinite && $0.time >= 0 &&
                  $0.time <= track.duration + durationTolerance }) else { return .rejected }
        return .found(LyricsMatch(lrc: lrc, providerID: record.id))
    }

    static func isAllowedURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "lrclib.net" &&
            (url.port == nil || url.port == 443) && url.path == "/api/get" &&
            url.user == nil && url.password == nil && url.fragment == nil
    }

    /// HTTP Retry-After supports whole delta-seconds and the three HTTP-date
    /// representations. Invalid headers use the coordinator's normal backoff.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.utf8.count <= 128 else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }),
           let seconds = TimeInterval(value), seconds.isFinite { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(0, date.timeIntervalSince(now))
            }
        }
        return nil
    }
}

private final class LyricsFetchTask: LyricsRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    private var underlying: LyricsRequest?
    private let queue: DispatchQueue
    private let completion: (Result<LyricsFetchOutcome, Error>) -> Void

    init(queue: DispatchQueue, completion: @escaping (Result<LyricsFetchOutcome, Error>) -> Void) {
        self.queue = queue
        self.completion = completion
    }

    func install(_ request: LyricsRequest) {
        lock.lock()
        let shouldCancel = cancelled || finished
        if !shouldCancel { underlying = request }
        lock.unlock()
        if shouldCancel { request.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = underlying
        underlying = nil
        lock.unlock()
        request?.cancel()
    }

    func finish(_ result: Result<LyricsFetchOutcome, Error>) {
        lock.lock()
        guard !cancelled && !finished else { lock.unlock(); return }
        finished = true
        underlying = nil
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            let deliver = !cancelled
            lock.unlock()
            if deliver { completion(result) }
        }
    }
}

/// A fresh ephemeral session per lookup avoids shared cookies, credentials and
/// HTTP caches. The delegate bounds bytes while streaming, not after buffering.
final class LRCLIBURLSessionTransport: LyricsHTTPTransport {
    private let protocolClasses: [AnyClass]?

    /// URLProtocol substitution is for offline tests; production uses the
    /// system HTTPS implementation with the fixed configuration below.
    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = LRCLIBProvider.timeout
        configuration.timeoutIntervalForResource = LRCLIBProvider.timeout + 3
        configuration.httpMaximumConnectionsPerHost = 1
        return configuration
    }

    @discardableResult
    func send(_ request: URLRequest, maximumResponseBytes: Int,
              completion: @escaping (Result<LyricsHTTPResponse, Error>) -> Void) -> LyricsRequest {
        let operation = LRCLIBHTTPOperation(limit: min(max(1, maximumResponseBytes), LRCLIBProvider.maximumResponseBytes),
                                           completion: completion)
        let configuration = Self.sessionConfiguration()
        if let protocolClasses = protocolClasses { configuration.protocolClasses = protocolClasses }
        operation.start(request, configuration: configuration)
        return operation
    }
}

private final class LRCLIBHTTPOperation: NSObject, LyricsRequest, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var response: HTTPURLResponse?
    private var session: URLSession?
    private var expectedURL: URL?
    private var completion: ((Result<LyricsHTTPResponse, Error>) -> Void)?

    init(limit: Int, completion: @escaping (Result<LyricsHTTPResponse, Error>) -> Void) {
        self.limit = limit
        self.completion = completion
    }

    func start(_ request: URLRequest, configuration: URLSessionConfiguration) {
        guard let url = request.url, LRCLIBProvider.isAllowedURL(url), request.httpMethod == "GET" else {
            finish(.failure(LRCLIBError.invalidResponse))
            return
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        expectedURL = url
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() { finish(.failure(URLError(.cancelled))) }

    private func finish(_ result: Result<LyricsHTTPResponse, Error>) {
        lock.lock()
        let callback = completion
        completion = nil
        let activeSession = session
        session = nil
        data = Data()
        lock.unlock()
        activeSession?.invalidateAndCancel()
        callback?(result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == expectedURL else {
            completionHandler(.cancel)
            finish(.failure(LRCLIBError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(LRCLIBError.responseTooLarge))
            return
        }
        lock.lock()
        let active = completion != nil
        if active { self.response = http }
        lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard completion != nil else { lock.unlock(); return }
        let tooLarge = chunk.count > limit - data.count
        if !tooLarge { data.append(chunk) }
        lock.unlock()
        if tooLarge { finish(.failure(LRCLIBError.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)); return }
        lock.lock()
        let payload = response.map { LyricsHTTPResponse(data: data, response: $0) }
        lock.unlock()
        if let payload = payload { finish(.success(payload)) }
        else { finish(.failure(LRCLIBError.invalidResponse)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(LRCLIBError.redirectNotAllowed))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Self.handle(challenge, completion: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        Self.handle(challenge, completion: completionHandler)
    }

    private static func handle(_ challenge: URLAuthenticationChallenge,
                               completion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default TLS certificate verification only. Never supply credentials.
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completion(.performDefaultHandling, nil)
        } else {
            completion(.cancelAuthenticationChallenge, nil)
        }
        #else
        // FoundationNetworking verifies TLS in its backend and only exposes
        // non-server-trust challenges here.
        completion(.cancelAuthenticationChallenge, nil)
        #endif
    }
}
