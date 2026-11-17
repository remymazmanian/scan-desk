import Foundation

public enum ScanError: LocalizedError {
    case notReady
    case unreadable(URL)
    case writeFailed(URL)
    case noFeeder

    public var errorDescription: String? {
        switch self {
        case .notReady: return "The scanner isn't ready yet."
        case .unreadable(let url): return "Couldn't read \(url.lastPathComponent)."
        case .writeFailed(let url): return "Couldn't write \(url.lastPathComponent)."
        case .noFeeder: return "This scanner doesn't offer a document feeder."
        }
    }
}

public enum ColorMode: String, CaseIterable, Identifiable, Codable {
    case color, gray, bw
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .color: return "Color"
        case .gray: return "Grayscale"
        case .bw: return "Black & White"
        }
    }
}

public enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case jpeg, tiff
    public var id: String { rawValue }
    public var label: String { self == .jpeg ? "JPEG" : "TIFF (no compression loss)" }
    public var fileExtension: String { self == .jpeg ? "jpg" : "tif" }
}

public enum DocumentFormat: String, CaseIterable, Identifiable, Codable {
    case pdf, jpeg, tiff
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .pdf: return "PDF"
        case .jpeg: return "JPEG (one per page)"
        case .tiff: return "TIFF (one per page)"
        }
    }
    public var imageFormat: ImageFormat? {
        switch self {
        case .pdf: return nil
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
}

/// What the scanner hardware should do for one feeder run.
public struct ScanParameters {
    public var dpi: Int
    public var color: ColorMode
    public var duplex: Bool
    /// The driver's own rotation only helps text pages (see PROBE.md).
    public var driverAutoRotate: Bool

    public init(dpi: Int, color: ColorMode, duplex: Bool, driverAutoRotate: Bool) {
        self.dpi = dpi
        self.color = color
        self.duplex = duplex
        self.driverAutoRotate = driverAutoRotate
    }
}
