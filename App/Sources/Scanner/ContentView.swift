import SwiftUI
import ScanKit

private func defaultFolder(_ dir: FileManager.SearchPathDirectory) -> String {
    (FileManager.default.urls(for: dir, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser)
        .appendingPathComponent("Scans", isDirectory: true).path
}

struct ContentView: View {
    @EnvironmentObject private var c: ScanController
    @AppStorage("mode") private var mode: Mode = .photos

    // Photos (remembered between launches)
    @AppStorage("photo.dpi") private var photoDPI = 300
    @AppStorage("photo.format") private var photoFormat: ImageFormat = .jpeg
    @AppStorage("photo.folder") private var photoFolder = defaultFolder(.picturesDirectory)
    @AppStorage("photo.year") private var year = ""
    @AppStorage("photo.album") private var album = ""
    @AppStorage("photo.backs") private var scanBacks = true
    @AppStorage("photo.skipBlankBacks") private var skipBlankBacks = true
    @AppStorage("photo.enhance") private var enhance = false
    @AppStorage("photo.addToPhotos") private var addToPhotos = false

    // Documents
    @AppStorage("doc.dpi") private var docDPI = 300
    @AppStorage("doc.color") private var docColor: ColorMode = .color
    @AppStorage("doc.format") private var docFormat: DocumentFormat = .pdf
    @AppStorage("doc.folder") private var docFolder = defaultFolder(.documentDirectory)
    @AppStorage("doc.title") private var docTitle = ""
    @AppStorage("doc.duplex") private var docDuplex = true
    @AppStorage("doc.skipBlank") private var docSkipBlank = true
    @AppStorage("doc.searchable") private var docSearchable = true

    var body: some View {
        NavigationSplitView {
            Form {
                if mode == .photos { photoSettings } else { documentSettings }
            }
            .formStyle(.grouped)
            .disabled(c.busy)
            .navigationSplitViewColumnWidth(min: 290, ideal: 310, max: 380)
        } detail: {
            VStack(spacing: 0) {
                preview
                if !c.items.isEmpty {
                    Divider()
                    strip
                }
                Divider()
                bottomBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(c.busy)
            }
            ToolbarItem {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mode == .photos ? photoFolder : docFolder, isDirectory: true))
                } label: { Label("Show Folder", systemImage: "folder") }
                .help("Open the save folder in Finder")
            }
        }
        .navigationTitle(mode.label)
    }

    // MARK: Settings

    @ViewBuilder private var photoSettings: some View {
        Section("Album") {
            TextField("Year", text: $year, prompt: Text("e.g. 1998"))
            TextField("Album", text: $album, prompt: Text("e.g. Summer Trip"))
            LabeledContent("Next file") {
                Text(nextPhotoName).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
        Section("Scanning") {
            Picker("Resolution", selection: $photoDPI) {
                Text("300 dpi").tag(300)
                Text("600 dpi").tag(600)
            }
            Toggle("Scan backs (saved as _b)", isOn: $scanBacks)
            Toggle("Skip blank backs", isOn: $skipBlankBacks).disabled(!scanBacks)
            Toggle("Enhance (saved as _e)", isOn: $enhance)
                .help("Restores faded color and sharpens lightly. The untouched original is always kept.")
        }
        Section("Saving") {
            Picker("Format", selection: $photoFormat) {
                ForEach(ImageFormat.allCases) { Text($0.label).tag($0) }
            }
            folderRow($photoFolder)
            Toggle("Add to Photos after each batch", isOn: $addToPhotos)
        }
    }

    @ViewBuilder private var documentSettings: some View {
        Section("Document") {
            TextField("Title", text: $docTitle, prompt: Text("e.g. Receipts"))
            LabeledContent("File name") {
                Text("\(dateStamp)_\(Naming.clean(docTitle).isEmpty ? "Scan" : Naming.clean(docTitle))")
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
        Section("Scanning") {
            Picker("Resolution", selection: $docDPI) {
                Text("300 dpi").tag(300)
                Text("600 dpi").tag(600)
            }
            Picker("Color", selection: $docColor) {
                ForEach(ColorMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Both sides", isOn: $docDuplex)
            Toggle("Skip blank pages", isOn: $docSkipBlank)
        }
        Section("Saving") {
            Picker("Format", selection: $docFormat) {
                ForEach(DocumentFormat.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Searchable text (OCR)", isOn: $docSearchable).disabled(docFormat != .pdf)
            folderRow($docFolder)
        }
    }

    private func folderRow(_ path: Binding<String>) -> some View {
        LabeledContent("Folder") {
            HStack {
                Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                    .help(path.wrappedValue)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = URL(fileURLWithPath: path.wrappedValue)
                    if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
                }
            }
        }
    }

    private var nextPhotoName: String {
        let prefix = Naming.photoPrefix(year: year, album: album)
        let n = Naming.nextPhotoNumber(prefix: prefix, in: URL(fileURLWithPath: photoFolder))
        return "\(Naming.photoBase(prefix: prefix, number: n)).\(photoFormat.fileExtension)"
    }

    private var dateStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: Preview and strip

    private var selectedItem: ThumbItem? {
        c.items.first { $0.id == c.selection } ?? c.items.last
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let item = selectedItem {
                VStack(spacing: 10) {
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(radius: 4)
                    Text(item.title).font(.headline)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: mode == .photos ? "photo.stack" : "doc.on.doc")
                        .font(.system(size: 56)).foregroundStyle(.tertiary)
                    Text(mode == .photos
                         ? "Load prints face down in the feeder, then click Scan."
                         : "Load pages in the feeder, then click Scan.")
                        .foregroundStyle(.secondary)
                    if mode == .photos {
                        Text("Photos are cropped, straightened and turned upright automatically. To fix one without faces, right-click its thumbnail.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(c.items) { item in
                        thumb(item).id(item.id)
                    }
                }
                .padding(10)
            }
            .frame(height: 132)
            .onChange(of: c.items.count) {
                if let last = c.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .trailing) } }
            }
        }
    }

    private func thumb(_ item: ThumbItem) -> some View {
        let selected = item.id == (c.selection ?? c.items.last?.id)
        return VStack(spacing: 4) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 92)
                .overlay(alignment: .bottomTrailing) {
                    if item.photo?.back != nil {
                        Text("B").font(.caption2.bold()).padding(3)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                            .help("Back saved")
                    }
                }
            Text(item.title).font(.caption2).lineLimit(1).frame(maxWidth: 110)
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onTapGesture { c.selection = item.id }
        .help(item.photo != nil ? "Right-click to rotate or show in Finder" : "")
        .contextMenu {
            if item.photo != nil {
                Button("Rotate Left") { c.rotate(item.id, clockwise: false) }
                Button("Rotate Right") { c.rotate(item.id, clockwise: true) }
                Divider()
                Button("Show in Finder") {
                    if let url = item.photo?.original { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                    Text(c.scanner.status.label).font(.callout)
                }
                if c.isScanning || c.isFinishing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(progressText).font(.callout.monospacedDigit())
                    }
                } else if let message = c.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if mode == .photos, !c.photosImportable.isEmpty, !c.busy, !addToPhotos {
                Button("Add to Photos") { c.addBatchToPhotos() }
            }
            if c.isScanning {
                Button("Stop", role: .cancel) { c.cancel() }
                    .controlSize(.large)
            }
            Button(action: startScan) {
                Label("Scan", systemImage: "scanner")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!c.scanner.status.isReady || c.busy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var progressText: String {
        let noun = mode == .photos ? "photo" : "page"
        let counted = "\(c.count) \(noun)\(c.count == 1 ? "" : "s")"
        if c.isFinishing { return mode == .documents ? "Saving \(counted)…" : "Finishing…" }
        return "Scanning… \(counted) so far"
    }

    private var statusColor: Color {
        switch c.scanner.status {
        case .ready: return .green
        case .scanning: return .blue
        case .unavailable: return .red
        default: return .orange
        }
    }

    private func startScan() {
        if mode == .photos {
            c.scanPhotos(PhotoOptions(dpi: photoDPI, format: photoFormat,
                                      destination: URL(fileURLWithPath: photoFolder, isDirectory: true),
                                      year: year, album: album, scanBacks: scanBacks,
                                      skipBlankBacks: skipBlankBacks, enhance: enhance),
                         addToPhotos: addToPhotos)
        } else {
            c.scanDocuments(DocumentOptions(dpi: docDPI, color: docColor, format: docFormat,
                                            destination: URL(fileURLWithPath: docFolder, isDirectory: true),
                                            title: docTitle, duplex: docDuplex,
                                            skipBlankPages: docSkipBlank, searchable: docSearchable))
        }
    }
}
