import Foundation
import Security

/// Small Keychain wrapper for the access / refresh tokens.
enum Keychain {
    private static let service = "in.atstores.admin.tokens"

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

/// Equivalent of the Android "AtStoresStoreAdmin" SharedPreferences.
@Observable
final class Session {
    static let shared = Session()

    private let defaults = UserDefaults.standard

    /// true once the user is a store owner (Android `isLogin`).
    var isLoggedIn: Bool { didSet { defaults.set(isLoggedIn, forKey: "isLogin") } }
    /// OTP verified but no store yet: the user must register a store first.
    var needsStore: Bool { didSet { defaults.set(needsStore, forKey: "needsStore") } }
    var userId: String { didSet { defaults.set(userId, forKey: "user_id") } }
    var uid: String { didSet { defaults.set(uid, forKey: "uid") } }
    var mobileNumber: String { didSet { defaults.set(mobileNumber, forKey: "mobile_number") } }
    var role: String { didSet { defaults.set(role, forKey: "role") } }
    var userData: JSONDict? {
        didSet {
            if let userData, let data = JSON.data(userData) { defaults.set(data, forKey: "user_data") }
            else { defaults.removeObject(forKey: "user_data") }
        }
    }

    // Currently selected store (Android `selectedStoreId` / `selectedStoreName` / `selectedStoreCategory`).
    var selectedStoreId: Int { didSet { defaults.set(selectedStoreId, forKey: "selectedStoreId") } }
    var selectedStoreName: String { didSet { defaults.set(selectedStoreName, forKey: "selectedStoreName") } }
    var selectedStoreCategory: String { didSet { defaults.set(selectedStoreCategory, forKey: "selectedStoreCategory") } }
    var hasBookingStore: Bool { didSet { defaults.set(hasBookingStore, forKey: "has_booking_store") } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notifications_enabled") } }

    var accessToken: String { get { Keychain.get("access_token") ?? "" } set { Keychain.set(newValue, for: "access_token") } }
    var refreshToken: String { get { Keychain.get("refresh_token") ?? "" } set { Keychain.set(newValue, for: "refresh_token") } }

    private init() {
        isLoggedIn = defaults.bool(forKey: "isLogin")
        needsStore = defaults.bool(forKey: "needsStore")
        userId = defaults.string(forKey: "user_id") ?? ""
        uid = defaults.string(forKey: "uid") ?? ""
        mobileNumber = defaults.string(forKey: "mobile_number") ?? ""
        role = defaults.string(forKey: "role") ?? ""
        selectedStoreId = defaults.integer(forKey: "selectedStoreId")
        selectedStoreName = defaults.string(forKey: "selectedStoreName") ?? ""
        selectedStoreCategory = defaults.string(forKey: "selectedStoreCategory") ?? ""
        hasBookingStore = defaults.bool(forKey: "has_booking_store")
        notificationsEnabled = defaults.object(forKey: "notifications_enabled") as? Bool ?? true
        if let data = defaults.data(forKey: "user_data") { userData = JSON.parse(data) as? JSONDict }
        // Keychain survives reinstall; drop stale tokens when the app was reinstalled.
        if !isLoggedIn && !needsStore { Keychain.set(nil, for: "access_token"); Keychain.set(nil, for: "refresh_token") }
    }

    /// `KEY_USER_ID` falling back to `KEY_UID`, as the Android screens read it.
    var effectiveUserId: String { userId.isEmpty ? uid : userId }

    /// Mobile / uid / userId with a +91 prefix for 10-digit numbers (HomeActivity.getStoreLookupIdentifier).
    var storeLookupIdentifier: String {
        for raw in [mobileNumber, uid, userId] where !raw.isEmpty {
            return (!raw.hasPrefix("+") && raw.count == 10) ? "+91" + raw : raw
        }
        return ""
    }

    var displayName: String { userData?.str("fullName", "name") ?? "" }
    var email: String { userData?.str("email") ?? "" }
    var city: String { userData?.str("city") ?? "" }

    var isServiceStore: Bool { Store.isServiceCategory(selectedStoreCategory) }

    func select(_ store: Store) {
        selectedStoreId = store.storeId
        selectedStoreName = store.storeName
        selectedStoreCategory = store.storeCategoryName ?? ""
    }

    /// OtpActivity.saveUserCredentials.
    func saveLogin(_ auth: AuthResult, fallbackMobile: String) {
        accessToken = auth.accessToken ?? ""
        refreshToken = auth.refreshToken ?? ""
        userId = auth.userId ?? ""
        uid = auth.userId ?? auth.uid ?? ""
        mobileNumber = (auth.mobile?.isEmpty == false ? auth.mobile : nil) ?? fallbackMobile
        role = auth.role ?? (auth.isStoreOwner ? "STORE" : "CUSTOMER")
        if let user = auth.user { userData = user }
        isLoggedIn = auth.isStoreOwner
        needsStore = !auth.isStoreOwner
    }

    /// RegisterStoreActivity.saveRegisteredStoreUser.
    func markStoreRegistered(_ auth: AuthResult?) {
        if let a = auth {
            if let t = a.accessToken, !t.isEmpty { accessToken = t }
            if let t = a.refreshToken, !t.isEmpty { refreshToken = t }
            if let id = a.userId, !id.isEmpty { userId = id; uid = id }
            if let m = a.mobile, !m.isEmpty { mobileNumber = m }
            if let u = a.user { userData = u }
        }
        role = "STORE"
        needsStore = false
        isLoggedIn = true
    }

    func updateUserData(name: String, email: String, city: String) {
        var d = userData ?? [:]
        d["fullName"] = name
        d["name"] = name
        d["email"] = email
        d["city"] = city
        userData = d
    }

    /// HTTP 401 on a core screen: end the session (Android cleared prefs and reopened Login).
    func expire(_ toast: ToastCenter) {
        #if DEBUG
        // `-demo YES` keeps a fake session alive so screens can be reviewed without a real login.
        if UserDefaults.standard.bool(forKey: "demo") { return }
        #endif
        toast.show("Session expired. Please login again.", long: true)
        logout()
    }

    func logout() {
        accessToken = ""
        refreshToken = ""
        userId = ""
        uid = ""
        mobileNumber = ""
        role = ""
        userData = nil
        selectedStoreId = 0
        selectedStoreName = ""
        selectedStoreCategory = ""
        hasBookingStore = false
        needsStore = false
        isLoggedIn = false
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("website_request_status_") {
            defaults.removeObject(forKey: key)
        }
        AppState.shared.stores = []
    }

    // Website request status per store (StoreWebsiteActivity).
    func websiteRequestStatus(_ storeId: Int) -> String { defaults.string(forKey: "website_request_status_\(storeId)") ?? "NONE" }
    func setWebsiteRequestStatus(_ storeId: Int, _ status: String) { defaults.set(status, forKey: "website_request_status_\(storeId)") }
}

/// Stores owned by the logged-in admin, shared by the dashboard, bookings and visitors tabs.
@Observable
final class AppState {
    static let shared = AppState()
    var stores: [Store] = []
    var loading = false
    var loaded = false

    /// GET api/store/byuid/{identifier}, falling back to the raw user id (HomeActivity.loadAdminStores).
    /// Returns false on HTTP 401 so the caller can end the session.
    @discardableResult
    func loadStores() async -> Bool {
        let s = Session.shared
        let identifier = s.storeLookupIdentifier
        guard !identifier.isEmpty else { return true }
        loading = true
        defer { loading = false; loaded = true }
        var response = try? await API.shared.send(.get, "api/store/byuid/\(API.seg(identifier))")
        if response?.ok != true {
            let raw = s.effectiveUserId
            if !raw.isEmpty, raw != identifier {
                response = try? await API.shared.send(.get, "api/store/byuid/\(API.seg(raw))")
            } else if response?.status == 401 {
                return false
            }
        }
        guard let r = response, r.ok else { return true }
        stores = JSON.objects(from: r.json).map(Store.init)
        s.hasBookingStore = stores.contains { Store.isBookingCategory($0.storeCategoryName) }
        if (s.selectedStoreId == 0 || !stores.contains { $0.storeId == s.selectedStoreId }), let first = stores.first {
            s.select(first)
        }
        return true
    }
}
