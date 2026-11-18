import Foundation

public enum Naming {
    /// Keeps names Finder- and Photos-friendly: no slashes or colons, spaces become hyphens.
    public static func clean(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let parts = s.components(separatedBy: bad).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        return parts.joined(separator: "-")
    }

    /// "1998_Summer-Trip", "Summer-Trip", "1998", or "Scan" when both are empty.
    public static func photoPrefix(year: String, album: String) -> String {
        let parts = [clean(year), clean(album)].filter { !$0.isEmpty }
        return parts.isEmpty ? "Scan" : parts.joined(separator: "_")
    }

    public static func photoBase(prefix: String, number: Int) -> String {
        "\(prefix)_\(String(format: "%04d", number))"
    }

    /// One past the highest number already used for this prefix in the folder,
    /// so new batches continue the series instead of overwriting.
    public static func nextPhotoNumber(prefix: String, in dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let pattern = "^" + NSRegularExpression.escapedPattern(for: prefix) + "_(\\d{4,})(_[a-z])?\\.[A-Za-z]+$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 1 }
        var highest = 0
        for f in files {
            let range = NSRange(f.startIndex..., in: f)
            if let m = re.firstMatch(in: f, range: range), let r = Range(m.range(at: 1), in: f), let n = Int(f[r]) {
                highest = max(highest, n)
            }
        }
        return highest + 1
    }

    /// "2026-11-17_Title" (or "2026-11-17_Scan"), with "_2", "_3"… if taken.
    public static func documentBase(title: String, date: Date = Date(), in dir: URL, extensions: [String]) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let t = clean(title)
        let base = "\(f.string(from: date))_\(t.isEmpty ? "Scan" : t)"
        func taken(_ name: String) -> Bool {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains { file in extensions.contains { file.lowercased().hasPrefix(name.lowercased()) && file.lowercased().hasSuffix(".\($0)") } }
        }
        if !taken(base) { return base }
        var i = 2
        while taken("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }
}
