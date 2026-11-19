//
//  AtstoresAdminApp.swift
//  AtstoresAdmin
//
//  iOS port of the AtStores Store Admin Android app (com.interaps.storeadmin).
//

import SwiftUI

@main
struct AtstoresAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var toast = ToastCenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Test hook (debug builds only): `-tokenTest expired` / `-tokenTest invalid` swaps the stored
        // access token at launch to reproduce "phone was idle for a day" without waiting 24 h.
        if let mode = UserDefaults.standard.string(forKey: "tokenTest"), Session.shared.isLoggedIn {
            func b64(_ s: String) -> String {
                Data(s.utf8).base64EncodedString()
                    .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            }
            let exp = Int(Date().timeIntervalSince1970) + (mode == "expired" ? -3600 : 3600)
            Session.shared.accessToken = b64("{\"alg\":\"HS256\"}") + "." + b64("{\"sub\":\"0\",\"exp\":\(exp)}") + ".invalid"
            NSLog("[TokenTest] access token replaced (%@)", mode)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(toast)
                .toastOverlay(toast)
                .tint(Theme.primary)
                .preferredColorScheme(.light)
                // Refresh token rejected (expired after 30 days, or revoked): back to login.
                .onReceive(NotificationCenter.default.publisher(for: .atstoresSessionExpired)) { _ in
                    if Session.shared.isLoggedIn { Session.shared.expire(toast) }
                }
        }
        // Coming back after the phone was idle: renew the 24 h access token before screens reload.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, Session.shared.isLoggedIn {
                Task { await API.shared.refreshIfNeeded() }
            }
        }
    }
}

/// SplashActivity routing: logged in -> dashboard, token but no store -> register store, else login.
struct RootView: View {
    @State private var showSplash = true
    private var session = Session.shared

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
            } else if session.isLoggedIn {
                MainTabView()
            } else if session.needsStore {
                NavigationStack { StoreFormView(storeId: 0, onboarding: true).appDestinations() }
            } else {
                NavigationStack { LoginView() }
            }
        }
        .animation(.easeInOut, value: session.isLoggedIn)
        .animation(.easeInOut, value: session.needsStore)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSplash = false }
        }
    }
}

/// Matches the launch screen (blue + centred bag) so the hand-off is seamless,
/// then adds the wordmark and a spinner like activity_splash.xml.
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.primary.ignoresSafeArea()
            Image("BagMark")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .overlay(alignment: .bottom) {
                    BrandWordmark(size: 38)
                        .fixedSize()
                        .offset(y: 86)
                }
            VStack {
                Spacer()
                ProgressView().tint(.white).controlSize(.regular).padding(.bottom, 48)
            }
        }
    }
}

/// "AtStores" in the brand colours with a "STORE ADMIN" caption.
struct BrandWordmark: View {
    var size: CGFloat = 34
    var body: some View {
        VStack(spacing: size * 0.12) {
            (Text("At").foregroundStyle(Theme.secondary) + Text("Stores").foregroundStyle(.white))
                .font(.system(size: size, weight: .heavy, design: .rounded))
            Text("STORE ADMIN")
                .font(.system(size: size * 0.34, weight: .semibold))
                .kerning(size * 0.1)
                .foregroundStyle(.white.opacity(0.85))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct MainTabView: View {
    enum Tab: Hashable { case dashboard, bookings, visitors, settings }
    @State private var tab: Tab = .dashboard
    @State private var dashboard = Router()
    @State private var bookings = Router()
    @State private var visitors = Router()
    @State private var settings = Router()
    private var session = Session.shared
    private var push = PushService.shared

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $dashboard.path) { DashboardView().appDestinations() }
                .environment(dashboard)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }.tag(Tab.dashboard)
            // Bookings only for service stores (BaseActivity.setupFooter).
            if session.hasBookingStore || session.isServiceStore {
                NavigationStack(path: $bookings.path) { BookingsView(openBookingId: 0, storeId: 0, pushed: false).appDestinations() }
                    .environment(bookings)
                    .tabItem { Label("Bookings", systemImage: "calendar.badge.clock") }.tag(Tab.bookings)
            }
            NavigationStack(path: $visitors.path) { VisitorView().appDestinations() }
                .environment(visitors)
                .tabItem { Label("Visitors", systemImage: "chart.bar.xaxis") }.tag(Tab.visitors)
            NavigationStack(path: $settings.path) { SettingsView().appDestinations() }
                .environment(settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(Tab.settings)
        }
        // Ask for notification permission once logged in, and keep the server's FCM token current.
        .task {
            #if DEBUG
            // Demo screenshots: don't cover screens with the permission prompt.
            if UserDefaults.standard.bool(forKey: "demo") { return }
            #endif
            PushService.shared.requestPermission()
            await PushService.shared.syncToken()
        }
        .onChange(of: push.pendingBookingId, initial: true) { _, id in openBooking(id) }
        #if DEBUG
        .task { openDebugScreen() }
        #endif
    }

    /// Notification tap -> open that booking (Android: BookingsActivity with openBookingId).
    private func openBooking(_ id: Int) {
        guard id > 0 else { return }
        push.pendingBookingId = 0
        let route = Route.bookings(openBookingId: id, storeId: 0)
        if session.hasBookingStore || session.isServiceStore {
            bookings.path = [route]
            tab = .bookings
        } else {
            dashboard.path.append(route)
            tab = .dashboard
        }
    }

    #if DEBUG
    /// Debug-only: `simctl launch <device> <bundle> -screen offers` opens a screen directly.
    private func openDebugScreen() {
        guard let name = UserDefaults.standard.string(forKey: "screen") else { return }
        let id = session.selectedStoreId
        let routes: [String: Route] = [
            "store": .store(id), "storeForm": .storeForm(id), "register": .storeForm(0),
            "addProduct": .productForm(storeId: id, product: nil), "categories": .categories(id),
            "offers": .offers(id), "createOffer": .createOffer, "selectProducts": .selectOfferProducts,
            "offerForm": .offerForm(OfferSeed()), "customers": .customers(id), "addCustomer": .customerForm(nil),
            "share": .shareStore(storeId: id, storeName: session.selectedStoreName),
            "orders": .orders, "notifications": .notifications, "editProfile": .editProfile, "faq": .helpFaq,
            "support": .contactSupport, "website": .storeWebsite, "requestWebsite": .requestWebsite,
            "privacy": .content(title: "Privacy Policy", type: "PRIVACY_POLICY"),
            "productCustomers": .productCustomers(storeId: id, productId: 0, title: "Product Customers"),
            "preview": .offerPreview(OfferDraft(offerName: "Weekend Special", description: "Flat discount on all services",
                                                discount: 20, startDate: "07 Nov 2026", endDate: "14 Nov 2026",
                                                terms: "Valid on weekends only", productName: "Hair Spa",
                                                originalPrice: 1200, offerPrice: 960))
        ]
        switch name {
        case "bookings": tab = .bookings
        case "visitors": tab = .visitors
        case "settings": tab = .settings
        default: if let r = routes[name] { dashboard.path = [r] }
        }
    }
    #endif
}
