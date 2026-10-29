import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import StashCore

struct FileOperationsTests {
    let dir: URL
    let out: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "stash-ops-\(UUID().uuidString)")
        out = dir.appending(path: "out")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// A solid-color image file.
    private func image(_ name: String, width: Int, height: Int, type: UTType = .png, gps: Bool = false) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = dir.appending(path: name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = gps ? [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0, kCGImagePropertyGPSLatitudeRef: "N"]] : [:]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func size(_ url: URL) -> (Int, Int) {
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil) as! [CFString: Any]
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
    }

    private func pdf(_ name: String, pages: Int) throws -> URL {
        let url = dir.appending(path: name)
        var box = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return url
    }

    @Test func `zip archives one or many files`() throws {
        let a = try image("a.png", width: 4, height: 4)
        let b = try image("b.png", width: 4, height: 4)
        let single = try FileOperations.zip([a], name: "a", in: out)
        let many = try FileOperations.zip([a, b], name: "Archive", in: out)
        #expect(single.lastPathComponent == "a.zip")
        #expect(many.lastPathComponent == "Archive.zip")
        #expect(FileManager.default.fileExists(atPath: many.path))
        // Like Finder's Compress: the files sit at the top of the archive, without their folder.
        #expect(try entries(single) == ["a.png"])
        #expect(try entries(many) == ["a.png", "b.png"])
    }

    @Test func `zipping a folder keeps the folder`() throws {
        let folder = dir.appending(path: "Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "x.txt"))
        let archive = try FileOperations.zip([folder], name: "Photos", in: out)
        #expect(try entries(archive) == ["Photos/", "Photos/x.txt"])
    }

    /// The archive's entries, without the __MACOSX metadata that Finder's archives also carry.
    private func entries(_ archive: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zipinfo")
        process.arguments = ["-1", archive.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("__MACOSX") }.sorted()
    }

    @Test func `password zip is encrypted`() throws {
        let a = try image("a.png", width: 4, height: 4)
        let archive = try FileOperations.zip([a], name: "secret", password: "abc123", in: out)
        // Bit 0 of the general purpose flag in the first local header marks encryption.
        let data = try Data(contentsOf: archive)
        #expect(data[6] & 1 == 1)
    }

    @Test func `resize by percent and by max pixels`() throws {
        let a = try image("a.png", width: 400, height: 200)
        let half = try FileOperations.resizeImages([a], mode: .percent(width: 50, height: 50), in: out)
        #expect(size(half[0]) == (200, 100))
        let boxed = try FileOperations.resizeImages([a], mode: .maxPixels(width: 100, height: 100), in: out)
        #expect(size(boxed[0]) == (100, 50))
        #expect(size(a) == (400, 200))
    }

    @Test func `max pixels never enlarges`() {
        let target = FileOperations.targetSize(width: 50, height: 40, mode: .maxPixels(width: 500, height: 500))
        #expect(target == (50, 40))
    }

    @Test func `resize can replace the original`() throws {
        let a = try image("a.png", width: 400, height: 200)
        let result = try FileOperations.resizeImages([a], mode: .percent(width: 25, height: 25), replacing: true, in: out)
        #expect(result == [a])
        #expect(size(a) == (100, 50))
    }

    @Test func `convert changes format and extension`() throws {
        let a = try image("a.png", width: 10, height: 10)
        let result = try FileOperations.convertImages([a], to: .jpeg, in: out)
        #expect(result[0].pathExtension == "jpeg" || result[0].pathExtension == "jpg")
        let type = CGImageSourceGetType(CGImageSourceCreateWithURL(result[0] as CFURL, nil)!)! as String
        #expect(type == UTType.jpeg.identifier)
    }

    @Test func `compress turns opaque png into jpeg`() throws {
        let a = try image("a.png", width: 300, height: 300)
        let result = try FileOperations.compressImages([a], quality: 0.3, in: out)
        let type = CGImageSourceGetType(CGImageSourceCreateWithURL(result[0] as CFURL, nil)!)! as String
        #expect(type == UTType.jpeg.identifier)
    }

    @Test func `remove metadata drops gps`() throws {
        let a = try image("a.jpg", width: 10, height: 10, type: .jpeg, gps: true)
        let before = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(a as CFURL, nil)!, 0, nil) as! [CFString: Any]
        #expect(before[kCGImagePropertyGPSDictionary] != nil)
        let result = try FileOperations.removeMetadata([a], in: out)
        let after = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(result[0] as CFURL, nil)!, 0, nil) as! [CFString: Any]
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func `stitch images stacks them`() throws {
        let a = try image("a.png", width: 100, height: 40)
        let b = try image("b.png", width: 60, height: 30)
        let result = try FileOperations.stitchImages([a, b], in: out)
        #expect(size(result) == (100, 70))
    }

    @Test func `non images are rejected`() throws {
        let text = dir.appending(path: "a.txt")
        try Data("hi".utf8).write(to: text)
        #expect(throws: FileOperationError.unsupportedFiles) { try FileOperations.resizeImages([text], mode: .percent(width: 50, height: 50), in: out) }
    }

    @Test func `stitch pdfs keeps every page`() throws {
        let merged = try FileOperations.stitchPDFs([try pdf("a.pdf", pages: 2), try pdf("b.pdf", pages: 3)], in: out)
        #expect(PDFDocument(url: merged)?.pageCount == 5)
    }

    @Test func `images to pdf makes a page per image`() throws {
        let result = try FileOperations.imagesToPDF([try image("a.png", width: 20, height: 20), try image("b.png", width: 30, height: 10)], in: out)
        #expect(PDFDocument(url: result)?.pageCount == 2)
    }

    @Test func `protected pdf needs the password`() throws {
        let result = try FileOperations.protectPDF(try pdf("a.pdf", pages: 1), password: "secret", in: out)
        let document = try #require(PDFDocument(url: result))
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: "secret"))
        #expect(throws: FileOperationError.alreadyProtected) { try FileOperations.protectPDF(result, password: "x", in: out) }
    }

    @Test func `copy keeps originals and renames collisions`() throws {
        let a = try image("a.png", width: 4, height: 4)
        let target = dir.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let first = try FileOperations.transfer([a], to: target, move: false)
        let second = try FileOperations.transfer([a], to: target, move: false)
        #expect(first[0].lastPathComponent == "a.png")
        #expect(second[0].lastPathComponent == "a 2.png")
        #expect(FileManager.default.fileExists(atPath: a.path))
    }
}
