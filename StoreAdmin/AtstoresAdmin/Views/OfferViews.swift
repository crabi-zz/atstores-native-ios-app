import SwiftUI

// MARK: - Offers list (OfferActivity)

struct OffersView: View {
    let storeId: Int
    @Environment(ToastCenter.self) private var toast
    @State private var offers: [Offer] = []
    @State private var loaded = false
    @State private var uploading: Int?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                NavigationLink(value: Route.createOffer) {
                    Label("Create Offer", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                if !loaded {
                    LoadingView()
                } else if offers.isEmpty {
                    EmptyStateView(icon: "tag", text: "No offers yet", detail: "Create an offer to promote your products and services.")
                }
                ForEach(offers) { offer in
                    NavigationLink(value: Route.offerForm(OfferSeed(existing: offer))) { row(offer) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader("Offers")
        .onAppear { Task { await load() } }
    }

    /// item_offer_admin: thumbnail with upload, name, discount, active switch.
    private func row(_ offer: Offer) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: offer.thumbnailImage)
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                ImagePickButton(onPick: { data in Task { await upload(offer.offerId, data) } }) {
                    Group {
                        if uploading == offer.offerId { ProgressView().tint(.white) }
                        else { Image(systemName: "camera.fill").font(.caption2) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.primary, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
                .offset(x: 5, y: 5)
                .disabled(uploading != nil)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.offerName).font(.subheadline.bold()).lineLimit(2)
                Text("\(offer.discount)% Discount").font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
                if let s = offer.startDate, let e = offer.endDate {
                    Text("\(s) – \(e)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { offer.activeStatus }, set: { v in Task { await setActive(offer, v) } }))
                .labelsHidden()
                .tint(Theme.success)
        }
        .cardStyle(padding: 12)
    }

    private func load() async {
        guard storeId > 0 else { loaded = true; return }
        guard let r = try? await API.shared.send(.get, "api/public/offer/store/\(storeId)"), r.ok else {
            if loaded == false { toast.show("Failed to load offers") }
            loaded = true
            return
        }
        offers = JSON.objects(from: r.json).map(Offer.init).sorted {
            if !$0.createdDate.isEmpty, !$1.createdDate.isEmpty, $0.createdDate != $1.createdDate { return $0.createdDate > $1.createdDate }
            return $0.offerId > $1.offerId
        }
        loaded = true
    }

    private func setActive(_ offer: Offer, _ active: Bool) async {
        guard let i = offers.firstIndex(where: { $0.offerId == offer.offerId }) else { return }
        offers[i].activeStatus = active
        if !(await API.shared.ok(.put, "api/public/offer/\(offer.offerId)/activeStatus/\(active)")) {
            toast.show("Failed to update status")
            if let j = offers.firstIndex(where: { $0.offerId == offer.offerId }) { offers[j].activeStatus = !active }
        }
    }

    private func upload(_ offerId: Int, _ data: Data) async {
        uploading = offerId
        defer { uploading = nil }
        toast.show("Uploading offer image...")
        guard let r = try? await API.shared.upload("api/store/offer/\(offerId)/thumbnailImage", field: "thumbnailImage", data: data) else {
            toast.show("Network error during image upload"); return
        }
        if r.ok {
            toast.show("Offer image uploaded successfully!")
            await load()
        } else {
            toast.show("Image upload failed: \(r.status)")
        }
    }
}

// MARK: - Choose offer type (CreateOfferTypeActivity)

struct CreateOfferTypeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What would you like to promote?").font(.title3.bold())
                    Text("Choose the type of promotion to create for your store").font(.subheadline).foregroundStyle(.secondary)
                }
                card(icon: "shippingbox.fill", color: Theme.primary, title: "Offer on Products",
                     detail: "Create a discount or promotion for one or more existing products in your store.",
                     action: "Select Products", route: .selectOfferProducts)
                card(icon: "sparkles", color: Color(hex: 0xF57F17), title: "New Store / Service Offer",
                     detail: "Create a general offer for your store or services (Salon, Spa, Restaurant, Boutique, etc.).",
                     action: "Create New Offer", route: .offerForm(OfferSeed()))
            }
            .padding(16)
        }
        .adminHeader("Create Offer")
    }

    private func card(icon: String, color: Color, title: String, detail: String, action: String, route: Route) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.title2).foregroundStyle(color)
                        .frame(width: 52, height: 52).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(title).font(.headline)
                }
                Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Text(action).font(.subheadline.bold()).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pick products for an offer (SelectOfferProductsActivity)

struct SelectOfferProductsView: View {
    @Environment(ToastCenter.self) private var toast
    @Environment(Router.self) private var router
    @State private var products: [Product] = []
    @State private var selected: Set<Int> = []
    @State private var query = ""
    @State private var loaded = false

    private var filtered: [Product] {
        query.trimmed.isEmpty ? products : products.filter { $0.productName.localizedCaseInsensitiveContains(query.trimmed) }
    }
    private var allSelected: Bool { !filtered.isEmpty && filtered.allSatisfy { selected.contains($0.productId) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                SearchField(prompt: "Search products", text: $query)
                HStack {
                    Text("\(selected.count) Products Selected").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected { selected.subtract(filtered.map(\.productId)) } else { selected.formUnion(filtered.map(\.productId)) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !loaded { LoadingView() } else if filtered.isEmpty { EmptyStateView(icon: "shippingbox", text: "No products found") }
                    ForEach(filtered) { p in
                        let on = selected.contains(p.productId)
                        Button {
                            if on { selected.remove(p.productId) } else { selected.insert(p.productId) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.title3).foregroundStyle(on ? Theme.primary : .secondary)
                                RemoteImage(url: p.thumbnailImage).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(p.productName).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(Format.price(p.listPrice)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .cardStyle(padding: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            Button("Continue") { proceed() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(16)
                .background(Color.white.shadow(.drop(color: .black.opacity(0.08), radius: 4, y: -2)))
        }
        .adminHeader("Select Products")
        .task { await load() }
    }

    private func load() async {
        let id = Session.shared.selectedStoreId
        products = await API.shared.objects("api/store/product/\(id)").map(Product.init)
        loaded = true
    }

    private func proceed() {
        // Android passes the first selected product to the offer form.
        guard let first = products.first(where: { selected.contains($0.productId) }) else {
            toast.show("Please select at least one product"); return
        }
        router.path.append(.offerForm(OfferSeed(productMode: true, productId: first.productId, productName: first.productName,
                                                productImage: first.thumbnailImage, originalPrice: first.listPrice)))
    }
}

// MARK: - Offer details form (AddOfferActivity)

struct OfferFormView: View {
    let seed: OfferSeed
    @Environment(ToastCenter.self) private var toast
    @Environment(Router.self) private var router

    @State private var name = ""
    @State private var desc = ""
    @State private var type = 0          // 0 percentage, 1 flat, 2 special price
    @State private var value = ""
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var terms = ""
    @State private var imageData: Data?
    @State private var populated = false

    private var isEdit: Bool { seed.existing != nil }
    private var remoteImage: String? { seed.existing?.thumbnailImage ?? seed.productImage }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !isEdit && seed.productMode && !seed.productName.isEmpty {
                    Label("Selected Product: \(seed.productName)\(seed.originalPrice > 0 ? " (₹\(Int(seed.originalPrice)))" : "")",
                          systemImage: "shippingbox.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(spacing: 14) {
                    FormField(label: "Offer Title *", text: $name)
                    FormField(label: "Description", text: $desc, multiline: true)
                    FormValue(label: "Discount Type") {
                        Picker("Discount Type", selection: $type) {
                            Text("Percentage Discount (%)").tag(0)
                            Text("Flat Discount (₹)").tag(1)
                            Text("Special Price (₹)").tag(2)
                        }
                        .labelsHidden()
                        Spacer()
                    }
                    FormField(label: type == 0 ? "Discount (%) *" : type == 1 ? "Discount Amount (₹) *" : "Special Price (₹) *",
                              text: $value, keyboard: .decimalPad)
                    HStack(spacing: 10) {
                        FormValue(label: "Start Date") {
                            DatePicker("", selection: $start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                                .labelsHidden()
                            Spacer(minLength: 0)
                        }
                        FormValue(label: "End Date") {
                            DatePicker("", selection: $end, in: start..., displayedComponents: .date).labelsHidden()
                            Spacer(minLength: 0)
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Offer Banner").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ImagePickButton(onPick: { imageData = $0 }) {
                        ZStack {
                            if imageData != nil || remoteImage != nil {
                                PickedOrRemoteImage(data: imageData, url: remoteImage)
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus").font(.title)
                                    Text("Upload offer image").font(.subheadline)
                                }
                                .foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Theme.tint)
                            }
                        }
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    FormField(label: "Terms & Conditions", text: $terms, multiline: true)
                }
                .cardStyle()

                Button("Preview Offer") { preview() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .adminHeader(isEdit ? "Edit Offer" : seed.productMode ? "Product Offer Details" : "Store Offer Details")
        .onAppear { populate() }
    }

    private func populate() {
        guard !populated else { return }
        populated = true
        if let o = seed.existing {
            name = o.offerName
            desc = o.description ?? ""
            value = "\(o.discount)"
            terms = o.terms ?? ""
            switch o.discountType?.uppercased() {
            case "FLAT": type = 1
            case "SPECIAL_PRICE": type = 2
            default: type = 0
            }
            if let s = o.startDate.flatMap({ DateParse.parse($0) }) { start = s }
            if let e = o.endDate.flatMap({ DateParse.parse($0) }) { end = max(e, start) }
        } else if seed.productMode, !seed.productName.isEmpty {
            name = seed.productName + " Offer"
        }
    }

    /// validateAndPreview: converts the chosen discount type into a percent + offer price.
    private func preview() {
        guard !name.trimmed.isEmpty else { toast.show("Please enter offer title"); return }
        guard let v = Double(value.trimmed) else { toast.show("Please enter discount value"); return }
        guard end >= Calendar.current.startOfDay(for: start) else { toast.show("End date cannot be before start date"); return }

        let original = seed.existing?.originalPrice ?? seed.originalPrice
        var percent = Int(v)
        var offerPrice = original
        let discountType: String
        switch type {
        case 1:
            discountType = "FLAT"
            if original > 0 { offerPrice = max(0, original - v); percent = Int(v / original * 100) }
        case 2:
            discountType = "SPECIAL_PRICE"
            offerPrice = v
            if original > v, original > 0 { percent = Int((original - v) / original * 100) }
        default:
            discountType = "PERCENTAGE"
            if original > 0 { offerPrice = original - original * v / 100 }
        }

        let draft = OfferDraft(
            offerId: seed.existing?.offerId ?? 0,
            offerName: name.trimmed, description: desc.trimmed, discount: percent, discountType: discountType,
            startDate: Format.date(start, "dd MMM yyyy"), endDate: Format.date(end, "dd MMM yyyy"), terms: terms.trimmed,
            productId: seed.existing?.productId ?? seed.productId,
            productName: seed.existing?.productName ?? seed.productName,
            originalPrice: original, offerPrice: offerPrice,
            remoteImage: remoteImage, imageData: imageData)
        router.path.append(.offerPreview(draft))
    }
}

// MARK: - Preview + publish (OfferPreviewActivity)

struct OfferPreviewView: View {
    let draft: OfferDraft
    @Environment(ToastCenter.self) private var toast
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    private var session = Session.shared

    init(draft: OfferDraft) { self.draft = draft }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    PickedOrRemoteImage(data: draft.imageData, url: draft.remoteImage)
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                    Text("\(draft.discount)% OFF")
                        .font(.headline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.danger, in: Capsule())
                        .padding(12)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft.offerName).font(.title3.bold())
                    if !draft.description.isEmpty { Text(draft.description).foregroundStyle(.secondary) }
                    if !draft.productName.isEmpty {
                        HStack(spacing: 8) {
                            Text(draft.productName).font(.subheadline.weight(.semibold))
                            Spacer()
                            if draft.originalPrice > 0 {
                                Text(Format.price(draft.originalPrice)).strikethrough().foregroundStyle(.secondary)
                            }
                            Text(Format.price(draft.offerPrice)).font(.headline).foregroundStyle(Theme.success)
                        }
                        .padding(10)
                        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Label("Valid: \(draft.startDate) – \(draft.endDate)", systemImage: "calendar")
                    Label("Store: \(session.selectedStoreName.isEmpty ? "AtStores Merchant" : session.selectedStoreName)", systemImage: "storefront")
                    if !draft.terms.isEmpty {
                        Text("* Terms: \(draft.terms)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(16)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .padding(16)

            HStack(spacing: 12) {
                Button("Edit Offer") { dismiss() }.buttonStyle(OutlineButtonStyle())
                BusyButton(title: draft.offerId > 0 ? "Update Offer" : "Publish Offer", busy: busy) { Task { await publish() } }
            }
            .padding(.horizontal, 16)
        }
        .adminHeader(draft.offerId > 0 ? "Edit Offer" : "Offer Preview")
    }

    private func publish() async {
        busy = true
        defer { busy = false }
        let uid = session.effectiveUserId
        var body: [String: Any] = [
            "offerName": draft.offerName, "description": draft.description, "offerDescription": draft.description,
            "storeId": session.selectedStoreId, "discount": draft.discount, "discountType": draft.discountType,
            "startDate": draft.startDate, "endDate": draft.endDate, "terms": draft.terms, "termcondition": draft.terms,
            "createBy": uid, "userId": uid
        ]
        if draft.productId > 0 {
            body["productId"] = draft.productId
            body["productName"] = draft.productName
            body["originalPrice"] = draft.originalPrice
            body["offerPrice"] = draft.offerPrice
        }

        var response: APIResponse?
        if draft.offerId > 0 {
            // Try the update endpoints in the same order as Android, moving on for 404/405.
            for path in ["api/store/offer/update/", "api/offer/update/", "api/public/offer/update/"] {
                response = try? await API.shared.send(.put, path + "\(draft.offerId)", body: body)
                if let s = response?.status, s == 404 || s == 405 { continue }
                break
            }
        } else {
            response = try? await API.shared.send(.post, "api/public/offer", body: body)
        }
        guard let r = response else { toast.show("Network error during save"); return }
        guard r.ok else { toast.show("Failed to save offer: \(r.status)"); return }

        let offerId = draft.offerId > 0 ? draft.offerId : Self.offerId(from: r)
        if offerId > 0, let data = draft.imageData {
            _ = try? await API.shared.upload("api/store/offer/\(offerId)/thumbnailImage", field: "thumbnailImage", data: data)
        }
        toast.show(draft.offerId > 0 ? "Offer Updated Successfully!" : "Offer Published Successfully!")
        router.popTo { if case .offers = $0 { return true } else { return false } }
        if !router.path.contains(where: { if case .offers = $0 { return true } else { return false } }) {
            router.path.append(.offers(session.selectedStoreId))
        }
    }

    /// parseOfferIdFromResponse: `_id` / `offerId` / `id`, possibly under `data`.
    static func offerId(from r: APIResponse) -> Int {
        if let d = r.json as? JSONDict {
            let id = d.int("_id", "offerId", "id")
            if id > 0 { return id }
            if let inner = d.dict("data") {
                let id2 = inner.int("_id", "dataId", "offerId", "id")
                if id2 > 0 { return id2 }
            }
        }
        if let n = r.json as? NSNumber { return n.intValue }
        return 0
    }
}
