import SwiftUI
import PhotosUI

// MARK: - Navigation

enum Route: Hashable {
    case store(Int)
    case storeForm(Int)                       // 0 = register a new store
    case productForm(storeId: Int, product: Product?)
    case productPhotos(Product)
    case categories(Int)
    case productCustomers(storeId: Int, productId: Int, title: String)
    case offers(Int)
    case createOffer
    case selectOfferProducts
    case offerForm(OfferSeed)
    case offerPreview(OfferDraft)
    case customers(Int)
    case customerForm(Customer?)
    case bookings(openBookingId: Int, storeId: Int)
    case shareStore(storeId: Int, storeName: String)
    case orders, notifications, editProfile, helpFaq, contactSupport, storeWebsite, requestWebsite
    case content(title: String, type: String)
}

/// Per-tab navigation path, so a screen can pop back to an earlier one (Android FLAG_ACTIVITY_CLEAR_TOP).
@Observable
final class Router {
    var path: [Route] = []

    /// Pops to the last route matching `match`; pops everything when none matches.
    func popTo(_ match: (Route) -> Bool) {
        if let i = path.lastIndex(where: match) { path.removeSubrange((i + 1)...) } else { path.removeAll() }
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .store(let id): StoreManageView(storeId: id)
        case .storeForm(let id): StoreFormView(storeId: id)
        case .productForm(let sid, let p): ProductFormView(storeId: sid, existing: p)
        case .productPhotos(let p): ProductPhotosView(product: p)
        case .categories(let id): ManageCategoriesView(storeId: id)
        case .productCustomers(let sid, let pid, let title): ProductCustomersView(storeId: sid, productId: pid, title: title)
        case .offers(let id): OffersView(storeId: id)
        case .createOffer: CreateOfferTypeView()
        case .selectOfferProducts: SelectOfferProductsView()
        case .offerForm(let seed): OfferFormView(seed: seed)
        case .offerPreview(let draft): OfferPreviewView(draft: draft)
        case .customers(let id): CustomerListView(storeId: id)
        case .customerForm(let c): CustomerFormView(existing: c)
        case .bookings(let open, let sid): BookingsView(openBookingId: open, storeId: sid, pushed: true)
        case .shareStore(let sid, let name): ShareStoreView(storeId: sid, storeName: name)
        case .orders: OrdersView()
        case .notifications: NotificationsView()
        case .editProfile: EditProfileView()
        case .helpFaq: HelpFaqView()
        case .contactSupport: ContactSupportView()
        case .storeWebsite: StoreWebsiteView()
        case .requestWebsite: RequestWebsiteView()
        case .content(let title, let type): ContentPageView(title: title, type: type)
        }
    }
}

extension View {
    func appDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }

    /// Blue AtStores header (BaseActivity.setupHeader): logo + bell, or "‹ Title" on pushed screens.
    func adminHeader(_ title: String? = nil) -> some View {
        modifier(AdminHeader(title: title, trailing: EmptyView()))
    }

    func adminHeader<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        modifier(AdminHeader(title: title, trailing: trailing()))
    }

    func cardStyle(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
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

struct AdminHeader<Trailing: View>: ViewModifier {
    var title: String?
    var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    if let title {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        Text(title).font(.headline).lineLimit(1)
                        Spacer(minLength: 4)
                        trailing
                    } else {
                        HeaderBrand()
                        Spacer()
                        NavigationLink(value: Route.notifications) {
                            Image(systemName: "bell.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Notifications")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, title == nil ? 14 : 8)
                .frame(height: 52)
                .background(Theme.primary.ignoresSafeArea(edges: .top))
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

    static func evict(_ url: URL) { cache.removeObject(forKey: url as NSURL) }

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

    /// Branded placeholder: faint AtStores bag on a soft blue background.
    private var fallback: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEEF3FF), Color(hex: 0xDCE6FF)], startPoint: .top, endPoint: .bottom)
                Image("PlaceholderMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: max(16, side * 0.38))
                    .opacity(0.25)
            }
        }
    }
}

/// Shows a picked local image, else the remote one.
struct PickedOrRemoteImage: View {
    let data: Data?
    let url: String?
    var body: some View {
        if let data, let img = UIImage(data: data) {
            Color.clear.overlay(Image(uiImage: img).resizable().scaledToFill()).clipped()
        } else {
            RemoteImage(url: url)
        }
    }
}

/// PhotosPicker that hands back JPEG data ready for upload.
struct ImagePickButton<Label: View>: View {
    var onPick: (Data) -> Void
    @ViewBuilder var label: () -> Label
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) { label() }
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let raw = try? await newItem.loadTransferable(type: Data.self), let jpeg = ImageData.jpeg(raw) {
                        onPick(jpeg)
                    }
                    item = nil
                }
            }
    }
}

// MARK: - Small building blocks

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 1.2))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Primary action button that shows a spinner while `busy`.
struct BusyButton: View {
    let title: String
    var busy: Bool
    var color: Color = Theme.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
        }
        .buttonStyle(PrimaryButtonStyle(color: color))
        .disabled(busy)
    }
}

struct StatusPill: View {
    let text: String
    let fg: Color
    var bg: Color? = nil
    var body: some View {
        Text(text).font(.caption.bold()).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg ?? fg.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Theme.primary)
                .frame(width: 74, height: 74)
                .background(Theme.primary.opacity(0.1), in: Circle())
            Text(text).font(.headline).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
    }
}

/// Labelled text input used by all the forms.
struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var disabled = false
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboard)
            .disabled(disabled)
            .foregroundStyle(disabled ? .secondary : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(disabled ? Theme.lightGray : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1)))
        }
    }
}

/// Labelled tappable value (for pickers / date fields).
struct FormValue<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack { content() }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.1)))
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Horizontal chips (category filter, booking status tabs, store switcher).
struct ChipRow: View {
    let items: [String]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { selected = item } label: {
                        Text(item)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundStyle(selected == item ? .white : Color(hex: 0x444444))
                            .background(selected == item ? Theme.primary : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(Color.black.opacity(selected == item ? 0 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Store switcher shown on the Bookings and Visitors tabs when the admin owns several stores
/// (Android StoreChipAdapter).
struct StorePicker: View {
    private var app = AppState.shared
    private var session = Session.shared
    var filter: (Store) -> Bool = { _ in true }

    init(filter: @escaping (Store) -> Bool = { _ in true }) { self.filter = filter }

    var body: some View {
        let stores = app.stores.filter(filter)
        if stores.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stores) { s in
                        let on = s.storeId == session.selectedStoreId
                        Button { session.select(s) } label: {
                            HStack(spacing: 8) {
                                RemoteImage(url: s.storeImage).frame(width: 30, height: 30).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.storeName).font(.caption.bold()).lineLimit(1)
                                        .foregroundStyle(on ? Color(hex: 0x1A73E8) : Color(hex: 0x212121))
                                    Text(s.city ?? s.locationText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .frame(maxWidth: 190, alignment: .leading)
                            .background(on ? Theme.tint : Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.primary.opacity(0.4) : Color.black.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, minHeight: 200)
    }
}

/// Bag + "AtStores" for the blue header bar (crisp at every screen size).
struct HeaderBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("BagMark").resizable().scaledToFit().frame(height: 30)
            (Text("At").foregroundStyle(Theme.secondary) + Text("Stores").foregroundStyle(.white))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AtStores")
    }
}
