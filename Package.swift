// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudePulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudePulse",
            path: "Sources/ClaudePulse"
        )
    ]
)
