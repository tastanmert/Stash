import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Why a file operation failed.
public enum FileOperationError: Error, Equatable, Sendable {
    /// None of the given files can be processed by this operation.
    case unsupportedFiles
    /// The image or PDF could not be read.
    case unreadable(String)
    /// Writing the result failed.
    case writeFailed(String)
    /// An external tool (ditto, zip) exited with an error.
    case toolFailed(String)
    case alreadyProtected
    case noTextFound
}

/// The file actions of the shelf. Everything here is synchronous and UI-free; callers run it off the main actor.
/// Results are written into `directory` (created when missing) unless an operation replaces the originals.
public enum FileOperations {
    // MARK: Archives

    /// Creates a ZIP archive called `name` (".zip" is added) holding `urls`.
    /// With a password the archive is encrypted using `/usr/bin/zip`; otherwise `ditto` keeps Finder metadata.
    public static func zip(_ urls: [URL], name: String, password: String? = nil, in directory: URL) throws -> URL {
        guard !urls.isEmpty else { throw FileOperationError.unsupportedFiles }
        try prepare(directory)
        let fileName = name.hasSuffix(".zip") ? name : name + ".zip"
        let archive = StashPaths.uniqueURL(in: directory, name: fileName)
        if let password, !password.isEmpty {
            // zip stores paths relative to the working directory, so group the files in one folder first.
            let staging = try stage(urls)
            defer { try? FileManager.default.removeItem(at: staging) }
            let names = try FileManager.default.contentsOfDirectory(atPath: staging.path)
            try run("/usr/bin/zip", ["-q", "-r", "-y", "-P", password, archive.path] + names, in: staging)
        } else if urls.count == 1 {
            // Like Finder: a folder goes in as itself, a single file sits at the top without its parent folder.
            let isFolder = (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc"] + (isFolder ? ["--keepParent"] : []) + [urls[0].path, archive.path])
        } else {
            let staging = try stage(urls)
            defer { try? FileManager.default.removeItem(at: staging) }
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, archive.path])
        }
        return archive
    }

    // MARK: Images

    public enum ResizeMode: Equatable, Sendable {
        /// Scale width and height by these percentages.
        case percent(width: Int, height: Int)
        /// Fit inside this box, keeping the aspect ratio; never enlarges.
        case maxPixels(width: Int, height: Int)
    }

    public enum ImageFormat: String, CaseIterable, Sendable {
        case jpeg, png, heic, tiff

        public var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            case .heic: .heic
            case .tiff: .tiff
            }
        }

        public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        /// Whether the encoder honors a lossy quality setting.
        public var isLossy: Bool { self == .jpeg || self == .heic }
    }

    public static func resizeImages(_ urls: [URL], mode: ResizeMode, replacing: Bool = false, in directory: URL) throws -> [URL] {
        try transformImages(urls, replacing: replacing, in: directory) { source, type in
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let size = targetSize(width: image.width, height: image.height, mode: mode)
            return (try scaled(source, to: size), type, nil)
        }
    }

    /// Re-encodes images in `format`. `quality` (0...1) applies to lossy formats.
    public static func convertImages(_ urls: [URL], to format: ImageFormat, quality: Double = 0.85, in directory: URL) throws -> [URL] {
        try transformImages(urls, replacing: false, in: directory) { source, _ in
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return (image, format.type, format.isLossy ? quality : nil)
        }
    }

    /// Makes images smaller. JPEG and HEIC are re-encoded at `quality`; other formats become JPEG
    /// (or HEIC when they have transparency) because lossless formats can't trade quality for size.
    public static func compressImages(_ urls: [URL], quality: Double, replacing: Bool = false, in directory: URL) throws -> [URL] {
        try transformImages(urls, replacing: replacing, in: directory) { source, type in
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            if type.conforms(to: .jpeg) || type.conforms(to: .heic) { return (image, type, quality) }
            return (image, hasAlpha(image) ? .heic : .jpeg, quality)
        }
    }

    /// Writes images without EXIF, GPS, IPTC and other metadata.
    public static func removeMetadata(_ urls: [URL], in directory: URL) throws -> [URL] {
        try transformImages(urls, replacing: false, in: directory) { source, type in
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let lossy = type.conforms(to: .jpeg) || type.conforms(to: .heic)
            return (image, type, lossy ? 0.95 : nil)
        }
    }

    /// Joins images into one PNG, top to bottom (or left to right).
    public static func stitchImages(_ urls: [URL], vertical: Bool = true, in directory: URL) throws -> URL {
        let images = urls.compactMap { url -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard images.count >= 2 else { throw FileOperationError.unsupportedFiles }
        let width = vertical ? images.map(\.width).max()! : images.map(\.width).reduce(0, +)
        let height = vertical ? images.map(\.height).reduce(0, +) : images.map(\.height).max()!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FileOperationError.writeFailed("context") }
        var offset = 0
        for image in images {
            // Core Graphics draws from the bottom left, so the first image goes at the top.
            let rect = vertical
                ? CGRect(x: 0, y: height - offset - image.height, width: image.width, height: image.height)
                : CGRect(x: offset, y: height - image.height, width: image.width, height: image.height)
            context.draw(image, in: rect)
            offset += vertical ? image.height : image.width
        }
        guard let result = context.makeImage() else { throw FileOperationError.writeFailed("stitch") }
        try prepare(directory)
        let base = urls[0].deletingPathExtension().lastPathComponent
        let url = StashPaths.uniqueURL(in: directory, name: base + ".png")
        try write(result, type: .png, quality: nil, properties: nil, to: url)
        return url
    }

    // MARK: PDF

    /// Joins PDFs into one document, in order.
    public static func stitchPDFs(_ urls: [URL], in directory: URL) throws -> URL {
        let documents = urls.compactMap { PDFDocument(url: $0) }
        guard documents.count >= 2 else { throw FileOperationError.unsupportedFiles }
        let merged = PDFDocument()
        for document in documents {
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) }
            }
        }
        try prepare(directory)
        let url = StashPaths.uniqueURL(in: directory, name: urls[0].deletingPathExtension().lastPathComponent + ".pdf")
        guard merged.write(to: url) else { throw FileOperationError.writeFailed(url.lastPathComponent) }
        return url
    }

    /// One PDF with a page per image, each page the size of its image.
    public static func imagesToPDF(_ urls: [URL], in directory: URL) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { continue }
            context.beginPDFPage(nil)
            context.draw(image, in: box)
            context.endPDFPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) { document.insert(page, at: document.pageCount) }
        }
        guard document.pageCount > 0 else { throw FileOperationError.unsupportedFiles }
        try prepare(directory)
        let url = StashPaths.uniqueURL(in: directory, name: urls[0].deletingPathExtension().lastPathComponent + ".pdf")
        guard document.write(to: url) else { throw FileOperationError.writeFailed(url.lastPathComponent) }
        return url
    }

    /// A copy of the PDF that needs `password` to open.
    public static func protectPDF(_ url: URL, password: String, in directory: URL) throws -> URL {
        guard let document = PDFDocument(url: url) else { throw FileOperationError.unreadable(url.lastPathComponent) }
        guard !document.isEncrypted else { throw FileOperationError.alreadyProtected }
        try prepare(directory)
        let output = StashPaths.uniqueURL(in: directory, name: url.lastPathComponent)
        let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard document.write(to: output, withOptions: options) else { throw FileOperationError.writeFailed(output.lastPathComponent) }
        return output
    }

    // MARK: Text

    /// Recognized text of each image, in order; images without text give an empty string.
    public static func recognizeText(in urls: [URL]) throws -> [String] {
        try urls.map { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FileOperationError.unreadable(url.lastPathComponent) }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
    }

    // MARK: Files

    /// Copies or moves files into `destination`, renaming on collisions.
    public static func transfer(_ urls: [URL], to destination: URL, move: Bool) throws -> [URL] {
        try urls.map { url in
            let target = StashPaths.uniqueURL(in: destination, name: url.lastPathComponent)
            if move { try FileManager.default.moveItem(at: url, to: target) } else { try FileManager.default.copyItem(at: url, to: target) }
            return target
        }
    }

    // MARK: Helpers

    static func targetSize(width: Int, height: Int, mode: ResizeMode) -> (width: Int, height: Int) {
        switch mode {
        case let .percent(w, h):
            return (max(1, width * w / 100), max(1, height * h / 100))
        case let .maxPixels(w, h):
            let scale = min(1, Double(w) / Double(width), Double(h) / Double(height))
            return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
        }
    }

    private static func scaled(_ source: CGImageSource, to size: (width: Int, height: Int)) throws -> CGImage {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FileOperationError.unreadable("image") }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FileOperationError.writeFailed("context") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let result = context.makeImage() else { throw FileOperationError.writeFailed("resize") }
        return result
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Runs `transform` on every readable image and writes the result next to the original or into `directory`.
    private static func transformImages(_ urls: [URL], replacing: Bool, in directory: URL,
                                        _ transform: (CGImageSource, UTType) throws -> (CGImage, UTType, Double?)?) throws -> [URL] {
        var results: [URL] = []
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String), type.conforms(to: .image),
                  let (image, outType, quality) = try transform(source, type) else { continue }
            // Keep the orientation and color profile; everything else is dropped by writing only these keys.
            let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            var properties: [CFString: Any] = [:]
            if let orientation = original[kCGImagePropertyOrientation] { properties[kCGImagePropertyOrientation] = orientation }
            let ext = outType.preferredFilenameExtension ?? url.pathExtension
            let name = url.deletingPathExtension().lastPathComponent + "." + ext
            let output: URL
            if replacing {
                output = url.deletingLastPathComponent().appending(path: name)
            } else {
                try prepare(directory)
                output = StashPaths.uniqueURL(in: directory, name: name)
            }
            try write(image, type: outType, quality: quality, properties: properties, to: output)
            if replacing, output != url { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            results.append(output)
        }
        guard !results.isEmpty else { throw FileOperationError.unsupportedFiles }
        return results
    }

    static func write(_ image: CGImage, type: UTType, quality: Double?, properties: [CFString: Any]?, to url: URL) throws {
        // Write next to the target first so replacing an original never leaves a half-written file.
        let temporary = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).\(url.pathExtension)")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type.identifier as CFString, 1, nil) else {
            throw FileOperationError.writeFailed(url.lastPathComponent)
        }
        var options = properties ?? [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileOperationError.writeFailed(url.lastPathComponent) }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Copies files into a fresh temporary folder (as clones on APFS, so it's cheap).
    private static func stage(_ urls: [URL]) throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appending(path: "stash-\(UUID().uuidString)", directoryHint: .isDirectory)
        try prepare(staging)
        for url in urls {
            try FileManager.default.copyItem(at: url, to: StashPaths.uniqueURL(in: staging, name: url.lastPathComponent))
        }
        return staging
    }

    private static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FileOperationError.toolFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
