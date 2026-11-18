// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScanProbe",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScanProbe",
            path: "Sources/ScanProbe",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ImageCaptureCore")]
        )
    ]
)
