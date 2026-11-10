// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Knock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Knock",
            path: "Sources/Knock",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
