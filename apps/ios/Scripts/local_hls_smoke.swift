import Foundation

@main
struct LocalHLSSmoke {
    static func main() async {
        LocalHLSServer.shared.startIfNeeded()

        let original = URL(
            string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
        )!

        var local: URL?
        for _ in 0..<50 {
            local = LocalHLSServer.shared.makePlaylistURL(for: original)
            if local != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let local else {
            fatalError("local server not ready")
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)

        let (playlistData, playlistResponse) = try! await session.data(from: local)
        guard let playlistHTTP = playlistResponse as? HTTPURLResponse,
              playlistHTTP.statusCode == 200,
              let playlistText = String(data: playlistData, encoding: .utf8),
              playlistText.contains("#EXTM3U") else {
            fatalError("master playlist failed")
        }
        print("master ok bytes=\(playlistData.count)")

        guard let variantHash = firstHash(in: playlistText),
              let variantURL = URL(string: variantHash, relativeTo: local) else {
            fatalError("no variant hash")
        }
        let (variantData, variantResponse) = try! await session.data(from: variantURL)
        guard let variantHTTP = variantResponse as? HTTPURLResponse,
              variantHTTP.statusCode == 200,
              let variantText = String(data: variantData, encoding: .utf8),
              variantText.contains("#EXTM3U") else {
            fatalError("variant playlist failed")
        }
        print("variant ok bytes=\(variantData.count)")

        guard let segmentHash = firstHash(in: variantText),
              let segmentURL = URL(string: segmentHash, relativeTo: variantURL) else {
            fatalError("no segment hash")
        }

        // 先整片拉一次，验证边看边存
        let (segmentData, segmentResponse) = try! await session.data(from: segmentURL)
        guard let segmentHTTP = segmentResponse as? HTTPURLResponse,
              segmentHTTP.statusCode == 200,
              !segmentData.isEmpty else {
            let status = (segmentResponse as? HTTPURLResponse)?.statusCode ?? -1
            fatalError("segment failed status=\(status) bytes=\(segmentData.count)")
        }
        print("segment ok bytes=\(segmentData.count)")

        // 再从本地缓存取 Range，验证 206
        var request = URLRequest(url: segmentURL)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (rangeData, rangeResponse) = try! await session.data(for: request)
        guard let rangeHTTP = rangeResponse as? HTTPURLResponse,
              rangeHTTP.statusCode == 206,
              rangeData.count == 1024 else {
            let status = (rangeResponse as? HTTPURLResponse)?.statusCode ?? -1
            fatalError("segment range failed status=\(status) bytes=\(rangeData.count)")
        }
        print("segment range ok bytes=\(rangeData.count)")

        let cached = LocalHLSServer.shared.cacheSizeBytes
        print("cache bytes=\(cached)")
        guard cached > 0 else {
            fatalError("cache empty")
        }
        print("LOCAL_HLS_SMOKE_OK")
    }

    private static func firstHash(in playlist: String) -> String? {
        for line in playlist.components(separatedBy: "\n") {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("#") else { continue }
            let path = value.split(separator: "?").first.map(String.init) ?? value
            if path.count == 64, path.allSatisfy({ $0.isHexDigit }) {
                return path
            }
        }
        return nil
    }
}
