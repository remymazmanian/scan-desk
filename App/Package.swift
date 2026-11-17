// swift-tools-version:6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Scanner",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "ScanKit",
            swiftSettings: swift5,
            linkerSettings: [
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("Vision"),
                .linkedFramework("Photos"),
            ]
        ),
        .executableTarget(name: "Scanner", dependencies: ["ScanKit"], swiftSettings: swift5),
        .executableTarget(name: "scankit-check", dependencies: ["ScanKit"], swiftSettings: swift5),
    ]
)
