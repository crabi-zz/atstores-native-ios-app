import SwiftUI

/// Shared search call: stores plus stores inferred from matching products.
enum StoreSearch {
    static func search(_ keyword: String) async -> [Store]? {
        guard let d = await API.shared.object("api/public/search", query: ["keyword": keyword]) else { return nil }
        var results = d.dicts("stores").map(Store.init)
        for p in d.dicts("products").map(Product.init) where p.storeId > 0 && !results.contains(where: { $0.storeId == p.storeId }) {
            var s = Store()
            s.storeId = p.storeId
            s.storeName = p.productName
            s.storeImage = p.thumbnailImage
            s.storeCategoryName = p.categoryName
            results.append(s)
        }
        return results
    }
}

struct SearchView: View {
    var initialText: String = ""
    @State private var text = ""
    @State private var results: [Store] = []
    @State private var searched = false
    @State private var hintIndex = 0

    private let hints = ["Search near sports stores...", "Search for beauty salons...", "Search for restaurants...",
                         "Search for real estate...", "Search for clinics...", "Search for boutique..."]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                SearchField(prompt: hints[hintIndex], text: $text) { Task { await run(text) } }

                if text.trimmingCharacters(in: .whitespaces).count < 2 {
                    suggestions
                } else {
                    ForEach(results) { StoreRow(store: $0) }
                    if searched && results.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", text: "No results", detail: "Try a different name or category.")
                    }
                }
            }
            .padding()
        }
        .task(id: text) {
            // 500 ms debounce, minimum 2 characters.
            let q = text.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = []; searched = false; return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await run(q)
        }
        .task {
            if !initialText.isEmpty && text.isEmpty { text = initialText }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                hintIndex = (hintIndex + 1) % hints.count
            }
        }
        .navigationTitle("Search")
        .appHeader()
    }

    /// Shown before the user types: quick searches for popular categories.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Popular searches").font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(["Salon", "Spa", "Boutique", "Mobile", "Eyeware", "Shoes", "Cake", "Clinic", "Furniture"], id: \.self) { s in
                    Button { text = s } label: {
                        Label(s, systemImage: "magnifyingglass")
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.lightGray, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 8) {
                Image(systemName: "storefront").font(.system(size: 40)).foregroundStyle(.orange.opacity(0.8))
                Text("Find stores, salons and products near you")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private func run(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { results = []; return }
        results = await StoreSearch.search(trimmed) ?? []
        searched = true
    }
}

struct StoreListView: View {
    let categoryId: Int
    let title: String

    @State private var categories: [Category] = []
    @State private var selected: Category?
    @State private var stores: [Store] = []
    @State private var original: [Store] = []
    @State private var query = ""
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SearchField(prompt: "Search stores", text: $query) { Task { await search(query) } }
                    .padding(.horizontal)
                if !categories.isEmpty {
                    ChipBar(items: categories, title: \.name, selection: $selected) { cat in
                        Task { await load(cat.categoryId) }
                    }
                }
                LazyVStack(spacing: 12) {
                    ForEach(stores) { StoreRow(store: $0) }
                }
                .padding(.horizontal)
                if !loading && stores.isEmpty {
                    EmptyStateView(icon: "storefront", text: "No stores found", detail: "Try another category or search term.")
                }
            }
            .padding(.vertical)
        }
        .overlay { if loading && stores.isEmpty { SkeletonView(style: .list).background(Color(.systemBackground)) } }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            if q.isEmpty { stores = original; return }
            guard q.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await search(q)
        }
        .appHeader(title: title)
        .task {
            guard categories.isEmpty else { return }
            async let cats = API.shared.objects("api/public/category")
            await load(categoryId)
            categories = [Category.all] + (await cats).map(Category.init)
            selected = categories.first { $0.categoryId == categoryId } ?? categories.first
        }
    }

    private func load(_ catId: Int) async {
        loading = true
        defer { loading = false }
        let loc = LocationService.shared
        // Your location first, then the default Bangalore point (outside the service area nothing is "nearby").
        var points = [(loc.lat, loc.lng)]
        if loc.lat != 12.9698 { points.append((12.9698, 77.7500)) }
        var list: [Store] = []
        for (lat, lng) in points where list.isEmpty {
            if catId == 0 {
                list = await API.shared.objects("api/public/stores/nearby",
                                                query: ["lat": lat, "lng": lng, "radiusKm": 50, "page": 0, "size": 50],
                                                keys: ["content", "data", "list", "stores", "nearbyStores"]).map(Store.init)
            } else {
                list = await API.shared.objects("api/public/store/categoryId/radious/\(catId)",
                                                query: ["userLat": lat, "userLng": lng, "radius": 50]).map(Store.init)
            }
        }
        if list.isEmpty {
            // The all-stores endpoint requires the login token.
            let path = catId == 0 ? "api/public/stores" : "api/public/store/categoryId/\(catId)"
            list = await API.shared.objects(path, auth: true).map(Store.init)
        }
        original = list
        stores = original
    }

    private func search(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { stores = original; return }
        if let found = await StoreSearch.search(trimmed), !found.isEmpty {
            stores = found
        } else {
            let lower = trimmed.lowercased()
            stores = original.filter {
                $0.storeName.lowercased().contains(lower) || ($0.storeCategoryName ?? "").lowercased().contains(lower)
            }
        }
    }
}

struct OffersView: View {
    @State private var offers: [Offer] = []
    @State private var categories: [Category] = []
    @State private var selected: Category?
    @State private var loading = true

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !categories.isEmpty {
                    // The Android screen shows category chips but always reloads all offers.
                    ChipBar(items: categories, title: \.name, selection: $selected) { _ in Task { await load() } }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(offers) { OfferCard(offer: $0) }
                }
                .padding(.horizontal)
                if !loading && offers.isEmpty {
                    EmptyStateView(icon: "tag", text: "No offers right now", detail: "Check back soon for deals near you.")
                }
            }
            .padding(.vertical)
        }
        .overlay { if loading && offers.isEmpty { SkeletonView(style: .grid).background(Color(.systemBackground)) } }
        .refreshable { await load() }
        .navigationTitle("Offers")
        .appHeader()
        .task {
            guard categories.isEmpty else { return }
            async let cats = API.shared.objects("api/public/category")
            await load()
            categories = [Category.all] + (await cats).map(Category.init)
            selected = categories.first
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let loc = LocationService.shared
        var list = await API.shared.objects("api/public/offer/nearby", query: ["lat": loc.lat, "lng": loc.lng, "radiusKm": 50])
        if list.isEmpty { list = await API.shared.objects("api/public/offer") }
        offers = list.map(Offer.init).filter { !$0.isExpired }
    }
}

struct OfferCard: View {
    let offer: Offer
    var body: some View {
        NavigationLink(value: Route.product(offer.asProduct)) {
            VStack(alignment: .leading, spacing: 5) {
                Color.clear
                    .aspectRatio(1.25, contentMode: .fit)
                    .overlay { RemoteImage(url: offer.thumbnailImage, placeholder: "tag") }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        if offer.discount > 0 {
                            Text("\(offer.discount)% OFF").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 4)).padding(6)
                        }
                    }
                Text(offer.offerName).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                if let till = offer.validTillText {
                    Label(till, systemImage: "calendar").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Limited time offer").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Analytics.offer(offer) })
    }
}
