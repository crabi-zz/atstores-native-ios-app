import SwiftUI

// MARK: - Coupons

struct CouponsView: View {
    enum Tab: String, CaseIterable { case all = "All", available = "Available", used = "Used", expired = "Expired" }

    @Environment(ToastCenter.self) private var toast
    @State private var coupons: [CouponItem] = []
    @State private var tab: Tab = .all
    @State private var query = ""
    @State private var grid = true
    @State private var loading = true

    private var filtered: [CouponItem] {
        coupons.filter { c in
            let match: Bool
            switch tab {
            case .all: match = true
            case .available: match = !c.isUsed && !c.isExpired
            case .used: match = c.isUsed
            case .expired: match = c.isExpired && !c.isUsed
            }
            guard match else { return false }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return q.isEmpty || [c.storeName, c.title, c.code].contains { $0.lowercased().contains(q) }
        }
    }

    private func count(_ t: Tab) -> Int {
        switch t {
        case .all: return coupons.count
        case .available: return coupons.filter { !$0.isUsed && !$0.isExpired }.count
        case .used: return coupons.filter(\.isUsed).count
        case .expired: return coupons.filter { $0.isExpired && !$0.isUsed }.count
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                SearchField(prompt: "Search coupons", text: $query)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button { tab = t } label: {
                                Text("\(t.rawValue) (\(count(t)))").font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(tab == t ? Color(hex: 0xE9D5FF) : Theme.lightGray, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: grid ? 2 : 1), spacing: 12) {
                    ForEach(filtered) { c in
                        CouponCard(coupon: c) { Task { await claim(c) } }
                    }
                }
                .padding(.horizontal)

                if !loading && filtered.isEmpty { EmptyStateView(icon: "ticket", text: "No coupons found") }
            }
            .padding(.vertical)
        }
        .overlay { if loading && coupons.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .appHeader(title: "My Coupons") {
            Button { grid.toggle() } label: {
                Image(systemName: grid ? "list.bullet" : "square.grid.2x2")
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
            }
        }
        .task { if coupons.isEmpty { await load() } }
    }

    private func parse(_ json: Any?) -> [CouponItem] {
        JSON.objects(from: json, preferredKeys: ["data", "content", "list", "coupons"]).map(CouponItem.init)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var list = parse(await API.shared.json(.get, "api/user/coupons", auth: true))
        if list.isEmpty {
            outer: for id in Session.shared.candidateIds.prefix(2) {
                let seg = API.seg(id)
                for (path, auth) in [("api/user/coupons/recipient/\(seg)", true),
                                     ("api/public/coupon/user/\(seg)", false),
                                     ("api/coupons/recipient/user/\(seg)", false)] {
                    list = parse(await API.shared.json(.get, path, auth: auth))
                    if !list.isEmpty { break outer }
                }
            }
        }
        coupons = list
        // Fill in coupon details for recipients that only carry a couponId.
        for (i, c) in list.enumerated() where c.code.isEmpty && !c.couponId.isEmpty {
            if let d = await API.shared.object("api/public/coupon/\(API.seg(c.couponId))"), i < coupons.count {
                coupons[i].merge(coupon: d)
            }
        }
    }

    private func claim(_ c: CouponItem) async {
        let id = API.seg(c.claimId)
        guard !id.isEmpty else { return }
        var r = try? await API.shared.send(.post, "api/user/coupons/\(id)/claim", auth: true)
        if r?.ok != true { r = try? await API.shared.send(.post, "api/user/coupons/claim/\(id)", auth: true) }
        let firstError = r
        if r?.ok != true, !Session.shared.uid.isEmpty {
            r = try? await API.shared.send(.post, "api/public/coupon/claim/\(id)/\(API.seg(Session.shared.uid))")
        }
        if r?.ok == true {
            toast.show("Coupon claimed successfully!")
            await load()
        } else {
            toast.show((firstError ?? r)?.errorMessage("Coupon claim failed") ?? "Coupon claim failed", long: true)
        }
    }
}

struct CouponCard: View {
    let coupon: CouponItem
    let onClaim: () -> Void
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        NavigationLink(value: Route.coupon(coupon)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RemoteImage(url: coupon.imageUrl, placeholder: "ticket")
                        .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    badge
                }
                Text(coupon.storeName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(coupon.title).font(.subheadline.bold()).lineLimit(2)
                Text(coupon.discountLabel).font(.headline).foregroundStyle(.purple)
                Text(coupon.minPurchaseAmount > 0 ? "🛒 Min. purchase: ₹\(Int(coupon.minPurchaseAmount))" : "🛒 No min. purchase")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("📅 Valid till \(coupon.expiryShort)").font(.caption2).foregroundStyle(.secondary)

                if coupon.isUsed || coupon.isExpired {
                    EmptyView()
                } else if coupon.isClaimed {
                    Button {
                        UIPasteboard.general.string = coupon.code
                        toast.show("Coupon Code \(coupon.code) copied!")
                    } label: {
                        HStack {
                            Text(coupon.code).font(.subheadline.monospaced().bold())
                            Spacer()
                            Image(systemName: "doc.on.doc")
                        }
                        .padding(8)
                        .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Claim", action: onClaim)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.black)
                        .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var badge: some View {
        if coupon.isUsed { StatusPill(text: "Used", fg: Color(hex: 0x6B7280), bg: Color(hex: 0xF3F4F6)) }
        else if coupon.status == "EXPIRED" { StatusPill(text: "Expired", fg: Color(hex: 0xDC2626), bg: Color(hex: 0xFEF2F2)) }
        else if coupon.isClaimed { StatusPill(text: "Claimed", fg: Color(hex: 0x1D4ED8), bg: Color(hex: 0xDBEAFE)) }
        else { StatusPill(text: "Available", fg: Color(hex: 0x15803D), bg: Color(hex: 0xDCFCE7)) }
    }
}

struct CouponDetailView: View {
    let coupon: CouponItem
    @Environment(ToastCenter.self) private var toast

    private var terms: String {
        coupon.terms.isEmpty || coupon.terms.contains("Standard terms")
            ? "• Valid for first-time & registered customers.\n• Applicable on selected products & services.\n• Cannot be combined with other store offers."
            : coupon.terms
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: coupon.imageUrl, placeholder: "ticket")
                    .frame(height: 170).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                HStack {
                    Text(coupon.storeName).font(.headline)
                    Spacer()
                    let s = coupon.status
                    if s == "AVAILABLE" { StatusPill(text: s, fg: Color(hex: 0x2E7D32), bg: Color(hex: 0xE8F5E9)) }
                    else if ["CLAIMED", "REDEEMED", "USED"].contains(s) { StatusPill(text: s, fg: Color(hex: 0x1D4ED8), bg: Color(hex: 0xDBEAFE)) }
                    else { StatusPill(text: s, fg: Color(hex: 0xDC2626), bg: Color(hex: 0xFEF2F2)) }
                }
                Text(coupon.title).font(.title2.bold())
                Text(coupon.discountLabel).font(.largeTitle.bold()).foregroundStyle(.purple)

                HStack {
                    Text(coupon.code.isEmpty ? "—" : coupon.code).font(.title3.monospaced().bold())
                    Spacer()
                    Button { copy(" ") } label: { Image(systemName: "doc.on.doc").font(.title3) }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])))

                Grid(alignment: .leading, verticalSpacing: 8) {
                    GridRow { Text("Valid till").foregroundStyle(.secondary); Text(coupon.expiryShort) }
                    GridRow { Text("Min. purchase").foregroundStyle(.secondary)
                        Text(coupon.minPurchaseAmount > 0 ? "₹\(Int(coupon.minPurchaseAmount))" : "No min spend") }
                    GridRow { Text("Max. discount").foregroundStyle(.secondary)
                        Text(coupon.maxDiscountAmount > 0 ? "₹\(Int(coupon.maxDiscountAmount))" : "No limit") }
                }

                Text("Terms & Conditions").font(.headline)
                Text(terms).font(.subheadline).foregroundStyle(.secondary)

                Button("Use at Store") { copy(" Present code at store.") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
        }
        .appHeader(title: "Coupon Details")
    }

    private func copy(_ suffix: String) {
        guard !coupon.code.isEmpty else { return }
        UIPasteboard.general.string = coupon.code
        toast.show("Coupon Code \(coupon.code) copied!\(suffix)".trimmingCharacters(in: .whitespaces), long: suffix.count > 1)
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var items: [AppNotification] = []
    @State private var loading = true

    var body: some View {
        List {
            ForEach(items) { n in
                HStack(alignment: .top, spacing: 12) {
                    let (icon, color) = style(n)
                    Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.subheadline.bold())
                        if !n.message.isEmpty { Text(n.message).font(.subheadline) }
                        if let s = n.serviceName.nonEmpty { Text("Service/Store: \(s)").font(.caption).foregroundStyle(.secondary) }
                        if let d = n.bookingDate.nonEmpty { Text("📅 Date: \(d)").font(.caption).foregroundStyle(.secondary) }
                        Text("🕒 " + Format.notificationDate(n.createdDate)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let img = n.imageUrl.nonEmpty {
                        RemoteImage(url: img).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && items.isEmpty { ProgressView() }
            else if items.isEmpty { EmptyStateView(icon: "bell.slash", text: "No notifications") }
        }
        .refreshable { await load() }
        .appHeader(title: "Notifications") {
            if !items.isEmpty {
                Button("Clear All") { Task { await clearAll() } }
                    .font(.subheadline.weight(.semibold))
                    .tint(.orange)
            }
        }
        .task { if items.isEmpty { await load() } }
    }

    private func style(_ n: AppNotification) -> (String, Color) {
        let t = (n.title + " " + n.type).lowercased()
        if t.contains("booking") || t.contains("order") { return ("shippingbox.fill", Color(hex: 0x2E7D32)) }
        if t.contains("store") { return ("storefront.fill", Color(hex: 0x1976D2)) }
        if t.contains("offer") || t.contains("promo") || t.contains("discount") { return ("tag.fill", Color(hex: 0xF57C00)) }
        return ("bell.fill", Color(hex: 0x333333))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        for id in Session.shared.candidateIds {
            for auth in [true, false] {
                let list = await API.shared.objects("api/public/notifications/userId/\(API.seg(id))", auth: auth,
                                                    keys: ["data", "list", "notifications", "content"])
                if !list.isEmpty {
                    items = list.map(AppNotification.init).sorted { $0.createdDate > $1.createdDate }
                    return
                }
            }
        }
    }

    private func clearAll() async {
        guard let target = Session.shared.candidateIds.first else { return }
        let path = "api/public/deletenotifications/userId/\(API.seg(target))"
        if !(await API.shared.ok(.delete, path, auth: true)) { _ = await API.shared.ok(.delete, path) }
        items = []
        toast.show("Notifications cleared")
    }
}

// MARK: - Static content

struct ContentPageView: View {
    let title: String
    let type: String
    @State private var heading = ""
    @State private var body_: NSAttributedString?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if let body_ {
                HTMLTextView(text: body_)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay { if loading { ProgressView() } }
        .appHeader(title: heading.isEmpty ? title : heading)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let r = try? await API.shared.send(.get, "api/public/content/\(type)"), r.ok {
            if let d = r.json as? JSONDict {
                if let t = d.str("title") { heading = t }
                if let html = d.str("content", "data", "text", "body", "description") {
                    body_ = HTMLText.styled(html); return
                }
            } else if !r.text.isEmpty {
                body_ = HTMLText.styled(r.text); return
            }
        }
        body_ = HTMLText.styled(Self.fallback[type] ?? Self.fallback["ABOUT_US"]!)
    }

    static let fallback: [String: String] = [
        "PRIVACY_POLICY": """
        <h2>AtStores Privacy Policy</h2>
        <p><b>1. Information Collection:</b><br/>We collect information such as your name, mobile number, email address, and device location to provide personalized store recommendations and booking services.</p>
        <p><b>2. Use of Information:</b><br/>Your data is used to process bookings, show nearby stores, send promotional offers, and improve platform experience.</p>
        <p><b>3. Data Security:</b><br/>We implement industry-standard security measures to safeguard your personal data. We do not sell your personal information to third parties.</p>
        <p><b>4. Location Usage:</b><br/>Location access is used solely to discover nearby stores, salons, clinics, and calculate distance.</p>
        <p><b>5. Contact Us:</b><br/>If you have questions regarding this Privacy Policy, please contact <b>support@atstores.in</b>.</p>
        """,
        "TERMS_CONDITIONS": """
        <h2>AtStores Terms &amp; Conditions</h2>
        <p><b>1. User Agreement:</b><br/>By accessing or using the AtStores mobile application, you agree to comply with and be bound by these terms and conditions.</p>
        <p><b>2. Booking &amp; Store Services:</b><br/>AtStores provides a discovery and booking platform connecting users with local stores, salons, restaurants, and service providers. Service fulfillment is managed directly by respective merchants.</p>
        <p><b>3. User Conduct:</b><br/>Users agree to provide accurate registration details and refrain from unauthorized activity, spamming, or fraudulent bookings.</p>
        <p><b>4. Cancellations &amp; Refunds:</b><br/>Booking cancellations and refund requests are subject to individual merchant policies.</p>
        <p><b>5. Intellectual Property:</b><br/>All logos, trademarks, content, and design elements within the app belong to AtStores and its licensors.</p>
        """,
        "FAQ": """
        <h2>Frequently Asked Questions (FAQs)</h2>
        <p><b>Q: How do I book a salon appointment?</b><br/>A: Select any Salon store or Salon product, tap 'Book Now', select your service, date, and preferred time slot.</p>
        <p><b>Q: How do I save my favorite stores?</b><br/>A: Tap the Heart icon on any store card or store detail page to save it to your Saved Stores list.</p>
        <p><b>Q: How do I update my location?</b><br/>A: Go to Profile -> Manage Location, or tap the location bar at the top of the screen.</p>
        """,
        "ABOUT_US": """
        <h2>About AtStores</h2>
        <p>AtStores is your premier hyper-local discovery and booking platform.</p>
        <h3>Our Mission:</h3>
        <p>Connecting consumers seamlessly with nearby local businesses, including beauty salons, boutiques, clinics, restaurants, and retail stores.</p>
        <h3>Key Features:</h3>
        <ul><li>Discover nearby stores and exclusive local offers.</li><li>Book salon &amp; spa appointments effortlessly.</li><li>Save favorite stores and track bookings in real-time.</li><li>Explore products and contact store owners directly via WhatsApp or Phone.</li></ul>
        <p>Thank you for choosing AtStores to support local businesses!</p>
        """
    ]
}

struct HelpSupportView: View {
    @Environment(ToastCenter.self) private var toast
    var body: some View {
        List {
            Section {
                supportRow("Call Support", "+91 91487 83102", "phone.fill") {
                    StoreActions.call("+919148783102", toast: toast)
                }
                supportRow("WhatsApp Support", "Chat with us on WhatsApp", "message.fill") {
                    StoreActions.whatsApp("919148783102", toast: toast)
                }
                supportRow("Email Support", "support@atstores.in", "envelope.fill") {
                    StoreActions.email("support@atstores.in", subject: "AtStores App Inquiry / Support")
                }
            } footer: {
                Text("Our support team is available Monday to Saturday, 9:00 AM - 8:00 PM.")
            }
            Section {
                NavigationLink(value: Route.content(title: "FAQs", type: "FAQ")) { Label("FAQs", systemImage: "questionmark.bubble") }
            }
        }
        .appHeader(title: "Help & Support")
    }

    private func supportRow(_ title: String, _ detail: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.orange).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                    Text(detail).font(.caption).foregroundStyle(Color(.secondaryLabel))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.vertical, 2)
        }
    }
}

struct ManagePrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @AppStorage("pref_location") private var location = true
    @AppStorage("pref_personalized") private var personalized = true
    @AppStorage("pref_notifications") private var notifications = true

    var body: some View {
        Form {
            Section {
                toggle("Location", "Show stores and offers near you", "location.fill", $location)
                toggle("Personalized recommendations", "Suggestions based on your activity", "sparkles", $personalized)
                toggle("Promotional notifications", "Offers and updates from stores", "bell.badge.fill", $notifications)
            } footer: {
                Text("You can change these at any time.")
            }
        }
        .tint(.orange)
        .safeAreaInset(edge: .bottom) {
            Button("Save Preferences") {
                toast.show("Privacy preferences saved successfully")
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 70)
        }
        .appHeader(title: "Manage Privacy")
    }

    private func toggle(_ title: String, _ subtitle: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AppVersionView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(v) (Build \(b))"
    }
    var body: some View {
        VStack(spacing: 14) {
            Image("AppIconPreview")
                .resizable().scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Image("Logo").resizable().scaledToFit().frame(height: 48)
            Text(version).font(.subheadline).foregroundStyle(.secondary)
            Text("© \(String(Calendar.current.component(.year, from: Date()))) AtStores. All rights reserved.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
        .appHeader(title: "App Version")
    }
}
