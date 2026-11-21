import Foundation
import SwiftUI

final class AppState: ObservableObject {
    static let defaultServer = "https://tv.acxou.hair"

    @Published var serverURL: String
    @Published var username: String
    @Published var siteName: String
    @Published var isLoggedIn = false
    @Published var isBooting = true
    @Published var sources: [SourceItem] = []
    @Published var favorites: [FavoriteItem] = []
    @Published var records: [PlayRecordItem] = []
    @Published var bootError: String?

    @Published var forceProxy: Bool = UserDefaults.standard.bool(forKey: "player.forceProxy") {
        didSet { UserDefaults.standard.set(forceProxy, forKey: "player.forceProxy") }
    }

    @Published var toast: String?

    private let defaults = UserDefaults.standard
    private var didBootstrap = false

    private enum Keys {
        static let server = "moon.server"
        static let username = "moon.username"
        static let siteName = "moon.siteName"
        static let token = "moon.token"
    }

    init() {
        serverURL = defaults.string(forKey: Keys.server) ?? Self.defaultServer
        username = defaults.string(forKey: Keys.username) ?? ""
        siteName = defaults.string(forKey: Keys.siteName) ?? "MoonPlayer"

        APIClient.shared.onTokenRefreshed = { newToken in
            Keychain.save(newToken, for: Keys.token)
        }
    }

    // MARK: - 启动 / 登录

    @MainActor
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        defer { isBooting = false }

        guard
            let token = Keychain.read(Keys.token),
            !token.isEmpty,
            let url = Self.normalizeServer(serverURL)
        else {
            return
        }

        APIClient.shared.configure(baseURL: url, token: token)
        do {
            let config: ServerConfig = try await APIClient.shared.serverConfig()
            if let name = config.siteName, !name.isEmpty { siteName = name }
            isLoggedIn = true
            await refreshSources()
            await refreshLibrary()
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            bootError = error.localizedDescription
        }
    }

    @MainActor
    func login(server: String, username loginName: String, password: String) async throws {
        guard let url = Self.normalizeServer(server) else {
            throw APIError.message("服务器地址无效")
        }
        let name = loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            throw APIError.message("请输入用户名和密码")
        }

        APIClient.shared.configure(baseURL: url, token: nil)
        let config: ServerConfig = try await APIClient.shared.serverConfig()
        let response: LoginResponse = try await APIClient.shared.login(username: name, password: password)

        guard let token = response.token, !token.isEmpty else {
            throw APIError.message(response.error ?? "服务器未返回登录凭证")
        }

        Keychain.save(token, for: Keys.token)
        defaults.set(url.absoluteString, forKey: Keys.server)
        defaults.set(name, forKey: Keys.username)
        if let site = config.siteName, !site.isEmpty {
            defaults.set(site, forKey: Keys.siteName)
        }

        serverURL = url.absoluteString
        self.username = name
        if let site = config.siteName, !site.isEmpty { siteName = site }
        APIClient.shared.configure(baseURL: url, token: token)
        bootError = nil
        isLoggedIn = true

        await refreshSources()
        await refreshLibrary()
    }

    @MainActor
    func logout() {
        clearSession()
    }

    @MainActor
    private func clearSession() {
        Keychain.delete(Keys.token)
        APIClient.shared.configure(baseURL: APIClient.shared.baseURL ?? URL(string: Self.defaultServer)!, token: nil)
        isLoggedIn = false
        sources = []
        favorites = []
        records = []
    }

    @MainActor
    func refreshAll() async {
        await refreshSources()
        await refreshLibrary()
    }

    // MARK: - 源与分类

    @MainActor
    func refreshSources() async {
        do {
            let response: SourceListResponse = try await APIClient.shared.request("/api/source-search/sources")
            var seen = Set<String>()
            sources = response.sources.filter { source in
                guard !source.key.isEmpty, !seen.contains(source.key) else { return false }
                seen.insert(source.key)
                return true
            }
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // 网络抖动时保留上一次列表
        }
    }

    @MainActor
    func categories(for sourceKey: String) async throws -> [CategoryItem] {
        let response: CategoryListResponse = try await APIClient.shared.request(
            "/api/source-search/categories",
            query: [URLQueryItem(name: "source", value: sourceKey)]
        )
        var seen = Set<String>()
        return response.categories.filter { category in
            guard !seen.contains(category.id) else { return false }
            seen.insert(category.id)
            return true
        }
    }

    @MainActor
    func videos(sourceKey: String, categoryID: String, page: Int) async throws -> VideoPage {
        try await APIClient.shared.request(
            "/api/source-search/videos",
            query: [
                URLQueryItem(name: "source", value: sourceKey),
                URLQueryItem(name: "categoryId", value: categoryID),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    @MainActor
    func search(sourceKey: String, keyword: String, page: Int = 1) async throws -> VideoPage {
        try await APIClient.shared.request(
            "/api/source-search/search",
            query: [
                URLQueryItem(name: "source", value: sourceKey),
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
    }

    @MainActor
    func globalSearch(_ keyword: String) async throws -> [SearchResult] {
        let response: SearchResponse = try await APIClient.shared.request(
            "/api/search",
            query: [URLQueryItem(name: "q", value: keyword)]
        )
        return response.results
    }

    // MARK: - 首页 / 豆瓣

    @MainActor
    func fetchTrending() async throws -> [TrendingItem] {
        let response: TrendingResponse = try await APIClient.shared.request("/api/tmdb/trending")
        return response.list ?? []
    }

    @MainActor
    func fetchUpcoming() async throws -> [TrendingItem] {
        let response: UpcomingResponse = try await APIClient.shared.request("/api/tmdb/upcoming")
        return response.data ?? []
    }

    @MainActor
    func fetchDoubanCategories(
        kind: String,
        category: String,
        type: String,
        start: Int,
        limit: Int = 24
    ) async throws -> [DoubanItem] {
        let response: DoubanResponse = try await APIClient.shared.request(
            "/api/douban/categories",
            query: [
                URLQueryItem(name: "kind", value: kind),
                URLQueryItem(name: "category", value: category),
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start))
            ]
        )
        return response.list ?? []
    }

    @MainActor
    func fetchDoubanRecommends(
        kind: String,
        category: String,
        format: String,
        start: Int,
        limit: Int = 24
    ) async throws -> [DoubanItem] {
        var query = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "start", value: String(start))
        ]
        if !format.isEmpty {
            query.append(URLQueryItem(name: "format", value: format))
        }
        let response: DoubanResponse = try await APIClient.shared.request(
            "/api/douban/recommends",
            query: query
        )
        return response.list ?? []
    }

    @MainActor
    func detail(sourceKey: String, videoID: String, title: String? = nil) async throws -> VideoDetail {
        var query = [
            URLQueryItem(name: "source", value: sourceKey),
            URLQueryItem(name: "id", value: videoID)
        ]
        if let title, !title.isEmpty {
            query.append(URLQueryItem(name: "title", value: title))
        }
        return try await APIClient.shared.request("/api/source-detail", query: query)
    }

    // MARK: - 收藏

    @MainActor
    func refreshFavorites() async {
        do {
            let dict: [String: FavoriteEnvelope] = try await APIClient.shared.request("/api/favorites")
            favorites = dict.compactMap { key, value in
                let parts = key.split(separator: "+", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return FavoriteItem(source: parts[0], id: parts[1], envelope: value)
            }
            .sorted { $0.saveTime > $1.saveTime }
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // 保留旧数据
        }
    }

    func isFavorite(sourceKey: String, videoID: String) -> Bool {
        favorites.contains { $0.source == sourceKey && $0.id == videoID }
    }

    @MainActor
    func toggleFavorite(detail: VideoDetail, fallbackSourceKey: String) async throws -> Bool {
        let sourceKey = detail.source ?? fallbackSourceKey
        let key = "\(sourceKey)+\(detail.id)"
        if isFavorite(sourceKey: sourceKey, videoID: detail.id) {
            try await APIClient.shared.sendVoid(
                "/api/favorites",
                query: [URLQueryItem(name: "key", value: key)],
                method: "DELETE"
            )
            favorites.removeAll { $0.key == key }
            return false
        }

        let favorite: [String: Any] = [
            "title": detail.title,
            "source_name": detail.source_name ?? sourceName(for: sourceKey),
            "cover": detail.poster ?? "",
            "year": detail.year ?? "",
            "total_episodes": detail.episodeCount,
            "save_time": Int(Date().timeIntervalSince1970 * 1000),
            "search_title": detail.title,
            "vod_remarks": detail.vod_remarks ?? ""
        ]
        try await APIClient.shared.sendVoid("/api/favorites", body: ["key": key, "favorite": favorite])
        await refreshFavorites()
        return true
    }

    @MainActor
    func deleteFavorite(key: String) async {
        do {
            try await APIClient.shared.sendVoid(
                "/api/favorites",
                query: [URLQueryItem(name: "key", value: key)],
                method: "DELETE"
            )
            favorites.removeAll { $0.key == key }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - 播放记录

    @MainActor
    func refreshRecords() async {
        do {
            let dict: [String: RecordEnvelope] = try await APIClient.shared.request("/api/playrecords")
            records = dict.compactMap { key, value in
                let parts = key.split(separator: "+", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return PlayRecordItem(source: parts[0], id: parts[1], envelope: value)
            }
            .sorted { $0.saveTime > $1.saveTime }
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // 保留旧数据
        }
    }

    @MainActor
    func refreshLibrary() async {
        await refreshFavorites()
        await refreshRecords()
    }

    func record(sourceKey: String, videoID: String) -> PlayRecordItem? {
        records.first { $0.source == sourceKey && $0.id == videoID }
    }

    @MainActor
    func saveProgress(
        context: PlaybackContext,
        episodeIndex: Int,
        playTime: Double,
        duration: Double
    ) async {
        guard playTime.isFinite, playTime >= 0 else { return }
        let key = "\(context.sourceKey)+\(context.videoID)"
        let record: [String: Any] = [
            "title": context.title,
            "source_name": context.sourceName,
            "cover": context.cover,
            "year": context.year,
            "index": max(1, episodeIndex + 1),
            "total_episodes": context.episodes.count,
            "play_time": playTime,
            "total_time": duration.isFinite ? max(0, duration) : 0,
            "save_time": Int(Date().timeIntervalSince1970 * 1000),
            "search_title": context.title
        ]
        do {
            try await APIClient.shared.sendVoid("/api/playrecords", body: ["key": key, "record": record])
            let envelope = RecordEnvelope(
                title: context.title,
                source_name: context.sourceName,
                cover: context.cover,
                year: context.year,
                index: max(1, episodeIndex + 1),
                total_episodes: context.episodes.count,
                play_time: playTime,
                total_time: duration.isFinite ? max(0, duration) : 0,
                save_time: Double(Int(Date().timeIntervalSince1970 * 1000)),
                search_title: context.title
            )
            let item = PlayRecordItem(source: context.sourceKey, id: context.videoID, envelope: envelope)
            records.removeAll { $0.key == key }
            records.insert(item, at: 0)
        } catch {
            // 播放记录失败不打断播放
        }
    }

    @MainActor
    func deleteRecord(key: String) async {
        do {
            try await APIClient.shared.sendVoid(
                "/api/playrecords",
                query: [URLQueryItem(name: "key", value: key)],
                method: "DELETE"
            )
            records.removeAll { $0.key == key }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - 地址与图片

    func sourceName(for key: String) -> String {
        sources.first { $0.key == key }?.name ?? key
    }

    func source(for key: String) -> SourceItem? {
        sources.first { $0.key == key }
    }

    /// 按频道定义查找采集源（兼容 key 大小写/前后缀，如 hanime → hanime1）。
    func sourceForChannel(_ channelKey: String) -> SourceItem? {
        if let exact = sources.first(where: { $0.key.caseInsensitiveCompare(channelKey) == .orderedSame }) {
            return exact
        }
        let needle = channelKey.lowercased()
        return sources.first { source in
            let key = source.key.lowercased()
            let api = source.api.lowercased()
            return key.contains(needle)
                || needle.contains(key)
                || api.contains("/\(needle)/")
        }
    }

    /// TMDB 图片完整地址（默认 w500）。
    static func tmdbImageURL(_ path: String?, size: String = "w500") -> String? {
        guard var path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        if path.hasPrefix("//") { path = "https:" + path }
        return "https://image.tmdb.org/t/p/\(size)\(path.hasPrefix("/") ? "" : "/")\(path)"
    }

    func imageURL(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard !value.lowercased().hasPrefix("data:") else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }

        guard let base = APIClient.shared.baseURL else {
            return URL(string: value)
        }
        if value.hasPrefix("/") {
            return URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + value)
        }
        guard value.lowercased().hasPrefix("http") else {
            return URL(string: base.absoluteString + "/" + value)
        }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return URL(string: value)
        }
        components.path = "/api/image-proxy"
        components.queryItems = [URLQueryItem(name: "url", value: value)]
        return components.url ?? URL(string: value)
    }

    func playURL(episode: String, sourceKey: String, proxyMode: Bool, forceProxy: Bool) -> URL? {
        guard let base = APIClient.shared.baseURL else { return nil }
        var raw = episode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }
        if raw.hasPrefix("/") {
            raw = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + raw
        }
        guard let direct = URL(string: raw) else { return nil }

        // AVPlayer 不受浏览器 CORS 限制，原生端优先直连：
        // 既省掉服务端转封装，也避开 /api/proxy/vod/* 需要的登录态。
        // 直连失败时播放器会自动降级到免鉴权的 /api/proxy-m3u8。
        _ = proxyMode
        if forceProxy {
            return proxyURL(
                path: "/api/proxy-m3u8",
                target: raw,
                sourceKey: "directplay",
                extra: [URLQueryItem(name: "proxySegments", value: "true")]
            ) ?? direct
        }
        return direct
    }

    private func proxyURL(
        path: String,
        target: String,
        sourceKey: String,
        extra: [URLQueryItem] = []
    ) -> URL? {
        guard let base = APIClient.shared.baseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "url", value: target),
            URLQueryItem(name: "source", value: sourceKey)
        ] + extra
        return components.url
    }

    // MARK: - 小工具

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    static func normalizeServer(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 封面比例（宽 / 高）：横图源用横版，避免 2:3 卡片把图裁掉。
    static func posterAspect(forSourceKey key: String) -> CGFloat {
        let value = key.lowercased()
        if value.contains("aqdlt") || value.contains("bjcam")
            || value.contains("pornhub") || value.contains("xhamster") {
            return 16.0 / 9.0
        }
        if value.contains("hohoj") {
            return 3.0 / 2.0
        }
        return 2.0 / 3.0
    }

    static func channelSymbol(for key: String) -> String {        let k = key.lowercased()
        if k.contains("hanime") { return "moon.stars.fill" }
        if k.contains("aqdlt") { return "heart.fill" }
        if k.contains("hohoj") { return "person.2.fill" }
        if k.contains("kinostream") { return "film.fill" }
        if k.contains("bjcam") { return "video.fill" }
        if k.contains("netflix") { return "play.rectangle.fill" }
        if k.contains("pornhub") { return "flame.fill" }
        if k.contains("xhamster") { return "bolt.fill" }
        return "tv.fill"
    }

    static func channelColor(for key: String) -> Color {
        let k = key.lowercased()
        if k.contains("hanime") { return Color(red: 0.55, green: 0.40, blue: 0.95) }
        if k.contains("aqdlt") { return Color(red: 0.95, green: 0.35, blue: 0.55) }
        if k.contains("hohoj") { return Color(red: 0.25, green: 0.65, blue: 0.95) }
        if k.contains("kinostream") { return Color(red: 0.15, green: 0.75, blue: 0.65) }
        if k.contains("bjcam") { return Color(red: 0.95, green: 0.60, blue: 0.25) }
        if k.contains("netflix") { return Color(red: 0.90, green: 0.15, blue: 0.20) }
        if k.contains("pornhub") { return Color(red: 1.00, green: 0.45, blue: 0.10) }
        if k.contains("xhamster") { return Color(red: 0.60, green: 0.55, blue: 0.95) }
        return Color(red: 0.45, green: 0.55, blue: 0.75)
    }
}
