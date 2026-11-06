import SwiftUI

struct LoginView: View {
    @Environment(ToastCenter.self) private var toast
    @State private var mobile = ""
    @State private var loading = false
    @State private var otpTarget: OtpTarget?

    struct OtpTarget: Hashable { let mobile: String; let uid: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image("Logo").resizable().scaledToFit().frame(height: 70)
            Text("Welcome to AtStores").font(.largeTitle.bold())
            Text("Enter your mobile number to continue").foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("+91").font(.headline).padding(.horizontal, 12).padding(.vertical, 14)
                    .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                TextField("Mobile number", text: $mobile)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.headline)
                    .padding(14)
                    .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: mobile) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(10))
                        if digits != v { mobile = digits }
                    }
            }

            Button {
                Task { await sendOtp() }
            } label: {
                if loading { ProgressView().tint(.black) } else { Text("Send OTP") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(loading)
            Spacer()
            Spacer()
        }
        .padding(24)
        .navigationDestination(item: $otpTarget) { OtpView(mobile: $0.mobile, otpUid: $0.uid) }
    }

    private func sendOtp() async {
        guard mobile.count == 10 else { toast.show("Enter valid 10-digit mobile number"); return }
        loading = true
        defer { loading = false }
        // Same payload as LoginActivity, including its static email ("Static as per current setup").
        let body = ["mobileNumber": mobile, "email": "rabichoudhury@gmail.com", "channel": "SMS",
                    "purpose": "LOGIN", "countryCode": "+91"]
        do {
            let r = try await API.shared.send(.post, "api/otp/send", body: body)
            guard r.ok else { toast.show("Failed to send OTP"); return }
            let d = r.json as? JSONDict
            let uid = d?.str("uid", "userId", "id") ?? mobile
            otpTarget = OtpTarget(mobile: mobile, uid: uid)
        } catch {
            toast.show("Network Error")
        }
    }
}

struct OtpView: View {
    let mobile: String
    let otpUid: String

    @Environment(ToastCenter.self) private var toast
    @State private var code = ""
    @State private var secondsLeft = 60
    @State private var verifying = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Verify OTP").font(.largeTitle.bold())
            Text("Enter the 6-digit code sent to +91 \(mobile)").foregroundStyle(.secondary)

            ZStack {
                // A single hidden field drives the six boxes; .oneTimeCode enables SMS autofill.
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
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(.title2.bold())
                            .frame(width: 46, height: 54)
                            .background(Theme.lightGray, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(i == chars.count && focused ? Theme.primary : .clear, lineWidth: 2))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }

            Button {
                Task { await verify() }
            } label: {
                if verifying { ProgressView().tint(.black) } else { Text("Verify") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(verifying)

            HStack {
                Spacer()
                if secondsLeft > 0 {
                    Text("Resend in \(secondsLeft)s").foregroundStyle(.secondary)
                } else {
                    Button("Resend OTP") { Task { await resend() } }.fontWeight(.semibold)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(24)
        .onAppear { focused = true }
        .task(id: secondsLeft) {
            guard secondsLeft > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            secondsLeft -= 1
        }
    }

    private var fullMobile: String { mobile.hasPrefix("+91") ? mobile : "+91" + mobile }

    private func verify() async {
        guard code.count == 6 else { toast.show("Enter 6-digit OTP"); return }
        guard !verifying else { return }
        verifying = true
        defer { verifying = false }
        let uid = otpUid.isEmpty ? fullMobile : otpUid
        do {
            let r = try await API.shared.send(.post, "api/otp/verify", body: ["uid": uid, "otp": code, "mobile": fullMobile])
            guard r.ok else { toast.show("Invalid OTP"); return }
            let loginUid = (r.json as? JSONDict)?.str("uid") ?? uid
            await login(uid: loginUid)
        } catch {
            toast.show("Network Error")
        }
    }

    private func login(uid: String) async {
        // Push notifications (FCM) are not wired up on iOS yet, so no device token is sent.
        let body = ["mobile": fullMobile, "uid": uid, "appType": "CUSTOMER", "fcmToken": ""]
        do {
            let r = try await API.shared.send(.post, "api/auth/otp-login", body: body)
            guard r.ok, let d = r.json as? JSONDict else { toast.show(r.errorMessage("Login Failed"), long: true); return }
            Session.shared.saveLogin(userId: d.str("userId"), accessToken: d.str("accessToken"),
                                     refreshToken: d.str("refreshToken"), mobile: d.str("mobile"),
                                     fallbackMobile: mobile)
        } catch {
            toast.show("Login session error")
        }
    }

    private func resend() async {
        if await API.shared.ok(.post, "api/otp/resend/\(API.seg(otpUid.isEmpty ? mobile : otpUid))") {
            toast.show("OTP Sent Again")
            secondsLeft = 60
        }
    }
}
