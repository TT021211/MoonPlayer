import Foundation

// MARK: - 服务器配置

struct ServerConfig: Codable {
    var siteName: String?
    var version: String?
    var storageType: String?

    enum CodingKeys: String, CodingKey {
        case siteName = "SiteName"
        case version = "Version"
        case storageType = "StorageType"
    }
}

struct LoginResponse: Codable {
    var ok: Bool?
    var token: String?
    var error: String?
}

// MARK: - 源 / 分类

struct SourceItem: Codable, Identifiable, Hashable {
    let key: String
    let name: String
    var api: String

    var id: String { key }

    var host: String {
        URL(string: api)?.host ?? api
    }
}

struct SourceListResponse: Codable {
    var sources: [SourceItem]
}

struct CategoryItem: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var pid: String?
    var group: String?

    var displayGroup: String {
        let g = (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? "分类" : g
    }
}

struct CategoryListResponse: Codable {
    var categories: [CategoryItem]
}

// MARK: - 视频

struct SearchResult: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var poster: String?
    var year: String?
    var episodes: [String]?
    var episodes_titles: [String]?
    var source: String?
    var source_name: String?
    var type_name: String?
    var vod_remarks: String?
    var desc: String?
    var proxyMode: Bool?

    var episodeCount: Int { episodes?.count ?? 0 }
}

struct VideoDetail: Codable, Identifiable {
    let id: String
    var title: String
    var poster: String?
    var year: String?
    var desc: String?
    var episodes: [String]?
    var episodes_titles: [String]?
    var source: String?
    var source_name: String?
    var type_name: String?
    var vod_remarks: String?
    var proxyMode: Bool?

    var episodeCount: Int { episodes?.count ?? 0 }
}

struct SearchResponse: Codable {
    var results: [SearchResult]
}

struct VideoPage: Codable {
    var results: [SearchResult]?
    var total: Int?
    var page: Int?
    var pageCount: Int?
}

// MARK: - 收藏 / 播放记录

struct FavoriteEnvelope: Codable {
    var title: String
    var source_name: String?
    var cover: String?
    var year: String?
    var total_episodes: Int?
    var save_time: Double?
    var search_title: String?
    var vod_remarks: String?
}

struct RecordEnvelope: Codable {
    var title: String
    var source_name: String?
    var cover: String?
    var year: String?
    var index: Int
    var total_episodes: Int?
    var play_time: Double?
    var total_time: Double?
    var save_time: Double?
    var search_title: String?
}

struct FavoriteItem: Identifiable, Hashable {
    let source: String
    let id: String
    let title: String
    let sourceName: String
    let cover: String?
    let year: String?
    let totalEpisodes: Int
    let saveTime: Double
    let searchTitle: String?
    let remarks: String?

    var key: String { "\(source)+\(id)" }

    init(source: String, id: String, envelope: FavoriteEnvelope) {
        self.source = source
        self.id = id
        self.title = envelope.title
        self.sourceName = envelope.source_name ?? source
        self.cover = envelope.cover
        self.year = envelope.year
        self.totalEpisodes = envelope.total_episodes ?? 0
        self.saveTime = envelope.save_time ?? 0
        self.searchTitle = envelope.search_title
        self.remarks = envelope.vod_remarks
    }
}

struct PlayRecordItem: Identifiable, Hashable {
    let source: String
    let id: String
    let title: String
    let sourceName: String
    let cover: String?
    let year: String?
    let index: Int
    let totalEpisodes: Int
    let playTime: Double
    let totalTime: Double
    let saveTime: Double
    let searchTitle: String?

    var key: String { "\(source)+\(id)" }

    var progress: Double {
        guard totalTime > 0 else { return 0 }
        return min(1, max(0, playTime / totalTime))
    }

    var progressText: String {
        guard totalTime > 0 else { return "" }
        return "\(Self.format(playTime)) / \(Self.format(totalTime))"
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    init(source: String, id: String, envelope: RecordEnvelope) {
        self.source = source
        self.id = id
        self.title = envelope.title
        self.sourceName = envelope.source_name ?? source
        self.cover = envelope.cover
        self.year = envelope.year
        self.index = max(1, envelope.index)
        self.totalEpisodes = envelope.total_episodes ?? 0
        self.playTime = envelope.play_time ?? 0
        self.totalTime = envelope.total_time ?? 0
        self.saveTime = envelope.save_time ?? 0
        self.searchTitle = envelope.search_title
    }
}

// MARK: - 播放上下文

struct PlaybackContext: Identifiable {
    let id = UUID()
    let sourceKey: String
    let sourceName: String
    let videoID: String
    let title: String
    let cover: String
    let year: String
    let episodes: [String]
    let episodeTitles: [String]
    let proxyMode: Bool
    let startIndex: Int
    let startTime: Double

    func episodeTitle(at index: Int) -> String {
        if index >= 0, index < episodeTitles.count, !episodeTitles[index].isEmpty {
            return episodeTitles[index]
        }
        return "第\(index + 1)集"
    }
}
