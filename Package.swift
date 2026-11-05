// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkTicker",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "WorkTicker", swiftSettings: [.swiftLanguageMode(.v5)])]
)
