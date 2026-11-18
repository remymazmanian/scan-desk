import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import ScanKit

/// Generated test images, so the repo never needs real scans.
enum Fixtures {
    /// The FF-680W feeder background as measured (light gray-blue); see PROBE.md.
    static let scannerBackground = (r: 218, g: 226, b: 231)

    struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static func context(width: Int, height: Int, gray: Bool = false) -> CGContext {
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: info)!
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// A busy, colorful "picture": gradient sky plus many random discs.
    static func picture(width: Int, height: Int, seed: UInt64 = 7) -> CGImage {
        let ctx = context(width: width, height: height)
        let colors = [rgb(40, 90, 160), rgb(230, 180, 120)] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        var rng = RNG(state: seed)
        for _ in 0..<60 {
            ctx.setFillColor(rgb(Int(rng.next() * 255), Int(rng.next() * 255), Int(rng.next() * 255)))
            let d = CGFloat(rng.next()) * CGFloat(width) * 0.25 + 10
            ctx.fillEllipse(in: CGRect(x: CGFloat(rng.next()) * CGFloat(width), y: CGFloat(rng.next()) * CGFloat(height), width: d, height: d))
        }
        return ctx.makeImage()!
    }

    /// Plain white photo paper, optionally with a short handwritten-style note.
    static func back(width: Int, height: Int, note: Bool = false) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(rgb(250, 250, 248))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if note {
            ctx.setStrokeColor(rgb(30, 40, 120))
            ctx.setLineWidth(CGFloat(width) / 180)
            var rng = RNG(state: 3)
            for line in 0..<3 {
                let y = CGFloat(height) * (0.75 - CGFloat(line) * 0.08)
                ctx.move(to: CGPoint(x: CGFloat(width) * 0.1, y: y))
                for i in 1...40 {
                    let x = CGFloat(width) * (0.1 + 0.7 * CGFloat(i) / 40)
                    ctx.addLine(to: CGPoint(x: x, y: y + CGFloat(rng.next() - 0.5) * CGFloat(height) * 0.03))
                }
                ctx.strokePath()
            }
        }
        return ctx.makeImage()!
    }

    /// A full Letter-size feeder frame the way the driver returns it without auto size:
    /// the print near the top, scanner background beside it, white padding after the paper end.
    static func uncroppedFrame(dpi: Int, print: CGImage, printInches: CGSize, paperEndInches: Double) -> CGImage {
        let w = Int(8.5 * Double(dpi)), h = 11 * dpi
        let ctx = context(width: w, height: h)
        ctx.setFillColor(rgb(255, 255, 255))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let bgHeight = CGFloat(paperEndInches) * CGFloat(dpi)
        ctx.setFillColor(rgb(scannerBackground.r, scannerBackground.g, scannerBackground.b))
        ctx.fill(CGRect(x: 0, y: CGFloat(h) - bgHeight, width: CGFloat(w), height: bgHeight))
        let pw = printInches.width * CGFloat(dpi), ph = printInches.height * CGFloat(dpi)
        let rect = CGRect(x: (CGFloat(w) - pw) / 2, y: CGFloat(h) - ph - CGFloat(dpi) * 0.1, width: pw, height: ph)
        ctx.draw(print, in: rect)
        return ctx.makeImage()!
    }

    /// A gray document page with lines of real text, optionally with two punch holes.
    static func textPage(dpi: Int, lines: [String], punchHoles: Bool = false) -> CGImage {
        let w = Int(8.5 * Double(dpi)), h = 11 * dpi
        let ctx = context(width: w, height: h, gray: true)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(dpi) * 0.25, nil)
        for (i, text) in lines.enumerated() {
            let attr = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            ctx.textPosition = CGPoint(x: CGFloat(dpi), y: CGFloat(h) - CGFloat(dpi) * (1.5 + 0.5 * CGFloat(i)))
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        if punchHoles { addHoles(ctx, w: w, h: h, dpi: dpi) }
        return ctx.makeImage()!
    }

    /// A blank page with one short handwritten-size word, like a quick note on the back.
    static func pageWithOneWord(dpi: Int) -> CGImage {
        let w = Int(8.5 * Double(dpi)), h = 11 * dpi
        let ctx = context(width: w, height: h, gray: true)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(dpi) * 0.22, nil)
        let attr = NSAttributedString(string: "Test", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 1),
        ])
        ctx.textPosition = CGPoint(x: CGFloat(dpi) * 2, y: CGFloat(h) - CGFloat(dpi) * 2)
        CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        return ctx.makeImage()!
    }

    static func blankPage(dpi: Int, punchHoles: Bool) -> CGImage {
        textPage(dpi: dpi, lines: [], punchHoles: punchHoles)
    }

    private static func addHoles(_ ctx: CGContext, w: Int, h: Int, dpi: Int) {
        ctx.setFillColor(gray: 0.1, alpha: 1)
        let d = CGFloat(dpi) / 4
        for x in [CGFloat(w) * 0.35, CGFloat(w) * 0.65] {
            ctx.fillEllipse(in: CGRect(x: x, y: CGFloat(h) - CGFloat(dpi) * 0.5, width: d, height: d))
        }
    }

    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scankit-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func writeTIFF(_ img: CGImage, to url: URL, dpi: Int) -> URL {
        try! ImageUtil.write(img, to: url, format: .tiff, dpi: dpi)
        return url
    }
}
