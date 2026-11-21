import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case badURL
    case unauthorized
    case http(Int, String)
    case decoding
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "请先登录服务器"
        case .badURL:
            return "服务器地址无效"
        case .unauthorized:
            return "登录已失效，请重新登录"
        case .http(let code, let message):
            if code == 429 { return message.isEmpty ? "操作太频繁，请稍后再试" : message }
            return message.isEmpty ? "请求失败（\(code)）" : message
        case .decoding:
            return "服务器返回的数据格式不正确"
        case .message(let text):
            return text
        }
    }
}

/// 极简 API 客户端：Bearer Token 鉴权，接口与 MoonTV Web 端保持一致。
final class APIClient {
    static let shared = APIClient()

    private(set) var baseURL: URL?
    private(set) var token: String?
    var onTokenRefreshed: ((String) -> Void)?

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "moonplayer-http"
        )
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    func configure(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - 业务接口

    func serverConfig() async throws -> ServerConfig {
        try await request("/api/server-config", authenticated: false)
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        try await request(
            "/api/login",
            method: "POST",
            body: ["username": username, "password": password],
            authenticated: false
        )
    }

    func request<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Any? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let data = try await send(
            path,
            query: query,
            method: method,
            body: body,
            authenticated: authenticated
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[API] decode failed \(path): \(error)")
            print("[API] body: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            #endif
            throw APIError.decoding
        }
    }

    func sendVoid(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "POST",
        body: Any? = nil
    ) async throws {
        _ = try await send(path, query: query, method: method, body: body, authenticated: true)
    }

    /// Access Token 只有 4 小时；401 时用 refreshToken 换新，调用方无需感知。
    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard token != nil else { return false }
        do {
            let data = try await send(
                "/api/auth/refresh",
                query: [],
                method: "POST",
                body: nil,
                authenticated: true,
                canRetry: false
            )
            guard let response = try? decoder.decode(RefreshResponse.self, from: data),
                  let newToken = response.token,
                  !newToken.isEmpty else {
                return false
            }
            token = newToken
            onTokenRefreshed?(newToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 底层

    private func send(
        _ path: String,
        query: [URLQueryItem],
        method: String,
        body: Any?,
        authenticated: Bool,
        canRetry: Bool = true
    ) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("MoonTVPlus-iOS/1.0 (MoonPlayer)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.message("网络连接失败：\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.message("服务器响应异常")
        }

        if http.statusCode == 401 {
            if authenticated, canRetry, await refreshAccessToken() {
                return try await send(
                    path,
                    query: query,
                    method: method,
                    body: body,
                    authenticated: true,
                    canRetry: false
                )
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            throw APIError.http(http.statusCode, message)
        }

        return data
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard let baseURL else { throw APIError.notConfigured }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.badURL }
        return url
    }

    private func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if let message = dict["error"] as? String, !message.isEmpty { return message }
        if let message = dict["message"] as? String, !message.isEmpty { return message }
        if let message = dict["msg"] as? String, !message.isEmpty { return message }
        return ""
    }
}
