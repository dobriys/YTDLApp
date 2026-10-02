// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YTDLApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTDLApp",
            path: "Sources/YTDLApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
