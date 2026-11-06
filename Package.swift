// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacVolume",
    // Core Audio process taps need macOS 14.4+.
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "ChromeSupport"),
        .executableTarget(name: "ChromeBridge", dependencies: ["ChromeSupport"]),
        .executableTarget(name: "MacVolume", dependencies: ["ChromeSupport"], path: "Sources/MacVolume"),
        .testTarget(name: "ChromeSupportTests", dependencies: ["ChromeSupport"]),
        .testTarget(name: "MacVolumeTests", dependencies: ["MacVolume", "ChromeSupport"])
    ],
    swiftLanguageModes: [.v5]
)
