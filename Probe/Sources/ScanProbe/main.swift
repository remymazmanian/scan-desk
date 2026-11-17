// ScanProbe — dumps what the Epson ICA driver exposes through ImageCaptureCore
// and optionally runs one feeder scan, saving raw TIFF output.
//
// Usage:
//   ScanProbe list                         # discover + dump capabilities, no scan
//   ScanProbe scan --dpi 300 [--duplex]    # dump, then scan whatever is in the feeder
//   Options: --match <text>  (device name filter, default "FF-680")
//            --out <dir>     (default ~/Pictures/ScanProbe)
//            --timeout <sec> (default 300)

import Foundation
import ImageCaptureCore
import ImageIO

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Options

struct Options {
    var mode = "list"
    var dpi = 300
    var duplex = false
    var match = "FF-680"
    var out = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/ScanProbe", isDirectory: true)
    var timeout: TimeInterval = 300
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    if let first = args.first, !first.hasPrefix("--") { o.mode = first; args.removeFirst() }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--dpi": o.dpi = Int(args.removeFirst()) ?? 300
        case "--duplex": o.duplex = true
        case "--match": o.match = args.removeFirst()
        case "--out": o.out = URL(fileURLWithPath: (args.removeFirst() as NSString).expandingTildeInPath, isDirectory: true)
        case "--timeout": o.timeout = TimeInterval(args.removeFirst()) ?? 300
        default: print("Unknown argument \(a)"); exit(2)
        }
    }
    return o
}

// MARK: - Naming helpers

func log(_ s: String) {
    let t = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
    print("[\(t)] \(s)")
}

func unitName(_ t: ICScannerFunctionalUnitType) -> String {
    switch t {
    case .flatbed: return "Flatbed"
    case .positiveTransparency: return "PositiveTransparency"
    case .negativeTransparency: return "NegativeTransparency"
    case .documentFeeder: return "DocumentFeeder"
    @unknown default: return "Unknown(\(t.rawValue))"
    }
}

func pixelTypeName(_ p: ICScannerPixelDataType) -> String {
    ["BW", "Gray", "RGB", "Palette", "CMY", "CMYK", "YUV", "YUVK", "CIEXYZ"][safe: Int(p.rawValue)] ?? "raw(\(p.rawValue))"
}

func measurementName(_ raw: Int) -> String {
    ["inches", "centimeters", "picas", "points", "twips", "pixels"][safe: raw] ?? "raw(\(raw))"
}

func stateName(_ s: ICScannerFunctionalUnitState) -> String {
    var parts: [String] = []
    let r = s.rawValue
    if r & 1 != 0 { parts.append("ready") }
    if r & 2 != 0 { parts.append("scanInProgress") }
    if r & 4 != 0 { parts.append("overviewScanInProgress") }
    return parts.isEmpty ? "raw(\(s.rawValue))" : parts.joined(separator: ",")
}

let documentTypeNames: [Int: String] = [
    0: "Default", 1: "A4", 2: "B5", 3: "USLetter", 4: "USLegal", 5: "A5", 6: "ISOB4", 7: "ISOB6",
    9: "USLedger", 10: "USExecutive", 11: "A3", 12: "ISOB3", 13: "A6", 14: "C4", 15: "C5", 16: "C6",
    17: "4A0", 18: "2A0", 19: "A0", 20: "A1", 21: "A2", 22: "A7", 23: "A8", 24: "A9", 25: "10",
    26: "ISOB0", 27: "ISOB1", 28: "ISOB2", 29: "ISOB5", 30: "ISOB7", 31: "ISOB8", 32: "ISOB9", 33: "ISOB10",
    34: "JISB0", 35: "JISB1", 36: "JISB2", 37: "JISB3", 38: "JISB4", 39: "JISB6", 40: "JISB7", 41: "JISB8",
    42: "JISB9", 43: "JISB10", 44: "C0", 45: "C1", 46: "C2", 47: "C3", 48: "C7", 49: "C8", 50: "C9", 51: "C10",
    52: "USStatement", 53: "BusinessCard", 60: "E", 61: "3R(3.5x5)", 62: "4R(4x6)", 63: "5R(5x7)",
    64: "6R(6x8)", 65: "8R(8x10)", 66: "S8R(8x12)", 67: "10R(10x12)", 68: "S10R(10x15)", 69: "11R(11x14)",
    70: "12R(12x15)", 71: "S12R(12x18)", 72: "110", 73: "APSH", 74: "APSC", 75: "APSP", 76: "135",
    77: "MF", 78: "LF",
]

func docTypes(_ set: IndexSet) -> String {
    set.map { "\(documentTypeNames[$0] ?? "?")[\($0)]" }.joined(separator: ", ")
}

func indexList(_ set: IndexSet) -> String {
    set.isEmpty ? "(none)" : set.map(String.init).joined(separator: ", ")
}

func transportName(_ t: String?) -> String {
    guard let t else { return "unknown" }
    return t.replacingOccurrences(of: "ICTransportType", with: "")
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Probe

final class Probe: NSObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    let opts: Options
    let browser = ICDeviceBrowser()
    var scanner: ICScannerDevice?
    var seen: [ICDevice] = []
    var pendingUnits: [ICScannerFunctionalUnitType] = []
    var dumpedUnits = Set<UInt>()
    var scanDir: URL?
    var scannedFiles: [URL] = []
    var scanStart = Date()
    var phase = "discover"

    init(_ o: Options) { opts = o }

    func start() {
        browser.delegate = self
        // Local covers USB; remote covers Bonjour/shared network devices.
        let mask = ICDeviceTypeMask(rawValue:
            ICDeviceTypeMask.scanner.rawValue |
            ICDeviceLocationTypeMask.local.rawValue |
            ICDeviceLocationTypeMask.shared.rawValue |
            ICDeviceLocationTypeMask.bonjour.rawValue |
            ICDeviceLocationTypeMask.remote.rawValue)!
        browser.browsedDeviceTypeMask = mask
        log("Browsing for scanners (local + network)…")
        browser.start()

        // Give discovery time, then pick a device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.pickDevice() }
        DispatchQueue.main.asyncAfter(deadline: .now() + opts.timeout) { [weak self] in
            log("TIMEOUT after \(Int(self?.opts.timeout ?? 0))s in phase '\(self?.phase ?? "?")'")
            self?.finish(code: 3)
        }
    }

    // MARK: Browser

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        seen.append(device)
        log("Found: \"\(device.name ?? "?")\" transport=\(transportName(device.transportType)) " +
            "productKind=\(device.productKind ?? "-") remote=\(device.isRemote)")
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        log("Removed: \(device.name ?? "?")")
    }

    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        log("Local (USB) enumeration complete.")
    }

    func pickDevice() {
        guard phase == "discover" else { return }
        let candidates = seen.compactMap { $0 as? ICScannerDevice }
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains(opts.match) }
        log("\(seen.count) scanner device(s) seen, \(candidates.count) match \"\(opts.match)\".")
        // Prefer USB if both appear.
        guard let dev = candidates.first(where: { $0.transportType == ICDeviceTransport.transportTypeUSB.rawValue }) ?? candidates.first else {
            log("No matching scanner. Is it on and visible in Image Capture?")
            finish(code: 1); return
        }
        log("Using \"\(dev.name ?? "?")\" over \(transportName(dev.transportType))")
        print("  moduleVersion=\(dev.moduleVersion ?? "-") modulePath=\(dev.modulePath)")
        print("  capabilities=\(dev.capabilities)")
        print("  locationDescription=\(dev.locationDescription ?? "-")")
        scanner = dev
        dev.delegate = self
        phase = "openSession"
        dev.requestOpenSession()
    }

    // MARK: Device delegate

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error { log("Open session FAILED: \(error)"); finish(code: 1); return }
        log("Session open.")
        pollForUnits(attempt: 0)
    }

    /// Some drivers never send scannerDeviceDidBecomeAvailable; poll the device instead.
    func pollForUnits(attempt: Int) {
        guard phase == "openSession", let scanner else { return }
        let types = scanner.availableFunctionalUnitTypes
        let sel = scanner.selectedFunctionalUnit
        if attempt % 5 == 0 {
            log("Poll \(attempt): availableFunctionalUnitTypes=\(types.map(\.intValue)) selected=\(unitName(sel.type)) state=\(stateName(sel.state))")
        }
        if !types.isEmpty && attempt >= 3 {
            log("Proceeding from poll (didBecomeAvailable not received).")
            scannerDeviceDidBecomeAvailable(scanner); return
        }
        if attempt == 10 && types.isEmpty {
            log("Still no functional units; trying requestSelect(.documentFeeder) directly.")
            phase = "dump"; pendingUnits = []
            scanner.requestSelect(.documentFeeder)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.pollForUnits(attempt: attempt + 1) }
    }

    func scannerDeviceDidBecomeAvailable(_ scanner: ICScannerDevice) {
        guard phase == "openSession" else { return }
        log("Scanner available. Functional units: " +
            scanner.availableFunctionalUnitTypes.map { unitName(ICScannerFunctionalUnitType(rawValue: $0.uintValue)!) }.joined(separator: ", "))
        print("  transferMode=\(scanner.transferMode == .fileBased ? "fileBased" : "memoryBased") " +
              "maxMemoryBandSize=\(scanner.maxMemoryBandSize) documentUTI=\(scanner.documentUTI)")
        pendingUnits = scanner.availableFunctionalUnitTypes.compactMap { ICScannerFunctionalUnitType(rawValue: $0.uintValue) }
        // The currently selected unit can be dumped right away.
        phase = "dump"
        selectNextUnit()
    }

    func selectNextUnit() {
        guard let scanner else { return }
        if let next = pendingUnits.first {
            pendingUnits.removeFirst()
            if scanner.selectedFunctionalUnit.type == next, !dumpedUnits.contains(next.rawValue) {
                dump(scanner.selectedFunctionalUnit); selectNextUnit(); return
            }
            log("Selecting \(unitName(next))…")
            scanner.requestSelect(next)
        } else {
            afterDump()
        }
    }

    func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: (any Error)?) {
        if let error { log("Select \(unitName(functionalUnit.type)) error: \(error)") }
        if phase == "dump" {
            dump(functionalUnit)
            selectNextUnit()
        } else if phase == "selectForScan" {
            configureAndScan(functionalUnit)
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        log("Session closed\(error.map { " with error: \($0)" } ?? "").")
    }

    func didRemove(_ device: ICDevice) { log("Device removed.") }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        log("Device error: \(error.map { "\($0)" } ?? "nil")")
    }

    func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        log("Status: \(status.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " "))")
    }

    // MARK: Dump

    func dump(_ fu: ICScannerFunctionalUnit) {
        dumpedUnits.insert(fu.type.rawValue)
        print("")
        print("=== Functional unit: \(unitName(fu.type)) (\(type(of: fu))) ===")
        print("  state: \(stateName(fu.state))")
        print("  pixelDataType (current): \(pixelTypeName(fu.pixelDataType))")
        print("  supportedBitDepths: \(indexList(fu.supportedBitDepths))   current: \(fu.bitDepth.rawValue)")
        print("  supportedMeasurementUnits: \(fu.supportedMeasurementUnits.map(measurementName).joined(separator: ", "))   current: \(measurementName(Int(fu.measurementUnit.rawValue)))")
        print("  supportedResolutions: \(compactRanges(fu.supportedResolutions))")
        print("  preferredResolutions: \(indexList(fu.preferredResolutions))   current: \(fu.resolution)")
        print("  nativeResolution: \(fu.nativeXResolution) x \(fu.nativeYResolution)")
        print("  supportedScaleFactors: \(compactRanges(fu.supportedScaleFactors))   current: \(fu.scaleFactor)")
        print("  physicalSize: \(fu.physicalSize.width) x \(fu.physicalSize.height)")
        print("  scanArea: \(fu.scanArea)   orientation: \(fu.scanAreaOrientation.rawValue)")
        print("  B&W threshold supported: \(fu.acceptsThresholdForBlackAndWhiteScanning)")
        print("  canPerformOverviewScan: \(fu.canPerformOverviewScan)")
        if let f = fu as? ICScannerFunctionalUnitDocumentFeeder {
            print("  [feeder] supportedDocumentTypes: \(docTypes(f.supportedDocumentTypes))")
            print("  [feeder] documentType: \(documentTypeNames[Int(f.documentType.rawValue)] ?? "?") documentSize: \(f.documentSize.width) x \(f.documentSize.height)")
            print("  [feeder] supportsDuplexScanning: \(f.supportsDuplexScanning)   duplexEnabled: \(f.duplexScanningEnabled)")
            print("  [feeder] documentLoaded: \(f.documentLoaded)   reverseFeederPageOrder: \(f.reverseFeederPageOrder)")
            print("  [feeder] oddPageOrientation: \(f.oddPageOrientation.rawValue)   evenPageOrientation: \(f.evenPageOrientation.rawValue)")
        } else if let f = fu as? ICScannerFunctionalUnitFlatbed {
            print("  [flatbed] supportedDocumentTypes: \(docTypes(f.supportedDocumentTypes))")
            print("  [flatbed] documentType: \(f.documentType.rawValue) documentSize: \(f.documentSize.width) x \(f.documentSize.height)")
        }
        print("  templates: \(fu.templates.count)")
        for (i, t) in fu.templates.enumerated() {
            print("    template[\(i)] \(t.humanReadableName ?? "-") targets=\(t.targets.count)")
        }
        let vf = fu.vendorFeatures ?? []
        print("  vendorFeatures: \(vf.count)")
        for f in vf { print(describe(f)) }
    }

    func describe(_ f: ICScannerFeature) -> String {
        var s = "    - \(f.humanReadableName ?? "?") [\(f.internalName ?? "?")]"
        switch f {
        case let e as ICScannerFeatureEnumeration:
            let labels = e.menuItemLabels
            let pairs = e.values.enumerated().map { i, v in "\(v)=\(labels[safe: i] ?? "?")" }
            s += " enum current=\(e.currentValue) default=\(e.defaultValue) values={\(pairs.joined(separator: "; "))}"
        case let r as ICScannerFeatureRange:
            s += " range current=\(r.currentValue) default=\(r.defaultValue) min=\(r.minValue) max=\(r.maxValue) step=\(r.stepSize)"
        case let b as ICScannerFeatureBoolean:
            s += " bool value=\(b.value)"
        case let t as ICScannerFeatureTemplate:
            s += " template targets=\(t.targets.count)"
        default:
            s += " type=\(f.type.rawValue)"
        }
        if let tip = f.tooltip, !tip.isEmpty { s += " tooltip=\"\(tip)\"" }
        return s
    }

    func compactRanges(_ set: IndexSet) -> String {
        if set.isEmpty { return "(none)" }
        return set.rangeView.map { r in r.count == 1 ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound - 1)" }
            .joined(separator: ", ") + "  (\(set.count) values)"
    }

    // MARK: Scan

    func afterDump() {
        guard opts.mode == "scan", let scanner else { finish(code: 0); return }
        guard scanner.availableFunctionalUnitTypes.contains(NSNumber(value: ICScannerFunctionalUnitType.documentFeeder.rawValue)) else {
            log("No document feeder exposed — cannot run feeder scan."); finish(code: 1); return
        }
        phase = "selectForScan"
        if scanner.selectedFunctionalUnit.type == .documentFeeder {
            configureAndScan(scanner.selectedFunctionalUnit)
        } else {
            scanner.requestSelect(.documentFeeder)
        }
    }

    func configureAndScan(_ fu: ICScannerFunctionalUnit) {
        guard let scanner, let feeder = fu as? ICScannerFunctionalUnitDocumentFeeder else {
            log("Selected unit is not a document feeder."); finish(code: 1); return
        }
        print("")
        log("Configuring feeder scan @ \(opts.dpi) dpi, duplex requested=\(opts.duplex)")
        if !feeder.supportedResolutions.contains(opts.dpi) {
            log("WARNING: \(opts.dpi) dpi not in supportedResolutions; setting anyway.")
        }
        feeder.measurementUnit = .inches
        feeder.resolution = opts.dpi
        feeder.bitDepth = .depth8Bits
        feeder.pixelDataType = .RGB
        if opts.duplex {
            if feeder.supportsDuplexScanning { feeder.duplexScanningEnabled = true }
            else { log("Duplex requested but driver reports supportsDuplexScanning=false.") }
        }
        // Letter-size area so prints up to 8x10 are not clipped; cropping happens later.
        if feeder.supportedDocumentTypes.contains(Int(ICScannerDocumentType.typeUSLetter.rawValue)) {
            feeder.documentType = .typeUSLetter
        }
        let size = feeder.documentSize.width > 0 ? feeder.documentSize : feeder.physicalSize
        feeder.scanArea = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        print("  after config: resolution=\(feeder.resolution) bitDepth=\(feeder.bitDepth.rawValue) " +
              "pixelType=\(pixelTypeName(feeder.pixelDataType)) duplex=\(feeder.duplexScanningEnabled) " +
              "scanArea=\(feeder.scanArea) documentLoaded=\(feeder.documentLoaded)")

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let dir = opts.out.appendingPathComponent("\(opts.dpi)dpi\(opts.duplex ? "-duplex" : "")-\(stamp.string(from: Date()))", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { log("Cannot create \(dir.path): \(error)"); finish(code: 1); return }
        scanDir = dir
        scanner.transferMode = .fileBased
        scanner.downloadsDirectory = dir
        scanner.documentName = "scan"
        scanner.documentUTI = "public.tiff"
        log("Saving to \(dir.path)")
        phase = "scanning"
        scanStart = Date()
        scanner.requestScan()
    }

    func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        scannedFiles.append(url)
        log("Page \(scannedFiles.count): \(url.lastPathComponent)  \(imageInfo(url))")
    }

    func scannerDevice(_ scanner: ICScannerDevice, didScanTo data: ICScannerBandData) {
        log("Band data received (memory mode): \(data.dataSize) bytes")
    }

    func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: (any Error)?) {
        let secs = Date().timeIntervalSince(scanStart)
        log("Scan complete in \(String(format: "%.1f", secs))s, \(scannedFiles.count) file(s)" +
            (error.map { ", error: \($0)" } ?? ", no error"))
        finish(code: error == nil ? 0 : 1)
    }

    func imageInfo(_ url: URL) -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return "(unreadable)" }
        let w = p[kCGImagePropertyPixelWidth] ?? "?", h = p[kCGImagePropertyPixelHeight] ?? "?"
        let dpi = p[kCGImagePropertyDPIWidth] ?? "?", depth = p[kCGImagePropertyDepth] ?? "?"
        let model = p[kCGImagePropertyColorModel] ?? "?"
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return "\(w)x\(h)px dpi=\(dpi) depth=\(depth) color=\(model) \(bytes / 1024)KB"
    }

    // MARK: Exit

    func finish(code: Int32) {
        phase = "done"
        if let scanner, scanner.hasOpenSession { scanner.requestCloseSession() }
        browser.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(code) }
    }
}

let probe = Probe(parseOptions())
probe.start()
RunLoop.main.run()
