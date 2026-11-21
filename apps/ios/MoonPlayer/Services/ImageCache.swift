import Foundation
import UIKit

/// 带登录态与内存缓存的图片加载器。
/// 封面大多经过 `/api/image-proxy`，该路由在鉴权中间件后面，必须带 Bearer Token。
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache.shared
        session = URLSession(configuration: configuration)
        cache.countLimit = 800
    }

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL, allowRefresh: Bool = true) async -> UIImage? {
        if let hit = cached(url) { return hit }

        var request = URLRequest(url: url)
        request.setValue("MoonTVPlus-iOS/1.0 (MoonPlayer)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let token = APIClient.shared.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401, allowRefresh, await APIClient.shared.refreshAccessToken() {
                    return await load(url, allowRefresh: false)
                }
                guard (200..<300).contains(http.statusCode) else { return nil }
            }
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
    }
}
