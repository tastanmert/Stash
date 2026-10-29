import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import StashCore

struct RedactionTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "stash-redact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// A white PNG, with a line of black text when `text` is given.
    private func image(_ name: String, width: Int = 400, height: Int = 200, text: String? = nil) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let text {
            let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
            let string = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font,
                                                                       .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 20, y: 120)
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }
        let url = dir.appending(path: name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The red channel of the pixel at (x, y), counted from the top left.
    private func red(_ url: URL, x: Int, y: Int) throws -> UInt8 {
        let image = try FileOperations.orientedImage(at: url)
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return bytes[(y * image.width + x) * 4]
    }

    @Test func `redacting paints the boxes and keeps the original`() throws {
        let url = try image("plain.png")
        let out = dir.appending(path: "out")
        let result = try FileOperations.redact(url, rects: [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)],
                                               color: CGColor(gray: 0, alpha: 1), replacing: false, in: out)
        #expect(result.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
        #expect(try red(result, x: 10, y: 10) == 0)      // top left is inside the box
        #expect(try red(result, x: 390, y: 190) == 255)  // bottom right is not
        #expect(try red(url, x: 10, y: 10) == 255)       // the original is untouched
    }

    @Test func `replacing rewrites the original`() throws {
        let url = try image("replace.png")
        let result = try FileOperations.redact(url, rects: [CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)],
                                               color: CGColor(gray: 0, alpha: 1), replacing: true, in: dir)
        #expect(result == url)
        #expect(try red(url, x: 390, y: 190) == 0)
    }

    @Test func `text boxes are found where the text is`() throws {
        let url = try image("text.png", text: "Secret Number 12345")
        let boxes = try FileOperations.textBoxes(in: try FileOperations.orientedImage(at: url))
        #expect(boxes.count == 1)
        // The baseline is 120 px from the bottom of a 200 px image, so the text sits in the upper half.
        #expect(boxes.first.map { $0.minY < 0.5 && $0.minX < 0.2 } == true)
    }
}
