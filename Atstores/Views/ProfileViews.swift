import PhotosUI
import SwiftUI

struct ProfileView: View {
    @Environment(ToastCenter.self) private var toast
    private var session = Session.shared
    @State private var confirmLogout = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        let user = session.user
        List {
            Section {
                NavigationLink(value: Route.editProfile) {
                    HStack(spacing: 14) {
                        RemoteImage(url: user?.thumbnailImage, placeholder: "person.fill")
                            .frame(width: 72, height: 72).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user?.name ?? "User").font(.title3.bold())
                            Text(user?.contactNo ?? (session.mobileNumber.isEmpty ? "No Mobile" : session.mobileNumber))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(user?.email ?? "No Email").font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "pencil.circle.fill").font(.title).foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label(locationLine(user), systemImage: "mappin.and.ellipse").font(.subheadline)
                    Text(user?.address.nonEmpty ?? "Address not set").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("My Activity") {
                row("My Bookings", "calendar", .bookings)
                row("My Orders", "shippingbox", .orders)
                row("Wishlist", "heart", .wishlist)
                row("My Coupons", "ticket", .coupons)
                row("Saved Stores", "bookmark", .savedStores)
                row("Notifications", "bell", .notifications)
                Button {
                    toast.show("Fetching current location...")
                    LocationService.shared.clearCache()
                    Task { await LocationService.shared.current() }
                } label: {
                    Label {
                        Text("Manage Location").foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "location")
                    }
                }
            }

            Section("Support & Legal") {
                row("Help & Support", "questionmark.circle", .help)
                row("Manage Privacy", "hand.raised", .privacy)
                row("About Atstores", "info.circle", .content(title: "About Atstores", type: "ABOUT_US"))
                row("Privacy Policy", "lock.shield", .content(title: "Privacy Policy", type: "PRIVACY_POLICY"))
                row("Terms & Conditions", "doc.text", .content(title: "Terms & Conditions", type: "TERMS_CONDITIONS"))
            }

            Section {
                Button(role: .destructive) { confirmLogout = true } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                NavigationLink(value: Route.appVersion) {
                    Text("Atstores v\(appVersion)").frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Profile")
        .appHeader()
        .confirmationDialog("Log out of AtStores?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Logout", role: .destructive) { session.logout() }
        }
        .task { await refreshUser() }
    }

    private func row(_ title: String, _ icon: String, _ route: Route) -> some View {
        NavigationLink(value: route) { Label(title, systemImage: icon) }
    }

    private func locationLine(_ u: UserProfile?) -> String {
        var s = ""
        if let a = u?.area.nonEmpty { s += a + ", " }
        if let c = u?.city.nonEmpty { s += c }
        if let z = u?.zipcode.nonEmpty { s += " - " + z }
        return s.isEmpty ? "Location not set" : s
    }

    private func refreshUser() async {
        let s = Session.shared
        guard !s.uid.isEmpty else { return }
        let path = Int(s.uid).map { "api/users/\($0)" } ?? "api/user/me"
        if let d = await API.shared.object(path, auth: true), !d.isEmpty { s.userData = d }
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var name = ""
    @State private var mobile = ""
    @State private var email = ""
    @State private var city = ""
    @State private var area = ""
    @State private var address = ""
    @State private var zipcode = ""
    @State private var imageURL: String?
    @State private var localImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let localImage { Image(uiImage: localImage).resizable().scaledToFill() }
                                else { RemoteImage(url: imageURL, placeholder: "person.fill") }
                            }
                            .frame(width: 100, height: 100).clipShape(Circle())
                            Image(systemName: "camera.circle.fill").font(.title).foregroundStyle(.orange)
                                .background(.white, in: Circle())
                        }
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            Section("Personal") {
                field("Name", "Full name", $name)
                field("Mobile", "Mobile number", $mobile).keyboardType(.phonePad)
                field("Email", "name@example.com", $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section("Address") {
                field("City", "City", $city)
                field("Area", "Area / locality", $area)
                field("Address", "House, street", $address)
                field("Zipcode", "6-digit PIN", $zipcode).keyboardType(.numberPad)
            }
        }
        .appHeader(title: "Edit Profile") {
            Button { Task { await save() } } label: {
                if saving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
            }
            .tint(.orange)
            .disabled(saving)
        }
        .onAppear(perform: fill)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        LabeledContent {
            TextField(placeholder, text: text).multilineTextAlignment(.trailing)
        } label: {
            Text(label).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func fill() {
        let s = Session.shared
        let u = s.user
        name = u?.name ?? ""
        email = u?.email ?? ""
        city = u?.city ?? ""
        area = u?.area ?? ""
        address = u?.address ?? ""
        zipcode = u?.zipcode ?? ""
        mobile = u?.contactNo.nonEmpty ?? s.mobileNumber
        imageURL = u?.thumbnailImage
    }

    private func upload(_ item: PhotosPickerItem) async {
        let id = Session.shared.numericUserId
        guard id > 0 else { toast.show("Could not identify user ID"); return }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
              let jpeg = img.jpegData(compressionQuality: 0.8) else { return }
        saving = true
        defer { saving = false }
        do {
            let r = try await API.shared.upload("api/users/\(id)/addImage", field: "thumbnailImage",
                                                filename: "profile_temp.jpg", data: jpeg, mime: "image/jpeg")
            if r.ok {
                localImage = img
                toast.show("Image uploaded successfully")
            } else {
                toast.show("Upload failed: \(r.status)", long: true)
            }
        } catch {
            toast.show("Network Error: \(error.localizedDescription)")
        }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespaces)
        let m = mobile.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !m.isEmpty else { toast.show("Name and Mobile are required"); return }
        let s = Session.shared
        let id = s.numericUserId
        guard id > 0 else { toast.show("User ID not found"); return }
        let u = s.user
        var body: [String: Any] = [
            "id": id, "name": n, "contactNo": m, "email": email, "city": city,
            "area": area, "address": address, "zipcode": zipcode
        ]
        body["username"] = u?.username ?? ""
        body["role"] = u?.role ?? "CUSTOMER"
        body["provider"] = u?.provider ?? ""
        body["active"] = u?.isActive ?? true

        saving = true
        defer { saving = false }
        do {
            let r = try await API.shared.send(.put, "api/users/\(id)/editProfile", body: body, auth: true)
            if r.ok {
                var d = s.userData ?? [:]
                d["name"] = n; d["contactNo"] = m; d["email"] = email; d["city"] = city
                d["area"] = area; d["address"] = address; d["zipcode"] = zipcode
                s.userData = d
                toast.show("Profile updated successfully")
                dismiss()
            } else {
                toast.show("Update failed: \(r.status)")
            }
        } catch {
            toast.show("Network Error")
        }
    }
}

// MARK: - Bookings

struct MyBookingsView: View {
    @State private var bookings: [BookingRecord] = []
    @State private var loading = true
    @State private var detail: BookingRecord?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(bookings) { b in
                    Button { detail = b } label: { BookingCard(booking: b) }.buttonStyle(.plain)
                }
                if !loading && bookings.isEmpty { EmptyStateView(icon: "calendar", text: "No bookings yet", detail: "Book a salon or spa appointment and it will show up here.", actionTitle: "Explore Salons", route: .storeList(categoryId: 32, title: "Salon & Spa")) }
            }
            .padding()
        }
        .overlay { if loading && bookings.isEmpty { SkeletonView(style: .list).background(Color(.systemBackground)) } }
        .refreshable { await load() }
        .appHeader(title: "My Bookings")
        .sheet(item: $detail) { BookingDetailSheet(booking: $0) }
        .task { if bookings.isEmpty { await load() } }
    }

    /// Tries each candidate id against the authenticated, public and uid endpoints in turn.
    private func load() async {
        loading = true
        defer { loading = false }
        for id in Session.shared.candidateIds {
            let seg = API.seg(id)
            for (path, auth) in [("api/public/booking/userId/\(seg)", true),
                                 ("api/public/booking/userId/\(seg)", false),
                                 ("api/public/booking/uid/\(seg)", false)] {
                let list = await API.shared.objects(path, auth: auth, keys: ["data", "content", "list", "bookings"])
                if !list.isEmpty {
                    bookings = list.map { BookingRecord(raw: $0) }.sorted { $0.sortKey > $1.sortKey }
                    return
                }
            }
        }
    }
}

struct BookingCard: View {
    let booking: BookingRecord
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: booking.imageUrl, placeholder: "scissors")
                .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(booking.storeName).font(.headline).lineLimit(1)
                    Spacer()
                    StatusPill(text: booking.status, fg: statusColor(booking.status), bg: statusColor(booking.status).opacity(0.12))
                }
                Text("Booking ID: #\(booking.bookingId.isEmpty ? "--" : booking.bookingId)").font(.caption).foregroundStyle(.secondary)
                Text("📅 Date: \(booking.date)   ⏰ \(booking.time)").font(.caption)
                Text("✂️ Services: \(booking.servicesSummary)").font(.caption).lineLimit(2)
                Text(Format.price(booking.totalPrice)).font(.subheadline.bold())
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

func statusColor(_ status: String) -> Color {
    switch status {
    case "CONFIRMED", "COMPLETED", "DELIVERED": return .green
    case "CANCELLED", "REJECTED": return .red
    default: return .orange
    }
}

struct BookingDetailSheet: View {
    @State var booking: BookingRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    RemoteImage(url: booking.imageUrl, placeholder: "scissors")
                        .frame(height: 160).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    HStack {
                        VStack(alignment: .leading) {
                            Text(booking.storeName).font(.title3.bold())
                            Text(booking.category).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(text: booking.status, fg: statusColor(booking.status), bg: statusColor(booking.status).opacity(0.12))
                    }
                    Text("Booking ID: #\(booking.bookingId.isEmpty ? "--" : booking.bookingId)").font(.subheadline)
                    Text("📅 Date: \(booking.date) | ⏰ \(booking.time)").font(.subheadline)
                    Text("Customer: \(booking.customerName) (\(booking.customerMobile))").font(.subheadline)
                    Divider()
                    Text("Services").font(.headline)
                    ForEach(booking.serviceRows) { row in
                        HStack(spacing: 10) {
                            RemoteImage(url: row.imageUrl, placeholder: "scissors")
                                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(row.name)
                            Spacer()
                            Text(Format.price(row.price)).bold()
                        }
                    }
                    Divider()
                    HStack { Text("Total").font(.headline); Spacer(); Text(Format.price(booking.totalPrice)).font(.headline) }
                    Text("Payment: \(booking.paymentMethod) (\(booking.paymentStatus))").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Booking Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task {
                // Fetch full details when the list entry lacks per-service images.
                guard !booking.bookingId.isEmpty, booking.detailImages.isEmpty,
                      let full = await API.shared.object("api/public/booking/\(API.seg(booking.bookingId))", auth: true),
                      !full.isEmpty else { return }
                booking = BookingRecord(raw: booking.raw.merging(full) { _, new in new })
            }
        }
    }
}

// MARK: - Orders

struct OrdersView: View {
    @State private var orders: [OrderRecord] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Order #\(o.orderId)").font(.headline)
                            Spacer()
                            StatusPill(text: o.status, fg: statusColor(o.status), bg: statusColor(o.status).opacity(0.12))
                        }
                        Text("📅 Date: \(o.date)").font(.subheadline)
                        Text(o.itemsLabel).font(.subheadline).foregroundStyle(.secondary)
                        Text(Format.price(o.total)).font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                if !loading && orders.isEmpty { EmptyStateView(icon: "shippingbox", text: "No orders yet", detail: "Your product orders will appear here.", actionTitle: "Browse Stores", route: .storeList(categoryId: 0, title: "All Stores")) }
            }
            .padding()
        }
        .overlay { if loading && orders.isEmpty { SkeletonView(style: .list).background(Color(.systemBackground)) } }
        .appHeader(title: "My Orders")
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let s = Session.shared
        let id = s.user.map { String($0.id) } ?? s.uid
        guard !id.isEmpty, id != "0" else { return }
        var list = await API.shared.objects("api/user/orders/\(API.seg(id))", auth: true)
        if list.isEmpty { list = await API.shared.objects("api/public/orders/\(API.seg(id))", auth: true) }
        orders = list.map { OrderRecord(raw: $0) }.filter { !$0.isBooking }
    }
}

// MARK: - Wishlist & saved stores

struct WishlistView: View {
    @State private var products: [Product] = []
    @State private var loading = true
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(products) { p in
                    ProductCard(product: p, wishlistMode: true) {
                        products.removeAll { $0.id == p.id }
                    }
                }
            }
            .padding()
            if !loading && products.isEmpty { EmptyStateView(icon: "heart", text: "Your wishlist is empty", detail: "Tap the heart on any product to save it here.", actionTitle: "Browse Stores", route: .storeList(categoryId: 0, title: "All Stores")) }
        }
        .overlay { if loading && products.isEmpty { SkeletonView(style: .grid).background(Color(.systemBackground)) } }
        .appHeader(title: "Wishlist")
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let s = Session.shared
        guard !s.uid.isEmpty else { return }
        let uid = API.seg(s.uid)
        let loc = LocationService.shared
        var json = await API.shared.json(.get, "api/wishlist/\(uid)", query: ["userLat": loc.lat, "userLng": loc.lng], auth: true)
        if json == nil { json = await API.shared.json(.get, "api/wishlist/byuser/\(uid)", auth: true) }
        var items = JSON.objects(from: json, preferredKeys: ["data", "list"])
        if items.isEmpty, let single = json as? JSONDict, single["productId"] != nil { items = [single] }
        // Real prices only; cards show "View details" when the server sends none.
        products = items.map(Product.init).reversed()
    }
}

struct SavedStoresView: View {
    @State private var stores: [Store] = []
    @State private var loading = true
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(stores) { s in
                    StoreGridCard(store: s) { stores.removeAll { $0.storeId == s.storeId } }
                }
            }
            .padding()
            if !loading && stores.isEmpty { EmptyStateView(icon: "bookmark", text: "No saved stores yet", detail: "Tap the heart on a store to keep it handy.", actionTitle: "Browse Stores", route: .storeList(categoryId: 0, title: "All Stores")) }
        }
        .overlay { if loading && stores.isEmpty { SkeletonView(style: .grid).background(Color(.systemBackground)) } }
        .appHeader(title: "Saved Stores")
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let uid = Session.shared.uid
        guard !uid.isEmpty else { return }
        stores = await API.shared.objects("api/user/stores/saved/\(API.seg(uid))", auth: true).map(Store.init).reversed()
    }
}
