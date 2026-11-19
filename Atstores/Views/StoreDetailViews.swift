import SwiftUI

struct StoreDetailView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var store: Store
    @State private var categories: [Category] = []
    @State private var selectedCategory: Category?
    @State private var allProducts: [Product] = []
    @State private var saved = false
    @State private var myRating: Double = 0
    @State private var myReview = ""
    @State private var showRating = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(initial: Store) { _store = State(initialValue: initial) }

    private var products: [Product] {
        guard let cat = selectedCategory, cat.categoryId != 0 || cat.name != "All" else { return allProducts }
        let target = cat.name.trimmingCharacters(in: .whitespaces).lowercased()
        return allProducts.filter {
            let p = ($0.categoryName ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return p.contains(target) || target.contains(p)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                storeHeader
                    .padding(.horizontal)
                    .padding(.top, 12)

                actionRow
                    .padding(.horizontal)

                Section {
                    if products.isEmpty {
                        Text(allProducts.isEmpty ? "No products yet" : "No products in this category")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(products) { ProductCard(product: $0, storeName: store.storeName) }
                        }
                        .padding(.horizontal)
                    }
                } header: {
                    // Stays pinned at the top while scrolling the products.
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(store.isSalon ? "Services" : "Products").font(.headline)
                            if !allProducts.isEmpty {
                                Text("\(products.count)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        if categories.count > 1 {
                            ChipBar(items: categories, title: \.name, selection: $selectedCategory)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                }
            }
            .padding(.bottom)
        }
        .refreshable {
            async let a: Void = loadDetails()
            async let b: Void = loadProducts()
            _ = await (a, b)
        }
        .appHeader(title: "Store Details")
        .sheet(isPresented: $showRating) {
            RateStoreSheet(storeId: store.storeId, initialRating: myRating, initialReview: myReview) {
                Task { await loadDetails(); await checkRating() }
            }
            .presentationDetents([.medium])
        }
        .task {
            guard store.storeId > 0, allProducts.isEmpty else { return }
            Analytics.store(store)
            async let a: Void = loadDetails()
            async let b: Void = loadProducts()
            async let c: Void = loadCategories()
            async let d: Void = checkSaved()
            async let e: Void = checkRating()
            _ = await (a, b, c, d, e)
        }
    }

    // MARK: Compact header

    /// Store photo, name, rating, status and address in one card (about 120pt instead of half the screen).
    private var storeHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: store.storeImage, placeholder: "storefront")
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(store.storeName).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    Button { Task { await toggleSave() } } label: {
                        Image(systemName: saved ? "heart.fill" : "heart")
                            .font(.body)
                            .foregroundStyle(saved ? Theme.heart : .secondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.lightGray, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(saved ? "Remove from saved" : "Save store")
                }

                HStack(spacing: 6) {
                    if let cat = store.storeCategoryName, !cat.isEmpty {
                        Text(cat).foregroundStyle(.secondary)
                    }
                    if store.avgRating > 0 {
                        Text("·").foregroundStyle(.secondary)
                        Text(String(format: "%.1f ★", store.avgRating)).bold().foregroundStyle(.orange)
                        if store.ratingCount > 0 { Text("(\(store.ratingCount))").foregroundStyle(.secondary) }
                    }
                }
                .font(.caption)
                .lineLimit(1)

                HStack(spacing: 6) {
                    if let open = store.isOpenNow {
                        Text(open ? "Open now" : "Closed").bold().foregroundStyle(open ? Theme.open : Theme.closed)
                    }
                    if let start = store.startTime.nonEmpty, let end = store.endTime.nonEmpty {
                        Text("\(Format.hour(start)) – \(Format.hour(end))").foregroundStyle(.secondary)
                    }
                    if let km = store.distanceKm(fromLat: LocationService.shared.lat, lng: LocationService.shared.lng) {
                        Text("· " + (Format.km(km) == "Nearby" ? "Nearby" : Format.km(km))).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)

                if let address = store.storeAddress, !address.isEmpty {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// One row of small actions instead of big circles plus two large buttons.
    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if store.isSalon {
                    NavigationLink(value: Route.booking(storeId: store.storeId, storeName: store.storeName,
                                                        category: store.storeCategoryName ?? "")) {
                        pill("Book Now", "calendar", filled: true)
                    }
                    .buttonStyle(.plain)
                }
                Button { StoreActions.call(store.storeContactNo, toast: toast) } label: { pill("Call", "phone.fill") }
                    .buttonStyle(.plain)
                Button { StoreActions.whatsApp(store.storeContactNo, toast: toast) } label: { pill("WhatsApp", "message.fill") }
                    .buttonStyle(.plain)
                Button { StoreActions.location(store.storeAddress, toast: toast) } label: { pill("Directions", "map.fill") }
                    .buttonStyle(.plain)
                if let site = store.storeWebsite, !site.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { StoreActions.website(store.storeWebsite, toast: toast) } label: { pill("Website", "globe") }
                        .buttonStyle(.plain)
                }
                Button {
                    if Session.shared.uid.isEmpty || Session.shared.accessToken.isEmpty {
                        toast.show("Please login to rate")
                    } else {
                        showRating = true
                    }
                } label: { pill(myRating > 0 ? "Edit Rating" : "Rate", "star.fill") }
                    .buttonStyle(.plain)
            }
        }
    }

    private func pill(_ title: String, _ icon: String, filled: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(filled ? Theme.primary : Theme.primary.opacity(0.18), in: Capsule())
            .foregroundStyle(.black)
    }

    private func loadDetails() async {
        guard let d = await API.shared.object("api/public/store/\(store.storeId)") else { return }
        let fresh = Store(d)
        if d.str("storeName") != nil { store.storeName = fresh.storeName }
        if let cat = fresh.storeCategoryName { store.storeCategoryName = cat.trimmingCharacters(in: .whitespaces) }
        else if fresh.storeCategoryId > 0 {
            let cats = await API.shared.objects("api/public/category").map(Category.init)
            if let name = cats.first(where: { $0.categoryId == fresh.storeCategoryId })?.name, !name.isEmpty {
                store.storeCategoryName = name
            }
        }
        if fresh.startTime != nil || fresh.endTime != nil { store.startTime = fresh.startTime; store.endTime = fresh.endTime }
        store.avgRating = fresh.avgRating
        store.ratingCount = fresh.ratingCount
        if store.storeContactNo == nil { store.storeContactNo = fresh.storeContactNo }
        if store.storeWebsite == nil { store.storeWebsite = fresh.storeWebsite }
        if store.storeAddress == nil { store.storeAddress = fresh.storeAddress }
        if store.storeImage == nil { store.storeImage = fresh.storeImage }
    }

    private func loadProducts() async {
        allProducts = await API.shared.objects("api/public/product/storeId/\(store.storeId)").map(Product.init)
    }

    private func loadCategories() async {
        let list = await API.shared.objects("api/public/storeCategory/storeId/\(store.storeId)").map(Category.init)
        categories = [Category.all] + list
        selectedCategory = categories.first
    }

    private func checkSaved() async {
        let uid = Session.shared.uid
        guard !uid.isEmpty else { return }
        if let r = try? await API.shared.send(.get, "api/user/stores/save/check/\(API.seg(uid))/\(store.storeId)", auth: true), r.ok {
            saved = r.isTrue
        }
    }

    private func checkRating() async {
        let uid = Session.shared.uid
        guard !uid.isEmpty,
              let d = await API.shared.object("api/public/store/rating/check/\(API.seg(uid))/\(store.storeId)"),
              d["rating"] != nil else { return }
        myRating = d.double("rating")
        myReview = d.str("review") ?? ""
    }

    private func toggleSave() async {
        let s = Session.shared
        guard s.isLoggedIn, !s.uid.isEmpty else { toast.show("Please login first"); return }
        if saved {
            if await API.shared.ok(.delete, "api/user/stores/save/\(API.seg(s.uid))/\(store.storeId)", auth: true) {
                saved = false
                toast.show("Removed from Saved")
            }
        } else {
            let body: [String: Any] = [
                "userId": s.uid, "storeId": store.storeId, "storeName": store.storeName,
                "storeImage": store.storeImage ?? "", "storeAddress": store.storeAddress ?? "",
                "storeCategoryName": store.storeCategoryName ?? "", "createdDate": Format.isoNow()
            ]
            if await API.shared.ok(.post, "api/user/stores/save", body: body, auth: true) {
                saved = true
                toast.show("Store Saved")
            }
        }
    }
}

struct RateStoreSheet: View {
    let storeId: Int
    let initialRating: Double
    let initialReview: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var rating = 0
    @State private var review = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 18) {
            Text(initialRating > 0 ? "Update your Rating" : "Rate this Store").font(.title3.bold())
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .onTapGesture { rating = i }
                }
            }
            TextField("Write a review (optional)", text: $review, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
            Button {
                Task { await submit() }
            } label: {
                if sending { ProgressView().tint(.black) } else { Text(initialRating > 0 ? "UPDATE RATING" : "SUBMIT RATING") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
        }
        .padding(24)
        .onAppear { rating = Int(initialRating.rounded()); review = initialReview }
    }

    private func submit() async {
        guard rating >= 1 else { toast.show("Please select at least 1 star"); return }
        sending = true
        defer { sending = false }
        let body: [String: Any] = ["storeId": String(storeId), "rating": Double(rating), "review": review]
        do {
            let r = try await API.shared.send(.post, "api/public/store/rating", body: body, auth: true)
            if r.ok {
                toast.show("Thank you for your rating!")
                onDone()
                dismiss()
            } else {
                toast.show("Failed to submit rating")
            }
        } catch {
            toast.show("Network error")
        }
    }
}

struct ProductDetailView: View {
    let product: Product
    @State private var store: Store?
    @State private var galleryIndex = 0
    @State private var viewerIndex: ViewerIndex?

    private struct ViewerIndex: Identifiable { let id: Int }

    private var isSalon: Bool { store?.isSalon ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Swipeable gallery: thumbnail plus any detail images, sized to the screen width.
                let images = galleryImages
                TabView(selection: $galleryIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                        RemoteImage(url: url, placeholder: "bag", contentMode: .fit)
                            .contentShape(Rectangle())
                            // Tap opens the full-screen viewer with pinch zoom.
                            .onTapGesture { if !url.isEmpty { viewerIndex = ViewerIndex(id: i) } }
                            .tag(i)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if images.first?.isEmpty == false {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { h, _ in h * 0.4 }   // ~40% of the screen on any iPhone
                .background(Color(hex: 0xF7F7F7))
                .fullScreenCover(item: $viewerIndex) { v in
                    PhotoViewer(urls: images.filter { !$0.isEmpty }, index: v.id)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(product.productName).font(.title2.bold())
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if product.sellPrice > 0 {
                            Text(Format.price(product.sellPrice)).font(.title2.bold())
                            if product.cutPrice > product.sellPrice {
                                Text(Format.price(product.cutPrice)).strikethrough().foregroundStyle(.secondary)
                            }
                        }
                        if product.discountText != "NEW" {
                            Text(product.discountText).font(.subheadline.bold()).foregroundStyle(Theme.open)
                        }
                    }
                    Text("Description").font(.headline).padding(.top, 6)
                    Text(product.description ?? "No description available.").foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if let store {
                    HStack(spacing: 12) {
                        RemoteImage(url: store.storeImage, placeholder: "storefront")
                            .frame(width: 56, height: 56).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(store.storeName).font(.headline)
                            Text(store.city ?? "Bangalore").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink(value: Route.store(store)) { Text("Visit Store").fontWeight(.semibold) }
                    }
                    .padding()
                    .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            if isSalon, let store {
                NavigationLink(value: Route.booking(storeId: store.storeId, storeName: store.storeName,
                                                    category: store.storeCategoryName ?? "")) {
                    Text("BOOK NOW")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
                .background(.bar)
            }
        }
        .refreshable { await loadStore() }
        .appHeader(title: "Product Details")
        .task {
            guard store == nil else { return }
            await loadStore()
            if let s = store {
                Analytics.visit(storeId: product.storeId, type: "PRODUCT_VIEW", name: product.productName, category: s.storeCategoryName)
            }
        }
    }

    private var galleryImages: [String] {
        var out: [String] = []
        for url in [product.thumbnailImage].compactMap({ $0 }) + product.detailImages
        where !url.isEmpty && !out.contains(url) { out.append(url) }
        return out.isEmpty ? [""] : out   // one branded placeholder when there are no images
    }

    private func loadStore() async {
        guard product.storeId > 0, let d = await API.shared.object("api/public/store/\(product.storeId)") else { return }
        store = Store(d)
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}
