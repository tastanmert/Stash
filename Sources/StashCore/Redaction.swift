import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

extension FileOperations {
    /// The image as it is shown (EXIF orientation applied), so detected boxes and painted areas line up with what you see.
    public static func orientedImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw FileOperationError.unreadable(url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileOperationError.unreadable(url.lastPathComponent)
        }
        return image
    }

    /// Lines of text in the image, in unit coordinates with the origin at the top left.
    public static func textBoxes(in image: CGImage) throws -> [CGRect] {
        // Only the boxes matter, not the words, so the fast recognizer is enough; the accurate one
        // can stall for a minute while its language models load.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    /// Paints `rects` (unit coordinates, origin at the top left) over the image in `color`.
    /// The result replaces the original, or goes into `directory` under the same name.
    public static func redact(_ url: URL, rects: [CGRect], color: CGColor, replacing: Bool, in directory: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String) else {
            throw FileOperationError.unreadable(url.lastPathComponent)
        }
        let image = try orientedImage(at: url)
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FileOperationError.writeFailed(url.lastPathComponent)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(color.copy(alpha: 1) ?? color)
        for rect in rects {
            // CoreGraphics counts y from the bottom.
            context.fill(CGRect(x: rect.minX * Double(width), y: (1 - rect.maxY) * Double(height),
                                width: rect.width * Double(width), height: rect.height * Double(height)))
        }
        guard let result = context.makeImage() else { throw FileOperationError.writeFailed(url.lastPathComponent) }
        let output: URL
        if replacing {
            output = url
        } else {
            try prepare(directory)
            output = StashPaths.uniqueURL(in: directory, name: url.lastPathComponent)
        }
        // The pixels are already upright, so no orientation is written.
        let lossy = type.conforms(to: .jpeg) || type.conforms(to: .heic)
        try write(result, type: type, quality: lossy ? 0.95 : nil, properties: nil, to: output)
        return output
    }
}
