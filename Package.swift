// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WinMix",
    // Core Audio process taps need macOS 14.4+.
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "ChromeSupport"),
        .executableTarget(name: "ChromeBridge", dependencies: ["ChromeSupport"]),
        .executableTarget(name: "WinMix", dependencies: ["ChromeSupport"], path: "Sources/WinMix"),
        .testTarget(name: "ChromeSupportTests", dependencies: ["ChromeSupport"]),
        .testTarget(name: "WinMixTests", dependencies: ["WinMix", "ChromeSupport"])
    ],
    swiftLanguageModes: [.v5]
)
