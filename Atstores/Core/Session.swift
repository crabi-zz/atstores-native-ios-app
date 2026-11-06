import Foundation
import Security

/// Small Keychain wrapper for the access / refresh tokens.
enum Keychain {
    private static let service = "in.atstores.tokens"

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Equivalent of the Android "AtStores" SharedPreferences.
@Observable
final class Session {
    static let shared = Session()

    private let defaults = UserDefaults.standard

    var isLoggedIn: Bool { didSet { defaults.set(isLoggedIn, forKey: "isLogin") } }
    var uid: String { didSet { defaults.set(uid, forKey: "uid") } }
    var mobileNumber: String { didSet { defaults.set(mobileNumber, forKey: "mobile_number") } }
    /// Raw JSON of the last `GET /api/users/{id}` response (Android: `user_data`).
    var userData: JSONDict? {
        didSet {
            if let userData, let data = JSON.data(userData) { defaults.set(data, forKey: "user_data") }
            else { defaults.removeObject(forKey: "user_data") }
        }
    }

    var accessToken: String { get { Keychain.get("access_token") ?? "" } set { Keychain.set(newValue, for: "access_token") } }
    var refreshToken: String { get { Keychain.get("refresh_token") ?? "" } set { Keychain.set(newValue, for: "refresh_token") } }

    private init() {
        isLoggedIn = defaults.bool(forKey: "isLogin")
        uid = defaults.string(forKey: "uid") ?? ""
        mobileNumber = defaults.string(forKey: "mobile_number") ?? ""
        if let data = defaults.data(forKey: "user_data") { userData = JSON.parse(data) as? JSONDict }
        // Keychain survives reinstall; drop stale tokens when the app was reinstalled.
        if !isLoggedIn { Keychain.set(nil, for: "access_token"); Keychain.set(nil, for: "refresh_token") }
    }

    var user: UserProfile? { userData.map(UserProfile.init) }

    /// Numeric user id from the cached profile, falling back to a numeric uid.
    var numericUserId: Int {
        if let id = user?.id, id > 0 { return id }
        return Int(uid) ?? 0
    }

    /// The Android app tried several ids against each endpoint (numeric id, uid, mobile).
    var candidateIds: [String] {
        var ids: [String] = []
        if let id = user?.id, id > 0 { ids.append(String(id)) }
        if !uid.isEmpty, !ids.contains(uid) { ids.append(uid) }
        if !mobileNumber.isEmpty, !ids.contains(mobileNumber) { ids.append(mobileNumber) }
        return ids
    }

    var contactMobile: String {
        if let m = user?.contactNo, !m.isEmpty { return m }
        if !mobileNumber.isEmpty { return mobileNumber }
        if uid.hasPrefix("+91") || (uid.count == 10 && uid.allSatisfy(\.isNumber)) { return uid }
        return ""
    }

    var anonymousId: String {
        if let id = defaults.string(forKey: "anonymous_id") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "anonymous_id")
        return id
    }

    func saveLogin(userId: String?, accessToken: String?, refreshToken: String?, mobile: String?, fallbackMobile: String) {
        uid = userId ?? fallbackMobile
        self.accessToken = accessToken ?? ""
        self.refreshToken = refreshToken ?? ""
        mobileNumber = mobile ?? fallbackMobile
        isLoggedIn = true
    }

    func logout() {
        let token = refreshToken
        let bearer = accessToken
        if !token.isEmpty {
            Task { _ = try? await API.shared.send(.post, "api/auth/logout", body: ["refreshToken": token], bearer: bearer) }
        }
        accessToken = ""
        refreshToken = ""
        uid = ""
        mobileNumber = ""
        userData = nil
        isLoggedIn = false
    }
}
