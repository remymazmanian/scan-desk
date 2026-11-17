import Foundation
import ImageCaptureCore
import os

let scanLog = Logger(subsystem: "local.scanner.app", category: "scanner")

public enum ScannerStatus: Equatable {
    case searching
    case connecting(String)
    case ready(String)
    case scanning(String)
    case unavailable(String)

    public var label: String {
        switch self {
        case .searching: return "Looking for scanner…"
        case .connecting(let n): return "Connecting to \(n)…"
        case .ready(let n): return "\(n) ready"
        case .scanning(let n): return "\(n) scanning"
        case .unavailable(let why): return why
        }
    }

    public var isReady: Bool { if case .ready = self { return true } else { return false } }
}

/// Finds a feeder scanner through Image Capture, keeps a session open, and runs feeder scans.
///
/// Findings from PROBE.md baked in here:
/// - The Epson driver never calls `scannerDeviceDidBecomeAvailable`, so readiness is polled.
/// - Duplex output arrives as separate files, strictly front then back.
/// - The driver's blank-page skip is unreliable and breaks front/back pairing, so it is forced off.
///
/// All ImageCaptureCore callbacks arrive on the main thread; use this class from the main thread only.
public final class ScannerService: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    @Published public private(set) var status: ScannerStatus = .searching

    private let browser = ICDeviceBrowser()
    private var candidates: [ICScannerDevice] = []
    private var scanner: ICScannerDevice?
    private var pollAttempts = 0
    private var pollTimer: Timer?
    private var stopping = false

    private var pageHandler: ((URL) -> Void)?
    private var completion: ((Error?) -> Void)?

    public override init() {
        super.init()
        browser.delegate = self
        let mask = ICDeviceTypeMask.scanner.rawValue
            | ICDeviceLocationTypeMask.local.rawValue
            | ICDeviceLocationTypeMask.shared.rawValue
            | ICDeviceLocationTypeMask.bonjour.rawValue
            | ICDeviceLocationTypeMask.remote.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask)!
    }

    public var deviceName: String { scanner?.name ?? "Scanner" }

    public func start() {
        stopping = false
        browser.start()
    }

    public func stop() {
        stopping = true
        pollTimer?.invalidate()
        if let scanner, scanner.hasOpenSession { scanner.requestCloseSession() }
        browser.stop()
    }

    // MARK: Scanning

    public func scan(_ p: ScanParameters, into directory: URL,
                     onPage: @escaping (URL) -> Void,
                     completion: @escaping (Error?) -> Void) throws {
        guard status.isReady, let scanner,
              let feeder = scanner.selectedFunctionalUnit as? ICScannerFunctionalUnitDocumentFeeder
        else { throw ScanError.notReady }

        feeder.measurementUnit = .inches
        feeder.resolution = p.dpi
        switch p.color {
        case .color: feeder.pixelDataType = .RGB; feeder.bitDepth = .depth8Bits
        case .gray: feeder.pixelDataType = .gray; feeder.bitDepth = .depth8Bits
        case .bw: feeder.pixelDataType = .BW; feeder.bitDepth = .depth1Bit
        }
        feeder.duplexScanningEnabled = p.duplex && feeder.supportsDuplexScanning
        // Letter-size area; the driver's Auto Size Detection crops each page to the paper.
        if feeder.supportedDocumentTypes.contains(Int(ICScannerDocumentType.typeUSLetter.rawValue)) {
            feeder.documentType = .typeUSLetter
        }
        let size = feeder.documentSize.width > 0 ? feeder.documentSize : feeder.physicalSize
        feeder.scanArea = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        setFeature("VF_AUTOCROP", on: feeder, enumValue: 1)        // Standard paper auto size
        setFeature("VF_DESKEW", on: feeder, bool: true)
        setFeature("VF_AUTOROTATE", on: feeder, bool: p.driverAutoRotate)
        setFeature("VF_BLANKPAGESKIP", on: feeder, enumValue: 0)   // app detects blanks itself
        setFeature("VF_DOUBLEFEEDDETECT", on: feeder, bool: true)

        scanner.transferMode = .fileBased
        scanner.downloadsDirectory = directory
        scanner.documentName = "page"
        scanner.documentUTI = "public.tiff"

        scanLog.info("scan: \(p.dpi) dpi, color \(p.color.rawValue, privacy: .public), duplex requested \(p.duplex), duplex set \(feeder.duplexScanningEnabled)")
        pageHandler = onPage
        self.completion = completion
        status = .scanning(deviceName)
        scanner.requestScan()
    }

    public func cancel() { scanner?.cancelScan() }

    /// Sets a driver feature. The Epson driver seems to ignore a write that matches the value it
    /// already reports (its blank-page skip read "Off" but still dropped blank backs), so every
    /// write first moves to a different value and then to the wanted one.
    private func setFeature(_ name: String, on fu: ICScannerFunctionalUnit, enumValue: Int? = nil, bool: Bool? = nil) {
        guard let f = fu.vendorFeatures?.first(where: { $0.internalName == name }) else {
            scanLog.info("feature \(name, privacy: .public) not offered by driver")
            return
        }
        if let bool, let b = f as? ICScannerFeatureBoolean {
            b.value = !bool
            b.value = bool
            scanLog.info("feature \(name, privacy: .public) = \(b.value)")
        }
        if let enumValue, let e = f as? ICScannerFeatureEnumeration,
           e.values.contains(NSNumber(value: enumValue)) {
            if let other = e.values.first(where: { $0.intValue != enumValue }) { e.currentValue = other }
            e.currentValue = NSNumber(value: enumValue)
            scanLog.info("feature \(name, privacy: .public) = \(String(describing: e.currentValue), privacy: .public)")
        }
    }

    // MARK: Connection

    private func connectBest() {
        guard scanner == nil, !stopping else { return }
        let usb = ICDeviceTransport.transportTypeUSB.rawValue
        guard let pick = candidates.first(where: { $0.transportType == usb }) ?? candidates.first else {
            status = .searching
            return
        }
        scanner = pick
        pick.delegate = self
        status = .connecting(pick.name ?? "Scanner")
        pick.requestOpenSession()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollAttempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let scanner else { pollTimer?.invalidate(); return }
        pollAttempts += 1
        let types = scanner.availableFunctionalUnitTypes.map(\.uintValue)
        if types.isEmpty {
            if pollAttempts > 45 {
                pollTimer?.invalidate()
                status = .unavailable("Scanner didn't respond. Is it awake?")
            }
            return
        }
        pollTimer?.invalidate()
        guard types.contains(ICScannerFunctionalUnitType.documentFeeder.rawValue) else {
            status = .unavailable(ScanError.noFeeder.localizedDescription)
            return
        }
        if scanner.selectedFunctionalUnit.type == .documentFeeder {
            becameReady()
        } else {
            scanner.requestSelect(.documentFeeder)
        }
    }

    private func becameReady() {
        if case .scanning = status { return }
        status = .ready(deviceName)
    }

    private func forget(_ device: ICDevice) {
        candidates.removeAll { $0 === device }
        if device === scanner {
            pollTimer?.invalidate()
            scanner = nil
            if let c = completion {
                completion = nil
                pageHandler = nil
                c(ScanError.notReady)
            }
            status = .searching
            connectBest()
        }
    }

    // MARK: ICDeviceBrowserDelegate

    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let s = device as? ICScannerDevice else { return }
        candidates.append(s)
        // Give a USB device that shows up a moment later a chance to win.
        DispatchQueue.main.asyncAfter(deadline: .now() + (moreComing ? 1.5 : 0.5)) { [weak self] in
            self?.connectBest()
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        forget(device)
    }

    // MARK: ICDeviceDelegate

    public func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error {
            status = .unavailable("Couldn't connect: \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak device] in
                guard let self, let device, device === self.scanner, !self.stopping else { return }
                self.status = .connecting(device.name ?? "Scanner")
                device.requestOpenSession()
            }
            return
        }
        startPolling()
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        guard !stopping, device === scanner else { return }
        status = .connecting(deviceName)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak device] in
            guard let self, let device, device === self.scanner, !self.stopping else { return }
            device.requestOpenSession()
        }
    }

    public func didRemove(_ device: ICDevice) { forget(device) }

    // MARK: ICScannerDeviceDelegate

    public func scannerDeviceDidBecomeAvailable(_ scanner: ICScannerDevice) { poll() }

    public func scannerDevice(_ scanner: ICScannerDevice, didSelect functionalUnit: ICScannerFunctionalUnit, error: (any Error)?) {
        if functionalUnit.type == .documentFeeder { becameReady() }
    }

    public func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        scanLog.info("page received: \(url.lastPathComponent, privacy: .public)")
        pageHandler?(url)
    }

    public func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: (any Error)?) {
        scanLog.info("scan complete, error: \(String(describing: error), privacy: .public)")
        let done = completion
        completion = nil
        pageHandler = nil
        status = .ready(deviceName)
        done?(error)
    }
}
