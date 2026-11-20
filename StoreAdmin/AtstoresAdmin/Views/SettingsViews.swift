import SwiftUI

// MARK: - Settings (ProfileActivity)

struct SettingsView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    private var session = Session.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayName.isEmpty ? "Store Admin" : session.displayName).font(.headline)
                        Text(session.mobileNumber).font(.subheadline).foregroundStyle(.secondary)
                        if !session.selectedStoreName.isEmpty {
                            Label(session.selectedStoreName, systemImage: "storefront").font(.caption).foregroundStyle(Theme.primary)
                        }
                    }
                    Spacer()
                }
                .cardStyle()

                menu {
                    item("My Profile", "person", .editProfile)
                    Divider().padding(.leading, 52)
                    item("Store Settings", "storefront", .storeForm(session.selectedStoreId), enabled: session.selectedStoreId > 0)
                    Divider().padding(.leading, 52)
                    item("Store Website", "globe", .storeWebsite, enabled: session.selectedStoreId > 0)
                    Divider().padding(.leading, 52)
                    item("Orders", "bag", .orders)
                }
                menu {
                    HStack(spacing: 14) {
                        icon("bell")
                        Toggle("Notifications", isOn: Binding(get: { session.notificationsEnabled }, set: { v in
                            session.notificationsEnabled = v
                            toast.show("Notifications turned \(v ? "ON" : "OFF")")
                        }))
                        .tint(Theme.primary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                menu {
                    item("Help & FAQ", "questionmark.circle", .helpFaq)
                    Divider().padding(.leading, 52)
                    item("Contact Support", "headphones", .contactSupport)
                    Divider().padding(.leading, 52)
                    item("Privacy Policy", "hand.raised", .content(title: "Privacy Policy", type: "PRIVACY_POLICY"))
                    Divider().padding(.leading, 52)
                    item("Terms & Conditions", "doc.text", .content(title: "Terms & Conditions", type: "TERMS_CONDITIONS"))
                }
                Button { confirmLogout = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.danger)
                            .frame(width: 36, height: 36).background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        Text("Logout").foregroundStyle(Theme.danger).font(.body.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                .buttonStyle(.plain)

                Button { confirmDelete = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(Theme.danger)
                            .frame(width: 36, height: 36).background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        Text("Delete Account").foregroundStyle(Theme.danger).font(.body.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                .buttonStyle(.plain)

                Text("AtStores Store Admin • Version \(version)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .adminHeader()
        .alert("Logout", isPresented: $confirmLogout) {
            Button("Logout", role: .destructive) {
                session.logout()
                toast.show("Logged out successfully")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to logout from AtStores Store Admin?")
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Request Deletion", role: .destructive) {
                AccountDeletion.request(accountType: "Store administrator", appName: "AtStores Admin",
                                        mobile: session.mobileNumber,
                                        userId: session.userId.isEmpty ? session.uid : session.userId)
            }
            Button("Learn More") { AccountDeletion.openInfoPage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends a deletion request for your account to AtStores support. After verifying it's you, they delete your account and personal data. Tell them in the email if your store listing should also be removed.")
        }
    }

    private func menu<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).foregroundStyle(Theme.primary)
            .frame(width: 36, height: 36).background(Theme.tint, in: RoundedRectangle(cornerRadius: 9))
    }

    private func item(_ title: String, _ symbol: String, _ route: Route, enabled: Bool = true) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                icon(symbol)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Edit profile (EditProfileActivity)

struct EditProfileView: View {
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var city = ""
    @State private var mobile = ""
    @State private var busy = false
    private var session = Session.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 14) {
                    FormField(label: "Full Name *", text: $name)
                    FormField(label: "Email", text: $email, keyboard: .emailAddress)
                    FormField(label: "City", text: $city)
                    FormField(label: "Mobile Number", text: $mobile, disabled: true)
                }
                .cardStyle()
                BusyButton(title: "SAVE", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
        .adminHeader("My Profile")
        .onAppear {
            name = session.displayName
            email = session.email
            city = session.city
            mobile = session.userData?.str("mobile") ?? session.mobileNumber
        }
    }

    private func save() async {
        guard !name.trimmed.isEmpty else { toast.show("Enter full name"); return }
        let userId = session.effectiveUserId
        guard !userId.isEmpty else { toast.show("User session invalid. Please log in again."); return }
        busy = true
        defer { busy = false }
        var body: [String: Any] = ["fullName": name.trimmed, "name": name.trimmed, "email": email.trimmed, "city": city.trimmed]
        var ok = await API.shared.ok(.put, "api/users/\(API.seg(userId))/editProfile", body: body)
        if !ok {
            body["userId"] = userId
            body["uid"] = userId
            ok = await API.shared.ok(.put, "api/user/\(API.seg(userId))", body: body)
        }
        if ok {
            session.updateUserData(name: name.trimmed, email: email.trimmed, city: city.trimmed)
            toast.show("Profile updated successfully!")
            dismiss()
        } else {
            toast.show("Update failed")
        }
    }
}

// MARK: - Notifications (NotificationActivity)

struct NotificationsView: View {
    @Environment(ToastCenter.self) private var toast
    @Environment(Router.self) private var router
    @State private var items: [AppNotification] = []
    @State private var loaded = false
    @State private var confirmClear = false
    private var session = Session.shared

    var body: some View {
        List {
            if !loaded {
                LoadingView().listRowBackground(Color.clear)
            } else if items.isEmpty {
                EmptyStateView(icon: "bell.slash", text: "No notifications").listRowBackground(Color.clear)
            }
            ForEach(items) { n in
                Button { open(n) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: n.bookingId > 0 ? "calendar.badge.clock" : "bell.fill")
                            .foregroundStyle(Theme.primary)
                            .frame(width: 36, height: 36).background(Theme.tint, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.title).font(.subheadline.bold())
                            if !n.message.isEmpty { Text(n.message).font(.subheadline).foregroundStyle(.secondary) }
                            Text(Format.timestamp(n.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { Task { await delete(n) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .adminHeader("Notifications") {
            if !items.isEmpty {
                Button("Clear All") { confirmClear = true }.font(.subheadline.weight(.semibold))
            }
        }
        .task { await load() }
        .alert("Clear all notifications?", isPresented: $confirmClear) {
            Button("Clear All", role: .destructive) { Task { await clearAll() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        let userId = session.effectiveUserId
        guard !userId.isEmpty else { loaded = true; return }
        let json = await API.shared.json(.get, "api/public/notifications/userId/\(API.seg(userId))")
        items = JSON.objects(from: json, preferredKeys: ["notifications", "data", "items", "list"])
            .map(AppNotification.init)
            .sorted { $0.createdAt > $1.createdAt }
        loaded = true
    }

    /// Booking notifications open the booking; anything else opens Orders.
    private func open(_ n: AppNotification) {
        if n.bookingId > 0 {
            router.path.append(.bookings(openBookingId: n.bookingId, storeId: n.storeId))
        } else {
            router.path.append(.orders)
        }
    }

    private func delete(_ n: AppNotification) async {
        if await API.shared.ok(.delete, "api/store/notification/\(n.id)", query: ["userId": session.effectiveUserId]) {
            items.removeAll { $0.id == n.id }
            toast.show("Notification deleted")
        } else {
            toast.show("Failed to delete notification")
        }
    }

    private func clearAll() async {
        if await API.shared.ok(.delete, "api/store/notification/clear-all", query: ["userId": session.effectiveUserId]) {
            items = []
            toast.show("All notifications cleared")
        } else {
            toast.show("Failed to clear notifications")
        }
    }
}

// MARK: - Help & FAQ (HelpFaqActivity)

struct HelpFaqView: View {
    @State private var expanded: Set<Int> = []

    private static let faqs: [(String, String)] = [
        ("How do I add or edit products in my store?",
         "Open your store from the Dashboard and tap 'Add New'. Enter the product name, price, discount, category and quantity or duration. Tap 'Save' to publish. Tap the camera icon on a product to upload its photo."),
        ("How do I update my store opening/closing hours and location?",
         "Go to Settings -> Store Settings. Here you can edit store details, address, opening/closing hours and category, and use your current location to fill in the address."),
        ("How do I create an offer or promotion?",
         "Open your store and tap 'Offers' -> 'Create Offer'. Choose 'Offer on Products' to promote specific products or 'New Store / Service Offer' for general promotions. Preview the offer card before publishing."),
        ("How do I manage customer bookings and orders?",
         "Tap the 'Bookings' tab to view incoming bookings. You can confirm, reschedule or mark bookings as completed. Orders are available under Settings -> Orders."),
        ("How do I share my store link with customers on WhatsApp?",
         "Open your store -> Customers and tap the message icon next to any customer. A pre-formatted message with your Store Link and App Download Links opens in WhatsApp.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(Self.faqs.enumerated()), id: \.offset) { i, faq in
                    let open = expanded.contains(i)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text(faq.0).font(.subheadline.bold()).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary)
                        }
                        if open { Text(faq.1).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { if open { expanded.remove(i) } else { expanded.insert(i) } }
                    }
                }
                NavigationLink(value: Route.contactSupport) { Text("Contact Support") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .adminHeader("Help & FAQ")
    }
}

// MARK: - Contact support (ContactSupportActivity)

struct ContactSupportView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var message = ""
    private var store: String { Session.shared.selectedStoreName.isEmpty ? "Our Store" : Session.shared.selectedStoreName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Need help setting up your store catalog, uploading products, or configuring your storefront? Select a topic below and send us a message — our team will get in touch with you shortly!")
                    .font(.subheadline).foregroundStyle(.secondary)
                SectionTitle(text: "Select Topic for Assistance")
                topic("Full Store & Storefront Setup", "Help setting up store details, hours, and branding", "storefront",
                      "Hello AtStores Team, I need help setting up my full store details and storefront creation for \(store).")
                topic("Catalog & Product Upload Help", "Assistance creating product inventory and photos", "photo.on.rectangle",
                      "Hello AtStores Team, I need assistance in creating my product catalog and uploading product photos for \(store).")
                topic("Offers & Promotion Setup", "Help creating special discounts & banners", "tag",
                      "Hello AtStores Team, I need help setting up special offers and marketing promotions for \(store).")
                FormField(label: "Your Message / Request", text: $message, multiline: true)
                Button("SEND MESSAGE VIA WHATSAPP") {
                    if message.trimmed.isEmpty { toast.show("Please type a message"); return }
                    StoreActions.whatsApp(StoreActions.supportPhone, message: message.trimmed, toast: toast)
                    toast.show("Our AtStores team will reach out to help you shortly.", long: true)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.success))
                HStack(spacing: 10) {
                    Button { StoreActions.call(StoreActions.supportPhone) } label: { Label("Call Support", systemImage: "phone.fill") }
                        .buttonStyle(OutlineButtonStyle())
                    Button {
                        StoreActions.email(StoreActions.supportEmail, subject: "AtStores Store Admin Support Request - \(store)", body: message)
                    } label: { Label("Email Us", systemImage: "envelope.fill") }
                        .buttonStyle(OutlineButtonStyle())
                }
                Text("Call Support: +91 91487 83102\nEmail: support@atstores.in").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .adminHeader("Contact Support")
        .onAppear {
            if message.isEmpty {
                message = "Hello AtStores Team,\n\nI need help setting up my store catalog and storefront for \(store). Please reach out to me."
            }
        }
    }

    private func topic(_ title: String, _ detail: String, _ icon: String, _ text: String) -> some View {
        Button {
            message = text
            toast.show("Topic selected! Message updated.")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.primary)
                    .frame(width: 40, height: 40).background(Theme.tint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold())
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .cardStyle(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content pages (WebViewActivity with contentType)

struct ContentPageView: View {
    let title: String
    let type: String
    @State private var html: NSAttributedString?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            Group {
                if let html {
                    HTMLTextView(text: html)
                } else if loaded {
                    EmptyStateView(icon: "doc.text", text: "Content not available")
                } else {
                    LoadingView()
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .adminHeader(title)
        .task {
            if let d = await API.shared.object("api/public/content/\(type)", query: ["appType": "STORE"]) {
                let text = d.str("content") ?? d.dict("data")?.str("content", "text") ?? d.str("data") ?? d.str("text", "body")
                if let text, !text.trimmed.isEmpty { html = HTMLText.styled(text) }
            }
            loaded = true
        }
    }
}

// MARK: - Store website (StoreWebsiteActivity + RequestWebsiteActivity)

struct StoreWebsiteView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var website: String?
    @State private var status = "NONE"
    @State private var loaded = false
    @State private var message = ""
    @State private var busy = false
    private var session = Session.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !loaded {
                    LoadingView()
                } else if let website {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your Store Website", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.success)
                        Text("Your official online website is live and accessible to customers").font(.subheadline).foregroundStyle(.secondary)
                        Text(website).font(.subheadline.bold()).foregroundStyle(Theme.primary)
                        Button("Visit My Site") { StoreActions.website(website, toast: toast) }.buttonStyle(PrimaryButtonStyle())
                    }
                    .cardStyle()
                    requestCard(title: "Need to Update or Change Your Website?",
                                detail: "If you need to update catalog products, design, or store details on your website, type your request below and submit to our team.",
                                button: "Submit Update Request", currentSite: website)
                } else if status == "SUBMITTED" || status == "IN_PROGRESS" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(status == "IN_PROGRESS" ? "⚙️ Website Request in Progress" : "⏳ Website Request Submitted").font(.headline)
                        Text("Thank you! Your website request has been submitted to the AtStores team. Our team is working on your request and will contact you shortly.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Store: \(session.selectedStoreName) (ID: #\(session.selectedStoreId))").font(.caption.bold())
                    }
                    .cardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "globe").font(.largeTitle).foregroundStyle(Theme.primary)
                        Text("Create Your Store Website").font(.title3.bold())
                        Text("Your store currently does not have a website configured. Tell us what you need and AtStores will create your website!")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink(value: Route.requestWebsite) { Text("Request a Professional Website") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .cardStyle()
                    requestCard(title: "Quick Request",
                                detail: "Enter your website requirements or preferences below and click submit to notify the AtStores team.",
                                button: "Submit Website Request", currentSite: nil)
                }
            }
            .padding(16)
        }
        .adminHeader("Store Website")
        .onAppear { Task { await load() } }
    }

    private func requestCard(title: String, detail: String, button: String, currentSite: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            FormField(label: "Your Message / Request", text: $message, multiline: true)
            BusyButton(title: button, busy: busy) { Task { await submit(currentSite) } }
        }
        .cardStyle()
    }

    private func load() async {
        let id = session.selectedStoreId
        status = session.websiteRequestStatus(id)
        if id > 0, let d = await API.shared.object("api/public/store/\(id)") {
            let site = Store(d).storeWebsite?.trimmed ?? ""
            website = site.isEmpty ? nil : site
        }
        loaded = true
    }

    private func submit(_ currentSite: String?) async {
        guard !message.trimmed.isEmpty else { toast.show("Please enter your website request"); return }
        busy = true
        defer { busy = false }
        var body: [String: Any] = ["storeId": session.selectedStoreId, "storeName": session.selectedStoreName, "message": message.trimmed]
        if let currentSite { body["websiteUrl"] = currentSite }
        _ = try? await API.shared.send(.post, "api/store/website", body: body)
        // Android treats the request as submitted whatever the response.
        session.setWebsiteRequestStatus(session.selectedStoreId, "SUBMITTED")
        toast.show("Website request submitted to AtStores team!")
        message = ""
        if currentSite == nil { status = "SUBMITTED" }
    }
}

struct RequestWebsiteView: View {
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var adminName = ""
    @State private var email = ""
    @State private var address = ""
    @State private var requirements = ""
    @State private var submitted = false
    private var session = Session.shared

    var body: some View {
        ScrollView {
            if submitted {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.success)
                    Text("Request Submitted").font(.title3.bold())
                    Text("Thank you! Your website request has been submitted to the AtStores team. Our team will contact you shortly.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
            } else {
                VStack(spacing: 14) {
                    VStack(spacing: 14) {
                        FormField(label: "Store Name", text: .constant(session.selectedStoreName), disabled: true)
                        FormField(label: "Admin Name *", text: $adminName)
                        FormField(label: "Mobile", text: .constant(session.mobileNumber), disabled: true)
                        FormField(label: "Email", text: $email, keyboard: .emailAddress)
                        FormField(label: "Store Address", text: $address, multiline: true)
                        FormField(label: "Website Requirements", text: $requirements, placeholder: "Pages, colours, features you'd like…", multiline: true)
                    }
                    .cardStyle()
                    Button("Submit Request") { submit() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .adminHeader("Request Website")
        .task {
            adminName = session.displayName
            email = session.email
            if let d = await API.shared.object("api/public/store/\(session.selectedStoreId)") {
                let s = Store(d)
                if address.isEmpty { address = s.storeAddress ?? "" }
                if email.isEmpty { email = s.storeEmail ?? "" }
            }
        }
    }

    private func submit() {
        guard !adminName.trimmed.isEmpty else { toast.show("Enter admin name"); return }
        let id = session.selectedStoreId
        session.setWebsiteRequestStatus(id, "SUBMITTED")
        let payload: [String: Any] = ["storeId": id, "action": "WEBSITE_REQUEST", "adminName": adminName.trimmed,
                                      "email": email.trimmed, "address": address.trimmed, "requirements": requirements.trimmed]
        Task { _ = try? await API.shared.send(.post, "api/public/activity/log", body: payload) }
        submitted = true
        toast.show("Website request submitted!")
    }
}
