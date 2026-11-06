import SwiftUI
import UIKit

enum Theme {
    static let primary = Color(red: 1.0, green: 0.757, blue: 0.027) // #FFC107
    static let open = Color(red: 0.106, green: 0.557, blue: 0.243)  // #1B8E3E
    static let closed = Color(red: 0.957, green: 0.263, blue: 0.212) // #F44336
    static let heart = Color(red: 0.914, green: 0.118, blue: 0.388) // #E91E63
    static let lightGray = Color(red: 0.96, green: 0.96, blue: 0.96)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

nonisolated enum Format {
    static func price(_ v: Double) -> String {
        v == v.rounded() ? "₹\(Int(v))" : "₹" + String(format: "%.2f", v)
    }

    static func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_IN")
        return "₹" + (f.string(from: NSNumber(value: v)) ?? "\(Int(v))")
    }

    static func distance(_ km: Double) -> String { km > 0 ? String(format: "%.1f km", km) : "Nearby" }

    /// "Nearby" / "450 m" / "2.3 km".
    static func km(_ km: Double) -> String {
        if km < 0.05 { return "Nearby" }
        if km < 1 { return "\(Int((km * 1000 / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", km)
    }

    static func rating(_ avg: Double, _ count: Int) -> String {
        count > 0 ? String(format: "%.1f (%d)", avg, count) : String(format: "%.1f", avg)
    }

    static func duration(_ mins: Int) -> String {
        mins >= 60 ? "\(mins / 60) hr \(mins % 60) mins" : "\(mins) mins"
    }

    static func discountText(_ percentOff: String?, sell: Double, cut: Double) -> String {
        if let p = percentOff, p.lowercased() != "null" {
            let cleaned = p.replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "OFF", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if let d = Double(cleaned), d > 0 { return "\(Int(d.rounded()))% OFF" }
        }
        if cut > sell, sell > 0 {
            let r = Int(((cut - sell) / cut * 100).rounded())
            if r > 0 { return "\(r)% OFF" }
        }
        return "NEW"
    }

    static let slotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "hh:mm a"
        return f
    }()

    /// "22:00" or "10:23:00" -> "10:00 PM" / "10:23 AM"; already-formatted values pass through.
    static func hour(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.uppercased().hasSuffix("AM") || s.uppercased().hasSuffix("PM") { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["HH:mm:ss", "HH:mm", "H:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return slotFormatter.string(from: d) }
        }
        return s
    }

    /// Minutes since midnight for "22:00", "10:23:00" or "09:00 PM"; nil when unparseable.
    static func minutes(_ raw: String?) -> Int? {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["HH:mm:ss", "HH:mm", "H:mm", "hh:mm a", "h:mm a"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        }
        return nil
    }

    static func endTime(start: String, durationMins: Int) -> String {
        guard let d = slotFormatter.date(from: start) else { return start }
        return slotFormatter.string(from: d.addingTimeInterval(Double(durationMins) * 60))
    }

    static func notificationDate(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Just now" }
        guard let d = DateParse.parse(raw) else { return raw }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM-yyyy | hh:mm a"
        return f.string(from: d)
    }

    static func isoNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: Date())
    }
}

nonisolated extension String {
    /// "NEW YEAR OFFER" -> "New Year Offer"; leaves normal casing and short codes alone.
    var displayCased: String {
        let letters = filter(\.isLetter)
        guard letters.count > 4, self == uppercased() else { return self }
        return capitalized
    }
}

nonisolated enum DateParse {
    static func parse(_ raw: String, extraFormats: [String] = []) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.lowercased() != "null" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in extraFormats + ["yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        // Fall back to the leading date part, e.g. "2026-10-15T23:59:59.123456Z".
        if s.count >= 10 {
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: String(s.prefix(10)))
        }
        return nil
    }
}

/// Replaces StoreActionHelper: WhatsApp, website, maps, call, share.
enum StoreActions {
    @discardableResult
    static func open(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    static func whatsApp(_ phone: String?, toast: ToastCenter) {
        guard var p = phone, !p.isEmpty else { toast.show("WhatsApp number not available"); return }
        p = p.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: " ", with: "")
        if p.count == 10 { p = "91" + p }
        open("https://wa.me/\(p)")
    }

    static func website(_ site: String?, toast: ToastCenter) {
        guard var s = site, !s.isEmpty else { toast.show("Website not available"); return }
        if !s.hasPrefix("http") { s = "https://" + s }
        if !open(s) { toast.show("Unable to open website") }
    }

    static func location(_ address: String?, toast: ToastCenter) {
        guard let a = address, !a.isEmpty,
              let q = a.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            toast.show("Location not available"); return
        }
        open("https://maps.apple.com/?q=\(q)")
    }

    static func call(_ phone: String?, toast: ToastCenter) {
        guard let p = phone?.replacingOccurrences(of: " ", with: ""), !p.isEmpty else {
            toast.show("Phone number not available"); return
        }
        if !open("tel:\(p)") { toast.show("Unable to make call") }
    }

    static func email(_ address: String, subject: String) {
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        open("mailto:\(address)?subject=\(s)")
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

/// Converts HTML from the content API into styled text (spacing, headings and bullets preserved).
enum HTMLText {
    static func styled(_ html: String) -> NSAttributedString {
        let css = """
        <style>
        body { font-family: -apple-system; font-size: 15px; line-height: 1.55; color: #3A3A3C; }
        h1, h2 { font-size: 21px; color: #111; margin: 0 0 10px 0; }
        h3 { font-size: 16px; color: #111; margin: 18px 0 6px 0; }
        p { margin: 0 0 12px 0; }
        b, strong { color: #111; }
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

/// Read-only UITextView that sizes to its content, so lists and paragraph spacing render properly.
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
        let width = proposal.width ?? UIScreen.main.bounds.width - 40
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
