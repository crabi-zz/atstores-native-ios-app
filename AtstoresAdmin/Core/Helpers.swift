import SwiftUI
import UIKit

enum Theme {
    static let primary = Color(hex: 0x0033B8)     // AtStores admin blue
    static let primaryDark = Color(hex: 0x1E3C71)
    static let secondary = Color(hex: 0xFFC400)   // AtStores yellow
    static let success = Color(hex: 0x28A745)
    static let danger = Color(hex: 0xDC3545)
    static let background = Color(hex: 0xF4F6FA)
    static let lightGray = Color(hex: 0xF5F5F5)
    static let tint = Color(hex: 0xF0F6FF)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

nonisolated enum Format {
    static func price(_ v: Double) -> String { "₹\(Int(v))" }

    static func amount(_ raw: String?) -> String {
        guard let raw, let v = Double(raw) else { return "₹" + (raw ?? "0") }
        return v == v.rounded() ? "₹\(Int(v))" : "₹" + String(format: "%.2f", v)
    }

    /// 1.2K / 3.4M (StoreListAdapter.formatVisitorCount).
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Strips a trailing ".0" so 10.0 shows as 10.
    static func number(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : "\(v)" }

    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: d)
    }

    static func isoNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: Date())
    }

    /// Readable notification / interaction time; unknown formats pass through.
    static func timestamp(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Just now" }
        guard let d = DateParse.parse(raw) else { return raw }
        return date(d, "dd MMM yyyy, hh:mm a")
    }
}

nonisolated enum DateParse {
    static func parse(_ raw: String, extraFormats: [String] = []) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.lowercased() != "null" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in extraFormats + ["yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSS",
                                   "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd MMM yyyy", "dd-MM-yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        if s.count >= 10 {
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: String(s.prefix(10)))
        }
        return nil
    }
}

/// StoreActionHelper: WhatsApp, website, call, email, share text.
enum StoreActions {
    static let supportPhone = "+919148783102"
    static let supportEmail = "support@atstores.in"

    @discardableResult
    static func open(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    static func whatsApp(_ phone: String?, message: String = "", toast: ToastCenter) {
        guard var p = phone, !p.isEmpty else { toast.show("Mobile number not available"); return }
        p = p.filter(\.isNumber)
        if p.count == 10 { p = "91" + p }
        let text = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if !open("https://wa.me/\(p)?text=\(text)") { toast.show("Unable to open WhatsApp") }
    }

    static func website(_ site: String?, toast: ToastCenter) {
        guard var s = site, !s.isEmpty else { toast.show("Website not available"); return }
        if !s.hasPrefix("http") { s = "https://" + s }
        if !open(s) { toast.show("Unable to open website") }
    }

    static func call(_ phone: String) { open("tel:\(phone.replacingOccurrences(of: " ", with: ""))") }

    static func email(_ address: String, subject: String, body: String = "") {
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        open("mailto:\(address)?subject=\(s)&body=\(b)")
    }

    /// StoreActionHelper.buildStoreShareMessage.
    static func storeShareMessage(customerName: String?, storeName: String, storeId: Int) -> String {
        let greeting = (customerName?.isEmpty == false) ? "Hello \(customerName!),\n\n" : "Hello,\n\n"
        return greeting
            + "Check out \(storeName.isEmpty ? "our store" : storeName) on AtStores!\n\n"
            + "🛒 Store Link: https://atstores.in/storefront?storeId=\(storeId)\n\n"
            + "Download the AtStores Customer App:\n"
            + "🤖 Android App: https://atstores.in/app/android/\n"
            + "🍏 Apple iOS App: https://atstores.in/app/ios"
    }
}

enum ImageData {
    /// JPEG for upload, scaled so the longest side is at most 1600px.
    static func jpeg(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.8)
    }
}

@Observable
final class ToastCenter {
    var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String, long: Bool = false) {
        message = text
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(long ? 3.5 : 2))
            if !Task.isCancelled { self?.message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    let center: ToastCenter
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let msg = center.message {
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 90)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.message)
    }
}

extension View {
    func toastOverlay(_ center: ToastCenter) -> some View { modifier(ToastOverlay(center: center)) }
}

/// Converts HTML from the content API into styled text.
enum HTMLText {
    static func styled(_ html: String) -> NSAttributedString {
        let css = """
        <style>
        body { font-family: -apple-system; font-size: 15px; line-height: 1.55; color: #3A3A3C; }
        h1, h2, h3 { color: #0033B8; margin: 14px 0 8px 0; }
        p { margin: 0 0 12px 0; }
        a { color: #0033B8; }
        ul { margin: 0 0 12px 0; padding-left: 18px; }
        li { margin-bottom: 6px; }
        </style>
        """
        if let data = (css + html).data(using: .utf8),
           let ns = try? NSAttributedString(data: data, options: [
               .documentType: NSAttributedString.DocumentType.html,
               .characterEncoding: String.Encoding.utf8.rawValue
           ], documentAttributes: nil) {
            return ns
        }
        return NSAttributedString(string: html)
    }
}

/// Read-only UITextView that sizes to its content.
struct HTMLTextView: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = [.link, .phoneNumber]
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) { v.attributedText = text }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 340
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

/// Apple guideline 5.1.1(v): account deletion must be startable inside the app.
/// AtStores handles deletion through support (https://atstores.in/static/delete-account),
/// so the app opens a pre-filled request email, falling back to that page if no mail app is set up.
enum AccountDeletion {
    static let supportEmail = "support@atstores.in"
    static let infoPage = URL(string: "https://atstores.in/static/delete-account")!

    static func request(accountType: String, appName: String, mobile: String, userId: String) {
        let body = """
        Hello AtStores Support,

        Please delete my AtStores account and the personal data associated with it.

        Registered mobile number: \(mobile.isEmpty ? "-" : mobile)
        User ID: \(userId.isEmpty ? "-" : userId)
        Platform: iOS (\(appName))
        Account type: \(accountType)

        Thank you.
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = supportEmail
        comps.queryItems = [URLQueryItem(name: "subject", value: "Account Deletion Request"),
                            URLQueryItem(name: "body", value: body)]
        guard let mail = comps.url else { UIApplication.shared.open(infoPage); return }
        UIApplication.shared.open(mail) { opened in
            if !opened { UIApplication.shared.open(infoPage) }
        }
    }

    static func openInfoPage() { UIApplication.shared.open(infoPage) }
}
