import Foundation
import Photos

/// Adds finished scans to the Photos library (add-only access, no reading of the library).
public enum PhotosImporter {
    public static func add(_ files: [URL]) async throws -> Int {
        guard !files.isEmpty else { return 0 }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "Scanner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Photos access was not allowed. You can allow it in System Settings → Privacy & Security → Photos.",
            ])
        }
        try await PHPhotoLibrary.shared().performChanges {
            for url in files {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
        }
        return files.count
    }
}
