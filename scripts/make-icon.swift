// Renders the app icon: usage `swift scripts/make-icon.swift <out.png>`
// Two files tucked into a stitched pocket: you stash things away to grab them later.
import AppKit

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ path: CGPath, _ colors: [CGColor], top: CGFloat, bottom: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: top), end: CGPoint(x: 512, y: bottom),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func fill(_ path: CGPath, _ color: CGColor, shadow: CGFloat = 0, offset: CGFloat = -10, darkness: CGFloat = 0.28) {
    ctx.saveGState()
    if shadow > 0 { ctx.setShadow(offset: CGSize(width: 0, height: offset), blur: shadow, color: rgb(0, darkness)) }
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

/// A file: a rounded page with three lines of text, tilted by `angle` degrees.
func file(center: CGPoint, angle: CGFloat, color: CGColor, lines: CGColor) {
    let width: CGFloat = 270, height: CGFloat = 340
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let page = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    fill(rounded(page, 36), color, shadow: 24)
    for i in 0..<3 {
        let lineWidth = width * (i == 2 ? 0.36 : 0.6)
        let y = page.maxY - 78 - CGFloat(i) * 46
        fill(rounded(CGRect(x: page.minX + 50, y: y, width: lineWidth, height: 20), 10), lines)
    }
    ctx.restoreGState()
}

// macOS icon body: 824 pt squircle centred on the 1024 canvas, a warm cream with a soft top light.
let body = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
fill(body, rgb(0xFFE3C6), shadow: 28, offset: -12, darkness: 0.35)
gradient(body, [rgb(0xFFF6EB), rgb(0xFFDDBC)], top: 924, bottom: 100)

// The files, behind the pocket.
file(center: CGPoint(x: 405, y: 590), angle: -10, color: rgb(0x4F7CFF), lines: rgb(0xFFFFFF, 0.75))
file(center: CGPoint(x: 580, y: 610), angle: 8, color: rgb(0xFFFFFF), lines: rgb(0xC5CCDA))

// The pocket: straight top, rounded point at the bottom.
func pocketPath(inset: CGFloat) -> CGPath {
    let left = 222 + inset, right = 802 - inset, top = 560 - inset
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: top))
    path.addLine(to: CGPoint(x: right, y: top))
    path.addLine(to: CGPoint(x: right, y: 330 + inset * 0.2))
    path.addQuadCurve(to: CGPoint(x: 512, y: 182 + inset), control: CGPoint(x: right, y: 205 + inset))
    path.addQuadCurve(to: CGPoint(x: left, y: 330 + inset * 0.2), control: CGPoint(x: left, y: 205 + inset))
    path.closeSubpath()
    return path
}
let pocket = pocketPath(inset: 0)
fill(pocket, rgb(0xF0532F), shadow: 34, offset: -16, darkness: 0.3)
gradient(pocket, [rgb(0xFF8C5E), rgb(0xEC4A2C)], top: 560, bottom: 182)
// The folded hem along the opening casts a little shade on the pocket.
ctx.saveGState()
ctx.addPath(pocket)
ctx.clip()
gradient(rounded(CGRect(x: 200, y: 516, width: 624, height: 44), 0), [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0.04)], top: 560, bottom: 516)
fill(rounded(CGRect(x: 200, y: 508, width: 624, height: 8), 0), rgb(0x9E2A12, 0.18))
ctx.restoreGState()
// Stitching.
ctx.saveGState()
ctx.addPath(pocketPath(inset: 34))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.75))
ctx.setLineWidth(10)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [24, 22])
ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))
