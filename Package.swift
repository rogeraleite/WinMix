// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacVolume",
    // Core Audio process taps need macOS 14.4+.
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "MacVolume", path: "Sources/MacVolume")
    ],
    swiftLanguageModes: [.v5]
)
