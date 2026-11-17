import Foundation
import CoreGraphics
import CoreText
import Vision

/// Builds a multi-page PDF from scanned page images, optionally with an invisible
/// text layer from on-device text recognition so the PDF is searchable.
public enum PDFBuilder {

    /// One recognized line: text plus its box in normalized page coordinates (origin bottom-left).
    public struct TextLine { public var text: String; public var box: CGRect }

    public static func write(pages: [URL], color: ColorMode, fallbackDPI: Int, searchable: Bool, to url: URL) throws {
        // Text recognition is the slow part (several seconds a page), so run it on all pages in parallel first.
        var layers = [[TextLine]](repeating: [], count: pages.count)
        if searchable {
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: pages.count) { i in
                autoreleasepool {
                    guard let img = try? ImageUtil.load(pages[i]) else { return }
                    let lines = recognize(img)
                    lock.lock(); layers[i] = lines; lock.unlock()
                }
            }
        }

        var box = CGRect.zero
        guard let ctx = CGContext(url as CFURL, mediaBox: &box,
                                  [kCGPDFContextCreator: "Scan Desk"] as CFDictionary)
        else { throw ScanError.writeFailed(url) }

        for (i, page) in pages.enumerated() {
            try autoreleasepool {
                let img = try ImageUtil.load(page)
                let dpi = CGFloat(ImageUtil.dpi(of: page) ?? fallbackDPI)
                var media = CGRect(x: 0, y: 0, width: CGFloat(img.width) * 72 / dpi, height: CGFloat(img.height) * 72 / dpi)
                let embedded: CGImage? = color == .bw
                    ? ImageUtil.oneBit(img)
                    : ImageUtil.jpegBacked(img, quality: color == .gray ? 0.75 : 0.8)

                ctx.beginPage(mediaBox: &media)
                ctx.interpolationQuality = .high
                ctx.draw(embedded ?? img, in: media)
                draw(layers[i], in: ctx, page: media)
                ctx.endPage()
            }
        }
        ctx.closePDF()
    }

    /// The first text recognition after an app is installed or updated can take 30+ seconds while
    /// macOS prepares its model. Running one tiny request at launch moves that wait off the first save.
    public static func prepareTextRecognition() {
        let t0 = Date()
        let size = 400
        guard let ctx = CGContext(data: nil, width: size, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: 120))
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let attr = NSAttributedString(string: "Ready", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        ctx.textPosition = CGPoint(x: 20, y: 40)
        CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        guard let img = ctx.makeImage() else { return }
        let found = recognize(img).count
        scanLog.info("text recognition ready in \(String(format: "%.1f", Date().timeIntervalSince(t0)), privacy: .public)s (\(found) line)")
    }

    public static func recognize(_ img: CGImage) -> [TextLine] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        return (req.results ?? []).compactMap { obs in
            guard let t = obs.topCandidates(1).first?.string, !t.isEmpty else { return nil }
            return TextLine(text: t, box: obs.boundingBox)
        }
    }

    /// Recognized text drawn invisibly over each line, stretched to the line's box,
    /// so selection and search line up with the page image.
    static func draw(_ lines: [TextLine], in ctx: CGContext, page: CGRect) {
        for line in lines {
            let b = line.box
            let r = CGRect(x: b.minX * page.width, y: b.minY * page.height,
                           width: b.width * page.width, height: b.height * page.height)
            guard r.width > 1, r.height > 1 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, r.height * 0.8, nil)
            let attr = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let ctLine = CTLineCreateWithAttributedString(attr)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            guard width > 0 else { continue }

            ctx.saveGState()
            ctx.setTextDrawingMode(.invisible)
            ctx.textMatrix = CGAffineTransform(scaleX: r.width / CGFloat(width), y: 1)
            ctx.textPosition = CGPoint(x: r.minX, y: r.minY + r.height * 0.2)
            CTLineDraw(ctLine, ctx)
            ctx.restoreGState()
        }
    }
}
