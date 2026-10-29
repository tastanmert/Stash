import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers
import StashCore

/// One thing on a shelf. Everything is backed by a file so it can be dragged anywhere;
/// text and links also keep their original value for apps that want a string.
struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var text: String?
    var link: URL?
    /// The file lives in Stash's temporary folder (created from raw drag data).
    var isTemporary = false

    var name: String { url.lastPathComponent }
    var displayName: String { FileManager.default.displayName(atPath: url.path) }

    var type: UTType? { (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType }
    var isImage: Bool { type?.conforms(to: .image) ?? false }
    var isFolder: Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var titleKind: ShelfTitle.Kind {
        if isImage { return .image }
        if isFolder { return .folder }
        if text != nil || (type?.conforms(to: .plainText) ?? false) { return .text }
        return .other
    }

    var size: Int64? {
        if isFolder { return nil }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Thumbnails for shelf items, cached by URL.
@Observable
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private(set) var images: [URL: NSImage] = [:]
    /// Bookkeeping only; it must not be observed, or every lookup from a view body would trigger another update.
    @ObservationIgnored private var requested: Set<URL> = []
    @ObservationIgnored private var pixelSizes: [URL: String] = [:]

    func image(for item: ShelfItem, size: CGFloat) -> NSImage {
        if let cached = images[item.url] { return cached }
        load(item.url, size: max(size, 128))
        return item.icon
    }

    private func load(_ url: URL, size: CGFloat) {
        guard requested.insert(url).inserted else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        // Finder's icon look: documents become a rounded page, pictures get rounded corners and a hairline.
        request.iconMode = true
        Task {
            guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
            images[url] = rep.nsImage
        }
    }

    /// "1520x1626" for images; read from the file's header, nothing is decoded.
    func dimensions(for item: ShelfItem) -> String? {
        guard item.isImage else { return nil }
        if let cached = pixelSizes[item.url] { return cached }
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let text = "\(width)x\(height)"
        pixelSizes[item.url] = text
        return text
    }

    func forget(_ url: URL) {
        pixelSizes[url] = nil
        images[url] = nil
        requested.remove(url)
    }
}
