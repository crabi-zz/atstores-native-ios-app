import SwiftUI

// MARK: - Dashboard (HomeActivity)

struct DashboardView: View {
    @Environment(ToastCenter.self) private var toast
    private var app = AppState.shared
    private var session = Session.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName.isEmpty ? "Welcome back" : "Hi, \(session.displayName)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("My Stores (\(app.stores.count))").font(.title3.bold())
                    }
                    Spacer()
                    NavigationLink(value: Route.storeForm(0)) {
                        Label("Add Store", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.primary, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                if app.stores.isEmpty {
                    if app.loading || !app.loaded {
                        LoadingView()
                    } else {
                        EmptyStateView(icon: "storefront", text: "No stores yet",
                                       detail: "Tap \"Add Store\" to register your first store on AtStores.")
                    }
                } else {
                    ForEach(app.stores) { store in
                        NavigationLink(value: Route.store(store.storeId)) { StoreCard(store: store) }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { session.select(store) })
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader()
        .task { await load() }
    }

    private func load() async {
        if !(await app.loadStores()) {
            Session.shared.expire(toast)
        }
    }
}

/// item_store_admin: image, name, address, hours, open badge and three counters.
struct StoreCard: View {
    let store: Store
    @State private var products = 0
    @State private var offers = 0
    @State private var visitors = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: store.storeImage)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Text(store.storeName).font(.headline).lineLimit(2)
                        Spacer(minLength: 4)
                        if store.isOpen { StatusPill(text: "Open", fg: Color(hex: 0x2E7D32), bg: Color(hex: 0xE8F5E9)) }
                    }
                    Label(store.locationText, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Label(store.hoursText, systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    if let cat = store.storeCategoryName {
                        Text(cat).font(.caption2.weight(.semibold)).foregroundStyle(Theme.primary)
                    }
                }
            }
            HStack(spacing: 0) {
                counter("\(products)", store.isService ? "Services" : "Products", "shippingbox")
                Divider().frame(height: 34)
                counter("\(offers)", "Offers", "tag")
                Divider().frame(height: 34)
                counter(Format.compact(visitors), "Visitors", "eye")
            }
            .padding(.vertical, 8)
            .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10))
        }
        .cardStyle()
        .task(id: store.storeId) { await loadSummary() }
    }

    private func counter(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.primary)
            Label(label, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadSummary() async {
        var d = await API.shared.object("api/store/\(store.storeId)/dashboard-summary")
        if d == nil { d = await API.shared.object("api/public/store/\(store.storeId)/dashboard-summary") }
        guard let d else { return }
        products = d.int("productCount")
        offers = d.int("offerCount")
        visitors = d.int("visitorCount")
    }
}

// MARK: - Manage store (ProductListActivity)

struct StoreManageView: View {
    let storeId: Int
    @Environment(ToastCenter.self) private var toast
    @State private var store = Store()
    @State private var categories: [String] = ["All"]
    @State private var selectedCategory = "All"
    @State private var allProducts: [Product] = []
    @State private var loaded = false
    @State private var uploadingStore = false
    @State private var uploadingProduct: Int?

    private var products: [Product] {
        selectedCategory == "All" ? allProducts
            : allProducts.filter { ($0.categoryName ?? "").caseInsensitiveCompare(selectedCategory) == .orderedSame }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                shareCard
                quickLinks
                if categories.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Store Categories").font(.subheadline.weight(.semibold)).padding(.horizontal, 16)
                        ChipRow(items: categories, selected: $selectedCategory)
                    }
                    .padding(.horizontal, -16)
                }
                HStack {
                    SectionTitle(text: store.isService ? "Services & Products" : "Featured Products")
                    NavigationLink(value: Route.productForm(storeId: storeId, product: nil)) {
                        Label("Add New", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                    }
                }
                productGrid
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader(store.storeName.isEmpty ? "Manage Store" : store.storeName) {
            NavigationLink(value: Route.storeForm(storeId)) {
                Image(systemName: "square.and.pencil").font(.title3).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Edit Store")
        }
        .onAppear { Task { await load() } }   // Android reloads in onResume
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: store.storeImage)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                ImagePickButton(onPick: { data in Task { await uploadStoreImage(data) } }) {
                    Group {
                        if uploadingStore { ProgressView().tint(.white) } else { Image(systemName: "camera.fill").font(.caption) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.primary, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .offset(x: 6, y: 6)
                .disabled(uploadingStore)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(store.storeName).font(.title3.bold()).lineLimit(2)
                Text(store.storeAddress ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                NavigationLink(value: Route.storeForm(storeId)) {
                    Label("Edit Store", systemImage: "pencil").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private var quickLinks: some View {
        HStack(spacing: 10) {
            quickLink("Offers", "tag.fill", Color(hex: 0xF57F17), .offers(storeId))
            quickLink("Customers", "person.2.fill", Theme.success, .customers(storeId))
            quickLink("Website", "globe", Theme.primary, .storeWebsite)
        }
    }

    /// "Share My Store" – full width so it's always noticed (same as the Android app).
    private var shareCard: some View {
        NavigationLink(value: Route.shareStore(storeId: storeId,
                                               storeName: store.storeName.isEmpty ? Session.shared.selectedStoreName : store.storeName)) {
            HStack(spacing: 14) {
                Image(systemName: "qrcode")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share My Store").font(.headline).foregroundStyle(.white)
                    Text("QR poster & WhatsApp link to get more customers")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share My Store")
    }

    private func quickLink(_ title: String, _ icon: String, _ color: Color, _ route: Route) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                    .frame(width: 42, height: 42).background(color.opacity(0.12), in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var productGrid: some View {
        if !loaded {
            LoadingView()
        } else if products.isEmpty {
            EmptyStateView(icon: "shippingbox", text: "No products yet", detail: "Add your first product or service.")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(products) { p in
                    NavigationLink(value: Route.productForm(storeId: storeId, product: p)) { productCard(p) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            NavigationLink(value: Route.productCustomers(storeId: storeId, productId: p.productId, title: p.productName)) {
                                Label("Interested Customers", systemImage: "person.2")
                            }
                            NavigationLink(value: Route.productForm(storeId: storeId, product: p)) {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                }
            }
        }
    }

    /// item_product_admin.
    private func productCard(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: p.thumbnailImage)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                ImagePickButton(onPick: { data in Task { await uploadProductImage(p.productId, data) } }) {
                    Group {
                        if uploadingProduct == p.productId { ProgressView().tint(.white) }
                        else { Image(systemName: "camera.fill").font(.caption2) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.55), in: Circle())
                }
                .padding(6)
                .disabled(uploadingProduct != nil)
                if p.hasDiscount, let off = p.percentOff {
                    Text(off).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.danger, in: Capsule())
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Text(p.productName).font(.subheadline.weight(.semibold)).lineLimit(2).frame(height: 38, alignment: .top)
            HStack(spacing: 6) {
                Text(Format.price(p.sellPrice)).font(.subheadline.bold()).foregroundStyle(Theme.primary)
                if p.hasDiscount {
                    Text(Format.price(p.cutPrice)).font(.caption).strikethrough().foregroundStyle(.secondary)
                }
            }
            if p.isService, let m = p.durationMinutes, m > 0 {
                Label("\(m) mins", systemImage: "clock").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 8)
    }

    private func load() async {
        async let detail = API.shared.object("api/public/store/\(storeId)")
        async let cats = API.shared.objects("api/store/category/\(storeId)")
        async let prods = try? API.shared.send(.get, "api/store/product/\(storeId)")
        if let d = await detail {
            store = Store(d)
            Session.shared.select(store)
        }
        let names = await cats.map(StoreCategory.init).map(\.name).filter { !$0.isEmpty }
        categories = ["All"] + names
        if !categories.contains(selectedCategory) { selectedCategory = "All" }
        if let r = await prods {
            if r.status == 401 {
                loaded = true
                Session.shared.expire(toast)
                return
            }
            if r.ok {
                allProducts = JSON.objects(from: r.json).map(Product.init).sorted { $0.createdDate > $1.createdDate }
            }
        } else {
            toast.show("Failed to load products")
        }
        loaded = true
    }

    private func uploadStoreImage(_ data: Data) async {
        uploadingStore = true
        defer { uploadingStore = false }
        // Field name "stroreImage" is what the backend expects (typo preserved from Android).
        guard let r = try? await API.shared.upload("api/store/\(storeId)/addImage", field: "stroreImage", data: data) else {
            toast.show("Network error during image upload"); return
        }
        if r.ok {
            toast.show("Store Image Updated Successfully")
            if let u = store.storeImage.flatMap(URL.init(string:)) { ImageLoader.evict(u) }
            await load()
            await AppState.shared.loadStores()
        } else {
            toast.show("Image upload failed: \(r.status)")
        }
    }

    private func uploadProductImage(_ productId: Int, _ data: Data) async {
        uploadingProduct = productId
        defer { uploadingProduct = nil }
        guard let r = try? await API.shared.upload("api/store/\(productId)/productImage", field: "productImage", data: data) else {
            toast.show("Network error during product image upload"); return
        }
        if r.ok {
            toast.show("Product Image Updated Successfully")
            await load()
        } else {
            toast.show("Product image upload failed: \(r.status)")
        }
    }
}

// MARK: - Register / edit store (RegisterStoreActivity)

struct StoreFormView: View {
    let storeId: Int
    var onboarding = false
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    private var session = Session.shared

    @State private var storeName = ""
    @State private var contactName = ""
    @State private var mobile = ""
    @State private var email = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var pincode = ""
    @State private var openTime = ""
    @State private var closeTime = ""
    @State private var categories: [Category] = []
    @State private var categoryId = 0
    @State private var categoryName = ""
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var busy = false
    @State private var locating = false
    @State private var timeEditing: TimeField?

    enum TimeField: Identifiable { case open, close; var id: Self { self } }

    init(storeId: Int, onboarding: Bool = false) {
        self.storeId = storeId
        self.onboarding = onboarding
    }

    private var isEdit: Bool { storeId != 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if onboarding {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Register your store").font(.title3.bold())
                        Text("Tell us about your store to start using AtStores Admin.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 14) {
                    FormField(label: "Store Name *", text: $storeName, placeholder: "e.g. ABC Fashion")
                    FormField(label: "Contact Name *", text: $contactName, placeholder: "Owner / manager name")
                    FormField(label: "Mobile Number", text: $mobile, keyboard: .phonePad, disabled: true)
                    FormField(label: "Email", text: $email, placeholder: "store@example.com", keyboard: .emailAddress)
                    FormValue(label: "Store Category *") {
                        Menu {
                            ForEach(categories) { c in
                                Button(c.name) { categoryId = c.categoryId; categoryName = c.name }
                            }
                        } label: {
                            HStack {
                                Text(categoryName.isEmpty ? "Select Store Category" : categoryName)
                                    .foregroundStyle(categoryName.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .cardStyle()

                VStack(spacing: 14) {
                    HStack {
                        Text("Store Address").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { Task { await useCurrentLocation() } } label: {
                            if locating { ProgressView() } else { Label("Use current location", systemImage: "location.fill") }
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(locating)
                    }
                    FormField(label: "Address", text: $address, placeholder: "Shop no, street, area", multiline: true)
                    HStack(spacing: 10) {
                        FormField(label: "City", text: $city)
                        FormField(label: "State", text: $state)
                    }
                    FormField(label: "Pincode", text: $pincode, keyboard: .numberPad)
                    HStack(spacing: 10) {
                        timeButton("Opening Time", openTime) { timeEditing = .open }
                        timeButton("Closing Time", closeTime) { timeEditing = .close }
                    }
                }
                .cardStyle()

                BusyButton(title: isEdit ? "UPDATE STORE" : "REGISTER STORE", busy: busy) { Task { await submit() } }
                if onboarding {
                    Button("Logout") { session.logout() }.font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .modifier(StoreFormHeader(onboarding: onboarding, title: isEdit ? "Store Settings" : "Register Store"))
        .sheet(item: $timeEditing) { field in
            TimePickerSheet(title: field == .open ? "Opening Time" : "Closing Time",
                            initial: field == .open ? openTime : closeTime) { value in
                if field == .open { openTime = value } else { closeTime = value }
            }
            .presentationDetents([.height(320)])
        }
        .task { await load() }
    }

    private func timeButton(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        FormValue(label: label) {
            Button(action: action) {
                HStack {
                    Text(value.isEmpty ? "Select" : value).foregroundStyle(value.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "clock").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func load() async {
        mobile = session.mobileNumber
        if isEdit, let d = await API.shared.object("api/public/store/\(storeId)") {
            let s = Store(d)
            storeName = s.storeName
            contactName = s.contactName ?? ""
            mobile = s.storeContactNo ?? session.mobileNumber
            email = s.storeEmail ?? ""
            address = s.storeAddress ?? ""
            city = s.city ?? ""
            state = s.state ?? ""
            pincode = s.pincode ?? ""
            openTime = s.startTime ?? ""
            closeTime = s.endTime ?? ""
            categoryId = s.storeCategoryId
            categoryName = s.storeCategoryName ?? ""
            latitude = s.latitude
            longitude = s.longitude
        }
        categories = await API.shared.objects("api/public/category").map(Category.init).filter { !$0.name.isEmpty }
        if let match = categories.first(where: { $0.categoryId == categoryId }) { categoryName = match.name }
        if !isEdit, address.isEmpty { await useCurrentLocation() }
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let place = await LocationService.shared.currentPlace() else {
            if isEdit { toast.show("Location not available") }
            return
        }
        latitude = place.latitude
        longitude = place.longitude
        if let a = place.address { address = a }
        if let c = place.city { city = c }
        if let s = place.state { state = s }
        if let p = place.pincode { pincode = p }
    }

    private func validate() -> Bool {
        if storeName.trimmed.isEmpty { toast.show("Please enter Store Name"); return false }
        if contactName.trimmed.isEmpty { toast.show("Please enter Contact Name"); return false }
        if mobile.trimmed.isEmpty { toast.show("Please enter Mobile Number"); return false }
        if categoryId == 0 { toast.show("Please select a Store Category"); return false }
        return true
    }

    private func submit() async {
        guard validate() else { return }
        busy = true
        defer { busy = false }
        if isEdit { await update() } else { await register() }
    }

    private func update() async {
        let uid = session.effectiveUserId
        let body: [String: Any] = [
            "storeId": storeId, "contactName": contactName.trimmed, "storeAddress": address.trimmed,
            "storeContactNo": mobile.trimmed, "storeLatitude": latitude, "storeLongitude": longitude,
            "latitude": latitude, "longitude": longitude, "storeWebsite": "", "storeCategoryId": categoryId,
            "storeEmail": email.trimmed, "storeName": storeName.trimmed, "startTime": openTime, "endTime": closeTime,
            "city": city.trimmed, "state": state.trimmed, "pincode": pincode.trimmed, "pinCode": pincode.trimmed,
            "postalCode": pincode.trimmed, "zipCode": pincode.trimmed, "storeState": state.trimmed,
            "uid": uid, "userId": uid, "storeCategoryName": categoryName
        ]
        guard let r = try? await API.shared.send(.put, "api/store/\(storeId)", body: body) else {
            toast.show("Network error"); return
        }
        if r.ok {
            toast.show("Store Updated Successfully")
            await AppState.shared.loadStores()
            dismiss()
        } else {
            toast.show("Update failed: \(r.status)")
        }
    }

    private func register() async {
        let uid = session.effectiveUserId
        var body: [String: Any] = [
            "storeName": storeName.trimmed, "contactName": contactName.trimmed, "storeContactNo": mobile.trimmed,
            "storeEmail": email.trimmed, "storeAddress": address.trimmed, "city": city.trimmed, "state": state.trimmed,
            "pincode": pincode.trimmed, "storeCategoryId": categoryId, "categoryId": categoryId,
            "storeCategoryName": categoryName, "categoryName": categoryName, "startTime": openTime, "endTime": closeTime,
            "openTime": openTime, "closeTime": closeTime, "storeLatitude": latitude, "storeLongitude": longitude,
            "latitude": latitude, "longitude": longitude, "storeType": "REGULAR"
        ]
        if !uid.isEmpty {
            body["uid"] = uid
            body["userId"] = uid
            body["user_id"] = uid
            body["user"] = ["userId": uid, "uid": uid, "mobile": session.mobileNumber.isEmpty ? mobile : session.mobileNumber]
        }

        let primary = try? await API.shared.send(.post, "api/store-registration/register", body: body)
        if let r = primary, r.ok {
            finishRegistration(r.json.flatMap { $0 as? JSONDict }.map(AuthResult.init))
            return
        }
        if let r = primary, r.status == 401 {
            Session.shared.expire(toast)
            return
        }
        if let r = primary, r.status != 404 {
            toast.show("Registration failed: \(r.status)", long: true)
            return
        }
        // 404 or network failure: legacy public endpoint, then refresh the token to pick up the STORE role.
        guard let alt = try? await API.shared.send(.post, "api/public/storeRegister", body: body) else {
            toast.show("Network error during registration"); return
        }
        guard alt.ok else { toast.show("Registration failed: \(alt.status)", long: true); return }
        finishRegistration(await API.shared.refreshAuth())
    }

    private func finishRegistration(_ auth: AuthResult?) {
        toast.show("Store Registered Successfully!")
        let wasLoggedIn = session.isLoggedIn
        session.markStoreRegistered(auth)   // onboarding: RootView switches to the dashboard
        if wasLoggedIn {
            Task { await AppState.shared.loadStores() }
            dismiss()
        }
    }
}

/// Onboarding shows a plain blue title bar (no back button); otherwise the normal pushed header.
private struct StoreFormHeader: ViewModifier {
    let onboarding: Bool
    let title: String
    func body(content: Content) -> some View {
        if onboarding {
            content
                .toolbar(.hidden, for: .navigationBar)
                .background(Theme.background)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        HeaderBrand()
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Theme.primary.ignoresSafeArea(edges: .top))
                }
        } else {
            content.adminHeader(title)
        }
    }
}

/// Wheel time picker returning "hh:mm a" (RegisterStoreActivity.showTimePicker).
struct TimePickerSheet: View {
    let title: String
    let initial: String
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Button("Done") { onDone(Format.date(date, "hh:mm a")); dismiss() }.bold()
            }
            .padding()
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
        .onAppear {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for fmt in ["hh:mm a", "h:mm a", "HH:mm:ss", "HH:mm"] {
                f.dateFormat = fmt
                if let d = f.date(from: initial) { date = d; break }
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
