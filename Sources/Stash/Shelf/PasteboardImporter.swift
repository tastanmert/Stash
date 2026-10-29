import AppKit
import UniformTypeIdentifiers
import StashCore

/// Turns whatever is on a pasteboard (a drag, the clipboard) into shelf items.
enum PasteboardImporter {
    static var paths = StashPaths.standard

    /// Reads items synchronously where possible; file promises arrive later through `promised`.
    static func items(from pb: NSPasteboard, promised: @escaping @MainActor ([ShelfItem]) -> Void) -> [ShelfItem] {
        try? paths.ensureDirectories()

        // 1. Real files.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map { ShelfItem(url: $0) }
        }

        // 2. File promises (Mail attachments, Photos, browsers).
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            let destination = paths.temporary.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { url, error in
                    guard error == nil else { return }
                    MainActor.assumeIsolated { promised([ShelfItem(url: url, isTemporary: true)]) }
                }
            }
            return []
        }

        // 3. Images as raw data.
        if let image = NSImage(pasteboard: pb), pb.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]) != nil,
           let url = writeImage(image, data: pb) {
            return [ShelfItem(url: url, isTemporary: true)]
        }

        // 4. Web links.
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let link = urls.first, !link.isFileURL {
            let title = pb.string(forType: NSPasteboard.PasteboardType("public.url-name")) ?? link.host() ?? "Link"
            if let url = writeWebloc(link, title: title) { return [ShelfItem(url: url, link: link, isTemporary: true)] }
        }

        // 5. Text (rich text kept as RTF unless "Convert text to plain text" is on).
        if let string = pb.string(forType: .string), !string.isEmpty {
            if !Prefs.bool(Pref.plainText), let rtf = pb.data(forType: .rtf),
               let url = write(rtf, name: textFileName(string, ext: "rtf")) {
                return [ShelfItem(url: url, text: string, isTemporary: true)]
            }
            if let url = write(Data(string.utf8), name: textFileName(string, ext: "txt")) {
                return [ShelfItem(url: url, text: string, isTemporary: true)]
            }
        }
        return []
    }

    static func canRead(_ pb: NSPasteboard) -> Bool {
        pb.availableType(from: acceptedTypes) != nil
    }

    static let acceptedTypes: [NSPasteboard.PasteboardType] = {
        let base: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff, .rtf, .string, NSPasteboard.PasteboardType("public.jpeg")]
        let promises: [NSPasteboard.PasteboardType] = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return base + promises
    }()

    // MARK: Writing raw data to files

    private static func write(_ data: Data, name: String) -> URL? {
        let url = StashPaths.uniqueURL(in: paths.temporary, name: name)
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private static func writeImage(_ image: NSImage, data pb: NSPasteboard) -> URL? {
        let stamp = Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        if let png = pb.data(forType: .png) { return write(png, name: "\(L("Image")) \(stamp).png") }
        if let jpeg = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { return write(jpeg, name: "\(L("Image")) \(stamp).jpg") }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return write(png, name: "\(L("Image")) \(stamp).png")
    }

    private static func writeWebloc(_ link: URL, title: String) -> URL? {
        let plist: [String: String] = ["URL": link.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
        return write(data, name: sanitized(title) + ".webloc")
    }

    /// A file name taken from the first words of the text.
    static func textFileName(_ text: String, ext: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var name = sanitized(firstLine)
        if name.count > 40 { name = String(name.prefix(40)).trimmingCharacters(in: .whitespaces) }
        return (name.isEmpty ? L("Text") : name) + ".\(ext)"
    }

    private static func sanitized(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
