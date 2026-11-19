import Foundation

nonisolated struct Store: Identifiable, Hashable {
    var storeId: Int = 0
    var storeName: String = ""
    var contactName: String?
    var storeAddress: String?
    var storeContactNo: String?
    var storeEmail: String?
    var storeWebsite: String?
    var storeCategoryId: Int = 0
    var storeCategoryName: String?
    var city: String?
    var state: String?
    var pincode: String?
    var startTime: String?
    var endTime: String?
    var storeImage: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var activeStatus: Bool?

    var id: Int { storeId }

    init() {}

    init(_ d: JSONDict) {
        storeId = d.int("storeId", "id")
        storeName = d.str("storeName", "name") ?? "Store"
        contactName = d.str("contactName")
        storeAddress = d.str("storeAddress", "address")
        storeContactNo = d.str("storeContactNo")
        storeEmail = d.str("storeEmail")
        // The backend sometimes stores the Swagger placeholder "string" as the website.
        storeWebsite = d.str("storeWebsite").flatMap { $0.lowercased() == "string" ? nil : $0 }
        storeCategoryId = d.int("storeCategoryId", "categoryId")
        storeCategoryName = d.str("storeCategoryName", "categoryName")
        city = d.str("city")
        state = d.str("state", "storeState")
        pincode = d.str("pincode", "postalCode", "zipCode", "pinCode")
        startTime = d.str("startTime")
        endTime = d.str("endTime")
        storeImage = d.str("storeImage")
        latitude = d.double("storeLatitude", "latitude")
        longitude = d.double("storeLongitude", "longitude")
        activeStatus = d.bool("activeStatus")
    }

    /// BaseActivity.isBookingEnabledCategory: which stores get the Bookings tab.
    static func isBookingCategory(_ name: String?) -> Bool {
        let c = (name ?? "").lowercased()
        return ["service", "spa", "salon", "dentist", "clinic", "doctor", "healthcare"].contains { c.contains($0) }
    }

    /// StoreListAdapter / VisitorActivity: "Services" wording and the bookings counter.
    static func isServiceCategory(_ name: String?) -> Bool {
        ["salon & spa", "salon services", "clinic", "services"].contains((name ?? "").lowercased())
    }

    var isService: Bool { Store.isServiceCategory(storeCategoryName) }
    var isOpen: Bool { activeStatus ?? true }

    var hoursText: String {
        if let s = startTime, !s.isEmpty, let e = endTime, !e.isEmpty { return "Open \(s) - \(e)" }
        return "Open 10:00 AM - 9:00 PM"
    }

    var locationText: String {
        if let a = storeAddress, !a.isEmpty { return a }
        return city ?? "Location"
    }
}

nonisolated struct Product: Identifiable, Hashable {
    var productId: Int = 0
    var productName: String = ""
    var categoryName: String?
    var storeId: Int = 0
    var sellPrice: Double = 0
    var cutPrice: Double = 0
    var percentOff: String?
    var thumbnailImage: String?
    /// The real main image (thumbnailImage) without the detailImages fallback.
    var mainImage: String?
    /// Extra product photos (up to 9 besides the main image).
    var detailImages: [String] = []
    var createdDate: String = ""
    var itemType: String?
    var quantity: Int?
    var durationMinutes: Int?
    var discountType: String?
    var discountValue: Double?
    var newArrival: Bool = false

    var id: Int { productId }

    init() {}

    init(_ d: JSONDict) {
        productId = d.int("productId", "id")
        productName = d.str("productName", "name") ?? ""
        categoryName = d.str("categoryName")
        storeId = d.int("storeId")
        sellPrice = d.double("sellPrice")
        cutPrice = d.double("cutPrice")
        percentOff = d.str("percentOff")
        mainImage = d.str("thumbnailImage", "image", "imageUrl", "productImage", "img")
        detailImages = d.strings("detailImages").filter { !$0.isEmpty && $0 != "null" }
        thumbnailImage = mainImage ?? detailImages.first
        createdDate = d.str("createdDate") ?? ""
        itemType = d.str("itemType")
        if d["quantity"] != nil, !(d["quantity"] is NSNull) { quantity = d.int("quantity") }
        if d["durationMinutes"] != nil, !(d["durationMinutes"] is NSNull) { durationMinutes = d.int("durationMinutes") }
        discountType = d.str("discountType")
        let dv = d.double("discountValue")
        discountValue = dv > 0 ? dv : nil
        newArrival = d.bool("newArrival") ?? false
    }

    var isService: Bool { itemType?.uppercased() == "SERVICE" }

    /// ProductAdapter: show the struck-through MRP and badge only for a real discount.
    var hasDiscount: Bool {
        guard cutPrice > sellPrice, let p = percentOff, !p.isEmpty else { return false }
        return !["0%", "0", "0% OFF", "null", "0.0% OFF", "0.0₹ OFF"].contains(p)
    }

    /// Price used for offers and selection lists.
    var listPrice: Double { cutPrice > 0 ? cutPrice : sellPrice }
}

nonisolated struct Category: Identifiable, Hashable {
    var categoryId: Int
    var name: String
    var id: Int { categoryId }

    init(_ d: JSONDict) {
        categoryId = d.int("categoryId", "id")
        name = d.str("categoryName", "name") ?? ""
    }
}

nonisolated struct StoreCategory: Identifiable, Hashable {
    var storeCategoryId: Int
    var name: String
    var id: Int { storeCategoryId }

    init(_ d: JSONDict) {
        storeCategoryId = d.int("storeCategoryId", "id")
        name = d.str("name", "categoryName") ?? ""
    }
}

nonisolated struct Offer: Identifiable, Hashable {
    var offerId: Int = 0
    var offerName: String = ""
    var discount: Int = 0
    var discountType: String?
    var description: String?
    var startDate: String?
    var endDate: String?
    var terms: String?
    var productId: Int = 0
    var productName: String?
    var originalPrice: Double = 0
    var offerPrice: Double = 0
    var thumbnailImage: String?
    var activeStatus: Bool = false
    var createdDate: String = ""

    var id: Int { offerId }

    init() {}

    init(_ d: JSONDict) {
        offerId = d.int("offerId", "id")
        offerName = d.str("offerName", "name") ?? ""
        discount = d.int("discount")
        discountType = d.str("discountType")
        description = d.str("description", "offerDescription", "details")
        startDate = d.str("startDate")
        endDate = d.str("endDate")
        terms = d.str("terms", "termcondition", "termCondition", "termsAndConditions")
        productId = d.int("productId")
        productName = d.str("productName")
        originalPrice = d.double("originalPrice")
        offerPrice = d.double("offerPrice")
        thumbnailImage = d.str("thumbnailImage", "image", "imageUrl", "productImage", "bannerImage", "banner", "img")
        activeStatus = d.bool("activeStatus") ?? false
        createdDate = d.str("createdDate") ?? ""
    }
}

nonisolated struct Customer: Identifiable, Hashable {
    var customerId: Int = 0
    var fullName: String = ""
    var email: String?
    var mobile: String = ""
    var dateOfBirth: String?
    var gender: String?
    var addressLine1: String?
    var city: String?
    var notes: String?

    var id: Int { customerId }

    init() {}

    init(_ d: JSONDict) {
        customerId = d.int("customerId", "id")
        fullName = d.str("fullName", "name") ?? ""
        email = d.str("email")
        mobile = d.str("mobile") ?? ""
        dateOfBirth = d.str("dateOfBirth")
        gender = d.str("gender")
        addressLine1 = d.str("addressLine1")
        city = d.str("city")
        notes = d.str("notes")
    }
}

nonisolated struct AppNotification: Identifiable, Hashable {
    var id: Int
    var title: String
    var message: String
    var createdAt: String
    var bookingId: Int
    var storeId: Int

    init(_ d: JSONDict) {
        id = d.int("id", "_id", "notificationId")
        title = d.str("title") ?? "Notification"
        message = d.str("message", "body") ?? ""
        createdAt = d.str("createdDate", "created_at", "timestamp", "date", "createdAt") ?? ""
        bookingId = d.int("bookingId", "booking_id", "bookingRefId")
        storeId = d.int("storeId", "store_id")
    }
}

/// One booking from `api/store/bookings/{storeId}` (the Android app kept these as raw maps).
nonisolated struct Booking: Identifiable, Hashable {
    var bookingId: Int
    var storeId: Int
    var storeName: String?
    var customerName: String
    var services: [String]
    var totalPrice: String?
    var images: [String]
    var status: String
    var dateText: String

    var id: Int { bookingId }

    init(_ d: JSONDict) {
        bookingId = d.int("bookingId", "id")
        storeId = d.int("storeId", "store_id")
        storeName = d.str("storeName")
        customerName = d.str("customerName", "userName") ?? ""
        var names = d.strings("serviceNames", "serviceName", "productNames")
        if names.isEmpty { names = ["Booking Service"] }
        services = names
        totalPrice = d.str("totalPrice")
        var imgs = d.strings("detailImages") + d.strings("productImages")
        let lead = d.str("storeImage", "storeLogo", "logo", "image", "productImage", "thumbnailImage", "imageUrl", "img")
        if let lead, !imgs.contains(lead) { imgs.insert(lead, at: 0) }
        images = imgs.filter { $0.lowercased() != "null" && !$0.isEmpty }
        status = (d.str("bookingStatus", "status") ?? "PENDING").uppercased()
        dateText = Booking.formatDate(d)
    }

    var isPending: Bool { status.contains("PENDING") }

    var statusLabel: String {
        switch status {
        case "": return "Pending"
        default: return status.prefix(1).uppercased() + status.dropFirst().lowercased()
        }
    }

    /// BookingUtils.formatBookingDate: a reschedule time wins, then "dd MMM yyyy | slot".
    static func formatDate(_ d: JSONDict) -> String {
        if let r = d.str("rescheduleTime", "rescheduledDateTime", "newDateTime", "rescheduleDate") { return r }
        if let c = d.str("comment"), let range = c.range(of: "Rescheduled to:") {
            let t = c[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        var date = ""
        if let inner = d.dict("bookDate") { date = inner.str("$date") ?? "" } else { date = d.str("bookDate") ?? "" }
        if date.count >= 10 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            if let parsed = f.date(from: String(date.prefix(10))) {
                f.dateFormat = "dd MMM yyyy"
                date = f.string(from: parsed)
            }
        }
        let slot = d.str("timeSlot") ?? ""
        if !slot.isEmpty { return date.isEmpty ? slot : "\(date) | \(slot)" }
        return date
    }
}

/// One order from `api/public/bookings/{userId}` (OrdersActivity).
nonisolated struct OrderRecord: Identifiable, Hashable {
    var orderId: Int
    var storeName: String
    var storeId: String
    var userName: String
    var productNames: String
    var orderDate: String
    var status: String
    var id: Int { orderId }

    init(_ d: JSONDict) {
        orderId = d.int("bookingId", "id")
        storeName = d.str("storeName") ?? ""
        storeId = d.str("storeId") ?? ""
        userName = d.str("userName", "customerName") ?? ""
        productNames = d.strings("productNames", "serviceNames").joined(separator: ", ")
        orderDate = d.str("orderDate", "bookDate") ?? ""
        status = d.str("status", "bookingStatus") ?? ""
    }
}

nonisolated struct ProductInterest: Identifiable, Hashable {
    var productId: Int
    var productName: String?
    var productImage: String?
    var viewCount: Int
    var wishlistCount: Int
    var id: Int { productId }

    init(_ d: JSONDict) {
        productId = d.int("productId")
        productName = d.str("productName")
        productImage = d.str("productImage")
        viewCount = d.int("viewCount")
        wishlistCount = d.int("wishlistCount")
    }
}

nonisolated struct OfferPerformance: Identifiable, Hashable {
    var offerId: Int
    var offerName: String?
    var viewCount: Int
    var id: Int { offerId }

    init(_ d: JSONDict) {
        offerId = d.int("offerId", "id")
        offerName = d.str("offerName", "name", "title")
        viewCount = d.int("viewCount", "views", "count")
    }
}

/// VisitorSummaryResponse: nested `visitorSummary` / `customerInterest` with flat fallbacks.
nonisolated struct VisitorSummary {
    var today = 0, last7Days = 0, last30Days = 0
    var storeViews = 0, productViews = 0, wishlistAdded = 0, offerViews = 0, bookings = 0
    var mostViewed: [ProductInterest] = []
    var mostWishlisted: [ProductInterest] = []
    var offerPerformance: [OfferPerformance] = []

    init() {}

    init(_ d: JSONDict) {
        let v = d.dict("visitorSummary") ?? d
        let c = d.dict("customerInterest") ?? d
        today = v.int("today", "todayVisitors")
        last7Days = v.int("last7Days", "weekVisitors", "lastSevenDays")
        last30Days = v.int("last30Days", "monthVisitors", "lastThirtyDays")
        storeViews = c.int("storeViews")
        productViews = c.int("productViews")
        wishlistAdded = c.int("wishlistAdded", "wishlistCount")
        offerViews = c.int("offerViews")
        bookings = c.int("bookings", "bookingCount")
        mostViewed = d.dicts("mostViewedProducts").map(ProductInterest.init)
        mostWishlisted = d.dicts("mostWishlistedProducts", "wishlistedProducts", "mostWishlisted").map(ProductInterest.init)
        offerPerformance = d.dicts("offerPerformance").map(OfferPerformance.init)
    }
}

/// ProductCustomerInteraction from `api/store/{storeId}/wishlist/customers`.
nonisolated struct ProductCustomer: Identifiable, Hashable {
    var userId: String
    var customerName: String
    var productId: Int
    var mobileNumber: String?
    var interestType: String
    var lastInteractionTime: String
    var notificationEligible: Bool
    var id: String { "\(userId)-\(productId)-\(lastInteractionTime)" }

    init(_ d: JSONDict) {
        userId = d.str("userId", "id", "customerId") ?? ""
        customerName = d.str("customerName", "name", "userName", "fullName", "storeName") ?? "Customer"
        productId = d.int("productId")
        mobileNumber = d.str("mobileNumber", "customerMobile", "mobile", "phone", "maskedMobile")
        interestType = d.str("interestType", "type", "interactionType") ?? ""
        lastInteractionTime = d.str("lastInteractionTime", "clickDate", "timestamp", "date", "updatedAt") ?? ""
        notificationEligible = d.bool("notificationEligible", "eligible", "promotionalEligible") ?? false
    }
}

/// Offer being created or edited, passed from the form to the preview (AddOfferActivity -> OfferPreviewActivity).
nonisolated struct OfferDraft: Hashable {
    var offerId: Int = 0
    var offerName = ""
    var description = ""
    var discount = 0
    var discountType = "PERCENTAGE"
    var startDate = ""
    var endDate = ""
    var terms = ""
    var productId = 0
    var productName = ""
    var originalPrice: Double = 0
    var offerPrice: Double = 0
    var remoteImage: String?
    var imageData: Data?
}

/// Where the offer form starts from (CreateOfferType / SelectOfferProducts / OfferActivity).
nonisolated struct OfferSeed: Hashable {
    var existing: Offer?
    var productMode = false
    var productId = 0
    var productName = ""
    var productImage: String?
    var originalPrice: Double = 0
}
