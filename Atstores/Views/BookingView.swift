import SwiftUI

struct BookingView: View {
    let storeId: Int
    let storeName: String
    let storeCategory: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast

    @State private var services: [ServiceItem] = []
    @State private var selectedServices: Set<Int> = []
    @State private var dates: [Day] = []
    @State private var selectedDate = ""
    @State private var slots: [TimeSlot] = []
    @State private var selectedTime = ""
    @State private var name = ""
    @State private var mobile = ""
    @State private var comments = ""
    @State private var loading = false

    struct Day: Identifiable, Hashable {
        let full: String, dayName: String, dayNumber: String, month: String
        var id: String { full }
    }

    private var chosen: [ServiceItem] { services.filter { selectedServices.contains($0.id) } }
    private var totalDuration: Int { chosen.reduce(0) { $0 + $1.durationMins } }
    private var totalAmount: Double { chosen.reduce(0) { $0 + $1.price } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(storeName).font(.title2.bold()).padding(.horizontal)

                section("Select Services") {
                    VStack(spacing: 10) {
                        ForEach(services) { s in
                            let on = selectedServices.contains(s.id)
                            Button {
                                if on { selectedServices.remove(s.id) } else {
                                    selectedServices.insert(s.id)
                                    Analytics.visit(storeId: storeId, serviceId: s.id, type: "SERVICE_VIEW", name: storeName, category: s.name)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: s.imageUrl, placeholder: "scissors")
                                        .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading) {
                                        Text(s.name).font(.subheadline.weight(.semibold))
                                        Text(Format.duration(s.durationMins)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Format.currency(s.price)).font(.subheadline.bold())
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(on ? .orange : .secondary)
                                }
                                .padding(10)
                                .background(on ? Theme.primary.opacity(0.15) : Theme.lightGray, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                section("Select Date") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(dates) { d in
                                let on = d.full == selectedDate
                                Button {
                                    selectedDate = d.full
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(d.dayName).font(.caption)
                                        Text(d.dayNumber).font(.title3.bold())
                                        Text(d.month).font(.caption)
                                    }
                                    .frame(width: 58, height: 72)
                                    .background(on ? Theme.primary : Theme.lightGray, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                section("Select Time") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(slots) { slot in
                            let on = slot.time == selectedTime
                            Button { selectedTime = slot.time } label: {
                                Text(slot.time).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(on ? Theme.primary : Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(slot.isAvailable ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(!slot.isAvailable)
                        }
                    }
                }

                section("Your Details") {
                    VStack(spacing: 10) {
                        field("Full Name", text: $name)
                        field("Mobile Number", text: $mobile, keyboard: .numberPad)
                        field("Comments (optional)", text: $comments)
                    }
                }

                section("Summary") {
                    VStack(spacing: 8) {
                        row("Services", "\(chosen.count) Services")
                        row("Duration", Format.duration(totalDuration))
                        row("Start Time", selectedTime.isEmpty ? "--" : selectedTime)
                        row("End Time", selectedTime.isEmpty || totalDuration == 0 ? "--" : Format.endTime(start: selectedTime, durationMins: totalDuration))
                        Divider()
                        row("Total", Format.currency(totalAmount)).font(.headline)
                    }
                    .padding()
                    .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.vertical)
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await submit() } } label: {
                if loading { ProgressView().tint(.black) } else { Text("Book Appointment") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(loading)
            .padding()
            .background(.bar)
        }
        .appHeader(title: "Book Appointment")
        .task {
            guard dates.isEmpty else { return }
            prefillUser()
            buildDates()
            services = await API.shared.objects("api/public/product/storeId/\(storeId)").map(Product.init).map(ServiceItem.init)
        }
        .task(id: selectedDate) { await loadSlots() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(.horizontal)
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .padding(12)
            .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
    }

    private func prefillUser() {
        let s = Session.shared
        var m = s.mobileNumber
        if m.isEmpty { m = s.user?.contactNo ?? "" }
        if m.hasPrefix("+91") { m = String(m.dropFirst(3)) }
        mobile = m
        name = s.user?.name ?? ""
    }

    private func buildDates() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var out: [Day] = []
        for i in 0..<7 {
            let d = Calendar.current.date(byAdding: .day, value: i, to: Date())!
            f.dateFormat = "yyyy-MM-dd"; let full = f.string(from: d)
            f.dateFormat = "EEE"; let dn = f.string(from: d)
            f.dateFormat = "dd"; let num = f.string(from: d)
            f.dateFormat = "MMM"; let mon = f.string(from: d)
            out.append(Day(full: full, dayName: dn, dayNumber: num, month: mon))
        }
        dates = out
        selectedDate = out.first?.full ?? ""
    }

    private func loadSlots() async {
        guard !selectedDate.isEmpty else { return }
        selectedTime = ""
        let list = await API.shared.objects("api/public/store/timeslots/\(storeId)/\(selectedDate)").map(TimeSlot.init)
        slots = list.isEmpty ? defaultSlots() : list
    }

    /// Local midnight of the selected day, expressed in UTC (same as the Android app).
    private var bookDateISO: String {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd"
        guard let d = local.date(from: selectedDate) else { return selectedDate + "T00:00:00.000Z" }
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return utc.string(from: d)
    }

    /// 9:00 AM to 9:00 PM every 30 minutes.
    private func defaultSlots() -> [TimeSlot] {
        var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        var out: [TimeSlot] = []
        for _ in 0..<25 {
            out.append(TimeSlot(time: Format.slotFormatter.string(from: start)))
            start = start.addingTimeInterval(30 * 60)
        }
        return out
    }

    private func submit() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { toast.show("Full Name is required"); return }
        guard mobile.count == 10 else { toast.show("Enter 10 digit mobile number"); return }
        guard !chosen.isEmpty else { toast.show("Select at least one service"); return }
        guard !selectedDate.isEmpty else { toast.show("Select a date"); return }
        guard !selectedTime.isEmpty else { toast.show("Select a time slot"); return }
        let s = Session.shared
        guard !s.uid.isEmpty else { toast.show("Please login first"); return }

        let images = chosen.map(\.imageUrl).filter { !$0.isEmpty }
        let body: [String: Any] = [
            "userId": s.user?.id ?? 0, "uid": s.uid, "storeId": storeId,
            "productIds": chosen.map(\.id), "serviceNames": chosen.map(\.name),
            "storeName": storeName, "category": storeCategory,
            "totalPrice": totalAmount, "discount": 0, "hours": Double(totalDuration) / 60.0,
            "customerName": name, "mobileNumber": mobile, "comments": comments,
            "timeSlot": selectedTime, "bookDate": bookDateISO,
            "bookingStatus": "PENDING", "paymentStatus": "UNPAID", "paymentMethod": "CASH",
            "reason": "", "newDate": "", "newTime": "",
            "image": images.first ?? "", "detailImages": images, "orderId": ""
        ]
        loading = true
        defer { loading = false }
        do {
            let r = try await API.shared.send(.post, "api/public/booking", body: body)
            if r.ok {
                toast.show("Booking Successful!", long: true)
                dismiss()
            } else {
                toast.show("Booking Failed: \(r.status)")
            }
        } catch {
            toast.show("Network Error")
        }
    }
}
