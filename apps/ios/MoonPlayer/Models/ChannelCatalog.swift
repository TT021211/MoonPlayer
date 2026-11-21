import SwiftUI

enum ChannelKind: Hashable {
    case douban(String)   // movie / tv / anime / show
    case source(String)   // 网关源 key
}

struct ChannelDef: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let kind: ChannelKind

    var doubanKind: String? {
        if case .douban(let value) = kind { return value }
        return nil
    }

    var sourceKey: String? {
        if case .source(let value) = kind { return value }
        return nil
    }
}

enum ChannelCatalog {
    /// 与网页端左侧栏保持一致：电影 / 剧集 / 动漫 / 8 个剧场 / 综艺。
    static let all: [ChannelDef] = [
        ChannelDef(id: "movie", title: "电影", subtitle: "豆瓣 · 热门 / 最新 / 高分", kind: .douban("movie")),
        ChannelDef(id: "tv", title: "剧集", subtitle: "豆瓣 · 剧集 / 美剧 / 日韩", kind: .douban("tv")),
        ChannelDef(id: "anime", title: "动漫", subtitle: "豆瓣 · 番剧 / 剧场版", kind: .douban("anime")),
        ChannelDef(id: "hanime", title: "深夜剧场", subtitle: "自建频道", kind: .source("hanime1")),
        ChannelDef(id: "aqdlt", title: "心动剧场", subtitle: "自建频道", kind: .source("aqdlt")),
        ChannelDef(id: "hohoj", title: "HoHo剧场", subtitle: "自建频道 · 人物墙", kind: .source("hohoj")),
        ChannelDef(id: "kinostream", title: "KinoStream", subtitle: "自建频道", kind: .source("kinostream")),
        ChannelDef(id: "bjcam", title: "BJ剧场", subtitle: "自建频道", kind: .source("bjcam")),
        ChannelDef(id: "netflixgc", title: "奈飞工厂", subtitle: "自建频道", kind: .source("netflixgc")),
        ChannelDef(id: "pornhub", title: "Pornhub", subtitle: "自建频道", kind: .source("pornhub")),
        ChannelDef(id: "xhamster", title: "xHamster", subtitle: "自建频道", kind: .source("xhamster")),
        ChannelDef(id: "show", title: "综艺", subtitle: "豆瓣 · 国内 / 国外", kind: .douban("show"))
    ]

    static var video: [ChannelDef] { all.filter { $0.doubanKind != nil } }
    static var theater: [ChannelDef] { all.filter { $0.sourceKey != nil } }

    static func symbol(for channel: ChannelDef) -> String {
        switch channel.id {
        case "movie": return "film.fill"
        case "tv": return "tv.fill"
        case "anime": return "sparkles"
        case "show": return "mic.fill"
        default: return AppState.channelSymbol(for: channel.id)
        }
    }

    static func color(for channel: ChannelDef) -> Color {
        switch channel.id {
        case "movie": return Color(red: 0.95, green: 0.40, blue: 0.28)
        case "tv": return Color(red: 0.30, green: 0.62, blue: 0.95)
        case "anime": return Color(red: 0.62, green: 0.45, blue: 0.95)
        case "show": return Color(red: 0.25, green: 0.72, blue: 0.55)
        default: return AppState.channelColor(for: channel.id)
        }
    }

    /// 频道封面比例（宽 / 高）。
    static func posterAspect(for channel: ChannelDef) -> CGFloat {
        switch channel.id {
        case "aqdlt", "bjcam", "pornhub", "xhamster":
            return 16.0 / 9.0
        case "hohoj":
            return 3.0 / 2.0
        default:
            return 2.0 / 3.0
        }
    }
}
