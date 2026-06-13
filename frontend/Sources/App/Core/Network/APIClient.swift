import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:        return "Неверный ответ сервера"
        case .httpError(_, let msg):  return msg
        case .decodingError:          return "Ошибка обработки данных"
        case .tokenExpired:           return "Сессия истекла, войди снова"
        }
    }
}

extension Notification.Name {
    static let didRefreshToken = Notification.Name("didRefreshToken")
    static let tokenExpired    = Notification.Name("tokenExpired")
}

final class APIClient: Sendable {
    static let shared = APIClient()

    private let base = AppConfig.apiBaseURL

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 120  // ждём ответа до 2 минут (AI генерация)
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = true       // ждём сети если нет соединения
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private init() {}

    // MARK: - Public API

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws -> T {
        var req = try buildRequest(path: path, method: method, body: body, token: token)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, token != nil {
            // Попытка обновить токен
            if let newToken = try? await refreshAccessToken() {
                req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await session.data(for: req)
                guard let http2 = response2 as? HTTPURLResponse else { throw APIError.invalidResponse }
                return try handleResponse(data: data2, statusCode: http2.statusCode)
            } else {
                await notifyTokenExpired()
                throw APIError.tokenExpired
            }
        }

        return try handleResponse(data: data, statusCode: http.statusCode)
    }

    func requestEmpty(
        _ path: String,
        method: String,
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws {
        var req = try buildRequest(path: path, method: method, body: body, token: token)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 {
            if let newToken = try? await refreshAccessToken() {
                req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (_, response2) = try await session.data(for: req)
                guard let http2 = response2 as? HTTPURLResponse else { throw APIError.invalidResponse }
                if !(200..<300).contains(http2.statusCode) {
                    throw APIError.httpError(http2.statusCode, "Ошибка \(http2.statusCode)")
                }
                return
            } else {
                await notifyTokenExpired()
                throw APIError.tokenExpired
            }
        }

        if !(200..<300).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode, "Ошибка \(http.statusCode)")
        }
    }

    // MARK: - Token refresh

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = Keychain.read("refresh_token") else {
            throw APIError.tokenExpired
        }

        struct RefreshBody: Encodable { let refreshToken: String }
        struct TokenResp: Decodable { let accessToken: String; let refreshToken: String }

        let req = try buildRequest(
            path: "auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refreshToken),
            token: nil
        )
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.tokenExpired
        }

        let tokenResp = try decoder.decode(TokenResp.self, from: data)
        Keychain.save("access_token", value: tokenResp.accessToken)
        Keychain.save("refresh_token", value: tokenResp.refreshToken)

        await notifyTokenRefreshed(newToken: tokenResp.accessToken)
        return tokenResp.accessToken
    }

    @MainActor
    private func notifyTokenRefreshed(newToken: String) {
        NotificationCenter.default.post(
            name: .didRefreshToken,
            object: nil,
            userInfo: ["token": newToken]
        )
    }

    @MainActor
    private func notifyTokenExpired() {
        NotificationCenter.default.post(name: .tokenExpired, object: nil)
    }

    // MARK: - Helpers

    private func buildRequest(
        path: String,
        method: String,
        body: (any Encodable)?,
        token: String?
    ) throws -> URLRequest {
        // Разбиваем путь и query-параметры корректно
        let url: URL
        if path.contains("?") {
            let parts = path.split(separator: "?", maxSplits: 1)
            var components = URLComponents(url: base.appendingPathComponent(String(parts[0])), resolvingAgainstBaseURL: false)!
            components.query = String(parts[1])
            url = components.url!
        } else {
            url = base.appendingPathComponent(path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try encoder.encode(body) }
        return req
    }

    private func handleResponse<T: Decodable>(data: Data, statusCode: Int) throws -> T {
        if !(200..<300).contains(statusCode) {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.detail ?? "Ошибка \(statusCode)"
            throw APIError.httpError(statusCode, msg)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Лог в консоль для отладки
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            print("⚠️ Decode error for \(T.self): \(error)")
            print("⚠️ Raw JSON: \(raw.prefix(500))")
            throw APIError.decodingError(error)
        }
    }
}

private struct APIErrorBody: Decodable { let detail: String }
