//
//  AtstoresApp.swift
//  Atstores
//
//  Created by Rabindra on 06/11/26.
//

import SwiftUI

@main
struct AtstoresApp: App {
    @State private var toast = ToastCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(toast)
                .toastOverlay(toast)
                .tint(.orange)
                // The brand colours are designed for light backgrounds; keep the app in Light Mode.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @State private var showSplash = true
    @Environment(ToastCenter.self) private var toast
    @Environment(\.scenePhase) private var scenePhase
    private var session = Session.shared

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
            } else if session.isLoggedIn {
                MainTabView()
            } else {
                NavigationStack { LoginView() }
            }
        }
        .animation(.easeInOut, value: session.isLoggedIn)
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSplash = false }
        }
        // Coming back after hours idle: renew the 24 h access token before screens load data.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await API.shared.refreshIfNeeded() } }
        }
        // Refresh token expired (30 days unused) or revoked: go back to login with a message.
        .onReceive(NotificationCenter.default.publisher(for: .atstoresSessionExpired)) { _ in
            guard session.isLoggedIn else { return }
            session.logout()
            toast.show("Session expired. Please log in again.", long: true)
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(hex: 0xF9B800).ignoresSafeArea()
            Image("SplashLogo").resizable().scaledToFit().frame(width: 220)
        }
    }
}

struct MainTabView: View {
    enum Tab { case home, search, offers, profile }
    @State private var tab: Tab = .home
    @State private var homePath: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $homePath) { HomeView().appDestinations() }
                .tabItem { Label("Home", systemImage: "house") }.tag(Tab.home)
            NavigationStack { SearchView().appDestinations() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Tab.search)
            NavigationStack { OffersView().appDestinations() }
                .tabItem { Label("Offers", systemImage: "tag") }.tag(Tab.offers)
            NavigationStack { ProfileView().appDestinations() }
                .tabItem { Label("Profile", systemImage: "person") }.tag(Tab.profile)
        }
        #if DEBUG
        .task { await openDebugScreen() }
        #endif
    }

    #if DEBUG
    /// Debug-only: `simctl launch <device> <bundle> -screen wishlist` opens a screen directly,
    /// so screens can be reviewed without tapping. Not compiled into release builds.
    private func openDebugScreen() async {
        guard let name = UserDefaults.standard.string(forKey: "screen") else { return }
        switch name {
        case "search": tab = .search
        case "offers": tab = .offers
        case "profile": tab = .profile
        default:
            let parts = name.split(separator: ":").map(String.init)
            let id = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            var store = Store(); store.storeId = id; store.storeName = "Store"
            let routes: [String: Route] = [
                "wishlist": .wishlist, "bookings": .bookings, "orders": .orders, "coupons": .coupons,
                "saved": .savedStores, "notifications": .notifications, "edit": .editProfile,
                "help": .help, "privacy": .privacy, "version": .appVersion,
                "about": .content(title: "About Atstores", type: "ABOUT_US"),
                "terms": .content(title: "Terms & Conditions", type: "TERMS_CONDITIONS"),
                "list": .storeList(categoryId: 0, title: "All Stores"),
                "store": .store(store),
                "booking": .booking(storeId: id, storeName: "Salon", category: "Salon & Spa")
            ]
            if parts[0] == "product" {
                // Open the store's first product.
                if let p = await API.shared.objects("api/public/product/storeId/\(id)").first {
                    homePath = [.product(Product(p))]
                }
            } else if let r = routes[parts[0]] {
                homePath = [r]
            }
        }
    }
    #endif
}
