import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision

/// Crop, rotation, blank detection and enhancement for scanned prints and pages.
public enum PhotoProcessing {

    // MARK: Blank detection

    /// Share of pixels that differ clearly from the paper color, ignoring a thin margin
    /// (edge shadows, punch holes near the border still count but are tiny).
    public static func inkFraction(_ img: CGImage, margin: Double = 0.03, maxSide: Int = 700) -> Double {
        let (px, w, h) = ImageUtil.grayBuffer(img, maxSide: maxSide)
        let mx = Int(Double(w) * margin), my = Int(Double(h) * margin)
        guard w - 2 * mx > 0, h - 2 * my > 0 else { return 0 }
        var hist = [Int](repeating: 0, count: 256)
        var n = 0
        for y in my..<(h - my) {
            let row = y * w
            for x in mx..<(w - mx) { hist[Int(px[row + x])] += 1; n += 1 }
        }
        var acc = 0, paper = 0
        for i in 0..<256 { acc += hist[i]; if acc * 2 >= n { paper = i; break } }
        var ink = 0
        for i in 0..<256 where abs(i - paper) > 48 { ink += hist[i] }
        return Double(ink) / Double(n)
    }

    /// Default threshold: two punch holes are about 0.1%, a short handwritten note well over 0.3%.
    public static func isBlank(_ img: CGImage, threshold: Double = 0.002) -> Bool {
        inkFraction(img) < threshold
    }

    /// Documents get a finer look than photo backs: thin or light text can wash out
    /// when a page is shrunk too far before measuring.
    public static func isBlankPage(_ img: CGImage, threshold: Double = 0.002) -> (blank: Bool, ink: Double) {
        let ink = inkFraction(img, maxSide: 1400)
        return (ink < threshold, ink)
    }

    /// A print's picture side has far more ink than any back (blank, stamped or written on).
    /// Used to notice when the scanner skipped a back, so pairing doesn't shift.
    public static func looksLikePictureSide(_ img: CGImage) -> Bool {
        inkFraction(img) > 0.05
    }

    // MARK: Crop and deskew

    /// True when the page came back at the full requested Letter area, meaning the driver's
    /// auto size detection didn't crop it (driver-cropped prints are always smaller).
    public static func isUncropped(_ img: CGImage, dpi: Int) -> Bool {
        let w = 8.5 * Double(dpi), h = 11.0 * Double(dpi)
        return abs(Double(img.width) - w) < w * 0.01 && abs(Double(img.height) - h) < h * 0.01
    }

    /// Outline of the print on the scanner background, in Vision-style normalized coordinates
    /// (origin bottom-left). The driver pads past the end of the paper with pure white, which is
    /// also the color of a print's back, so the paper end is found first from the side edges,
    /// where only background or padding can appear.
    public static func foregroundBounds(_ img: CGImage) -> CGRect? {
        let (px, w, h) = ImageUtil.rgbBuffer(img, maxSide: 800)
        let margin = max(2, w * 15 / 1000)          // skip sensor-edge artifacts
        let side = Array(margin..<(margin + max(2, w / 50))) + Array((w - margin - max(2, w / 50))..<(w - margin))

        func lum(_ i: Int) -> Int { (Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])) / 3 }
        // Paper end: last row whose side strips are not padding-white.
        var paperEnd = 0
        for y in 0..<h {
            let dark = side.filter { lum((y * w + $0) * 4) < 245 }.count
            if dark * 2 > side.count { paperEnd = y }
        }
        let rowsEnd = max(1, paperEnd - 2)          // drop the soft transition row

        var rs: [Int] = [], gs: [Int] = [], bs: [Int] = []
        for y in stride(from: 0, to: rowsEnd, by: 2) {
            for x in side { let i = (y * w + x) * 4; rs.append(Int(px[i])); gs.append(Int(px[i + 1])); bs.append(Int(px[i + 2])) }
        }
        guard !rs.isEmpty else { return nil }
        func median(_ a: [Int]) -> Int { a.sorted()[a.count / 2] }
        let bg = (median(rs), median(gs), median(bs))
        func isPrint(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return abs(Int(px[i]) - bg.0) + abs(Int(px[i + 1]) - bg.1) + abs(Int(px[i + 2]) - bg.2) > 36
        }

        let cols = margin..<(w - margin)
        var colHits = [Int](repeating: 0, count: w)
        for y in 0..<rowsEnd { for x in cols where isPrint(x, y) { colHits[x] += 1 } }
        let colMin = max(3, rowsEnd / 4)
        guard let left = cols.first(where: { colHits[$0] >= colMin }),
              let right = cols.last(where: { colHits[$0] >= colMin }), right > left else { return nil }

        let rowMin = max(3, (right - left) / 12)   // pale areas of a picture can look like background
        var top: Int?, bottom: Int?
        for y in 0..<rowsEnd {
            var n = 0
            for x in left...right where isPrint(x, y) { n += 1 }
            if n >= rowMin { if top == nil { top = y }; bottom = y }
        }
        guard let top, let bottom, bottom > top else { return nil }
        let W = Double(w), H = Double(h)
        return CGRect(x: Double(left) / W, y: 1 - Double(bottom + 1) / H,
                      width: Double(right - left + 1) / W, height: Double(bottom - top + 1) / H)
    }

    /// Fallback for pages the driver didn't crop. Vision rectangle detection finds the print and
    /// straightens it with perspective correction; it's trusted only when it agrees with the
    /// background outline, because busy pictures can fool it. Otherwise the outline is the crop.
    public static func detectAndCrop(_ img: CGImage) -> CGImage? {
        guard let bounds = foregroundBounds(img), bounds.width * bounds.height < 0.95 else { return nil }
        let W = CGFloat(img.width), H = CGFloat(img.height)
        let space = img.colorSpace?.model == .rgb ? img.colorSpace : nil

        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.2
        req.maximumAspectRatio = 1.0
        req.minimumSize = 0.2
        req.quadratureTolerance = 20
        req.minimumConfidence = 0.5
        req.maximumObservations = 1
        try? VNImageRequestHandler(cgImage: ImageUtil.scaled(img, maxSide: 1600), options: [:]).perform([req])

        if let r = req.results?.first {
            let xs = [r.topLeft.x, r.topRight.x, r.bottomLeft.x, r.bottomRight.x]
            let ys = [r.topLeft.y, r.topRight.y, r.bottomLeft.y, r.bottomRight.y]
            let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let tol: CGFloat = 0.012   // a tilted print's corners still touch the outline, so a real match is close
            let agrees = abs(box.minX - bounds.minX) < tol && abs(box.maxX - bounds.maxX) < tol
                && abs(box.minY - bounds.minY) < tol && abs(box.maxY - bounds.maxY) < tol
            if agrees, let f = CIFilter(name: "CIPerspectiveCorrection") {
                func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x * W, y: p.y * H) }
                f.setValue(CIImage(cgImage: img), forKey: kCIInputImageKey)
                f.setValue(v(r.topLeft), forKey: "inputTopLeft")
                f.setValue(v(r.topRight), forKey: "inputTopRight")
                f.setValue(v(r.bottomRight), forKey: "inputBottomRight")
                f.setValue(v(r.bottomLeft), forKey: "inputBottomLeft")
                // The corrected image must also match the outline's size; a quad with a skewed
                // corner can pass the box check yet stretch the result.
                if let out = f.outputImage, let img2 = ImageUtil.render(out, colorSpace: space) {
                    let ew = bounds.width * W, eh = bounds.height * H
                    let a = CGFloat(img2.width), b = CGFloat(img2.height)
                    if abs(a - ew) < ew * 0.03, abs(b - eh) < eh * 0.03 { return img2 }
                }
            }
        }
        // CGImage.cropping uses top-left origin.
        let rect = CGRect(x: bounds.minX * W, y: (1 - bounds.maxY) * H,
                          width: bounds.width * W, height: bounds.height * H).integral
        return img.cropping(to: rect)
    }

    // MARK: Rotation

    /// Orientation that makes the picture upright, judged by faces that read as upright.
    /// Returns `.up` when there are no faces to go by.
    public static func uprightOrientation(_ img: CGImage) -> CGImagePropertyOrientation {
        let small = ImageUtil.scaled(img, maxSide: 1200)
        var scores: [(CGImagePropertyOrientation, Float)] = []
        for o in [CGImagePropertyOrientation.up, .right, .down, .left] {
            let req = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(cgImage: small, orientation: o, options: [:]).perform([req])
            let score = (req.results ?? []).reduce(Float(0)) { acc, face in
                let roll = abs(face.roll?.doubleValue ?? 0)
                return roll < .pi / 5 ? acc + face.confidence : acc
            }
            scores.append((o, score))
        }
        let up = scores[0].1
        guard let best = scores.max(by: { $0.1 < $1.1 }), best.0 != .up, best.1 >= up + 0.5 else { return .up }
        return best.0
    }

    /// Rotation for the back of a print whose front needed `front`.
    /// A duplex feeder images the back flipped left-to-right, so quarter turns reverse.
    public static func backOrientation(for front: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch front {
        case .right: return .left
        case .left: return .right
        default: return front
        }
    }

    // MARK: Enhancement

    /// One-click restore for faded prints: per-channel levels stretch (removes color casts and
    /// lifts contrast), a touch of vibrance, and light sharpening.
    public static func enhance(_ img: CGImage) -> CGImage {
        let (px, w, h) = ImageUtil.rgbBuffer(img, maxSide: 600)
        let n = w * h
        var lo = [Double](repeating: 0, count: 3), hi = [Double](repeating: 255, count: 3)
        for c in 0..<3 {
            var hist = [Int](repeating: 0, count: 256)
            for i in 0..<n { hist[Int(px[i * 4 + c])] += 1 }
            let cut = max(1, n / 200)   // 0.5% each end
            var acc = 0
            for v in 0..<256 { acc += hist[v]; if acc >= cut { lo[c] = Double(v); break } }
            acc = 0
            for v in stride(from: 255, through: 0, by: -1) { acc += hist[v]; if acc >= cut { hi[c] = Double(v); break } }
        }

        var image = CIImage(cgImage: img)
        let extent = image.extent
        var vectors: [CIVector] = []
        var bias = [CGFloat](repeating: 0, count: 3)
        for c in 0..<3 {
            let range = max(hi[c] - lo[c], 1)
            let scale = min(255 / range, 2.2)            // don't blow up nearly-flat channels
            let offset = -lo[c] / 255 * scale
            var comps = [CGFloat](repeating: 0, count: 4)
            comps[c] = CGFloat(scale)
            vectors.append(CIVector(x: comps[0], y: comps[1], z: comps[2], w: 0))
            bias[c] = CGFloat(offset)
        }
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": vectors[0], "inputGVector": vectors[1], "inputBVector": vectors[2],
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias[0], y: bias[1], z: bias[2], w: 0),
        ])
        image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.15])
        image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35, "inputRadius": 1.2])
        return ImageUtil.render(image.cropped(to: extent)) ?? img
    }
}
