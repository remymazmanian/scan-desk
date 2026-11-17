import AppKit
import Combine
import ScanKit

enum Mode: String, CaseIterable, Identifiable {
    case photos, documents
    var id: String { rawValue }
    var label: String { self == .photos ? "Photos" : "Documents" }
}

struct ThumbItem: Identifiable {
    let id = UUID()
    var title: String
    var image: NSImage
    var detail: String
    var photo: PhotoResult?
}

/// Runs one feeder batch at a time: hands each page to the right pipeline on a background
/// queue and publishes thumbnails, counts and messages for the window.
@MainActor
final class ScanController: ObservableObject {
    let scanner = ScannerService()

    @Published var items: [ThumbItem] = []
    @Published var selection: ThumbItem.ID?
    @Published var isScanning = false
    @Published var isFinishing = false
    @Published var count = 0
    @Published var message: String?
    @Published var lastFolder: URL?
    @Published var photosImportable: [URL] = []

    private var bag = Set<AnyCancellable>()
    private let work = DispatchQueue(label: "scanner.processing", qos: .userInitiated)
    private var batchFormat: ImageFormat = .jpeg
    private var batchDPI = 300

    init() {
        scanner.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        scanner.start()
    }

    var busy: Bool { isScanning || isFinishing }

    // MARK: Photos

    func scanPhotos(_ o: PhotoOptions, addToPhotos: Bool) {
        guard let temp = beginBatch(destination: o.destination) else { return }
        batchFormat = o.format
        batchDPI = o.dpi
        let pipeline = PhotoPipeline(options: o)
        start(o.scanParameters, temp: temp, onPage: { url in
            let events = try pipeline.handle(page: url)
            return { [weak self] in events.forEach { self?.apply($0) } }
        }, finish: {
            return { [weak self] in
                guard let self else { return }
                if addToPhotos { self.addBatchToPhotos() }
            }
        }, nothingScanned: "No photos came through. Check that the prints are loaded in the feeder, face down.",
           summary: { [weak self] in
            guard let self else { return "" }
            return "Saved \(self.count) photo\(self.count == 1 ? "" : "s") to \(o.destination.lastPathComponent)."
        })
    }

    private func apply(_ e: PhotoPipeline.Event) {
        switch e {
        case .front(let r):
            items.append(ThumbItem(title: r.name, image: NSImage(cgImage: r.thumbnail, size: .zero),
                                   detail: r.enhanced != nil ? "Original + enhanced" : "", photo: r))
            selection = items.last?.id
            count += 1
            photosImportable.append(r.enhanced ?? r.original)
        case .back(let r):
            guard let i = items.lastIndex(where: { $0.photo?.name == r.name }) else { return }
            items[i].photo = r
            let back = r.backMissing ? "no back received" : r.backSkippedAsBlank ? "blank back skipped" : "back saved"
            items[i].detail = items[i].detail.isEmpty ? back.capitalizedFirst : "\(items[i].detail), \(back)"
        }
    }

    func rotate(_ id: ThumbItem.ID, clockwise: Bool) {
        guard let item = items.first(where: { $0.id == id }), let photo = item.photo, !busy else { return }
        let format = batchFormat, dpi = batchDPI
        work.async { [weak self] in
            do {
                let updated = try PhotoPipeline.rotate(photo, clockwise: clockwise, format: format, dpi: dpi)
                Task { @MainActor in
                    guard let self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                    self.items[i].photo = updated
                    self.items[i].image = NSImage(cgImage: updated.thumbnail, size: .zero)
                }
            } catch {
                Task { @MainActor in self?.message = error.localizedDescription }
            }
        }
    }

    func addBatchToPhotos() {
        let files = photosImportable
        guard !files.isEmpty else { return }
        Task {
            do {
                let n = try await PhotosImporter.add(files)
                message = "Added \(n) photo\(n == 1 ? "" : "s") to Photos."
                photosImportable = []
            } catch {
                message = error.localizedDescription
            }
        }
    }

    // MARK: Documents

    func scanDocuments(_ o: DocumentOptions) {
        guard let temp = beginBatch(destination: o.destination) else { return }
        let pipeline = DocumentPipeline(options: o)
        var saved: [URL] = []
        start(o.scanParameters, temp: temp, onPage: { url in
            let event = try pipeline.handle(page: url)
            return { [weak self] in
                guard let self else { return }
                switch event {
                case .page(let n, let thumb):
                    self.items.append(ThumbItem(title: "Page \(n)", image: NSImage(cgImage: thumb, size: .zero),
                                                detail: "", photo: nil))
                    self.selection = self.items.last?.id
                    self.count = n
                case .skippedBlank:
                    break
                }
            }
        }, finish: {
            // Pages stay as raw files in the temp folder until the PDF or images are written here.
            saved = try pipeline.finish()
            return {}
        }, nothingScanned: "No pages came through. Check that the pages are loaded in the feeder.",
           summary: {
            let skipped = pipeline.skippedBlank
            let what = saved.count == 1 ? saved[0].lastPathComponent : "\(saved.count) files"
            return "Saved \(what) to \(o.destination.lastPathComponent)"
                + (skipped > 0 ? " (\(skipped) blank page\(skipped == 1 ? "" : "s") skipped)." : ".")
        })
    }

    // MARK: Batch plumbing

    func cancel() { scanner.cancel() }

    private func beginBatch(destination: URL) -> URL? {
        guard !busy else { return nil }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            items = []
            selection = nil
            count = 0
            message = nil
            photosImportable = []
            lastFolder = destination
            return temp
        } catch {
            message = "Can't use that folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// `onPage` and `finish` run on the processing queue and return a closure to apply on the main actor.
    private func start(_ params: ScanParameters, temp: URL,
                       onPage: @escaping (URL) throws -> () -> Void,
                       finish: @escaping () throws -> () -> Void,
                       nothingScanned: String,
                       summary: @escaping () -> String) {
        let work = self.work
        var pageError: String?
        do {
            isScanning = true
            try scanner.scan(params, into: temp, onPage: { url in
                work.async {
                    do {
                        let apply = try onPage(url)
                        Task { @MainActor in apply() }
                    } catch {
                        pageError = error.localizedDescription
                    }
                }
            }, completion: { [weak self] scanError in
                Task { @MainActor in
                    guard let self else { return }
                    self.isScanning = false
                    self.isFinishing = true
                    work.async {
                        var finishError: Error?
                        var apply: () -> Void = {}
                        do { apply = try finish() } catch { finishError = error }
                        try? FileManager.default.removeItem(at: temp)
                        Task { @MainActor in
                            self.isFinishing = false
                            apply()
                            if let finishError {
                                self.message = "Couldn't save: \(finishError.localizedDescription)"
                            } else if self.count == 0 {
                                self.message = pageError.map { "Couldn't process the scan: \($0)" } ?? nothingScanned
                            } else if let pageError {
                                self.message = summary() + " Some pages failed: \(pageError)"
                            } else if let scanError {
                                self.message = summary() + " The scanner stopped early: \(scanError.localizedDescription)"
                            } else if self.message == nil {
                                self.message = summary()
                            }
                        }
                    }
                }
            })
        } catch {
            isScanning = false
            try? FileManager.default.removeItem(at: temp)
            message = error.localizedDescription
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
