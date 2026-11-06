import Foundation

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
        let token = bearer ?? (auth ? Session.shared.accessToken : "")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var response = try await raw(req)
        if response.status == 401, auth, bearer == nil {
            let current = Session.shared.accessToken
            // Another request may already have refreshed the token.
            let refreshed = (!current.isEmpty && current != token) ? true : await refreshTokens()
            if refreshed {
                req.setValue("Bearer \(Session.shared.accessToken)", forHTTPHeaderField: "Authorization")
                response = try await raw(req)
            }
        }
        return response
    }

    private func raw(_ req: URLRequest) async throws -> APIResponse {
        let (data, resp) = try await session.data(for: req)
        return APIResponse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    private func refreshTokens() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task<Bool, Never> {
            let s = Session.shared
            let refresh = s.refreshToken
            guard !refresh.isEmpty else { return false }
            var body: [String: String] = ["refreshToken": refresh, "refresh_token": refresh, "token": refresh]
            if !s.uid.isEmpty { body["userId"] = s.uid; body["uid"] = s.uid }
            guard let r = try? await send(.post, "api/auth/refresh", body: body), r.ok,
                  let d = r.json as? JSONDict, let access = d.str("accessToken") else { return false }
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
