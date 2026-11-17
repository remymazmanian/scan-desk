import Foundation
import CoreGraphics
import ImageIO

public struct PhotoOptions {
    public var dpi: Int
    public var format: ImageFormat
    public var destination: URL
    public var year: String
    public var album: String
    public var scanBacks: Bool
    public var skipBlankBacks: Bool
    public var enhance: Bool

    public init(dpi: Int, format: ImageFormat, destination: URL, year: String, album: String,
                scanBacks: Bool, skipBlankBacks: Bool, enhance: Bool) {
        self.dpi = dpi; self.format = format; self.destination = destination
        self.year = year; self.album = album
        self.scanBacks = scanBacks; self.skipBlankBacks = skipBlankBacks; self.enhance = enhance
    }

    public var scanParameters: ScanParameters {
        ScanParameters(dpi: dpi, color: .color, duplex: scanBacks, driverAutoRotate: false)
    }
}

public struct DocumentOptions {
    public var dpi: Int
    public var color: ColorMode
    public var format: DocumentFormat
    public var destination: URL
    public var title: String
    public var duplex: Bool
    public var skipBlankPages: Bool
    public var searchable: Bool

    public init(dpi: Int, color: ColorMode, format: DocumentFormat, destination: URL, title: String,
                duplex: Bool, skipBlankPages: Bool, searchable: Bool) {
        self.dpi = dpi; self.color = color; self.format = format; self.destination = destination
        self.title = title; self.duplex = duplex; self.skipBlankPages = skipBlankPages; self.searchable = searchable
    }

    public var scanParameters: ScanParameters {
        ScanParameters(dpi: dpi, color: color, duplex: duplex, driverAutoRotate: true)
    }
}

/// One saved photo (front, optional enhanced copy, optional back).
public struct PhotoResult {
    public var name: String
    public var original: URL
    public var enhanced: URL?
    public var back: URL?
    public var backSkippedAsBlank = false
    /// The scanner sent the next picture where this photo's back was expected.
    public var backMissing = false
    public var orientation: CGImagePropertyOrientation
    public var thumbnail: CGImage
}

/// Turns feeder pages into finished photo files. Not thread-safe: use from one serial queue.
public final class PhotoPipeline {
    public let options: PhotoOptions
    public let prefix: String
    private var nextNumber: Int
    private var current: PhotoResult?   // front waiting for its back

    public init(options: PhotoOptions) {
        self.options = options
        prefix = Naming.photoPrefix(year: options.year, album: options.album)
        nextNumber = Naming.nextPhotoNumber(prefix: prefix, in: options.destination)
    }

    public enum Event {
        case front(PhotoResult)
        case back(PhotoResult)   // the same photo, updated with its back
    }

    /// Handles one page straight from the scanner, in feeder order. Pages normally alternate
    /// front, back; if a back is missing (the next picture arrives instead), the pending photo
    /// is closed without a back and the page is handled as a new front.
    public func handle(page url: URL) throws -> [Event] {
        let img = try ImageUtil.load(url)
        scanLog.info("photo page \(url.lastPathComponent, privacy: .public): \(img.width)x\(img.height), ink \(String(format: "%.3f%%", PhotoProcessing.inkFraction(img) * 100), privacy: .public), waiting for back: \(self.current != nil)")
        if options.scanBacks, var pending = current {
            if PhotoProcessing.looksLikePictureSide(img) {
                pending.backMissing = true
                current = nil
                return [.back(pending), try handleFront(img)]
            }
            return [try handleBack(img)]
        }
        return [try handleFront(img)]
    }

    private func handleFront(_ loaded: CGImage) throws -> Event {
        var img = loaded
        if PhotoProcessing.isUncropped(img, dpi: options.dpi), let cropped = PhotoProcessing.detectAndCrop(img) {
            img = cropped
        }
        let o = PhotoProcessing.uprightOrientation(img)
        img = ImageUtil.oriented(img, o)

        let base = Naming.photoBase(prefix: prefix, number: nextNumber)
        nextNumber += 1
        let ext = options.format.fileExtension
        let dir = options.destination
        let original = dir.appendingPathComponent("\(base).\(ext)")
        try ImageUtil.write(img, to: original, format: options.format, dpi: options.dpi)

        var enhanced: URL?
        if options.enhance {
            let e = dir.appendingPathComponent("\(base)_e.\(ext)")
            try ImageUtil.write(PhotoProcessing.enhance(img), to: e, format: options.format, dpi: options.dpi)
            enhanced = e
        }
        let result = PhotoResult(name: base, original: original, enhanced: enhanced, orientation: o,
                                 thumbnail: ImageUtil.scaled(img, maxSide: 480))
        current = result
        return .front(result)
    }

    private func handleBack(_ loaded: CGImage) throws -> Event {
        guard var result = current else { return try handleFront(loaded) }
        current = nil
        var img = loaded
        if PhotoProcessing.isUncropped(img, dpi: options.dpi), let cropped = PhotoProcessing.detectAndCrop(img) {
            img = cropped
        }
        if options.skipBlankBacks && PhotoProcessing.isBlank(img) {
            result.backSkippedAsBlank = true
            return .back(result)
        }
        img = ImageUtil.oriented(img, PhotoProcessing.backOrientation(for: result.orientation))
        let back = options.destination.appendingPathComponent("\(result.name)_b.\(options.format.fileExtension)")
        try ImageUtil.write(img, to: back, format: options.format, dpi: options.dpi)
        result.back = back
        return .back(result)
    }

    /// Rotates every saved file of a photo by a quarter turn (manual fix for photos without faces).
    public static func rotate(_ result: PhotoResult, clockwise: Bool, format: ImageFormat, dpi: Int) throws -> PhotoResult {
        let turn: CGImagePropertyOrientation = clockwise ? .right : .left
        var r = result
        for url in [result.original, result.enhanced].compactMap({ $0 }) {
            let img = ImageUtil.oriented(try ImageUtil.load(url), turn)
            try ImageUtil.write(img, to: url, format: format, dpi: dpi)
            if url == result.original { r.thumbnail = ImageUtil.scaled(img, maxSide: 480) }
        }
        if let back = result.back {
            let img = ImageUtil.oriented(try ImageUtil.load(back), PhotoProcessing.backOrientation(for: turn))
            try ImageUtil.write(img, to: back, format: format, dpi: dpi)
        }
        return r
    }
}

/// Collects document pages during a feeder run and writes the PDF or page images at the end.
public final class DocumentPipeline {
    public let options: DocumentOptions
    private var kept: [URL] = []
    public private(set) var skippedBlank = 0

    public init(options: DocumentOptions) { self.options = options }

    public enum Event {
        case page(number: Int, thumbnail: CGImage)
        case skippedBlank
    }

    public func handle(page url: URL) throws -> Event {
        let img = try ImageUtil.load(url)
        let check = PhotoProcessing.isBlankPage(img)
        scanLog.info("document page \(url.lastPathComponent, privacy: .public): \(img.width)x\(img.height), ink \(String(format: "%.3f%%", check.ink * 100), privacy: .public)\(check.blank && self.options.skipBlankPages ? ", skipped as blank" : "", privacy: .public)")
        if options.skipBlankPages && check.blank {
            skippedBlank += 1
            return .skippedBlank
        }
        kept.append(url)
        return .page(number: kept.count, thumbnail: ImageUtil.scaled(img, maxSide: 480))
    }

    /// Writes the output and returns the saved files. Pages stay in the scanner's temp folder until then.
    public func finish() throws -> [URL] {
        guard !kept.isEmpty else { return [] }
        let dir = options.destination
        if let fmt = options.format.imageFormat {
            let base = Naming.documentBase(title: options.title, in: dir, extensions: [fmt.fileExtension])
            var out: [URL] = []
            for (i, page) in kept.enumerated() {
                try autoreleasepool {
                    var img = try ImageUtil.load(page)
                    if options.color == .bw, fmt == .tiff, let bits = ImageUtil.oneBit(img) { img = bits }
                    let name = kept.count == 1 ? base : "\(base)_p\(String(format: "%03d", i + 1))"
                    let url = dir.appendingPathComponent("\(name).\(fmt.fileExtension)")
                    try ImageUtil.write(img, to: url, format: fmt, dpi: ImageUtil.dpi(of: page) ?? options.dpi)
                    out.append(url)
                }
            }
            scanLog.info("saved \(out.count) page image(s)")
            return out
        }
        let base = Naming.documentBase(title: options.title, in: dir, extensions: ["pdf"])
        let url = dir.appendingPathComponent("\(base).pdf")
        try PDFBuilder.write(pages: kept, color: options.color, fallbackDPI: options.dpi,
                             searchable: options.searchable, to: url)
        scanLog.info("saved PDF with \(self.kept.count) page(s)")
        return [url]
    }
}
