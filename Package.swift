// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawdBridge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClawdBridge",
            path: "Sources"
        )
    ]
)
