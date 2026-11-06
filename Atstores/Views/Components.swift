import SwiftUI

// MARK: - Navigation

enum Route: Hashable {
    case store(Store)
    case storeList(categoryId: Int, title: String)
    case product(Product)
    case booking(storeId: Int, storeName: String, category: String)
    case notifications, bookings, orders, wishlist, coupons, savedStores, editProfile, help, privacy, appVersion
    case coupon(CouponItem)
    case content(title: String, type: String)
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .store(let s): StoreDetailView(initial: s)
        case .storeList(let id, let title): StoreListView(categoryId: id, title: title)
        case .product(let p): ProductDetailView(product: p)
        case .booking(let id, let name, let cat): BookingView(storeId: id, storeName: name, storeCategory: cat)
        case .notifications: NotificationsView()
        case .bookings: MyBookingsView()
        case .orders: OrdersView()
        case .wishlist: WishlistView()
        case .coupons: CouponsView()
        case .coupon(let c): CouponDetailView(coupon: c)
        case .savedStores: SavedStoresView()
        case .editProfile: EditProfileView()
        case .content(let title, let type): ContentPageView(title: title, type: type)
        case .help: HelpSupportView()
        case .privacy: ManagePrivacyView()
        case .appVersion: AppVersionView()
        }
    }
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }

    /// Logo + location + bell (BaseActivity.setupHeader). With a title, adds a "‹ Title" row for pushed screens.
    func appHeader(title: String? = nil) -> some View {
        modifier(AppHeader(title: title, trailing: EmptyView()))
    }

    func appHeader<T: View>(title: String, @ViewBuilder trailing: () -> T) -> some View {
        modifier(AppHeader(title: title, trailing: trailing()))
    }
}

/// Keeps the swipe-back gesture working while the system navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

struct AppHeader<Trailing: View>: ViewModifier {
    var title: String?
    var trailing: Trailing
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    private var location = LocationService.shared

    init(title: String?, trailing: Trailing) {
        self.title = title
        self.trailing = trailing
    }

    func body(content: Content) -> some View {
        // Android layout_header: logo, then location, then the bell on the right.
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
              VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                        .frame(maxWidth: 130, alignment: .leading)
                    Button {
                        toast.show("Updating location...")
                        location.clearCache()
                        Task { await location.current() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
                            Text(location.headerText).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: 0x555555))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    NavigationLink(value: Route.notifications) {
                        Image(systemName: "bell")
                            .font(.title3)
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                if let title {
                    Divider()
                    HStack(spacing: 6) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        Text(title).font(.headline).lineLimit(1)
                        Spacer()
                        trailing
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
              }
                .background {
                    Color.white
                        .ignoresSafeArea(edges: .top)
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                }
            }
    }
}

// MARK: - Images

/// Memory + URLCache-backed image loading (replaces Glide). Downsamples large images.
enum ImageLoader {
    private static let cache = NSCache<NSURL, UIImage>()
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 30_000_000, diskCapacity: 200_000_000)
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()

    static func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    static func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        for _ in 0..<2 {
            guard let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { continue }
            let img = await Task.detached { downsample(data, maxPixel: 1200) }.value
            if let img { cache.setObject(img, forKey: url as NSURL); return img }
        }
        return nil
    }

    nonisolated private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage: View {
    let url: String?
    var placeholder: String = "photo"
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    private var resolved: URL? {
        let clean = url?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !clean.isEmpty, clean.lowercased() != "null" else { return nil }
        return URL(string: clean) ?? clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init)
    }

    var body: some View {
        Group {
            if let img = image ?? resolved.flatMap({ ImageLoader.cached($0) }) {
                Color.clear.overlay(Image(uiImage: img).resizable().aspectRatio(contentMode: contentMode))
            } else if failed || resolved == nil {
                fallback
            } else {
                Rectangle().fill(Theme.lightGray)
            }
        }
        .clipped()
        .task(id: url) {
            guard let u = resolved else { return }
            image = ImageLoader.cached(u)
            if image == nil {
                image = await ImageLoader.load(u)
                failed = image == nil
            }
        }
    }

    private var fallback: some View {
        ZStack {
            Rectangle().fill(Theme.lightGray)
            Image(systemName: placeholder).font(.title2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Store cards

private struct SaveStoreButton: View {
    let store: Store
    var removeMode = false
    var onRemoved: (() -> Void)?
    @Environment(ToastCenter.self) private var toast
    @State private var saved = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: removeMode ? "xmark" : (saved ? "heart.fill" : "heart"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .task(id: store.storeId) {
            guard !removeMode, !Session.shared.uid.isEmpty else { return }
            let uid = API.seg(Session.shared.uid)
            if let r = try? await API.shared.send(.get, "api/user/stores/save/check/\(uid)/\(store.storeId)", auth: true), r.ok {
                saved = r.isTrue
            }
        }
    }

    private func toggle() async {
        let s = Session.shared
        guard s.isLoggedIn, !s.uid.isEmpty else { toast.show("Please login first"); return }
        let uid = API.seg(s.uid)
        if saved || removeMode {
            if await API.shared.ok(.delete, "api/user/stores/save/\(uid)/\(store.storeId)", auth: true) {
                saved = false
                toast.show("Removed from saved stores")
                onRemoved?()
            }
        } else {
            let body: [String: Any] = [
                "userId": s.uid, "storeId": store.storeId, "storeName": store.storeName,
                "storeImage": store.storeImage ?? "", "storeAddress": store.storeAddress ?? "",
                "storeCategoryName": store.storeCategoryName ?? "", "createdDate": Format.isoNow()
            ]
            if await API.shared.ok(.post, "api/user/stores/save", body: body, auth: true) {
                saved = true
                toast.show("Store saved")
            }
        }
    }
}

private struct OpenBadge: View {
    var body: some View {
        // DateTimeUtils.isStoreOpen always returned true in the Android app.
        Text("OPEN").font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.open.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct RatingLabel: View {
    let store: Store
    var body: some View {
        if store.avgRating > 0 {
            Label(Format.rating(store.avgRating, store.ratingCount), systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// Horizontal carousel card used on Home (item_store_horizontal).
struct StoreCard: View {
    let store: Store
    var body: some View {
        NavigationLink(value: Route.store(store)) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: store.storeImage, placeholder: "storefront")
                    .frame(width: 200, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) { OpenBadge().padding(8) }
                    .overlay(alignment: .topTrailing) { SaveStoreButton(store: store).padding(6) }
                Text(store.storeName).font(.subheadline.bold()).lineLimit(1)
                Text(store.storeCategoryName ?? "Category").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text(store.city ?? store.storeAddress ?? "Address").lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Format.distance(store.distance))
                }
                .font(.caption).foregroundStyle(.secondary)
                RatingLabel(store: store)
            }
            .frame(width: 200, alignment: .leading)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Analytics.store(store) })
    }
}

/// Full-width list row (search_store_list).
struct StoreRow: View {
    let store: Store
    var body: some View {
        NavigationLink(value: Route.store(store)) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: store.storeImage, placeholder: "storefront")
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.storeName).font(.headline).lineLimit(1)
                    Text(store.storeCategoryName ?? "").font(.caption).foregroundStyle(.secondary)
                    Text(store.storeAddress ?? "Address not available").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 10) {
                        Text("OPEN").font(.caption.bold()).foregroundStyle(Theme.open)
                        Text(Format.distance(store.distance)).font(.caption).foregroundStyle(.secondary)
                        RatingLabel(store: store)
                    }
                }
                Spacer(minLength: 0)
                SaveStoreButton(store: store)
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Analytics.store(store) })
    }
}

/// Grid card (item_store_vertical), used on Saved Stores with a remove button.
struct StoreGridCard: View {
    let store: Store
    var onRemoved: () -> Void
    var body: some View {
        NavigationLink(value: Route.store(store)) {
            VStack(alignment: .leading, spacing: 4) {
                RemoteImage(url: store.storeImage, placeholder: "storefront")
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        SaveStoreButton(store: store, removeMode: true, onRemoved: onRemoved).padding(6)
                    }
                Text(store.storeName).font(.subheadline.bold()).lineLimit(1)
                Text(store.storeCategoryName ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(store.storeAddress ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Product card

struct ProductCard: View {
    let product: Product
    var storeName: String = ""
    var wishlistMode = false
    var onRemoved: (() -> Void)?
    @Environment(ToastCenter.self) private var toast
    @State private var liked = false

    var body: some View {
        NavigationLink(value: Route.product(product)) {
            VStack(alignment: .leading, spacing: 4) {
                RemoteImage(url: product.thumbnailImage, placeholder: "bag")
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        Text(product.discountText).font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 4)).padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { Task { await toggle() } } label: {
                            Image(systemName: wishlistMode ? "xmark" : (liked ? "heart.fill" : "heart"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(wishlistMode ? .black : Theme.heart)
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.9), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                Text(product.productName).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.price(product.sellPrice)).font(.subheadline.bold())
                    Text(Format.price(product.cutPrice)).font(.caption).strikethrough().foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Analytics.product(product, storeName: storeName) })
        .task(id: product.productId) {
            guard !wishlistMode, !Session.shared.uid.isEmpty, product.productId > 0 else { return }
            let uid = API.seg(Session.shared.uid)
            if let r = try? await API.shared.send(.get, "api/wishlist/check/\(uid)/\(product.productId)", auth: true), r.ok {
                liked = r.isTrue
            }
        }
    }

    private func toggle() async {
        let s = Session.shared
        guard !s.uid.isEmpty else { toast.show("Please login first"); return }
        let uid = API.seg(s.uid)
        if liked || wishlistMode {
            if await API.shared.ok(.delete, "api/wishlist/\(uid)/\(product.productId)", auth: true) {
                liked = false
                toast.show("Removed from wishlist")
                onRemoved?()
            }
        } else {
            let body: [String: Any] = [
                "userId": s.uid, "productId": product.productId, "productName": product.productName,
                "thumbnailImage": product.thumbnailImage ?? "", "sellPrice": product.sellPrice,
                "cutPrice": product.cutPrice, "storeId": product.storeId
            ]
            do {
                let r = try await API.shared.send(.post, "api/wishlist", body: body, auth: true)
                if r.ok { liked = true; toast.show("Added to wishlist") } else { toast.show("Failed to add to wishlist") }
            } catch {
                toast.show("Network Error")
            }
        }
    }
}

// MARK: - Small pieces

struct SectionHeader: View {
    let title: String
    var route: Route?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let route {
                NavigationLink(value: route) {
                    HStack(spacing: 2) {
                        Text("View All")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                }
                .tint(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, -8)
    }
}

struct ChipBar<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item?
    var onSelect: (Item) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let selected = selection == item
                    Button {
                        selection = item
                        onSelect(item)
                    } label: {
                        Text(title(item)).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(selected ? Theme.primary : Theme.lightGray, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Wraps children onto new lines, like chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyStateView: View {
    let icon: String
    let text: String
    var body: some View {
        ContentUnavailableView(text, systemImage: icon)
            .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.black)
    }
}

struct StatusPill: View {
    let text: String
    let fg: Color
    let bg: Color
    var body: some View {
        Text(text).font(.caption.bold()).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}
