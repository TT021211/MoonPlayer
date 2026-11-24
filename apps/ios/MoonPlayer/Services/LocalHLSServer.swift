import CryptoKit
import Foundation
import Network

/// 手机本地 HLS 缓存：
/// - 在 127.0.0.1 起一个极简 HTTP 服务给 AVPlayer 用；
/// - 播放列表重写成相对 hash，分片/密钥边下边存到 Caches；
/// - 播放时预取后面几片，网络抖动时直接读本地；
/// - 缓存 2GB，LRU 清理。
final class LocalHLSServer {
    static let shared = LocalHLSServer()

    private enum ResourceKind: String, Codable {
        case playlist
        case media
    }

    private struct CacheEntry: Codable {
        var url: String
        var kind: ResourceKind
        var contentType: String
        var savedAt: Double
        var size: Int
    }

    private struct CachedResource {
        let data: Data
        let contentType: String
    }

    private let queue = DispatchQueue(label: "com.tt021211.moonplayer.hls")
    private let session: URLSession
    private let cacheDir: URL
    private let indexURL: URL
    private let maxBytes: Int64 = 2 * 1024 * 1024 * 1024

    private var index: [String: CacheEntry] = [:]
    private var listener: NWListener?
    private var port: UInt16?
    private var starting = false

    private var inflight: [String: [(Result<CachedResource, Error>) -> Void]] = [:]
    private var playlistSegments: [String: [String]] = [:]
    private var segmentIndex: [String: (playlist: String, index: Int)] = [:]
    private var indexSaveItem: DispatchWorkItem?

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDir = base.appendingPathComponent("MoonPlayerHLS", isDirectory: true)
        indexURL = cacheDir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            index = decoded
        }
        cleanOrphans()
        sweepIfNeeded()
        startIfNeeded()
    }

    // MARK: - 对外

    func startIfNeeded() {
        queue.async {
            guard self.listener == nil, !self.starting else { return }
            self.starting = true

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: parameters, on: .any) else {
                self.starting = false
                return
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = listener.port?.rawValue
                    self.listener = listener
                    self.starting = false
                case .failed, .cancelled:
                    self.listener = nil
                    self.port = nil
                    self.starting = false
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
    }

    /// 为原始播放地址生成本地播放地址（相对 hash 播放列表，跨启动也能用）。
    func makePlaylistURL(for original: URL) -> URL? {
        var result: URL?
        queue.sync {
            guard let port = self.port else { return }
            let hash = Self.hash(original.absoluteString)
            register(
                hash: hash,
                url: original,
                kind: .playlist,
                contentType: "application/vnd.apple.mpegurl"
            )
            result = URL(string: "http://127.0.0.1:\(port)/r/\(hash)")
        }
        return result
    }

    /// 后台预取：下一集播放列表 + 前几片（不占当前集带宽太多，调用方控制时机）。
    func preload(for original: URL) {
        queue.async {
            guard self.port != nil else { return }
            let hash = Self.hash(original.absoluteString)
            self.register(
                hash: hash,
                url: original,
                kind: .playlist,
                contentType: "application/vnd.apple.mpegurl"
            )
            self.loadResource(hash: hash, url: original, kind: .playlist, completion: nil)
        }
    }

    var cacheSizeBytes: Int64 {
        queue.sync {
            index.values.reduce(Int64(0)) { $0 + Int64($1.size) }
        }
    }

    func clearCache() {
        queue.async {
            for key in self.index.keys {
                try? FileManager.default.removeItem(at: self.fileURL(key))
            }
            self.index.removeAll()
            self.playlistSegments.removeAll()
            self.segmentIndex.removeAll()
            self.saveIndexNow()
        }
    }

    func flushIndex() {
        queue.async { self.saveIndexNow() }
    }

    // MARK: - HTTP 服务

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(data: Data(buffer[..<range.lowerBound]), encoding: .utf8) ?? ""
                self.handleRequest(connection, header: header)
                return
            }

            if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func handleRequest(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendText(connection, status: "400 Bad Request", text: "Bad Request")
            return
        }

        let method = String(parts[0]).uppercased()
        var path = String(parts[1])
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[..<queryIndex])
        }
        guard method == "GET" || method == "HEAD" else {
            sendText(connection, status: "405 Method Not Allowed", text: "Method Not Allowed")
            return
        }
        guard path.hasPrefix("/r/") else {
            sendText(connection, status: "404 Not Found", text: "Not Found")
            return
        }

        let hash = String(path.dropFirst(3))
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
            sendText(connection, status: "404 Not Found", text: "Not Found")
            return
        }

        var rangeHeader: String?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2,
               pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "range" {
                rangeHeader = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }

        serve(connection, hash: hash, method: method, rangeHeader: rangeHeader)
    }

    private func serve(_ connection: NWConnection, hash: String, method: String, rangeHeader: String?) {
        guard let entry = index[hash], let url = URL(string: entry.url) else {
            sendText(connection, status: "404 Not Found", text: "Not Found")
            return
        }

        if let cached = readCached(hash) {
            if entry.kind == .playlist {
                rebuildIndexIfNeeded(hash: hash, data: cached.data)
                prefetchFirstSegments(playlistHash: hash)
            } else {
                prefetchNext(for: hash)
            }
            send(
                connection,
                data: cached.data,
                contentType: cached.contentType,
                method: method,
                rangeHeader: rangeHeader
            )
            return
        }

        // fMP4 的 BYTERANGE 可能是同一个大文件里的不同区间：未缓存时直接透传 Range，
        // 不把整个 main.mp4 拉到手机本地。播放列表永远走完整抓取+重写。
        if method == "GET", entry.kind == .media, let rangeHeader {
            forwardRange(connection, url: url, rangeHeader: rangeHeader)
            return
        }

        loadResource(hash: hash, url: url, kind: entry.kind) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resource):
                if entry.kind == .playlist {
                    self.rebuildIndexIfNeeded(hash: hash, data: resource.data)
                }
                self.send(
                    connection,
                    data: resource.data,
                    contentType: resource.contentType,
                    method: method,
                    rangeHeader: rangeHeader
                )
            case .failure:
                self.sendText(connection, status: "502 Bad Gateway", text: "Bad Gateway")
            }
        }
    }

    private func send(
        _ connection: NWConnection,
        data: Data,
        contentType: String,
        method: String,
        rangeHeader: String?
    ) {
        let total = data.count
        var headers: [String: String] = [
            "Content-Type": contentType,
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store"
        ]

        if method == "HEAD" {
            headers["Content-Length"] = String(total)
            sendResponse(connection, status: "200 OK", headers: headers, body: nil)
            return
        }

        if let rangeHeader {
            // 播放列表不做 Range 切片，避免客户端只拿到半截 m3u8
            if contentType.lowercased().contains("mpegurl") {
                headers["Content-Length"] = String(total)
                sendResponse(connection, status: "200 OK", headers: headers, body: data)
                return
            }
            guard let range = parseRange(rangeHeader, total: total) else {
                headers["Content-Range"] = "bytes */\(total)"
                headers["Content-Length"] = "0"
                sendResponse(connection, status: "416 Range Not Satisfiable", headers: headers, body: nil)
                return
            }
            let body = data.subdata(in: range.start..<(range.end + 1))
            headers["Content-Range"] = "bytes \(range.start)-\(range.end)/\(total)"
            headers["Content-Length"] = String(body.count)
            sendResponse(connection, status: "206 Partial Content", headers: headers, body: body)
            return
        }

        headers["Content-Length"] = String(total)
        sendResponse(connection, status: "200 OK", headers: headers, body: data)
    }

    private func forwardRange(_ connection: NWConnection, url: URL, rangeHeader: String) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(rangeHeader, forHTTPHeaderField: "Range")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      let data else {
                    self.sendText(connection, status: "502 Bad Gateway", text: "Bad Gateway")
                    return
                }

                let contentType = http.value(forHTTPHeaderField: "Content-Type")
                    ?? "application/octet-stream"

                if http.statusCode == 206 {
                    var headers: [String: String] = [
                        "Content-Type": contentType,
                        "Accept-Ranges": "bytes",
                        "Cache-Control": "no-store",
                        "Content-Length": String(data.count)
                    ]
                    if let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
                        headers["Content-Range"] = contentRange
                    }
                    self.sendResponse(connection, status: "206 Partial Content", headers: headers, body: data)
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    self.sendText(connection, status: "502 Bad Gateway", text: "Bad Gateway")
                    return
                }

                let total = data.count
                if let range = self.parseRange(rangeHeader, total: total) {
                    let body = data.subdata(in: range.start..<(range.end + 1))
                    let headers: [String: String] = [
                        "Content-Type": contentType,
                        "Accept-Ranges": "bytes",
                        "Cache-Control": "no-store",
                        "Content-Range": "bytes \(range.start)-\(range.end)/\(total)",
                        "Content-Length": String(body.count)
                    ]
                    self.sendResponse(connection, status: "206 Partial Content", headers: headers, body: body)
                } else {
                    self.sendResponse(
                        connection,
                        status: "200 OK",
                        headers: [
                            "Content-Type": contentType,
                            "Content-Length": String(total),
                            "Cache-Control": "no-store"
                        ],
                        body: data
                    )
                }
            }
        }.resume()
    }

    private func sendText(_ connection: NWConnection, status: String, text: String) {        let body = Data(text.utf8)
        sendResponse(
            connection,
            status: status,
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": String(body.count),
                "Cache-Control": "no-store"
            ],
            body: body
        )
    }

    private func sendResponse(
        _ connection: NWConnection,
        status: String,
        headers: [String: String],
        body: Data?
    ) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        if let body { payload.append(body) }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func parseRange(_ header: String, total: Int) -> (start: Int, end: Int)? {
        guard total > 0, header.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            let start = max(0, total - suffix)
            return (start, total - 1)
        }

        guard let start = Int(parts[0]), start >= 0, start < total else { return nil }
        let end = parts[1].isEmpty ? total - 1 : (Int(parts[1]) ?? total - 1)
        guard end >= start else { return nil }
        return (start, min(end, total - 1))
    }

    // MARK: - 资源加载 / 缓存

    private func loadResource(
        hash: String,
        url: URL,
        kind: ResourceKind,
        completion: ((Result<CachedResource, Error>) -> Void)?
    ) {
        if let cached = readCached(hash) {
            if kind == .playlist {
                rebuildIndexIfNeeded(hash: hash, data: cached.data)
                prefetchFirstSegments(playlistHash: hash)
            } else {
                prefetchNext(for: hash)
            }
            completion?(.success(cached))
            return
        }

        if inflight[hash] != nil {
            if let completion {
                inflight[hash]?.append(completion)
            }
            return
        }
        inflight[hash] = completion.map { [$0] } ?? []

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                let http = response as? HTTPURLResponse
                let finalURL = response?.url ?? url
                let result: Result<CachedResource, Error>

                if let error {
                    result = .failure(error)
                } else if let http, !(200..<300).contains(http.statusCode) {
                    result = .failure(URLError(.badServerResponse))
                } else if let data {
                    if kind == .playlist, let text = String(data: data, encoding: .utf8) {
                        let rewritten = self.rewritePlaylist(text, baseURL: finalURL, playlistHash: hash)
                        let output = Data(rewritten.utf8)
                        let contentType = "application/vnd.apple.mpegurl"
                        self.writeCached(hash: hash, data: output, contentType: contentType, kind: .playlist, url: finalURL)
                        result = .success(CachedResource(data: output, contentType: contentType))
                        self.prefetchFirstSegments(playlistHash: hash)
                    } else {
                        let contentType = http?.value(forHTTPHeaderField: "Content-Type")
                            ?? self.defaultContentType(kind: kind, url: finalURL)
                        self.writeCached(hash: hash, data: data, contentType: contentType, kind: kind, url: finalURL)
                        result = .success(CachedResource(data: data, contentType: contentType))
                        self.prefetchNext(for: hash)
                    }
                } else {
                    result = .failure(URLError(.badServerResponse))
                }

                let waiters = self.inflight.removeValue(forKey: hash) ?? []
                for waiter in waiters {
                    waiter(result)
                }
            }
        }
        task.resume()
    }

    private func rewritePlaylist(_ text: String, baseURL: URL, playlistHash: String) -> String {
        var segments: [String] = []
        var output: [String] = []
        var pendingPlaylist = false

        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine
            if line.hasSuffix("\r") { line.removeLast() }

            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                output.append(line)
                pendingPlaylist = true
                continue
            }
            if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                output.append(rewriteURI(in: line, baseURL: baseURL, kind: .media))
                continue
            }
            if line.hasPrefix("#EXT-X-MAP:") {
                output.append(rewriteURI(in: line, baseURL: baseURL, kind: .media))
                continue
            }
            if line.hasPrefix("#EXT-X-MEDIA:") {
                output.append(rewriteURI(in: line, baseURL: baseURL, kind: .playlist))
                continue
            }
            if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                output.append(rewriteURI(in: line, baseURL: baseURL, kind: .playlist))
                continue
            }
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                output.append(line)
                continue
            }

            let kind: ResourceKind = pendingPlaylist ? .playlist : .media
            pendingPlaylist = false

            guard let resolved = resolve(line, baseURL: baseURL) else {
                output.append(line)
                continue
            }
            let hash = Self.hash(resolved.absoluteString)
            register(
                hash: hash,
                url: resolved,
                kind: kind,
                contentType: kind == .playlist
                    ? "application/vnd.apple.mpegurl"
                    : "application/octet-stream"
            )
            output.append(hash)
            if kind == .media {
                segments.append(hash)
            }
        }

        playlistSegments[playlistHash] = segments
        for (index, hash) in segments.enumerated() {
            segmentIndex[hash] = (playlistHash, index)
        }
        return output.joined(separator: "\n")
    }

    private func rewriteURI(in line: String, baseURL: URL, kind: ResourceKind) -> String {
        guard let startRange = line.range(of: "URI=\"") else { return line }
        let start = startRange.upperBound
        guard let end = line[start...].firstIndex(of: "\"") else { return line }
        let raw = String(line[start..<end])
        guard !raw.hasPrefix("data:"), let resolved = resolve(raw, baseURL: baseURL) else {
            return line
        }
        let hash = Self.hash(resolved.absoluteString)
        register(
            hash: hash,
            url: resolved,
            kind: kind,
            contentType: kind == .playlist
                ? "application/vnd.apple.mpegurl"
                : "application/octet-stream"
        )
        return line.replacingCharacters(in: start..<end, with: hash)
    }

    private func resolve(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.hasPrefix("data:") else { return nil }

        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "https:" + value)
        }

        guard let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        // 签名常挂在父级查询串里（pornhub ?h=&e=），相对地址不能把父查询串丢掉
        if resolved.query == nil, let query = baseURL.query, !query.isEmpty,
           var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            components.query = query
            return components.url
        }
        return resolved
    }

    private func rebuildIndexIfNeeded(hash: String, data: Data) {
        guard playlistSegments[hash] == nil,
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        var segments: [String] = []
        for line in text.components(separatedBy: "\n") {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("#") else { continue }
            let path = value.split(separator: "?").first.map(String.init) ?? value
            if path.count == 64, path.allSatisfy({ $0.isHexDigit }) {
                segments.append(path)
            }
        }
        playlistSegments[hash] = segments
        for (index, segment) in segments.enumerated() {
            segmentIndex[segment] = (hash, index)
        }
    }

    private func prefetchFirstSegments(playlistHash: String) {
        guard let segments = playlistSegments[playlistHash] else { return }
        prefetch(Array(segments.prefix(8)))
    }

    private func prefetchNext(for segmentHash: String) {
        guard let (playlistHash, index) = segmentIndex[segmentHash],
              let segments = playlistSegments[playlistHash] else {
            return
        }
        let start = index + 1
        guard start < segments.count else { return }
        let end = min(segments.count, start + 6)
        prefetch(Array(segments[start..<end]))
    }

    private func prefetch(_ hashes: [String]) {
        for hash in hashes {
            guard let entry = index[hash], let url = URL(string: entry.url) else { continue }
            if hasCached(hash) || inflight[hash] != nil { continue }
            loadResource(hash: hash, url: url, kind: entry.kind, completion: nil)
        }
    }

    private func readCached(_ hash: String) -> CachedResource? {
        guard let entry = index[hash] else { return nil }
        guard let data = try? Data(contentsOf: fileURL(hash)) else { return nil }
        return CachedResource(data: data, contentType: entry.contentType)
    }

    private func hasCached(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(hash).path)
    }

    private func writeCached(
        hash: String,
        data: Data,
        contentType: String,
        kind: ResourceKind,
        url: URL
    ) {
        do {
            try data.write(to: fileURL(hash), options: .atomic)
        } catch {
            return
        }
        index[hash] = CacheEntry(
            url: url.absoluteString,
            kind: kind,
            contentType: contentType,
            savedAt: Date().timeIntervalSince1970,
            size: data.count
        )
        scheduleIndexSave()
        sweepIfNeeded()
    }

    private func register(hash: String, url: URL, kind: ResourceKind, contentType: String) {
        guard index[hash] == nil else { return }
        index[hash] = CacheEntry(
            url: url.absoluteString,
            kind: kind,
            contentType: contentType,
            savedAt: Date().timeIntervalSince1970,
            size: 0
        )
        scheduleIndexSave()
    }

    private func defaultContentType(kind: ResourceKind, url: URL) -> String {
        if kind == .playlist { return "application/vnd.apple.mpegurl" }
        switch url.pathExtension.lowercased() {
        case "ts": return "video/mp2t"
        case "m4s", "mp4", "m4v": return "video/mp4"
        case "aac": return "audio/aac"
        case "vtt": return "text/vtt"
        case "key": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }

    private func fileURL(_ hash: String) -> URL {
        cacheDir.appendingPathComponent("r-\(hash).bin")
    }

    private func scheduleIndexSave() {
        indexSaveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveIndexNow()
        }
        indexSaveItem = item
        queue.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func saveIndexNow() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func sweepIfNeeded() {
        var total = index.values.reduce(Int64(0)) { $0 + Int64($1.size) }
        guard total > maxBytes else { return }

        for (hash, entry) in index.sorted(by: { $0.value.savedAt < $1.value.savedAt }) {
            if total <= maxBytes { break }
            try? FileManager.default.removeItem(at: fileURL(hash))
            index.removeValue(forKey: hash)
            total -= Int64(entry.size)
        }
        scheduleIndexSave()
    }

    private func cleanOrphans() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let known = Set(index.keys.map { fileURL($0).lastPathComponent })
        for file in files where file.lastPathComponent.hasPrefix("r-") && !known.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }
}
