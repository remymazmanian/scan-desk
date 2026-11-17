import Foundation
import CoreGraphics
import PDFKit
import Testing
@testable import ScanKit

@Suite("Naming")
struct NamingTests {
    @Test func cleansUnsafeCharacters() {
        #expect(Naming.clean("  Summer / Trip: Day 1 ") == "Summer-Trip-Day-1")
        #expect(Naming.clean("") == "")
    }

    @Test func photoPrefixCombinesYearAndAlbum() {
        #expect(Naming.photoPrefix(year: "1998", album: "Summer Trip") == "1998_Summer-Trip")
        #expect(Naming.photoPrefix(year: "", album: "Summer Trip") == "Summer-Trip")
        #expect(Naming.photoPrefix(year: "1998", album: "") == "1998")
        #expect(Naming.photoPrefix(year: " ", album: "") == "Scan")
        #expect(Naming.photoBase(prefix: "1998_Trip", number: 7) == "1998_Trip_0007")
    }

    @Test func numberingContinuesAfterExistingFiles() throws {
        let dir = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Naming.nextPhotoNumber(prefix: "1998_Trip", in: dir) == 1)
        for name in ["1998_Trip_0001.jpg", "1998_Trip_0001_b.jpg", "1998_Trip_0012_e.tif", "1998_Other_0099.jpg", "1998_Trip_notes.txt"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        #expect(Naming.nextPhotoNumber(prefix: "1998_Trip", in: dir) == 13)
        #expect(Naming.nextPhotoNumber(prefix: "1998", in: dir) == 1)
    }

    @Test func documentNamesDontOverwrite() throws {
        let dir = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = DateComponents(calendar: .current, year: 2026, month: 3, day: 4).date!
        let first = Naming.documentBase(title: "Receipts", date: date, in: dir, extensions: ["pdf"])
        #expect(first == "2026-03-04_Receipts")
        try Data().write(to: dir.appendingPathComponent("\(first).pdf"))
        #expect(Naming.documentBase(title: "Receipts", date: date, in: dir, extensions: ["pdf"]) == "2026-03-04_Receipts_2")
        #expect(Naming.documentBase(title: "", date: date, in: dir, extensions: ["pdf"]) == "2026-03-04_Scan")
    }
}

@Suite("Blank and picture detection")
struct DetectionTests {
    @Test func blankBackIsBlank() {
        #expect(PhotoProcessing.isBlank(Fixtures.back(width: 1200, height: 1800)))
    }

    @Test func backWithWritingIsKept() {
        let img = Fixtures.back(width: 1200, height: 1800, note: true)
        #expect(!PhotoProcessing.isBlank(img))
        #expect(!PhotoProcessing.looksLikePictureSide(img))
    }

    @Test func pictureSideIsRecognized() {
        let img = Fixtures.picture(width: 1200, height: 1800)
        #expect(PhotoProcessing.looksLikePictureSide(img))
        #expect(!PhotoProcessing.isBlank(img))
    }

    @Test func punchHolesAloneCountAsBlank() {
        #expect(PhotoProcessing.isBlank(Fixtures.blankPage(dpi: 150, punchHoles: true)))
        #expect(!PhotoProcessing.isBlank(Fixtures.textPage(dpi: 150, lines: ["A line of text on the page"])))
    }
}

@Suite("Cropping")
struct CropTests {
    @Test func detectsUncroppedLetterFrames() {
        let frame = Fixtures.uncroppedFrame(dpi: 150, print: Fixtures.back(width: 600, height: 900),
                                            printInches: CGSize(width: 4, height: 6), paperEndInches: 6.6)
        #expect(PhotoProcessing.isUncropped(frame, dpi: 150))
        #expect(!PhotoProcessing.isUncropped(Fixtures.back(width: 600, height: 900), dpi: 150))
    }

    @Test(arguments: [true, false])
    func cropsPrintFromScannerBackground(pictureSide: Bool) throws {
        let dpi = 150
        let print = pictureSide ? Fixtures.picture(width: 600, height: 900) : Fixtures.back(width: 600, height: 900)
        let frame = Fixtures.uncroppedFrame(dpi: dpi, print: print,
                                            printInches: CGSize(width: 4, height: 6), paperEndInches: 6.6)
        let cropped = try #require(PhotoProcessing.detectAndCrop(frame))
        // 4 x 6 in at 150 dpi = 600 x 900 px; allow a few percent for edges.
        #expect(abs(cropped.width - 600) < 30, "width \(cropped.width)")
        #expect(abs(cropped.height - 900) < 45, "height \(cropped.height)")
    }

    @Test func backOrientationMirrorsQuarterTurns() {
        #expect(PhotoProcessing.backOrientation(for: .right) == .left)
        #expect(PhotoProcessing.backOrientation(for: .left) == .right)
        #expect(PhotoProcessing.backOrientation(for: .down) == .down)
        #expect(PhotoProcessing.backOrientation(for: .up) == .up)
    }
}

@Suite("Photo pipeline")
struct PhotoPipelineTests {
    func pipeline(_ dir: URL, backs: Bool = true, enhance: Bool = false) -> PhotoPipeline {
        PhotoPipeline(options: PhotoOptions(dpi: 150, format: .jpeg, destination: dir, year: "1998",
                                            album: "Test", scanBacks: backs, skipBlankBacks: true, enhance: enhance))
    }

    func page(_ img: CGImage, _ name: String, in dir: URL) -> URL {
        Fixtures.writeTIFF(img, to: dir.appendingPathComponent("\(name).tiff"), dpi: 150)
    }

    @Test func pairsFrontsWithBacks() throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = pipeline(out)
        let pages = [
            page(Fixtures.picture(width: 600, height: 900, seed: 1), "1", in: raw),
            page(Fixtures.back(width: 600, height: 900, note: true), "2", in: raw),
            page(Fixtures.picture(width: 600, height: 900, seed: 2), "3", in: raw),
            page(Fixtures.back(width: 600, height: 900), "4", in: raw),
        ]
        let events = try pages.flatMap { try p.handle(page: $0) }
        #expect(events.count == 4)
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(files == ["1998_Test_0001.jpg", "1998_Test_0001_b.jpg", "1998_Test_0002.jpg"])
        if case .back(let r) = events[3] { #expect(r.backSkippedAsBlank) } else { Issue.record("expected a back") }
    }

    /// The scanner drops blank backs on its own (PROBE.md); pairing must not shift.
    @Test func missingBacksDontShiftPairing() throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = pipeline(out)
        var names: [String] = []
        var missing = 0
        for i in 1...3 {
            for e in try p.handle(page: page(Fixtures.picture(width: 600, height: 900, seed: UInt64(i)), "\(i)", in: raw)) {
                switch e {
                case .front(let r): names.append(r.name)
                case .back(let r): if r.backMissing { missing += 1 }
                }
            }
        }
        #expect(names == ["1998_Test_0001", "1998_Test_0002", "1998_Test_0003"])
        #expect(missing == 2)   // the third photo's back is still pending when the batch ends
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(!files.contains { $0.contains("_b.") })
    }

    @Test func enhanceKeepsOriginal() throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = pipeline(out, backs: false, enhance: true)
        _ = try p.handle(page: page(Fixtures.picture(width: 600, height: 900), "1", in: raw))
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(files == ["1998_Test_0001.jpg", "1998_Test_0001_e.jpg"])
    }

    @Test func manualRotationTurnsFilesAndKeepsSize() throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = pipeline(out, backs: false)
        guard case .front(let r) = try p.handle(page: page(Fixtures.picture(width: 600, height: 900), "1", in: raw)).first
        else { Issue.record("expected a front"); return }
        _ = try PhotoPipeline.rotate(r, clockwise: true, format: .jpeg, dpi: 150)
        let img = try ImageUtil.load(r.original)
        #expect(img.width == 900 && img.height == 600)
        #expect(ImageUtil.dpi(of: r.original) == 150)
    }
}

@Suite("Document pipeline")
struct DocumentPipelineTests {
    @Test(arguments: [ColorMode.gray, .bw])
    func searchablePDFSkipsBlankPages(color: ColorMode) throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = DocumentPipeline(options: DocumentOptions(dpi: 200, color: color, format: .pdf, destination: out,
                                                          title: "Receipts", duplex: true,
                                                          skipBlankPages: true, searchable: true))
        let pages = [
            Fixtures.textPage(dpi: 200, lines: ["Quarterly garden supply receipt", "Total paid forty two dollars"], punchHoles: true),
            Fixtures.blankPage(dpi: 200, punchHoles: true),
            Fixtures.textPage(dpi: 200, lines: ["Second page of the test document"], punchHoles: true),
            Fixtures.blankPage(dpi: 200, punchHoles: true),
        ]
        for (i, img) in pages.enumerated() {
            _ = try p.handle(page: Fixtures.writeTIFF(img, to: raw.appendingPathComponent("\(i).tiff"), dpi: 200))
        }
        #expect(p.skippedBlank == 2)
        let saved = try p.finish()
        #expect(saved.count == 1)
        let pdf = try #require(PDFDocument(url: saved[0]))
        #expect(pdf.pageCount == 2)
        let text = pdf.string ?? ""
        #expect(text.localizedCaseInsensitiveContains("garden supply"), "OCR text: \(text)")
        #expect(text.localizedCaseInsensitiveContains("second page"))
        // Letter page at its real size: 612 x 792 points.
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - 612) < 2 && abs(box.height - 792) < 2)
    }

    @Test func imageOutputNamesEachPage() throws {
        let out = Fixtures.tempDir(), raw = Fixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: raw) }
        let p = DocumentPipeline(options: DocumentOptions(dpi: 150, color: .gray, format: .jpeg, destination: out,
                                                          title: "Receipts", duplex: false,
                                                          skipBlankPages: false, searchable: false))
        for i in 0..<2 {
            _ = try p.handle(page: Fixtures.writeTIFF(Fixtures.textPage(dpi: 150, lines: ["Page \(i)"]),
                                                      to: raw.appendingPathComponent("\(i).tiff"), dpi: 150))
        }
        let names = try p.finish().map(\.lastPathComponent)
        #expect(names.count == 2)
        #expect(names.allSatisfy { $0.hasSuffix("_Receipts_p00\($0.contains("p001") ? 1 : 2).jpg") })
    }
}
