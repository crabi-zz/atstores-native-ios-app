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
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: store.storeImage, placeholder: "storefront")
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button { Task { await toggleSave() } } label: {
                            Image(systemName: saved ? "heart.fill" : "heart")
                                .font(.title3).foregroundStyle(.black)
                                .frame(width: 42, height: 42)
                                .background(.white, in: Circle())
                        }
                        .padding(12)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.storeName).font(.title2.bold())
                        Spacer()
                        if store.avgRating > 0 {
                            Text(String(format: "%.1f ★", store.avgRating)).font(.headline).foregroundStyle(.orange)
                            if store.ratingCount > 0 { Text("(\(store.ratingCount))").foregroundStyle(.secondary) }
                        }
                    }
                    Text(store.storeCategoryName ?? "Category").font(.subheadline).foregroundStyle(.secondary)
                    Text(store.storeAddress ?? "Address not available").font(.subheadline)
                    HStack {
                        Text(store.distance > 0 ? String(format: "%.1f km away", store.distance) : "Nearby")
                        Text("•")
                        Text("OPEN").bold().foregroundStyle(Theme.open)
                    }
                    .font(.subheadline)
                    Label("\(Format.hour(store.startTime.nonEmpty ?? "10:00 AM")) – \(Format.hour(store.endTime.nonEmpty ?? "09:00 PM"))",
                          systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                HStack {
                    action("WhatsApp", "message.fill") { StoreActions.whatsApp(store.storeContactNo, toast: toast) }
                    action("Call", "phone.fill") { StoreActions.call(store.storeContactNo, toast: toast) }
                    action("Location", "map.fill") { StoreActions.location(store.storeAddress, toast: toast) }
                    action("Website", "globe") { StoreActions.website(store.storeWebsite, toast: toast) }
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    if store.isSalon {
                        NavigationLink(value: Route.booking(storeId: store.storeId, storeName: store.storeName,
                                                            category: store.storeCategoryName ?? "")) {
                            Text("BOOK NOW")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Button(myRating > 0 ? "EDIT RATING" : "RATE STORE") {
                        if Session.shared.uid.isEmpty || Session.shared.accessToken.isEmpty {
                            toast.show("Please login to rate")
                        } else {
                            showRating = true
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary, lineWidth: 2))
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal)

                if categories.count > 1 {
                    ChipBar(items: categories, title: \.name, selection: $selectedCategory)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(products) { ProductCard(product: $0, storeName: store.storeName) }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
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

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Theme.primary.opacity(0.2), in: Circle())
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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

    private var isSalon: Bool { store?.isSalon ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RemoteImage(url: product.thumbnailImage, placeholder: "bag", contentMode: .fit)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(Theme.lightGray)

                VStack(alignment: .leading, spacing: 8) {
                    Text(product.productName).font(.title2.bold())
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Format.price(product.sellPrice)).font(.title2.bold())
                        if product.cutPrice > product.sellPrice {
                            Text(Format.price(product.cutPrice)).strikethrough().foregroundStyle(.secondary)
                        }
                        Text(product.discountText).font(.subheadline.bold()).foregroundStyle(.green)
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
        .appHeader(title: "Product Details")
        .task {
            guard store == nil, product.storeId > 0,
                  let d = await API.shared.object("api/public/store/\(product.storeId)") else { return }
            let s = Store(d)
            store = s
            Analytics.visit(storeId: product.storeId, type: "PRODUCT_VIEW", name: product.productName, category: s.storeCategoryName)
        }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}
