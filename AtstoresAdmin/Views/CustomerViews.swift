import SwiftUI

// MARK: - Customers (CustomerListActivity)

struct CustomerListView: View {
    let storeId: Int
    @Environment(ToastCenter.self) private var toast
    @State private var customers: [Customer] = []
    @State private var query = ""
    @State private var selected: Set<Int> = []
    @State private var loaded = false
    @State private var messaging: Customer?
    @State private var message = ""
    private var session = Session.shared

    init(storeId: Int) { self.storeId = storeId }

    private var filtered: [Customer] {
        let q = query.trimmed
        return q.isEmpty ? customers : customers.filter { $0.fullName.localizedCaseInsensitiveContains(q) || $0.mobile.contains(q) }
    }
    private var selectedCustomers: [Customer] { filtered.filter { selected.contains($0.customerId) } }
    private var allSelected: Bool { !filtered.isEmpty && selectedCustomers.count == filtered.count }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SearchField(prompt: "Search by name or mobile", text: $query)
                    NavigationLink(value: Route.customerForm(nil)) {
                        Image(systemName: "person.badge.plus").font(.title3).foregroundStyle(.white)
                            .frame(width: 42, height: 42).background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Add Customer")
                }
                HStack {
                    Button {
                        if allSelected { selected.removeAll() } else { selected = Set(filtered.map(\.customerId)) }
                    } label: {
                        Label("Select All", systemImage: allSelected ? "checkmark.square.fill" : "square")
                    }
                    .font(.subheadline)
                    Spacer()
                    Text("\(filtered.count) customers").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if !loaded {
                        LoadingView()
                    } else if filtered.isEmpty {
                        EmptyStateView(icon: "person.2", text: "No customers yet", detail: "Add customers to share offers and your store link on WhatsApp.")
                    }
                    ForEach(filtered) { c in row(c) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            if !selectedCustomers.isEmpty {
                Button("Send Message (\(selectedCustomers.count))") { sendBulk() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success))
                    .padding(16)
            }
        }
        .adminHeader("Customers")
        .onAppear { Task { await load() } }
        .alert("Send WhatsApp to \(messaging?.fullName ?? "")",
               isPresented: Binding(get: { messaging != nil }, set: { if !$0 { messaging = nil } })) {
            TextField("Message", text: $message, axis: .vertical)
            Button("SEND WHATSAPP") {
                guard let c = messaging else { return }
                if message.trimmed.isEmpty { toast.show("Message cannot be empty") }
                else { StoreActions.whatsApp(c.mobile, message: message.trimmed, toast: toast) }
            }
            Button("CANCEL", role: .cancel) {}
        }
    }

    /// item_customer: checkbox, name, mobile, WhatsApp + edit.
    private func row(_ c: Customer) -> some View {
        let on = selected.contains(c.customerId)
        return HStack(spacing: 12) {
            Button {
                if on { selected.remove(c.customerId) } else { selected.insert(c.customerId) }
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.title3)
                    .foregroundStyle(on ? Theme.primary : .secondary)
            }
            .buttonStyle(.plain)
            Text(String(c.fullName.prefix(1)).uppercased())
                .font(.headline).foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40).background(Theme.tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(c.fullName).font(.subheadline.weight(.semibold))
                Text(c.mobile).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                message = StoreActions.storeShareMessage(customerName: c.fullName, storeName: session.selectedStoreName, storeId: storeId)
                messaging = c
            } label: {
                Image(systemName: "message.fill").foregroundStyle(Theme.success).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("WhatsApp")
            NavigationLink(value: Route.customerForm(c)) {
                Image(systemName: "pencil").foregroundStyle(Theme.primary).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit")
        }
        .cardStyle(padding: 10)
    }

    private func load() async {
        guard storeId > 0 else { loaded = true; return }
        guard let r = try? await API.shared.send(.get, "api/store/customer/store/\(storeId)") else {
            toast.show("Failed to load customers"); loaded = true; return
        }
        if r.ok { customers = JSON.objects(from: r.json).map(Customer.init) } else { toast.show("Failed to load customers") }
        loaded = true
    }

    /// Android opens WhatsApp for the first selected customer (one chat at a time).
    private func sendBulk() {
        guard let first = selectedCustomers.first else { return }
        let msg = StoreActions.storeShareMessage(customerName: first.fullName, storeName: session.selectedStoreName, storeId: storeId)
        StoreActions.whatsApp(first.mobile, message: msg, toast: toast)
    }
}

// MARK: - Add / edit customer (AddCustomerActivity)

struct CustomerFormView: View {
    let existing: Customer?
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mobile = ""
    @State private var email = ""
    @State private var dob: Date?
    @State private var gender = ""
    @State private var address = ""
    @State private var city = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var populated = false
    @State private var pickingDob = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 14) {
                    FormField(label: "Full Name *", text: $name)
                    FormField(label: "Mobile *", text: $mobile, keyboard: .phonePad)
                    FormField(label: "Email", text: $email, keyboard: .emailAddress)
                    HStack(spacing: 10) {
                        FormValue(label: "Date of Birth") {
                            Button { pickingDob = true } label: {
                                Text(dob.map { Format.date($0, "yyyy-MM-dd") } ?? "Select")
                                    .foregroundStyle(dob == nil ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "calendar").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        FormValue(label: "Gender") {
                            Picker("Gender", selection: $gender) {
                                Text("Select").tag("")
                                Text("Male").tag("Male")
                                Text("Female").tag("Female")
                                Text("Other").tag("Other")
                            }
                            .labelsHidden()
                            Spacer(minLength: 0)
                        }
                    }
                }
                .cardStyle()
                VStack(spacing: 14) {
                    FormField(label: "Address", text: $address)
                    FormField(label: "City", text: $city)
                    FormField(label: "Notes", text: $notes, multiline: true)
                }
                .cardStyle()
                BusyButton(title: existing == nil ? "SAVE CUSTOMER" : "UPDATE CUSTOMER", busy: busy) { Task { await save() } }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .adminHeader(existing == nil ? "Add Customer" : "Edit Customer")
        .onAppear { populate() }
        .sheet(isPresented: $pickingDob) {
            DobPicker(initial: dob ?? Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()) { dob = $0 }
                .presentationDetents([.height(360)])
        }
    }

    private func populate() {
        guard !populated, let c = existing else { return }
        populated = true
        name = c.fullName
        mobile = c.mobile
        email = c.email ?? ""
        dob = c.dateOfBirth.flatMap { DateParse.parse(String($0.split(separator: "T").first ?? "")) }
        gender = ["Male", "Female", "Other"].contains(c.gender ?? "") ? c.gender! : ""
        address = c.addressLine1 ?? ""
        city = c.city ?? ""
        notes = c.notes ?? ""
    }

    private func save() async {
        guard !name.trimmed.isEmpty, !mobile.trimmed.isEmpty else { toast.show("Name and Mobile are required"); return }
        let storeId = Session.shared.selectedStoreId
        guard storeId > 0 else { toast.show("Please select a store first"); return }
        let now = Format.isoNow()
        var body: [String: Any] = [
            "storeId": storeId, "fullName": name.trimmed, "email": email.trimmed, "mobile": mobile.trimmed,
            "dateOfBirth": dob.map { Format.date($0, "yyyy-MM-dd") + "T00:00:00.000Z" } ?? now,
            "gender": gender, "addressLine1": address.trimmed, "addressLine2": "", "city": city.trimmed,
            "state": "", "postalCode": "", "country": "India", "registeredDate": now, "updatedDate": now,
            "notes": notes.trimmed, "profileImagePath": "", "active": true, "verified": true
        ]
        busy = true
        defer { busy = false }
        let r: APIResponse?
        if let c = existing {
            body["customerId"] = c.customerId
            r = try? await API.shared.send(.put, "api/store/customer/\(c.customerId)", body: body)
        } else {
            r = try? await API.shared.send(.post, "api/store/customer", body: body)
        }
        guard let r else { toast.show("Network error"); return }
        if r.ok {
            toast.show(existing == nil ? "Customer Added Successfully" : "Customer Updated Successfully")
            dismiss()
        } else {
            toast.show((existing == nil ? "Failed: " : "Update Failed: ") + "\(r.status)")
        }
    }
}

private struct DobPicker: View {
    let initial: Date
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Date of Birth").font(.headline)
                Spacer()
                Button("Done") { onDone(date); dismiss() }.bold()
            }
            .padding()
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
        }
        .onAppear { date = initial }
    }
}
