import SwiftUI

/// LoginActivity: 10-digit mobile -> POST api/otp/send.
struct LoginView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var mobile = ""
    @State private var busy = false
    @State private var otpTarget: OtpTarget?

    struct OtpTarget: Hashable { var uid: String; var rawMobile: String }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    // Brand area scales with the screen: shorter on SE / mini, taller on Pro Max.
                    VStack(spacing: 18) {
                        Image("BagMark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: min(130, geo.size.height * 0.15))
                        BrandWordmark(size: min(38, geo.size.width * 0.095))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 24)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Store Admin Login").font(.title2.bold())
                        Text("Manage your store, products, offers and bookings.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Text("🇮🇳 +91").font(.body.weight(.semibold))
                                .padding(.horizontal, 12).frame(height: 50)
                                .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                            TextField("Mobile number", text: $mobile)
                                .keyboardType(.numberPad)
                                .textContentType(.telephoneNumber)
                                .font(.title3)
                                .padding(.horizontal, 12).frame(height: 50)
                                .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                                .onChange(of: mobile) { _, v in
                                    let digits = String(v.filter(\.isNumber).prefix(10))
                                    if digits != v { mobile = digits }
                                }
                        }
                        BusyButton(title: "SEND OTP", busy: busy) { Task { await sendOtp() } }
                        Text("By continuing you agree to the AtStores Terms & Privacy Policy.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(maxWidth: 520)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.primary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $otpTarget) { t in OtpView(uid: t.uid, rawMobile: t.rawMobile) }
    }

    private func sendOtp() async {
        guard mobile.count == 10 else { toast.show("Enter valid 10-digit mobile number"); return }
        busy = true
        defer { busy = false }
        do {
            let r = try await API.shared.send(.post, "api/otp/send", body: OtpView.sendBody(mobile))
            guard r.ok else { toast.show("Failed to send OTP: \(r.status)"); return }
            let d = r.json as? JSONDict
            let uid = d?.str("uid") ?? d?.dict("data")?.str("uid") ?? mobile
            otpTarget = OtpTarget(uid: uid, rawMobile: mobile)
        } catch {
            toast.show("Network error")
        }
    }
}

/// OtpActivity: verify, then otp-login as STORE (falling back to CUSTOMER).
struct OtpView: View {
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State var uid: String
    let rawMobile: String
    @State private var code = ""
    @State private var busy = false
    @State private var secondsLeft = 60
    @State private var timerRun = 0
    @FocusState private var focused: Bool

    private var mobile: String { "+91" + rawMobile }

    static func sendBody(_ raw: String) -> [String: Any] {
        ["mobileNumber": raw, "email": "store@atstores.in", "channel": "SMS", "purpose": "LOGIN", "countryCode": "+91"]
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                }
                Spacer()
            }
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44)).foregroundStyle(Theme.primary)
                .frame(width: 92, height: 92).background(Theme.primary.opacity(0.1), in: Circle())
            VStack(spacing: 6) {
                Text("Verify OTP").font(.title2.bold())
                Text("Enter the 6-digit code sent to\n\(mobile)")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            ZStack {
                // One hidden field drives the six boxes, so SMS autofill (.oneTimeCode) works.
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.02)
                    .onChange(of: code) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(6))
                        if digits != v { code = digits }
                        if digits.count == 6 { Task { await verify() } }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(.title2.bold())
                            .frame(maxWidth: 50)
                            .frame(height: 54)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(i == chars.count && focused ? Theme.primary : Color.black.opacity(0.15), lineWidth: 1.5))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            BusyButton(title: "VERIFY", busy: busy) { Task { await verify() } }

            Button(secondsLeft > 0 ? "Resend OTP in \(secondsLeft)s" : "Resend OTP") { Task { await resend() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondsLeft > 0 ? .gray : Theme.primary)
                .disabled(secondsLeft > 0)
            Spacer()
        }
        .padding(.horizontal, 22)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .task(id: timerRun) {
            secondsLeft = 60
            while secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
        }
    }

    private func verify() async {
        guard !busy else { return }
        guard code.count == 6 else { toast.show("Enter valid 6-digit OTP"); return }
        busy = true
        defer { busy = false }
        guard let r = try? await API.shared.send(.post, "api/otp/verify", body: ["uid": uid, "otp": code, "mobile": mobile]) else {
            toast.show("Network error during OTP verification"); return
        }
        guard r.ok else { toast.show("Invalid or expired OTP"); return }

        // STORE login first; fall back to CUSTOMER (new owners register a store next).
        var auth: AuthResult?
        var lastStatus = 0
        for appType in ["STORE", "CUSTOMER"] {
            let body: [String: Any] = ["mobile": mobile, "uid": uid, "appType": appType, "fcmToken": PushService.shared.fcmToken]
            if let res = try? await API.shared.send(.post, "api/auth/otp-login", body: body) {
                lastStatus = res.status
                if res.ok, let d = res.json as? JSONDict { auth = AuthResult(d); break }
            }
        }
        guard let auth else { toast.show(lastStatus > 0 ? "Login failed: \(lastStatus)" : "Network error during login"); return }
        Session.shared.saveLogin(auth, fallbackMobile: mobile)
        if !auth.isStoreOwner { toast.show("OTP Verified! Please register your store.", long: true) }
    }

    private func resend() async {
        guard let r = try? await API.shared.send(.post, "api/otp/send", body: Self.sendBody(rawMobile)) else {
            toast.show("Network error"); return
        }
        guard r.ok else { toast.show("Failed to resend OTP"); return }
        if let newUid = (r.json as? JSONDict)?.str("uid") { uid = newUid }
        toast.show("OTP Resent")
        code = ""
        timerRun += 1
    }
}
