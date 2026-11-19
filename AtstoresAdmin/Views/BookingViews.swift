import SwiftUI

// MARK: - Bookings (BookingActivity)

struct BookingsView: View {
    let openBookingId: Int
    let storeId: Int
    let pushed: Bool
    @Environment(ToastCenter.self) private var toast
    private var session = Session.shared

    @State private var all: [Booking] = []
    @State private var filter = "All"
    @State private var loaded = false
    @State private var busy = false
    @State private var detail: Booking?
    @State private var rescheduling: Booking?
    @State private var pendingOpenId = 0

    private static let filters = ["All", "Pending", "Accepted", "Completed", "Cancelled"]

    init(openBookingId: Int, storeId: Int, pushed: Bool) {
        self.openBookingId = openBookingId
        self.storeId = storeId
        self.pushed = pushed
        _pendingOpenId = State(initialValue: openBookingId)
    }

    private var activeStoreId: Int { storeId > 0 ? storeId : session.selectedStoreId }

    /// applyFilter: status match, then pending first and newest booking id first.
    private var bookings: [Booking] {
        all.filter { b in
            switch filter {
            case "Pending": return b.status.contains("PENDING")
            case "Accepted": return b.status.contains("CONFIRMED") || b.status.contains("ACCEPTED")
            case "Completed": return b.status.contains("COMPLETED")
            case "Cancelled": return b.status.contains("CANCELLED") || b.status.contains("REJECTED")
            default: return true
            }
        }
        .sorted { a, b in
            if (a.status == "PENDING") != (b.status == "PENDING") { return a.status == "PENDING" }
            return a.bookingId > b.bookingId
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !pushed { StorePicker(filter: { Store.isBookingCategory($0.storeCategoryName) }).padding(.horizontal, -16) }
                ChipRow(items: Self.filters, selected: $filter).padding(.horizontal, -16)
                if !loaded {
                    LoadingView()
                } else if bookings.isEmpty {
                    EmptyStateView(icon: "calendar", text: "No bookings found",
                                   detail: filter == "All" ? "New booking requests from customers will appear here." : nil)
                }
                LazyVStack(spacing: 12) {
                    ForEach(bookings) { b in
                        BookingCard(booking: b, fallbackStoreName: session.selectedStoreName, fallbackStoreId: activeStoreId,
                                    onConfirm: { Task { await update(b, "Confirmed") } },
                                    onReschedule: { rescheduling = b })
                            .onTapGesture { detail = b }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .overlay { if busy { ProgressView().controlSize(.large).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .modifier(BookingsHeader(pushed: pushed))
        .task(id: activeStoreId) { await load() }
        .sheet(item: $detail) { b in
            BookingDetailSheet(booking: b,
                               onPrimary: { status in detail = nil; Task { await update(b, status) } },
                               onReschedule: { detail = nil; rescheduling = b })
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $rescheduling) { b in
            RescheduleSheet { date in rescheduling = nil; Task { await reschedule(b, to: date) } }
                .presentationDetents([.height(460)])
        }
    }

    private func load() async {
        guard activeStoreId > 0 else { loaded = true; return }
        guard let r = try? await API.shared.send(.get, "api/store/bookings/\(activeStoreId)") else {
            toast.show("Failed to load bookings"); loaded = true; return
        }
        if r.status == 401 {
            loaded = true
            Session.shared.expire(toast)
            return
        }
        if r.ok { all = JSON.objects(from: r.json).map(Booking.init) }
        loaded = true
        if pendingOpenId > 0, let b = all.first(where: { $0.bookingId == pendingOpenId }) {
            pendingOpenId = -1
            detail = b
        }
    }

    private func update(_ b: Booking, _ status: String, extra: [String: Any] = [:], comment: String = "") async {
        guard b.bookingId > 0 else { toast.show("Invalid Booking ID"); return }
        var body: [String: Any] = ["comment": comment, "comments": comment, "reason": comment]
        body.merge(extra) { $1 }
        busy = true
        defer { busy = false }
        guard let r = try? await API.shared.send(.put, "api/store/bookings/update/\(b.bookingId)/status/\(status)", body: body) else {
            toast.show("Network error"); return
        }
        if r.ok {
            toast.show("Booking \(status)")
            await load()
        } else {
            toast.show("Update failed: \(r.status)")
        }
    }

    private func reschedule(_ b: Booking, to date: Date) async {
        let iso = Format.date(date, "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        let time = Format.date(date, "hh:mm a")
        await update(b, "Rescheduled",
                     extra: ["bookDate": iso, "newDate": iso, "newTime": time, "timeSlot": time],
                     comment: "Rescheduled to: " + Format.date(date, "yyyy-MM-dd HH:mm"))
    }
}

private struct BookingsHeader: ViewModifier {
    let pushed: Bool
    func body(content: Content) -> some View {
        if pushed { content.adminHeader("Bookings") } else { content.adminHeader() }
    }
}

/// item_booking_admin.
struct BookingCard: View {
    let booking: Booking
    let fallbackStoreName: String
    let fallbackStoreId: Int
    let onConfirm: () -> Void
    let onReschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: booking.images.first)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(booking.storeName ?? (fallbackStoreName.isEmpty ? "AtStores" : fallbackStoreName))
                            .font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        Text(booking.statusLabel).font(.caption.bold()).foregroundStyle(BookingCard.color(booking.status))
                    }
                    Text("Booking ID: #\(booking.bookingId > 0 ? "\(booking.bookingId)" : "-")  •  Store ID: \(booking.storeId > 0 ? booking.storeId : fallbackStoreId)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Label(booking.customerName, systemImage: "person").font(.caption)
                    Text(booking.services.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                Label(booking.dateText, systemImage: "calendar").font(.caption.weight(.medium))
                Spacer()
                if let p = booking.totalPrice { Text(Format.amount(p)).font(.subheadline.bold()).foregroundStyle(Theme.primary) }
            }
            if booking.isPending {
                HStack(spacing: 10) {
                    Button("Reschedule", action: onReschedule).buttonStyle(OutlineButtonStyle())
                    Button("Confirm", action: onConfirm).buttonStyle(OutlineButtonStyle(color: Theme.success))
                }
            }
        }
        .cardStyle()
        .contentShape(Rectangle())
    }

    static func color(_ status: String) -> Color {
        switch status {
        case "PENDING": return Color(hex: 0xE65100)
        case "CONFIRMED", "ACCEPTED", "RESCHEDULED": return Color(hex: 0x2E7D32)
        case "COMPLETED": return Color(hex: 0x1565C0)
        case "CANCELLED", "REJECTED": return Color(hex: 0xC62828)
        default: return Color(hex: 0x616161)
        }
    }
}

/// dialog_booking_detail: one row per service with an equal share of the total.
struct BookingDetailSheet: View {
    let booking: Booking
    let onPrimary: (String) -> Void
    let onReschedule: () -> Void

    private var perItem: Double {
        let total = Double(booking.totalPrice ?? "") ?? 0
        return booking.services.isEmpty ? total : total / Double(booking.services.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Booking #\(booking.bookingId)").font(.title3.bold())
                    Spacer()
                    StatusPill(text: booking.statusLabel, fg: BookingCard.color(booking.status))
                }
                ForEach(Array(booking.services.enumerated()), id: \.offset) { i, name in
                    HStack(spacing: 12) {
                        RemoteImage(url: booking.images.isEmpty ? nil : booking.images[i % booking.images.count])
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("₹" + String(format: "%.2f", perItem)).font(.subheadline)
                    }
                }
                Divider()
                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(Format.amount(booking.totalPrice ?? "0")).font(.headline).foregroundStyle(Theme.primary)
                }
                Label("Customer: \(booking.customerName)", systemImage: "person")
                Label("Date & Time: \(booking.dateText)", systemImage: "calendar")
                HStack(spacing: 10) {
                    if booking.status != "COMPLETED" {
                        Button("Reschedule", action: onReschedule).buttonStyle(OutlineButtonStyle())
                    }
                    switch booking.status {
                    case "CONFIRMED":
                        Button("Mark Completed") { onPrimary("Completed") }.buttonStyle(PrimaryButtonStyle(color: Theme.success))
                    case "COMPLETED":
                        Button("Completed") {}.buttonStyle(PrimaryButtonStyle(color: .gray)).disabled(true)
                    default:
                        Button("Confirm") { onPrimary("Confirmed") }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
            .font(.subheadline)
            .padding(20)
        }
    }
}

/// Date + time chooser for rescheduling (DatePickerDialog + TimePickerDialog).
struct RescheduleSheet: View {
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("New date & time", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                Button("Reschedule Booking") { onConfirm(date) }.buttonStyle(PrimaryButtonStyle())
            }
            .padding()
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Orders (OrdersActivity)

struct OrdersView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var orders: [OrderRecord] = []
    @State private var loaded = false
    @State private var rejecting: OrderRecord?
    @State private var reason = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !loaded {
                    LoadingView()
                } else if orders.isEmpty {
                    EmptyStateView(icon: "bag", text: "No orders yet")
                }
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(o.storeName).font(.subheadline.bold())
                            Spacer()
                            Text(o.status).font(.caption.bold()).foregroundStyle(BookingCard.color(o.status.uppercased()))
                        }
                        Text("ID: \(o.storeId)").font(.caption2).foregroundStyle(.secondary)
                        Label(o.userName, systemImage: "person").font(.caption)
                        Text(o.productNames).font(.caption).foregroundStyle(.secondary)
                        Label(o.orderDate, systemImage: "calendar").font(.caption)
                        if o.status.uppercased() == "PENDING" {
                            HStack(spacing: 10) {
                                Button("Reject") { reason = ""; rejecting = o }.buttonStyle(OutlineButtonStyle(color: Theme.danger))
                                Button("Confirm") { Task { await update(o, "CONFIRMED", "") } }.buttonStyle(OutlineButtonStyle(color: Theme.success))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .adminHeader("Orders")
        .task { await load() }
        .alert("Reject Order", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
            TextField("Reason for rejection", text: $reason)
            Button("REJECT", role: .destructive) {
                guard let o = rejecting else { return }
                if reason.trimmed.isEmpty { toast.show("Please provide a reason") }
                else { Task { await update(o, "REJECTED", reason.trimmed) } }
            }
            Button("CANCEL", role: .cancel) {}
        }
    }

    private func load() async {
        let userId = Session.shared.effectiveUserId
        guard !userId.isEmpty else { loaded = true; return }
        orders = await API.shared.objects("api/public/bookings/\(API.seg(userId))").map(OrderRecord.init).sorted { $0.orderId > $1.orderId }
        loaded = true
    }

    private func update(_ o: OrderRecord, _ status: String, _ comment: String) async {
        guard o.orderId > 0 else { toast.show("Invalid Order ID"); return }
        if await API.shared.ok(.put, "api/store/bookings/update/\(o.orderId)/status/\(status)", body: ["comment": comment]) {
            toast.show("Order \(status)")
            await load()
        } else {
            toast.show("Update failed")
        }
    }
}
