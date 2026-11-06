import SwiftUI

struct HomeView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var data = HomeData()
    @State private var loading = true
    @State private var loaded = false
    @State private var bannerIndex = 0

    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NavigationLink(value: Route.storeList(categoryId: 0, title: "All Stores")) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search stores, salons, products...")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(11)
                    .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if !data.banners.isEmpty { banners }

                if !data.categories.isEmpty {
                    SectionHeader(title: "Categories", route: .storeList(categoryId: 0, title: "All Categories"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(data.categories) { cat in
                                NavigationLink(value: Route.storeList(categoryId: cat.categoryId, title: cat.name)) {
                                    VStack(spacing: 5) {
                                        RemoteImage(url: cat.categoryImage, placeholder: "square.grid.2x2", contentMode: .fit)
                                            .padding(8)
                                            .frame(width: 52, height: 52)
                                            .background(Color.white, in: Circle())
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                                        Text(cat.name).font(.caption2.weight(.medium)).lineLimit(1).frame(width: 62)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !data.offers.isEmpty {
                    SectionHeader(title: "Today's Offers", route: nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(data.offers) { offer in HomeOfferCard(offer: offer) }
                        }
                        .padding(.horizontal)
                    }
                }

                storeSection("Nearby Stores", data.nearby, route: .storeList(categoryId: 0, title: "Nearby Stores"))

                if !data.trending.isEmpty {
                    SectionHeader(title: "Trending Products", route: .storeList(categoryId: 0, title: "Trending Products"))
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(data.trending) { ProductCard(product: $0) }
                    }
                    .padding(.horizontal)
                }

                storeSection("Salon & Spa", data.salon, route: .storeList(categoryId: 32, title: "Salon & Spa"))
                storeSection("Boutique", data.boutique, route: .storeList(categoryId: 19, title: "Boutique"))

                NavigationLink(value: Route.storeList(categoryId: 0, title: "All Stores")) {
                    HStack {
                        Image(systemName: "storefront")
                        Text("View All Stores").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Theme.primary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if loaded && !data.hasContent {
                    EmptyStateView(icon: "storefront", text: "No stores found near you")
                }
            }
            .padding(.vertical)
        }
        .overlay { if loading && !loaded { ProgressView() } }
        .refreshable { await load(force: true) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appHeader()
        .task {
            guard !loaded else { return }
            Analytics.activity("HOME_VIEWED", "User landed on Home")
            await load(force: false)
        }
    }

    private var banners: some View {
        TabView(selection: $bannerIndex) {
            ForEach(Array(data.banners.enumerated()), id: \.offset) { i, b in
                RemoteImage(url: b.bannerImage, placeholder: "photo")
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 170)
        .task(id: data.banners.count) {
            // Auto-advance every 4 seconds, like the Android banner slider.
            while !Task.isCancelled, data.banners.count > 1 {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { bannerIndex = (bannerIndex + 1) % max(data.banners.count, 1) }
            }
        }
    }

    @ViewBuilder
    private func storeSection(_ title: String, _ stores: [Store], route: Route) -> some View {
        if !stores.isEmpty {
            SectionHeader(title: title, route: route)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(stores) { StoreCard(store: $0) }
                }
                .padding(.horizontal)
            }
        }
    }

    private func load(force: Bool) async {
        loading = true
        defer { loading = false }
        if force { LocationService.shared.clearCache() }
        let loc = await LocationService.shared.current()
        var lat = loc?.lat ?? 12.9698
        var lng = loc?.lng ?? 77.7500
        do {
            var r = try await API.shared.send(.get, "api/public/mobilehome", query: ["lat": lat, "lng": lng])
            var home = (r.json as? JSONDict).map(HomeData.init)
            // Nothing nearby for this location (e.g. outside the service area): retry with the default coordinates.
            if let h = home, h.nearby.isEmpty, h.offers.isEmpty, h.salon.isEmpty,
               h.boutique.isEmpty, h.trending.isEmpty, lat != 12.9698 {
                lat = 12.9698; lng = 77.7500
                r = try await API.shared.send(.get, "api/public/mobilehome", query: ["lat": lat, "lng": lng])
                home = (r.json as? JSONDict).map(HomeData.init)
            }
            if r.ok, let home {
                data = home
                loaded = true
            }
        } catch {
            toast.show("Network Error. Please try again.")
        }
    }
}

struct HomeOfferCard: View {
    let offer: Offer
    var body: some View {
        NavigationLink(value: Route.product(offer.asProduct)) {
            VStack(alignment: .leading, spacing: 4) {
                RemoteImage(url: offer.thumbnailImage, placeholder: "tag")
                    .frame(width: 160, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        if offer.discount > 0 {
                            Text("\(offer.discount)% OFF").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 4)).padding(6)
                        }
                    }
                Text(offer.offerName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("AtStores").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 160, alignment: .leading)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Analytics.offer(offer) })
    }
}
