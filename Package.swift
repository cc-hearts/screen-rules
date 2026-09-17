// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenRules",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ScreenRules", path: "Sources/ScreenRules")
    ]
)
