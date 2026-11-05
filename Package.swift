// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PayBeat",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "PayBeat", swiftSettings: [.swiftLanguageMode(.v5)])]
)
