import SwiftUI

// MARK: - Add / edit product or service (AddProductActivity)

struct ProductFormView: View {
    let storeId: Int
    let existing: Product?
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    @State private var isService = false
    @State private var name = ""
    @State private var categories: [StoreCategory] = []
    @State private var categoryName = ""
    @State private var quantity = ""
    @State private var duration = 30
    @State private var price = ""
    @State private var percentage = true
    @State private var discount = ""
    @State private var newArrival = false
    @State private var busy = false
    @State private var populated = false

    private static let durations = [15, 30, 45, 60, 90, 120, 180]

    /// calculateOfferPrice: MRP minus the percentage / flat discount, clamped at 0.
    private var offerPrice: Int? {
        guard let p = Double(price.trimmed) else { return nil }
        guard var d = Double(discount.trimmed) else { return Int(p) }
        if percentage { d = min(d, 100); return max(0, Int(p - p * d / 100)) }
        d = min(d, p)
        return max(0, Int(p - d))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 14) {
                    Picker("Type", selection: $isService) {
                        Text("Product").tag(false)
                        Text("Service").tag(true)
                    }
                    .pickerStyle(.segmented)
                    FormField(label: "\(isService ? "Service" : "Product") Name *", text: $name)
                    FormValue(label: "Category *") {
                        Menu {
                            if categories.isEmpty {
                                Button("General (Default)") { categoryName = "General" }
                            }
                            ForEach(categories) { c in Button(c.name) { categoryName = c.name } }
                        } label: {
                            HStack {
                                Text(categoryName.isEmpty ? "Select Category" : categoryName)
                                    .foregroundStyle(categoryName.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        NavigationLink(value: Route.categories(storeId)) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("Manage categories")
                    }
                    if isService {
                        FormValue(label: "Duration") {
                            Picker("Duration", selection: $duration) {
                                ForEach(Self.durations, id: \.self) { Text("\($0) mins").tag($0) }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                    } else {
                        FormField(label: "Quantity in stock", text: $quantity, placeholder: "0", keyboard: .numberPad)
                    }
                }
                .cardStyle()

                VStack(spacing: 14) {
                    FormField(label: "MRP (₹) *", text: $price, placeholder: "0", keyboard: .decimalPad)
                    Picker("Discount type", selection: $percentage) {
                        Text("Percentage (%)").tag(true)
                        Text("Flat (₹)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    FormField(label: percentage ? "Discount (%)" : "Discount (₹)", text: $discount, placeholder: "0", keyboard: .decimalPad)
                    HStack {
                        Text("Offer Price").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(offerPrice.map { "₹\($0)" } ?? "—").font(.title3.bold()).foregroundStyle(Theme.success)
                    }
                    Toggle("Mark as New Arrival", isOn: $newArrival).tint(Theme.primary)
                }
                .cardStyle()

                if let p = existing {
                    NavigationLink(value: Route.productPhotos(p)) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Manage Photos").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\((p.mainImage == nil ? 0 : 1) + p.detailImages.count) / \(ProductPhotosView.maxPhotos)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                    .cardStyle()
                }

                BusyButton(title: existing == nil ? "SAVE" : "UPDATE", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .adminHeader(existing == nil ? "Add Product / Service" : "Edit Product / Service") {
            if let p = existing {
                NavigationLink(value: Route.productCustomers(storeId: storeId, productId: p.productId, title: p.productName)) {
                    Image(systemName: "person.2.fill").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Interested customers")
            }
        }
        .onAppear { populate() }
        .onAppear { Task { await loadCategories() } }   // reloads when returning from Manage Categories
    }

    private func populate() {
        guard !populated, let p = existing else { return }
        populated = true
        name = p.productName
        price = "\(Int(p.cutPrice))"
        categoryName = p.categoryName ?? ""
        let off = p.percentOff ?? ""
        percentage = !(p.discountType?.uppercased() == "FLAT" || off.contains("₹"))
        if let dv = p.discountValue, dv > 0 {
            discount = Format.number(dv)
        } else {
            let digits = off.filter { $0.isNumber || $0 == "." }
            discount = Double(digits).map(Format.number) ?? ""
        }
        isService = p.isService
        if p.isService, let m = p.durationMinutes, Self.durations.contains(m) { duration = m }
        if !p.isService, let q = p.quantity { quantity = "\(q)" }
        newArrival = p.newArrival
    }

    private func loadCategories() async {
        categories = await API.shared.objects("api/store/category/\(storeId)").map(StoreCategory.init).filter { !$0.name.isEmpty }
        if categories.isEmpty, categoryName.isEmpty { categoryName = "General" }
    }

    private func save() async {
        guard !name.trimmed.isEmpty, let mrp = Double(price.trimmed), !categoryName.isEmpty else {
            toast.show("Please fill required fields"); return
        }
        let disc = Double(discount.trimmed) ?? 0
        if mrp < 0 || disc < 0 { toast.show("MRP and discount cannot be negative"); return }
        if percentage && disc > 100 { toast.show("Percentage discount cannot exceed 100%"); return }
        if !percentage && disc > mrp { toast.show("Flat discount cannot exceed MRP"); return }

        let uid = Session.shared.effectiveUserId
        var body: [String: Any] = [
            "productName": name.trimmed, "offerId": 0, "offerName": "", "categoryName": categoryName,
            "description": "", "rating": 0, "storeId": storeId, "uid": uid, "colorName": "",
            "sellPrice": offerPrice ?? Int(mrp), "cutPrice": Int(mrp),
            "percentOff": "\(disc)" + (percentage ? "% OFF" : "₹ OFF"),
            "newArrival": newArrival, "itemType": isService ? "SERVICE" : "PRODUCT",
            "discountType": percentage ? "PERCENTAGE" : "FLAT", "discountValue": disc
        ]
        if isService {
            body["durationMinutes"] = duration
            body["quantity"] = 0
        } else {
            let q = Int(quantity.trimmed) ?? 0
            body["stockQuantity"] = q
            body["quantity"] = q
            body["durationMinutes"] = 0
        }

        busy = true
        defer { busy = false }
        let path = existing.map { "api/store/product/\($0.productId)" } ?? "api/store/addproduct/\(storeId)"
        guard let r = try? await API.shared.send(existing == nil ? .post : .put, path, body: body) else {
            toast.show("Network error"); return
        }
        if r.ok {
            toast.show(existing == nil ? "Product/Service Added Successfully" : "Product/Service Updated Successfully")
            // New product: go straight to adding its photos (up to 10).
            if existing == nil, let d = (r.json as? JSONDict)?["data"] as? JSONDict {
                let saved = Product(d)
                if saved.productId != 0, case .productForm? = router.path.last {
                    router.path.removeLast()
                    router.path.append(.productPhotos(saved))
                    return
                }
            }
            dismiss()
        } else {
            toast.show("Failed: \(r.status)")
        }
    }
}

// MARK: - Store categories (AddStoreCategoryActivity)

struct ManageCategoriesView: View {
    let storeId: Int
    @Environment(ToastCenter.self) private var toast
    @State private var categories: [StoreCategory] = []
    @State private var name = ""
    @State private var editing: StoreCategory?
    @State private var deleting: StoreCategory?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Category name", text: $name)
                    Button(editing == nil ? "ADD" : "UPDATE") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || name.trimmed.isEmpty)
                }
                if editing != nil {
                    Button("Cancel editing") { editing = nil; name = "" }.font(.footnote)
                }
            } header: { Text(editing == nil ? "Add Category" : "Edit Category") }

            Section("Your Categories") {
                if categories.isEmpty {
                    Text("No categories yet").foregroundStyle(.secondary)
                }
                ForEach(categories) { c in
                    HStack {
                        Text(c.name)
                        Spacer()
                        Button { editing = c; name = c.name } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) { deleting = c } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .adminHeader("Store Categories")
        .task { await load() }
        .alert("Delete Category", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("DELETE", role: .destructive) { if let c = deleting { Task { await delete(c) } } }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(deleting?.name ?? "")'?")
        }
    }

    private func load() async {
        categories = await API.shared.objects("api/store/category/\(storeId)").map(StoreCategory.init)
    }

    private func save() async {
        let n = name.trimmed
        guard !n.isEmpty else { toast.show("Please enter category name"); return }
        busy = true
        defer { busy = false }
        if let c = editing {
            let body: [String: Any] = ["name": n, "storeCategoryId": c.storeCategoryId, "storeId": storeId]
            if await API.shared.ok(.put, "api/store/category/\(c.storeCategoryId)", body: body) {
                toast.show("Category Updated")
                editing = nil
                name = ""
                await load()
            } else {
                toast.show("Update failed")
            }
        } else {
            if await API.shared.ok(.post, "api/store/category", body: ["name": n, "storeId": storeId]) {
                toast.show("Category Added Successfully")
                name = ""
                await load()
            } else {
                toast.show("Failed to add category")
            }
        }
    }

    private func delete(_ c: StoreCategory) async {
        if await API.shared.ok(.delete, "api/store/category/\(c.storeCategoryId)") {
            toast.show("Category Deleted")
            await load()
        } else {
            toast.show("Delete failed")
        }
    }
}

// MARK: - Customers interested in a product (ProductCustomerListActivity)

struct ProductCustomersView: View {
    let storeId: Int
    let productId: Int
    let title: String
    @State private var customers: [ProductCustomer] = []
    @State private var loaded = false
    @State private var offerTarget: ProductCustomer?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !loaded {
                    LoadingView()
                } else if customers.isEmpty {
                    EmptyStateView(icon: "person.2", text: "No interested customers yet",
                                   detail: "Customers who view or wishlist this product will appear here.")
                }
                ForEach(customers) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.customerName).font(.headline)
                            Spacer()
                            if !c.interestType.isEmpty { StatusPill(text: c.interestType, fg: Theme.primary) }
                        }
                        if let m = c.mobileNumber, !m.isEmpty {
                            Label(m, systemImage: "phone").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Last Interaction: \(Format.timestamp(c.lastInteractionTime))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Promotional Notifications: \(c.notificationEligible ? "Eligible" : "Not Eligible")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(c.notificationEligible ? Theme.success : .gray)
                        Button("Send Extra Offer") { offerTarget = c }
                            .buttonStyle(OutlineButtonStyle())
                            .padding(.top, 4)
                    }
                    .cardStyle()
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader(title.isEmpty ? "Product Customers" : title)
        .task { await load() }
        .sheet(item: $offerTarget) { c in SendExtraOfferSheet(storeId: storeId, customer: c) }
    }

    private func load() async {
        let json = await API.shared.json(.get, "api/store/\(storeId)/wishlist/customers", query: ["productId": productId])
        customers = JSON.objects(from: json, preferredKeys: ["customers", "customerList", "data", "items"])
            .map(ProductCustomer.init)
            .filter { productId == 0 || $0.productId == productId }
        loaded = true
    }
}

/// dialog_send_extra_offer: coupon templates + preview, sent with api/store/{id}/coupons/send.
struct SendExtraOfferSheet: View {
    let storeId: Int
    let customer: ProductCustomer
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var template = 0
    @State private var title = ""
    @State private var desc = ""
    @State private var percentage = true
    @State private var discount = ""
    @State private var validFrom = Date()
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var minPurchase = ""
    @State private var maxDiscount = ""
    @State private var busy = false
    @State private var showPreview = false

    private static let templates: [(label: String, title: String, desc: String, percent: Bool, value: String)] = [
        ("10% Off Storewide", "10% Off Storewide", "Get 10% off on your next visit or purchase", true, "10"),
        ("Flat ₹200 Off", "Flat ₹200 Off", "Get ₹200 off on your next booking or purchase", false, "200"),
        ("First-Time Customer Offer (15% Off)", "First-Time Customer Offer", "Special discount for first-time customers", true, "15"),
        ("Repeat Customer Offer (10% Off)", "Repeat Customer Offer", "Exclusive offer for returning customers", true, "10"),
        ("Weekend Special (15% Off)", "Weekend Special", "Special weekend discount", true, "15"),
        ("Festival Special (20% Off)", "Festival Special", "Special festive offer", true, "20"),
        ("Buy One Get One Free", "Buy One Get One Free", "Buy one, get one free on eligible products or services", true, "50"),
        ("Service Package Offer (₹150 Off)", "Service Package Offer", "Save on selected service packages", false, "150"),
        ("Product Bundle Offer (₹100 Off)", "Product Bundle Offer", "Special price on selected products", false, "100"),
        ("Loyalty Reward (25% Off)", "Loyalty Reward", "Exclusive reward for loyal customers", true, "25"),
        ("Seasonal Sale (30% Off)", "Seasonal Sale", "Discounts on selected seasonal products or services", true, "30"),
        ("Custom Offer (Write your own)", "Custom Offer", "Write your own offer description", true, "10")
    ]

    private var badge: String { percentage ? "\(discount)% OFF" : "₹\(discount) OFF" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    Text("\(customer.customerName)\(customer.mobileNumber.map { " (\($0))" } ?? "")")
                }
                Section("Offer") {
                    Picker("Template", selection: $template) {
                        Text("Select template...").tag(0)
                        ForEach(Array(Self.templates.enumerated()), id: \.offset) { i, t in Text(t.label).tag(i + 1) }
                    }
                    .onChange(of: template) { _, i in
                        guard i > 0 else { return }
                        let t = Self.templates[i - 1]
                        title = t.title; desc = t.desc; percentage = t.percent; discount = t.value
                    }
                    TextField("Offer title", text: $title)
                    TextField("Description", text: $desc, axis: .vertical)
                    Picker("Type", selection: $percentage) {
                        Text("Percentage (%)").tag(true)
                        Text("Flat (₹)").tag(false)
                    }
                    TextField("Discount value", text: $discount).keyboardType(.decimalPad)
                }
                Section("Validity") {
                    DatePicker("Valid from", selection: $validFrom, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    DatePicker("Expiry date", selection: $expiry, in: validFrom..., displayedComponents: .date)
                }
                Section("Conditions (optional)") {
                    TextField("Min purchase (₹)", text: $minPurchase).keyboardType(.decimalPad)
                    TextField("Max discount (₹)", text: $maxDiscount).keyboardType(.decimalPad)
                }
                Section {
                    Button("Preview Offer") {
                        if title.trimmed.isEmpty || desc.trimmed.isEmpty || discount.trimmed.isEmpty {
                            toast.show("Please fill in Title, Description, and Discount Value")
                        } else { showPreview = true }
                    }
                    Button { Task { await send() } } label: {
                        HStack { Text("Send Offer").bold(); Spacer(); if busy { ProgressView() } }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("Send Extra Offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showPreview) { preview.presentationDetents([.medium]) }
        }
    }

    /// dialog_offer_preview.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                Text(badge).font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.danger, in: Capsule())
            }
            Text(desc).foregroundStyle(.secondary)
            Divider()
            Label("Valid: \(Format.date(validFrom, "dd-MM-yyyy")) to \(Format.date(expiry, "dd-MM-yyyy"))", systemImage: "calendar")
            Label(conditions, systemImage: "info.circle")
            Label("Recipient: \(customer.customerName) (\(customer.mobileNumber ?? ""))", systemImage: "person")
            Spacer()
            Button("Close") { showPreview = false }.buttonStyle(PrimaryButtonStyle())
        }
        .font(.subheadline)
        .padding(20)
    }

    private var conditions: String {
        var parts: [String] = []
        if !minPurchase.trimmed.isEmpty { parts.append("Min Purchase: ₹\(minPurchase.trimmed)") }
        if !maxDiscount.trimmed.isEmpty { parts.append("Max Discount: ₹\(maxDiscount.trimmed)") }
        return parts.isEmpty ? "No minimum or maximum purchase limits" : parts.joined(separator: " | ")
    }

    private func send() async {
        guard !title.trimmed.isEmpty else { toast.show("Offer title is required"); return }
        guard !desc.trimmed.isEmpty else { toast.show("Description is required"); return }
        guard let value = Double(discount.trimmed), value > 0 else { toast.show("Discount must be greater than 0"); return }
        if percentage && value > 100 { toast.show("Percentage cannot exceed 100"); return }
        let minP = Double(minPurchase.trimmed) ?? 0, maxD = Double(maxDiscount.trimmed) ?? 0
        if minP < 0 || maxD < 0 { toast.show("Amounts cannot be negative"); return }

        let uid = Session.shared.effectiveUserId
        var target = customer.userId
        if target.isEmpty { target = customer.mobileNumber ?? "" }
        if target.isEmpty { target = customer.customerName }
        var body: [String: Any] = [
            "storeId": storeId, "userId": Int(uid).map { $0 as Any } ?? uid, "title": title.trimmed,
            "description": desc.trimmed, "code": "", "discount": value,
            "discountType": percentage ? "PERCENTAGE" : "FLAT",
            "validFrom": Format.date(validFrom, "dd-MM-yyyy"), "expiryDate": Format.date(expiry, "dd-MM-yyyy"),
            "customerIds": [target]
        ]
        if maxD > 0 { body["maxDiscountAmount"] = maxD }
        if minP > 0 { body["minPurchaseAmount"] = minP }

        busy = true
        defer { busy = false }
        var r = try? await API.shared.send(.post, "api/store/\(storeId)/coupons/send", body: body)
        if r?.status == 404 { r = try? await API.shared.send(.post, "api/store/\(storeId)/coupon/send", body: body) }
        guard let r else { toast.show("Network error"); return }
        if r.ok {
            toast.show((r.json as? JSONDict)?.str("message") ?? "Coupon distributed successfully", long: true)
            dismiss()
        } else {
            toast.show("Failed to distribute coupon: \(r.status)")
        }
    }
}
