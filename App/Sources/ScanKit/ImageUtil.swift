import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum ImageUtil {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Filters run in gamma-encoded sRGB so levels math matches the 8-bit histograms.
    static let ciContext = CIContext(options: [
        .workingColorSpace: sRGB,
        .cacheIntermediates: false,
    ])

    public static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw ScanError.unreadable(url) }
        return img
    }

    public static func dpi(of url: URL) -> Int? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let d = p[kCGImagePropertyDPIWidth] as? Double, d > 0 else { return nil }
        return Int(d.rounded())
    }

    public static func write(_ img: CGImage, to url: URL, format: ImageFormat, dpi: Int, quality: Double = 0.92) throws {
        let type: UTType = format == .jpeg ? .jpeg : .tiff
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw ScanError.writeFailed(url) }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        } else {
            props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // LZW, lossless
        }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ScanError.writeFailed(url) }
    }

    public static func render(_ image: CIImage, colorSpace: CGColorSpace? = nil) -> CGImage? {
        let e = image.extent.integral
        let moved = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        let rect = CGRect(origin: .zero, size: e.size)
        return ciContext.createCGImage(moved, from: rect, format: .RGBA8, colorSpace: colorSpace ?? sRGB)
    }

    public static func oriented(_ img: CGImage, _ o: CGImagePropertyOrientation) -> CGImage {
        guard o != .up else { return img }
        let space = (img.colorSpace?.model == .rgb) ? img.colorSpace : nil
        return render(CIImage(cgImage: img).oriented(o), colorSpace: space) ?? img
    }

    /// Downscaled copy whose longer side is at most `maxSide` pixels.
    public static func scaled(_ img: CGImage, maxSide: Int) -> CGImage {
        let longest = max(img.width, img.height)
        guard longest > maxSide else { return img }
        let s = Double(maxSide) / Double(longest)
        let w = max(1, Int(Double(img.width) * s)), h = max(1, Int(Double(img.height) * s))
        let gray = img.colorSpace?.model == .monochrome
        let space = gray ? CGColorSpaceCreateDeviceGray() : sRGB
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    /// 8-bit gray pixels, row 0 at the top. `maxSide` nil keeps full size.
    static func grayBuffer(_ img: CGImage, maxSide: Int?) -> (pixels: [UInt8], width: Int, height: Int) {
        var w = img.width, h = img.height
        if let m = maxSide, max(w, h) > m {
            let s = Double(m) / Double(max(w, h))
            w = max(1, Int(Double(w) * s)); h = max(1, Int(Double(h) * s))
        }
        var px = [UInt8](repeating: 0, count: w * h)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (px, w, h)
    }

    /// RGBX 8-bit pixels in sRGB.
    static func rgbBuffer(_ img: CGImage, maxSide: Int) -> (pixels: [UInt8], width: Int, height: Int) {
        var w = img.width, h = img.height
        if max(w, h) > maxSide {
            let s = Double(maxSide) / Double(max(w, h))
            w = max(1, Int(Double(w) * s)); h = max(1, Int(Double(h) * s))
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (px, w, h)
    }

    /// True 1-bit image (for black & white pages), thresholded at mid-gray.
    public static func oneBit(_ img: CGImage) -> CGImage? {
        let (px, w, h) = grayBuffer(img, maxSide: nil)
        let rowBytes = (w + 7) / 8
        var bits = [UInt8](repeating: 0, count: rowBytes * h)
        for y in 0..<h {
            let row = y * w, out = y * rowBytes
            for x in 0..<w where px[row + x] >= 128 {
                bits[out + x >> 3] |= UInt8(0x80 >> (x & 7))   // 1 = white in DeviceGray
            }
        }
        guard let provider = CGDataProvider(data: Data(bits) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// JPEG-backed CGImage, so PDF contexts embed the JPEG data as-is instead of lossless pixels.
    static func jpegBacked(_ img: CGImage, quality: Double) -> CGImage? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
