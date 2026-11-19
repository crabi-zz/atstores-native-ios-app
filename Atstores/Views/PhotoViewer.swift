import SwiftUI
import UIKit

// MARK: - Full-screen photo viewer with pinch zoom

/// Full-screen product photos: swipe between photos, pinch or double-tap to zoom,
/// drag to move while zoomed, swipe down (when not zoomed) or tap ✕ to close.
struct PhotoViewer: View {
    let urls: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    @State private var zoomed = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragOffset) / 400, 0.6))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(url: url, isZoomed: i == index ? $zoomed : .constant(false))
                        .tag(i)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .simultaneousGesture(
                // Swipe down to close, only when the photo is not zoomed in.
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard !zoomed, abs(v.translation.height) > abs(v.translation.width) else { return }
                        dragOffset = v.translation.height
                    }
                    .onEnded { v in
                        if !zoomed, abs(v.translation.height) > 140 {
                            dismiss()
                        } else {
                            withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                        }
                    }
            )
            .onChange(of: index) { _, _ in zoomed = false }

            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(index + 1) / \(urls.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                if !zoomed {
                    Text("Pinch or double-tap to zoom")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 12)
                }
            }
            .opacity(abs(dragOffset) > 10 ? 0 : 1)
        }
        .statusBarHidden()
    }
}

/// UIScrollView-backed image: native pinch zoom (1×–4×), panning while zoomed,
/// and double-tap to zoom in on the tapped point / back out.
private struct ZoomableImage: UIViewRepresentable {
    let url: String
    @Binding var isZoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isZoomed: $isZoomed) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        scroll.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        context.coordinator.load(url, spinner: spinner)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.isZoomed = $isZoomed
        // Reset when another photo becomes current.
        if !isZoomed, scroll.zoomScale != 1 {
            scroll.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var isZoomed: Binding<Bool>
        weak var imageView: UIImageView?

        init(isZoomed: Binding<Bool>) { self.isZoomed = isZoomed }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomedNow = scrollView.zoomScale > 1.01
            if isZoomed.wrappedValue != zoomedNow { isZoomed.wrappedValue = zoomedNow }
        }

        @objc func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = g.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }

        func load(_ urlString: String, spinner: UIActivityIndicatorView) {
            let clean = urlString.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: clean) ?? clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init) else {
                spinner.stopAnimating()
                imageView?.image = UIImage(systemName: "photo")
                imageView?.tintColor = .gray
                return
            }
            // Show the cached (smaller) copy at once, then swap in the full-size photo for sharp zooming.
            if let cached = ImageLoader.cached(url) {
                imageView?.image = cached
                spinner.stopAnimating()
            }
            Task { [weak self] in
                let full: UIImage?
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    full = UIImage(data: data)
                } else {
                    full = await ImageLoader.load(url)
                }
                await MainActor.run {
                    spinner.stopAnimating()
                    if let full { self?.imageView?.image = full }
                    else if self?.imageView?.image == nil {
                        self?.imageView?.image = UIImage(systemName: "photo")
                        self?.imageView?.tintColor = .gray
                    }
                }
            }
        }
    }
}
