import SwiftUI

/// VisitorActivity: visitor counts, customer interest, most viewed / wishlisted products, offer performance.
struct VisitorView: View {
    private var session = Session.shared
    @State private var summary = VisitorSummary()
    @State private var products: [Int: Product] = [:]
    @State private var offers: [Int: Offer] = [:]
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StorePicker().padding(.horizontal, -16)
                Text("Visitor & Interest: \(session.selectedStoreName.isEmpty ? "Store" : session.selectedStoreName)")
                    .font(.title3.bold())

                if session.selectedStoreId == 0 {
                    EmptyStateView(icon: "storefront", text: "Select a store from the dashboard first")
                } else if !loaded {
                    LoadingView()
                } else {
                    content
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader()
        .task(id: session.selectedStoreId) { loaded = false; await load() }
    }

    @ViewBuilder
    private var content: some View {
        SectionTitle(text: "Visitors Summary")
        HStack(spacing: 10) {
            stat("Today", summary.today, Theme.primary)
            stat("This Week", summary.last7Days, Color(hex: 0x6A1B9A))
            stat("This Month", summary.last30Days, Color(hex: 0x00897B))
        }

        SectionTitle(text: "Customer Interest")
        VStack(spacing: 0) {
            interestRow("👁️ Store Views", summary.storeViews)
            Divider()
            interestRow("📦 Product Views", summary.productViews)
            Divider()
            interestRow("❤️ Wishlist Adds", summary.wishlistAdded)
            Divider()
            interestRow("🏷️ Offer Views", summary.offerViews)
            if session.isServiceStore {
                Divider()
                interestRow("📅 Bookings", summary.bookings)
            }
        }
        .cardStyle(padding: 4)

        SectionTitle(text: "Most Viewed Products")
        productList(summary.mostViewed, empty: "No product view activity available") { "\($0.viewCount) views" }

        SectionTitle(text: "Most Wishlisted Products")
        productList(summary.mostWishlisted, empty: "No wishlist activity yet.") { "❤️ \($0.wishlistCount) customers" }

        SectionTitle(text: "Offer Performance")
        VStack(spacing: 0) {
            if summary.offerPerformance.isEmpty {
                Text("No offer performance activity available").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            ForEach(summary.offerPerformance.prefix(10)) { o in
                HStack {
                    Text(o.offerName ?? offers[o.offerId]?.offerName ?? "Offer #\(o.offerId)").font(.subheadline)
                    Spacer()
                    Text("\(o.viewCount) views").font(.subheadline.bold()).foregroundStyle(Color(hex: 0xF57F17))
                }
                .padding(12)
            }
        }
        .cardStyle(padding: 2)
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(Format.compact(value)).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 12)
    }

    private func interestRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text("\(value)").font(.subheadline.bold())
        }
        .padding(12)
    }

    private func productList(_ list: [ProductInterest], empty: String, metric: @escaping (ProductInterest) -> String) -> some View {
        VStack(spacing: 8) {
            if list.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(list.prefix(10)) { item in
                let p = products[item.productId]
                let name = item.productName ?? p?.productName ?? "Product #\(item.productId)"
                NavigationLink(value: Route.productCustomers(storeId: session.selectedStoreId, productId: item.productId, title: name)) {
                    HStack(spacing: 12) {
                        RemoteImage(url: item.productImage ?? p?.thumbnailImage)
                            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(metric(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .cardStyle(padding: 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        let id = session.selectedStoreId
        guard id > 0 else { loaded = true; return }
        async let prods = API.shared.objects("api/store/product/\(id)")
        async let offs = API.shared.objects("api/public/offer/store/\(id)")
        var d = await API.shared.object("api/admin/\(id)/visitor-summary")
        if d == nil { d = await API.shared.object("api/store/\(id)/visitor-summary") }
        products = Dictionary(await prods.map(Product.init).map { ($0.productId, $0) }, uniquingKeysWith: { a, _ in a })
        offers = Dictionary(await offs.map(Offer.init).map { ($0.offerId, $0) }, uniquingKeysWith: { a, _ in a })
        summary = d.map(VisitorSummary.init) ?? VisitorSummary()
        loaded = true
    }
}
