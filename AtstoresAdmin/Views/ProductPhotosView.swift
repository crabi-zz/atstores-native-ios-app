import PhotosUI
import SwiftUI

// MARK: - Product photos (up to 10: 1 main + 9 extra)

/// Lets a store owner add up to `maxPhotos` photos to a product.
/// The first photo is the main image (`thumbnailImage`); the rest are `detailImages`.
/// Photos are compressed and uploaded one per request, so slow mobile data and the
/// server's request size limit are not a problem.
struct ProductPhotosView: View {
    static let maxPhotos = 10

    let product: Product
    @Environment(ToastCenter.self) private var toast

    @State private var mainImage: String?
    @State private var extraImages: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var replaceItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var statusText = ""
    @State private var pendingDelete: String?
    @State private var loaded = false

    private var photos: [String] { (mainImage.map { [$0] } ?? []) + extraImages }
    private var remaining: Int { max(0, Self.maxPhotos - photos.count) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.productName.isEmpty ? "Product Photos" : product.productName)
                        .font(.title3.bold())
                    Text("\(photos.count) / \(Self.maxPhotos) photos · The first photo is the main image")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if photos.isEmpty {
                    Text("No photos yet. Add up to \(Self.maxPhotos) photos so customers can see your product.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                        .multilineTextAlignment(.center)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                            photoTile(url, isMain: index == 0 && mainImage != nil)
                        }
                    }
                }

                if uploading {
                    VStack(alignment: .leading, spacing: 6) {
                        if progress.total > 0 {
                            ProgressView(value: Double(progress.done), total: Double(progress.total))
                        } else {
                            ProgressView()
                        }
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }

                PhotosPicker(selection: $pickerItems,
                             maxSelectionCount: max(1, remaining),
                             selectionBehavior: .ordered,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Text(remaining == 0 ? "MAXIMUM \(Self.maxPhotos) PHOTOS" : "ADD PHOTOS")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(remaining == 0 || uploading ? Color.gray : Theme.primary,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(remaining == 0 || uploading)

                if mainImage != nil {
                    PhotosPicker(selection: $replaceItem, matching: .images, photoLibrary: .shared()) {
                        Text("Replace main photo")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Theme.primary)
                    }
                    .disabled(uploading)
                }
            }
            .padding(16)
        }
        .adminHeader("Product Photos")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            mainImage = product.mainImage
            extraImages = product.detailImages
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            let selected = Array(items.prefix(remaining))
            if items.count > selected.count {
                toast.show("Only \(selected.count) more photo(s) allowed. Extra photos were skipped.", long: true)
            }
            pickerItems = []
            Task { await upload(selected) }
        }
        .onChange(of: replaceItem) { _, item in
            guard let item else { return }
            replaceItem = nil
            Task { await replaceMain(item) }
        }
        .confirmationDialog("Remove photo?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let url = pendingDelete { Task { await remove(url) } }
            }
        } message: {
            Text("This photo will be removed from the product.")
        }
    }

    private func photoTile(_ url: String, isMain: Bool) -> some View {
        ZStack {
            RemoteImage(url: url)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .overlay(alignment: .bottomLeading) {
            if isMain {
                Text("MAIN").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.primary, in: Capsule())
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The main photo is replaced, not removed (the API has no call for that).
            if !isMain {
                Button { pendingDelete = url } label: {
                    Image(systemName: "xmark").font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .padding(6)
                .disabled(uploading)
                .accessibilityLabel("Remove photo")
            }
        }
    }

    // MARK: Upload

    private func upload(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        uploading = true
        progress = (0, items.count)
        defer { uploading = false; progress = (0, 0) }

        var failed = 0
        for (i, item) in items.enumerated() {
            statusText = "Uploading \(i + 1) of \(items.count)…"
            guard let raw = try? await item.loadTransferable(type: Data.self), let jpeg = ImageData.jpeg(raw) else {
                failed += 1; progress.done = i + 1; continue
            }
            // No main image yet: the first photo becomes the main image.
            let ok = mainImage == nil ? await uploadMain(jpeg) : await uploadExtra(jpeg)
            if !ok { failed += 1 }
            progress.done = i + 1
        }
        toast.show(failed == 0 ? "Photos uploaded" : "\(failed) photo(s) failed to upload. Please try again.",
                   long: failed > 0)
    }

    private func replaceMain(_ item: PhotosPickerItem) async {
        uploading = true
        statusText = "Uploading main photo…"
        defer { uploading = false }
        guard let raw = try? await item.loadTransferable(type: Data.self), let jpeg = ImageData.jpeg(raw) else {
            toast.show("Could not read that photo"); return
        }
        let old = mainImage
        if await uploadMain(jpeg) {
            if let u = old.flatMap(URL.init(string:)) { ImageLoader.evict(u) }
            toast.show("Main photo updated")
        }
    }

    private func uploadMain(_ jpeg: Data) async -> Bool {
        guard let r = try? await API.shared.upload("api/store/\(product.productId)/productImage",
                                                   field: "productImage", data: jpeg) else {
            toast.show("Network error during upload"); return false
        }
        guard r.ok else { toast.show(r.errorMessage("Upload failed: \(r.status)"), long: true); return false }
        if let url = Self.urls(from: r.json).first { mainImage = url }
        return true
    }

    private func uploadExtra(_ jpeg: Data) async -> Bool {
        guard let r = try? await API.shared.upload("api/store/product/\(product.productId)/images",
                                                   field: "detailImages", data: jpeg) else {
            toast.show("Network error during upload"); return false
        }
        guard r.ok else { toast.show(r.errorMessage("Upload failed: \(r.status)"), long: true); return false }
        extraImages.append(contentsOf: Self.urls(from: r.json))
        return true
    }

    // MARK: Delete

    private func remove(_ url: String) async {
        pendingDelete = nil
        uploading = true
        statusText = "Removing photo…"
        defer { uploading = false }
        guard let r = try? await API.shared.send(.delete, "api/store/product/\(product.productId)/images",
                                                 query: ["url": url]) else {
            toast.show("Network error"); return
        }
        if r.ok {
            extraImages.removeAll { $0 == url }
        } else {
            toast.show(r.errorMessage("Remove failed: \(r.status)"))
        }
    }

    /// MessageVO `data` is one URL (main image) or a list of URLs (extra images).
    private static func urls(from json: Any?) -> [String] {
        guard let d = json as? JSONDict else { return [] }
        if let s = d["data"] as? String, !s.isEmpty { return [s] }
        if let list = d["data"] as? [Any] { return list.compactMap { $0 as? String }.filter { !$0.isEmpty } }
        return []
    }
}
