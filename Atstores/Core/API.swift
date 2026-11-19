import Foundation
import UIKit

enum HTTPMethod: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

struct APIResponse {
    let status: Int
    let data: Data
    var ok: Bool { (200..<300).contains(status) }
    var json: Any? { JSON.parse(data) }
    var text: String { String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var isTrue: Bool { ok && ["true", "1"].contains(text.lowercased()) }

    /// Extracts `error` / `message` from an error body, like the Android toasts did.
    func errorMessage(_ fallback: String) -> String {
        if let d = json as? JSONDict, let m = d.str("error", "message") { return m }
        if !text.isEmpty, !text.hasPrefix("<"), text.count < 200 { return text }
        return fallback
    }
}

/// Port of ApiService + RetrofitClient: one URLSession client, bearer auth,
/// and a single-flight token refresh on HTTP 401.
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

    func send(_ method: HTTPMethod, _ path: String, query: [String: Any] = [:], body: Any? = nil,
              auth: Bool = false, bearer: String? = nil) async throws -> APIResponse {
        var request = makeRequest(method, path, query: query)
        var body = body
        // Logins send this phone's id, so the server keeps one login per device
        // (logging in elsewhere no longer logs this phone out).
        if path.hasSuffix("auth/otp-login") || path.hasSuffix("auth/login"),
           var dict = body as? [String: Any], dict["deviceId"] == nil {
            dict["deviceId"] = Self.deviceId
            body = dict
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request, auth: auth, bearer: bearer)
    }

    func upload(_ path: String, field: String, filename: String, data: Data, mime: String) async throws -> APIResponse {
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
        return try await perform(request, auth: true, bearer: nil)
    }

    // MARK: Convenience (errors -> nil / empty / false)

    func json(_ method: HTTPMethod = .get, _ path: String, query: [String: Any] = [:], body: Any? = nil, auth: Bool = false) async -> Any? {
        guard let r = try? await send(method, path, query: query, body: body, auth: auth), r.ok else { return nil }
        return r.json
    }

    func objects(_ path: String, query: [String: Any] = [:], auth: Bool = false, keys: [String] = ["data", "content", "list"]) async -> [JSONDict] {
        JSON.objects(from: await json(.get, path, query: query, auth: auth), preferredKeys: keys)
    }

    func object(_ path: String, query: [String: Any] = [:], auth: Bool = false) async -> JSONDict? {
        await json(.get, path, query: query, auth: auth) as? JSONDict
    }

    func ok(_ method: HTTPMethod, _ path: String, body: Any? = nil, auth: Bool = false) async -> Bool {
        (try? await send(method, path, body: body, auth: auth))?.ok ?? false
    }

    // MARK: Internals

    private func makeRequest(_ method: HTTPMethod, _ path: String, query: [String: Any]) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        // appendingPathComponent re-encodes; rebuild the path from the already-encoded string.
        comps.percentEncodedPath = "/" + path
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = method.rawValue
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func perform(_ request: URLRequest, auth: Bool, bearer: String?) async throws -> APIResponse {
        var req = request
        // The access token lives 24 h. After the phone has been idle it is usually expired:
        // refresh first instead of sending a request we know will fail.
        if auth, bearer == nil, Self.isExpiringSoon(Session.shared.accessToken), !Session.shared.refreshToken.isEmpty {
            _ = await refreshTokens()
        }
        let token = bearer ?? (auth ? Session.shared.accessToken : "")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var response = try await rawRetryingIdle(req)
        if response.status == 401, auth, bearer == nil {
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

    /// Refresh now if the access token is (nearly) expired - called when the app comes to the foreground.
    func refreshIfNeeded() async {
        guard Session.shared.isLoggedIn, Self.isExpiringSoon(Session.shared.accessToken),
              !Session.shared.refreshToken.isEmpty else { return }
        _ = await refreshTokens()
    }

    private func refreshTokens() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task<Bool, Never> {
            let s = Session.shared
            let refresh = s.refreshToken
            guard !refresh.isEmpty else { return false }
            // Sent without a Bearer header: the server rejects any request carrying an expired token.
            var req = makeRequest(.post, "api/auth/refresh", query: [:])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refresh])
            guard let r = try? await raw(req) else { return false }   // offline: stay logged in
            guard r.ok, let d = r.json as? JSONDict, let access = d.str("accessToken") else {
                // The backend reports an invalid / expired refresh token as a 4xx or a 500 whose
                // message mentions it; any other 5xx is a temporary problem, so keep the user logged in.
                let rejected = (400..<500).contains(r.status) || r.text.lowercased().contains("refresh token")
                if rejected, s.isLoggedIn {
                    await MainActor.run { NotificationCenter.default.post(name: .atstoresSessionExpired, object: nil) }
                }
                return false
            }
            s.accessToken = access
            if let newRefresh = d.str("refreshToken") { s.refreshToken = newRefresh }
            return true
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }
}

/// VisitorLogger + ActivityLogger: fire-and-forget analytics calls.
enum Analytics {
    static func visit(storeId: Int, productId: Int = 0, serviceId: Int = 0, offerId: Int = 0,
                      type: String, name: String?, category: String?) {
        let s = Session.shared
        let body: [String: Any] = [
            "userId": s.numericUserId, "storeId": storeId, "productId": productId,
            "serviceId": serviceId, "offerId": offerId, "type": type,
            "customerMobile": s.contactMobile, "storeName": name ?? "",
            "storeCategory": category ?? "", "clickDate": Format.isoNow()
        ]
        Task { _ = try? await API.shared.send(.post, "api/public/visitor", body: body) }
    }

    static func store(_ store: Store) {
        visit(storeId: store.storeId, type: "STORE_VIEW", name: store.storeName, category: store.storeCategoryName)
    }

    static func product(_ p: Product, storeName: String?) {
        visit(storeId: p.storeId, productId: p.productId, type: "PRODUCT_VIEW", name: p.productName, category: storeName)
    }

    static func offer(_ o: Offer) {
        visit(storeId: o.storeIdInt, offerId: o.offerId, type: "OFFER_VIEW", name: o.offerName, category: "Offer")
    }

    static func activity(_ event: String, _ data: String) {
        let s = Session.shared
        let body: [String: Any] = ["userId": s.uid.isEmpty ? s.anonymousId : s.uid, "eventType": event, "eventData": data]
        Task { _ = try? await API.shared.send(.post, "api/user-activity/log", body: body) }
    }
}

extension Notification.Name {
    /// Posted when the refresh token is rejected; the app shows "Session expired" and logs out.
    static let atstoresSessionExpired = Notification.Name("atstoresSessionExpired")
}
