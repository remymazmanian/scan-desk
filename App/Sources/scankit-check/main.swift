// Offline check of the processing pipeline against saved raw scans (e.g. the probe output),
// without a scanner.
//
//   scankit-check analyze <files...>
//   scankit-check photos  <out-dir> [--backs] [--enhance] <files in feeder order...>
//   scankit-check docs    <out-dir> <pdf|jpeg|tiff> <color|gray|bw> [--duplex] <files...>

import Foundation
import ScanKit
import ImageIO

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print("usage: analyze | photos | docs"); exit(2) }
args.removeFirst()

func flag(_ f: String) -> Bool {
    if let i = args.firstIndex(of: f) { args.remove(at: i); return true }
    return false
}

func name(_ o: CGImagePropertyOrientation) -> String {
    switch o {
    case .up: return "up"
    case .right: return "rotate 90 cw"
    case .down: return "rotate 180"
    case .left: return "rotate 90 ccw"
    default: return "\(o.rawValue)"
    }
}

do {
    switch cmd {
    case "analyze":
        for path in args {
            let url = URL(fileURLWithPath: path)
            let img = try ImageUtil.load(url)
            let t0 = Date()
            let ink = PhotoProcessing.inkFraction(img)
            let uncropped = PhotoProcessing.isUncropped(img, dpi: ImageUtil.dpi(of: url) ?? 300)
            let crop = uncropped ? PhotoProcessing.detectAndCrop(img) : nil
            let o = PhotoProcessing.uprightOrientation(crop ?? img)
            print(String(format: "%@  %dx%d  ink=%.4f%%  uncropped=%@  crop=%@  orient=%@  (%.2fs)",
                         url.lastPathComponent, img.width, img.height, ink * 100, uncropped ? "yes" : "no",
                         crop.map { "\($0.width)x\($0.height)" } ?? "none", name(o), Date().timeIntervalSince(t0)))
        }

    case "photos":
        let out = URL(fileURLWithPath: args.removeFirst())
        let backs = flag("--backs"), enhance = flag("--enhance")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let p = PhotoPipeline(options: PhotoOptions(dpi: 300, format: .jpeg, destination: out, year: "1999",
                                                    album: "Probe Test", scanBacks: backs,
                                                    skipBlankBacks: true, enhance: enhance))
        for path in args {
            let t0 = Date()
            switch try p.handle(page: URL(fileURLWithPath: path)) {
            case .front(let r):
                print("front \(r.name)  orient=\(name(r.orientation))  enhanced=\(r.enhanced != nil)  " + String(format: "%.2fs", Date().timeIntervalSince(t0)))
            case .back(let r):
                print("  back \(r.name)  " + (r.backSkippedAsBlank ? "skipped (blank)" : "saved") + String(format: "  %.2fs", Date().timeIntervalSince(t0)))
            }
        }

    case "docs":
        let out = URL(fileURLWithPath: args.removeFirst())
        let format = DocumentFormat(rawValue: args.removeFirst())!
        let color = ColorMode(rawValue: args.removeFirst())!
        let duplex = flag("--duplex")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let p = DocumentPipeline(options: DocumentOptions(dpi: 300, color: color, format: format, destination: out,
                                                          title: "Probe Test", duplex: duplex,
                                                          skipBlankPages: true, searchable: true))
        for path in args {
            switch try p.handle(page: URL(fileURLWithPath: path)) {
            case .page(let n, _): print("page \(n) kept: \((path as NSString).lastPathComponent)")
            case .skippedBlank: print("blank skipped: \((path as NSString).lastPathComponent)")
            }
        }
        let t0 = Date()
        for url in try p.finish() {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("wrote \(url.lastPathComponent)  \(size / 1024) KB  " + String(format: "%.1fs", Date().timeIntervalSince(t0)))
        }

    default:
        print("unknown command \(cmd)"); exit(2)
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
