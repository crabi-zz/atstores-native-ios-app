import Foundation

nonisolated struct Store: Identifiable, Hashable {
    var storeId: Int = 0
    var storeName: String = ""
    var storeAddress: String?
    var storeContactNo: String?
    var storeWebsite: String?
    var storeCategoryId: Int = 0
    var storeCategoryName: String?
    var city: String?
    var startTime: String?
    var endTime: String?
    var storeImage: String?
    var storeBanner: String?
    var distance: Double = 0
    var avgRating: Double = 0
    var ratingCount: Int = 0

    var id: Int { storeId }

    init() {}

    init(_ d: JSONDict) {
        storeId = d.int("storeId", "id")
        storeName = d.str("storeName", "name") ?? "Store"
        storeAddress = d.str("storeAddress", "address")
        storeContactNo = d.str("storeContactNo", "mobile", "contactNo")
        storeWebsite = d.str("storeWebsite", "website")
        storeCategoryId = d.int("storeCategoryId")
        storeCategoryName = d.str("storeCategoryName", "categoryName", "category", "storeCategory")
        city = d.str("city")
        startTime = d.str("startTime")
        endTime = d.str("endTime")
        storeImage = d.str("storeImage", "image", "thumbnailImage")
        storeBanner = d.str("storeBanner")
        distance = d.double("distance")
        avgRating = d.double("avgRating")
        ratingCount = d.int("ratingCount")
    }

    var isSalon: Bool { (storeCategoryName ?? "").lowercased().contains("salon") }
}

nonisolated struct Product: Identifiable, Hashable {
    var productId: Int = 0
    var productName: String = "Product"
    var categoryName: String?
    var description: String?
    var storeId: Int = 0
    var sellPrice: Double = 0
    var cutPrice: Double = 0
    var percentOff: String?
    var thumbnailImage: String?
    var durationMinutes: Int = 30
    var detailImages: [String] = []

    var id: String { "\(productId)-\(storeId)-\(productName)" }

    init() {}

    init(_ d: JSONDict) {
        productId = d.int("productId", "id", "product_id", "pid")
        productName = d.str("productName", "name") ?? "Product"
        categoryName = d.str("categoryName")
        description = d.str("description")
        storeId = d.int("storeId", "sid", "store_id")
        sellPrice = d.double("sellPrice")
        cutPrice = d.double("cutPrice")
        percentOff = d.str("percentOff")
        thumbnailImage = d.str("thumbnailImage", "imageUrl", "image_url", "imageURL", "image", "ImageUrl",
                               "thumbnail_image", "thumbnail", "productImage", "product_image", "productThumbnail")
        let dur = d.int("durationMinutes", "duration_mins", "durationMins", "duration", "durationInMinutes")
        durationMinutes = dur > 0 ? dur : 30
        detailImages = d.strings("detailImages")
    }

    var discountText: String { Format.discountText(percentOff, sell: sellPrice, cut: cutPrice) }
}

nonisolated struct Category: Identifiable, Hashable {
    var categoryId: Int
    var name: String
    var categoryImage: String?
    var id: Int { categoryId }

    init(categoryId: Int, name: String, categoryImage: String? = nil) {
        self.categoryId = categoryId; self.name = name; self.categoryImage = categoryImage
    }

    init(_ d: JSONDict) {
        categoryId = d.int("categoryId", "storeCategoryId", "id")
        name = d.str("name", "categoryName") ?? ""
        categoryImage = d.str("categoryImage", "image")
    }

    static let all = Category(categoryId: 0, name: "All")
}

nonisolated struct Offer: Identifiable, Hashable {
    var offerId: Int = 0
    var offerName: String = "Offer"
    var storeId: String?
    var discount: Int = 0
    var thumbnailImage: String?
    var activeStatus: Bool?
    var endDate: String?

    var id: Int { offerId }

    init(_ d: JSONDict) {
        offerId = d.int("offerId", "id")
        offerName = d.str("offerName", "name") ?? "Special Offer"
        storeId = d.str("storeId")
        discount = d.int("discount")
        thumbnailImage = d.str("thumbnailImage", "image")
        activeStatus = d.bool("activeStatus", "active", "isActive", "status")
        endDate = d.str("endDate", "validTill", "expiryDate", "expireDate", "validUntil",
                        "expirationDate", "validityDate", "valid_till", "end_date", "validTo")
    }

    var storeIdInt: Int { Int(storeId ?? "") ?? 0 }

    var isExpired: Bool {
        if activeStatus == false { return true }
        if let end = endDate, let date = DateParse.parse(end) { return date < Date() }
        return false
    }

    /// Offers open the product detail screen in the Android app with placeholder prices.
    var asProduct: Product {
        var p = Product()
        p.productName = offerName
        p.sellPrice = 999
        p.cutPrice = 1499
        p.percentOff = String(discount)
        p.thumbnailImage = thumbnailImage
        p.description = "Exclusive offer from AtStores."
        p.storeId = storeIdInt
        return p
    }
}

nonisolated struct Banner: Identifiable, Hashable {
    var bannerId: Int
    var bannerImage: String?
    var id: Int { bannerId }
    init(_ d: JSONDict) {
        bannerId = d.int("bannerId", "id")
        bannerImage = d.str("bannerImage", "thumbnailImage")
    }
}

nonisolated struct HomeData {
    var banners: [Banner] = []
    var categories: [Category] = []
    var offers: [Offer] = []
    var nearby: [Store] = []
    var trending: [Product] = []
    var salon: [Store] = []
    var boutique: [Store] = []

    var hasContent: Bool {
        !(banners.isEmpty && categories.isEmpty && offers.isEmpty && nearby.isEmpty
          && trending.isEmpty && salon.isEmpty && boutique.isEmpty)
    }

    /// Mirrors HomeActivity.loadHomeData section bucketing.
    init(_ d: JSONDict) {
        banners = d.dicts("banners").map(Banner.init)
        categories = d.dicts("categories").map(Category.init)
        for section in d.dicts("sections") {
            let code = section.str("sectionCode") ?? ""
            let cat = section.str("category") ?? ""
            let title = (section.str("title") ?? "").lowercased()
            let stores = section.dicts("stores").map(Store.init)
            if !stores.isEmpty {
                if code == "NEARBY_STORES" || title.contains("nearby") { nearby += stores }
                else if cat == "Salon & Spa" || title.contains("salon") { salon += stores }
                else if cat == "Boutique" || title.contains("boutique") { boutique += stores }
                else if nearby.isEmpty { nearby += stores }
            }
            let products = section.dicts("products").map(Product.init)
            if !products.isEmpty, cat == "Mobile" || title.contains("trending") || title.contains("product") {
                trending += products
            }
            let offs = section.dicts("offers").map(Offer.init)
            if !offs.isEmpty, code == "TODAY_OFFERS" || title.contains("offer") {
                offers += offs.filter { !$0.isExpired }
            }
        }
        if nearby.isEmpty { nearby = d.dicts("popularStores").map(Store.init) }
        if salon.isEmpty, let cw = d.dict("categoryWiseStores") {
            let list = (cw["Salon & Spa"] as? [Any]) ?? (cw["Beauty"] as? [Any]) ?? []
            salon = list.compactMap { $0 as? JSONDict }.map(Store.init)
        }
    }

    init() {}
}

nonisolated struct ServiceItem: Identifiable, Hashable {
    var id: Int
    var name: String
    var durationMins: Int
    var price: Double
    var imageUrl: String

    init(product p: Product) {
        id = p.productId
        name = p.productName
        durationMins = p.durationMinutes > 0 ? p.durationMinutes : 30
        price = p.sellPrice
        imageUrl = (p.thumbnailImage?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
            ?? p.detailImages.first ?? ""
    }
}

nonisolated struct TimeSlot: Identifiable, Hashable {
    var time: String
    var isAvailable: Bool
    var id: String { time }
    init(time: String, isAvailable: Bool = true) { self.time = time; self.isAvailable = isAvailable }
    init(_ d: JSONDict) {
        time = d.str("time", "slot", "timeSlot") ?? ""
        isAvailable = d.bool("isAvailable", "available") ?? true
    }
}

nonisolated struct AppNotification: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var message: String
    var createdDate: String
    var type: String
    var imageUrl: String?
    var serviceName: String?
    var bookingDate: String?

    init(_ d: JSONDict) {
        title = d.str("title", "subject", "heading") ?? "Notification"
        message = d.str("message", "description", "body", "content", "msg") ?? ""
        createdDate = d.str("createdDate", "created_at", "createdAt", "date", "timestamp") ?? ""
        type = d.str("type", "notificationType", "category") ?? ""
        imageUrl = d.str("imageUrl", "image_url", "image", "thumbnailImage", "productImage", "storeImage")
        serviceName = d.str("serviceName", "service_name", "storeName", "productName")
        bookingDate = d.str("bookingDate", "booking_date", "slotDate")
    }
}

/// CouponRecipient: a coupon assigned to the user, either flat or with a nested `coupon`.
nonisolated struct CouponItem: Identifiable, Hashable {
    var recipientId: String
    var couponId: String
    var rawStatus: String
    var claimedFlag: Bool?
    var storeName: String
    var title: String
    var code: String
    var discount: Double
    var discountType: String
    var maxDiscountAmount: Double
    var minPurchaseAmount: Double
    var expiryDate: String
    var terms: String
    var imageUrl: String

    var id: String { recipientId + "|" + couponId }

    init(_ d: JSONDict) {
        recipientId = d.str("id", "recipientId", "couponRecipientId", "_id") ?? UUID().uuidString
        couponId = d.str("couponId", "coupon_id", "cid") ?? ""
        rawStatus = d.str("redemptionStatus", "status", "redemption_status", "claimStatus") ?? ""
        claimedFlag = d.bool("claimed", "isClaimed", "claimedStatus")
        let flatStore = d.str("storeName", "store_name", "merchantName")
        storeName = flatStore ?? "All Stores"
        title = d.str("title") ?? "Special Coupon Offer"
        code = d.str("code") ?? ""
        discount = d.double("discount")
        discountType = d.str("discountType") ?? "PERCENTAGE"
        maxDiscountAmount = d.double("maxDiscountAmount")
        minPurchaseAmount = d.double("minPurchaseAmount")
        expiryDate = d.str("expiryDate", "expiry_date", "validTill", "endDate") ?? "No Expiry"
        terms = d.str("terms", "description", "termsAndConditions") ?? "Standard terms & conditions apply."
        imageUrl = d.str("imageUrl", "image_url", "image", "thumbnailImage") ?? ""
        if let c = d.dict("coupon", "couponDetails", "couponData") { merge(coupon: c) }
    }

    mutating func merge(coupon c: JSONDict) {
        if let v = c.str("title") { title = v }
        if let v = c.str("code") { code = v }
        if c.double("discount") > 0 { discount = c.double("discount") }
        if let v = c.str("discountType") { discountType = v }
        if c.double("maxDiscountAmount") > 0 { maxDiscountAmount = c.double("maxDiscountAmount") }
        if c.double("minPurchaseAmount") > 0 { minPurchaseAmount = c.double("minPurchaseAmount") }
        if let v = c.str("expiryDate") { expiryDate = v }
        if let v = c.str("description") { terms = v }
        if let v = c.str("imageUrl") { imageUrl = v }
    }

    var status: String {
        let s = rawStatus.trimmingCharacters(in: .whitespaces).uppercased()
        if s.isEmpty || s == "PENDING" || s == "ACTIVE" { return "AVAILABLE" }
        return s
    }
    var isUsed: Bool { status == "USED" || status == "REDEEMED" }
    var isClaimed: Bool { claimedFlag ?? (status == "CLAIMED" || isUsed) }
    var isExpired: Bool {
        if status == "EXPIRED" { return true }
        if expiryDate.contains("No Expiry") { return false }
        if let date = DateParse.parse(expiryDate, extraFormats: ["dd-MM-yyyy"]) { return Date() > date }
        return false
    }
    var claimId: String { couponId.isEmpty ? recipientId : couponId }
    var discountLabel: String {
        discountType.uppercased() == "PERCENTAGE" ? "\(Int(discount))% OFF" : "₹\(Int(discount)) OFF"
    }
    var expiryShort: String { expiryDate.components(separatedBy: "T").first ?? expiryDate }
}

/// Bookings and orders come back as loosely shaped maps; keep them as dictionaries
/// and expose the same fallbacks MyBookingAdapter / OrderAdapter used.
nonisolated struct BookingRecord: Identifiable, Hashable {
    let raw: JSONDict
    let id = UUID()

    static func == (a: BookingRecord, b: BookingRecord) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var bookingId: String {
        (raw.str("_id", "bookingId", "id") ?? "").replacingOccurrences(of: ".0", with: "")
    }
    var sortKey: Double { Double(bookingId) ?? 0 }
    var storeName: String { raw.str("storeName", "store_name") ?? "AtStores Merchant" }
    var category: String { raw.str("category", "storeCategory") ?? "Salon & Spa" }
    var status: String { (raw.str("bookingStatus", "status") ?? "CONFIRMED").uppercased() }
    var time: String { raw.str("timeSlot", "slotTime") ?? "--" }
    var totalPrice: Double { raw.double("totalPrice", "price", "totalAmount") }
    var customerName: String { raw.str("customerName", "userName") ?? "Guest" }
    var customerMobile: String { raw.str("mobileNumber", "userMobile") ?? "--" }
    var paymentMethod: String { raw.str("paymentMethod") ?? "CASH" }
    var paymentStatus: String { raw.str("paymentStatus") ?? "UNPAID" }

    var date: String {
        for key in ["bookDate", "bookingDate", "createDate", "createdDate", "date", "slotDate"] {
            var s: String?
            if let m = raw[key] as? JSONDict { s = m.str("$date", "date") } else { s = raw.str(key) }
            if let s, !s.isEmpty { return s.components(separatedBy: "T").first ?? s }
        }
        return "--"
    }

    var serviceNames: [String] { JSON.stringList(raw["serviceNames"] ?? raw["services"] ?? raw["serviceName"]) }
    var servicesSummary: String { serviceNames.isEmpty ? "Salon Appointment" : serviceNames.joined(separator: ", ") }
    var detailImages: [String] { JSON.stringList(raw["detailImages"] ?? raw["detail_images"]) }

    var imageUrl: String {
        if let s = raw.str("image") { return s }
        if let s = detailImages.first { return s }
        return raw.str("storeImage", "store_image", "thumbnailImage", "imageUrl") ?? ""
    }

    struct ServiceRow: Identifiable { let id = UUID(); let name: String; let price: Double; let imageUrl: String }

    var serviceRows: [ServiceRow] {
        let images = detailImages
        let names = serviceNames
        if !names.isEmpty {
            let avg = totalPrice / Double(names.count)
            return names.enumerated().map { i, n in
                ServiceRow(name: n, price: avg, imageUrl: i < images.count ? images[i] : imageUrl)
            }
        }
        return [ServiceRow(name: "Salon Service", price: totalPrice, imageUrl: imageUrl)]
    }
}

nonisolated struct OrderRecord: Identifiable {
    let raw: JSONDict
    let id = UUID()
    var orderId: String { raw.str("orderId", "id") ?? "--" }
    var status: String { (raw.str("orderStatus", "status") ?? "CONFIRMED").uppercased() }
    var date: String { (raw.str("orderDate", "createdDate") ?? "--").components(separatedBy: "T").first ?? "--" }
    var total: Double { raw.double("orderTotal", "totalAmount", "price") }
    var itemsLabel: String { (raw["orderItem"] ?? raw["items"]) != nil ? "Product Items Purchased" : "Product Order" }
    var isBooking: Bool { ["timeSlot", "slotTime", "bookingId", "bookingDate"].contains { raw[$0] != nil } }
}

nonisolated struct UserProfile {
    var id: Int
    var username: String?
    var name: String?
    var contactNo: String?
    var email: String?
    var role: String?
    var address: String?
    var area: String?
    var city: String?
    var zipcode: String?
    var thumbnailImage: String?
    var provider: String?
    var isActive: Bool

    init(_ d: JSONDict) {
        id = d.int("id")
        username = d.str("username")
        name = d.str("name", "fullName")
        contactNo = d.str("contactNo", "mobile", "mobileNumber", "phone")
        email = d.str("email")
        role = d.str("role")
        address = d.str("address")
        area = d.str("area")
        city = d.str("city")
        zipcode = d.str("zipcode")
        thumbnailImage = d.str("thumbnailImage")
        provider = d.str("provider")
        isActive = d.bool("isActive", "active") ?? true
    }
}
