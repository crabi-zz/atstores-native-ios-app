import Foundation
import UIKit

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

struct APIResponse {
    let status: Int
    let data: Data
    var ok: Bool { (200..<300).contains(status) }
    var json: Any? { JSON.parse(data) }
    var text: String { String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// Extracts `error` / `message` from an error body, like the Android toasts did.
    func errorMessage(_ fallback: String) -> String {
        if let d = json as? JSONDict, let m = d.str("error", "message") { return m }
        if !text.isEmpty, !text.hasPrefix("<"), text.count < 200 { return text }
        return fallback
    }
}

/// Port of ApiService + RetrofitClient: one URLSession client, bearer auth on
/// non-public paths, and a single-flight token refresh on HTTP 401.
final class API {
    static let shared = API()

    private let base = URL(string: "https://api.atstores.in/")!
    private let session: URLSession
    private var refreshTask: Task<Bool, Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    static func seg(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The Android interceptor sent the bearer token on every path except `/api/public/`.
    private static func needsAuth(_ path: String) -> Bool { !path.contains("api/public/") }

    func send(_ method: HTTPMethod, _ path: String, query: [String: Any] = [:], body: Any? = nil) async throws -> APIResponse {
        var request = makeRequest(method, path, query: query)
        var body = body
        // Logins send this phone's id, so the server keeps one login per device
        // (logging in on the website or another phone no longer logs this one out).
        if path.hasSuffix("auth/otp-login") || path.hasSuffix("auth/login"),
           var dict = body as? [String: Any], dict["deviceId"] == nil {
            dict["deviceId"] = Self.deviceId
            body = dict
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request, auth: Self.needsAuth(path))
    }

    /// Multipart upload of one image (Android `@Multipart` + `MultipartBody.Part`).
    func upload(_ path: String, field: String, data: Data, filename: String = "upload.jpg", mime: String = "image/jpeg") async throws -> APIResponse {
        var request = makeRequest(.post, path, query: [:])
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        request.timeoutInterval = 60
        return try await perform(request, auth: true)
    }

    // MARK: Convenience (errors -> nil / empty / false)

    func json(_ method: HTTPMethod = .get, _ path: String, query: [String: Any] = [:], body: Any? = nil) async -> Any? {
        guard let r = try? await send(method, path, query: query, body: body), r.ok else { return nil }
        return r.json
    }

    func objects(_ path: String, query: [String: Any] = [:], keys: [String] = ["data", "content", "list"]) async -> [JSONDict] {
        JSON.objects(from: await json(.get, path, query: query), preferredKeys: keys)
    }

    func object(_ path: String, query: [String: Any] = [:]) async -> JSONDict? {
        await json(.get, path, query: query) as? JSONDict
    }

    func ok(_ method: HTTPMethod, _ path: String, query: [String: Any] = [:], body: Any? = nil) async -> Bool {
        (try? await send(method, path, query: query, body: body))?.ok ?? false
    }

    // MARK: Internals

    private func makeRequest(_ method: HTTPMethod, _ path: String, query: [String: Any]) -> URLRequest {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.percentEncodedPath = "/" + path
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method.rawValue
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func perform(_ request: URLRequest, auth: Bool) async throws -> APIResponse {
        var req = request
        // The access token lives 24 h. After the phone has been idle it is usually expired:
        // refresh first instead of sending a request we know will fail.
        if auth, Self.isExpiringSoon(Session.shared.accessToken), !Session.shared.refreshToken.isEmpty {
            _ = await refreshTokens()
        }
        let token = auth ? Session.shared.accessToken : ""
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var response = try await rawRetryingIdle(req)
        if response.status == 401, auth {
            let current = Session.shared.accessToken
            // Another request may already have refreshed the token.
            let refreshed = (!current.isEmpty && current != token) ? true : await refreshTokens()
            if refreshed {
                req.setValue("Bearer \(Session.shared.accessToken)", forHTTPHeaderField: "Authorization")
                response = try await rawRetryingIdle(req)
            }
        }
        return response
    }

    private func raw(_ req: URLRequest) async throws -> APIResponse {
        let (data, resp) = try await session.data(for: req)
        return APIResponse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// After the app has been idle, the first request often fails with "network connection
    /// was lost" or a timeout. Retry reads once; never retry writes.
    private func rawRetryingIdle(_ req: URLRequest) async throws -> APIResponse {
        do {
            return try await raw(req)
        } catch let error as URLError
            where req.httpMethod == "GET" && [.networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            try await Task.sleep(for: .milliseconds(400))
            return try await raw(req)
        }
    }

    /// Stable id for this install, sent with logins (one server-side login per device).
    static var deviceId: String {
        let key = "atstores_device_id"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = "IOS-" + (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// True if the JWT is missing, unreadable, or expires within a minute.
    static func isExpiringSoon(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return !jwt.isEmpty }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = (payload["exp"] as? NSNumber)?.doubleValue else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < 60
    }

    /// Refresh now if the access token is (nearly) expired - used when the app comes to the foreground.
    func refreshIfNeeded() async {
        guard Self.isExpiringSoon(Session.shared.accessToken), !Session.shared.refreshToken.isEmpty else { return }
        _ = await refreshTokens()
    }

    /// `POST api/auth/refresh` with the stored refresh token; returns the parsed auth body on success.
    ///
    /// Sent on its own: the backend (Spring resource server) rejects ANY request that carries an
    /// expired Bearer token with 401 - even /api/auth/refresh - and going through `perform` made
    /// that 401 wait on the refresh already in progress, so requests hung and screens stayed empty.
    func refreshAuth() async -> AuthResult? {
        await refreshAuthDetailed().auth
    }

    /// `rejected` is true when the server refused the refresh token (log out), false for network errors.
    private func refreshAuthDetailed() async -> (auth: AuthResult?, rejected: Bool) {
        let refresh = Session.shared.refreshToken
        guard !refresh.isEmpty else { return (nil, true) }
        var req = makeRequest(.post, "api/auth/refresh", query: [:])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refresh])
        guard let r = try? await raw(req) else { return (nil, false) }
        guard r.ok, let d = r.json as? JSONDict else {
            // The backend reports an invalid/expired refresh token as a 500 whose message mentions it;
            // any other 5xx is a temporary server problem, so keep the user logged in.
            let refusedToken = (400..<500).contains(r.status) || r.text.lowercased().contains("refresh token")
            return (nil, refusedToken)
        }
        let auth = AuthResult(d)
        return auth.accessToken == nil ? (nil, true) : (auth, false)
    }

    private func refreshTokens() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task<Bool, Never> {
            let result = await refreshAuthDetailed()
            guard let auth = result.auth, let access = auth.accessToken else {
                // Refresh token expired or revoked: send the user to login instead of empty screens.
                #if DEBUG
                NSLog("[Auth] refresh failed (rejected: %@)", result.rejected ? "yes" : "no")
                #endif
                if result.rejected, Session.shared.isLoggedIn {
                    await MainActor.run { NotificationCenter.default.post(name: .atstoresSessionExpired, object: nil) }
                }
                return false
            }
            Session.shared.accessToken = access
            if let newRefresh = auth.refreshToken { Session.shared.refreshToken = newRefresh }
            #if DEBUG
            NSLog("[Auth] access token refreshed")
            #endif
            return true
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
}

extension Notification.Name {
    /// Posted when the refresh token is rejected; the app shows "Session expired" and logs out.
    static let atstoresSessionExpired = Notification.Name("atstoresSessionExpired")
}

/// Parsed `AuthResponse` (otp-login, refresh, store registration).
nonisolated struct AuthResult {
    var accessToken: String?
    var refreshToken: String?
    var mobile: String?
    var role: String?
    var userId: String?
    var uid: String?
    var user: JSONDict?

    init(_ d: JSONDict) {
        // Some endpoints wrap the payload in `data`.
        let src = d.dict("data").flatMap { $0.str("accessToken") != nil ? $0 : nil } ?? d
        accessToken = src.str("accessToken", "jwtToken", "token")
        refreshToken = src.str("refreshToken")
        mobile = src.str("mobile")
        role = src.str("role")
        userId = src.str("userId")
        uid = src.str("uid")
        user = src.dict("user")
        if userId == nil, let u = user { userId = u.str("userId", "id") }
    }

    var isStoreOwner: Bool {
        let r = (role ?? "").uppercased()
        return r == "STORE" || r == "ADMIN"
    }
}
