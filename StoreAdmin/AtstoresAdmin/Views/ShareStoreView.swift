import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// "Share My Store": the store's QR code, a printable QR poster, and one-tap WhatsApp / link sharing,
/// so store owners can bring their own customers to AtStores.
struct ShareStoreView: View {
    let storeId: Int
    let storeName: String

    @Environment(ToastCenter.self) private var toast
    @State private var poster: UIImage?

    private var storeURL: URL { URL(string: "https://atstores.in/storefront?storeId=\(storeId)")! }
    private var shareMessage: String {
        StoreActions.storeShareMessage(customerName: nil, storeName: storeName, storeId: storeId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Text(storeName).font(.title3.bold()).multilineTextAlignment(.center)
                    Text("Customers scan this to open your store on AtStores")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let qr = QRCode.image(for: storeURL.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.primary.opacity(0.15)))
                            .accessibilityLabel("QR code for \(storeName)")
                    }
                    HStack(spacing: 8) {
                        Text(storeURL.absoluteString)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Button {
                            UIPasteboard.general.string = storeURL.absoluteString
                            toast.show("Store link copied")
                        } label: {
                            Image(systemName: "doc.on.doc").font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("Copy store link")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.lightGray, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                VStack(spacing: 10) {
                    Button { shareOnWhatsApp() } label: {
                        Label("Share on WhatsApp", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareButtonStyle(color: Color(hex: 0x25D366)))

                    ShareLink(item: storeURL, message: Text(shareMessage)) {
                        Label("Share Store Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareButtonStyle(color: Theme.primary))

                    if let poster {
                        ShareLink(item: Image(uiImage: poster),
                                  preview: SharePreview("\(storeName) – AtStores QR poster", image: Image(uiImage: poster))) {
                            Label("Save or Print QR Poster", systemImage: "printer.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ShareButtonStyle(color: Theme.primaryDark))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Get more customers").font(.headline)
                    tip("printer", "Print the QR poster and keep it at your billing counter or entrance.")
                    tip("message", "Send your store link to your customers' WhatsApp and your status.")
                    tip("tag", "Add an app-only offer so customers have a reason to download AtStores.")
                    tip("chart.bar", "Watch the Visitors tab to see how many people open your store.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                if let poster {
                    VStack(spacing: 8) {
                        Text("Poster preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Image(uiImage: poster)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(16)
        }
        .adminHeader("Share My Store")
        .task { renderPoster() }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.primary).frame(width: 22)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shareOnWhatsApp() {
        let text = shareMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // No phone number: WhatsApp lets the owner pick contacts, groups or their status.
        if !StoreActions.open("https://wa.me/?text=\(text)") { toast.show("Unable to open WhatsApp") }
    }

    private func renderPoster() {
        guard poster == nil, let qr = QRCode.image(for: storeURL.absoluteString) else { return }
        let renderer = ImageRenderer(content: StorePoster(storeName: storeName, qr: qr))
        renderer.scale = 3   // 1080 × 1620 px: sharp enough to print at A5 / A4
        poster = renderer.uiImage
    }
}

/// Printable poster: AtStores branding, store name, big QR code and download line.
private struct StorePoster: View {
    let storeName: String
    let qr: UIImage

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image("BagMark").resizable().scaledToFit().frame(height: 46)
                    (Text("At").foregroundStyle(Theme.secondary) + Text("Stores").foregroundStyle(.white))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                }
                Text("FIND STORES NEAR YOU").font(.system(size: 12, weight: .semibold)).kerning(1.5)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(Theme.primary)

            VStack(spacing: 16) {
                Text(storeName)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.primaryDark)
                Text("Scan to see our offers\n& book on AtStores")
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black.opacity(0.75))
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(12)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.secondary, lineWidth: 4))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)

            Spacer(minLength: 0)

            Text("Download the AtStores app on the App Store & Google Play")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.primaryDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Theme.secondary)
        }
        .frame(width: 360, height: 540)
        .background(Color.white)
    }
}

private struct ShareButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

enum QRCode {
    /// Crisp QR image for `text` (scaled up without smoothing).
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
