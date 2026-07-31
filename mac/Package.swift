// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClawdBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "clawdbridge", targets: ["ClawdBridge"]),
    ],
    dependencies: [
        // 零外部依赖：仅使用 Foundation + Network + AppKit 系统框架
    ],
    targets: [
        .executableTarget(
            name: "ClawdBridge",
            path: "Sources/ClawdBridge"
        ),
        .testTarget(
            name: "ClawdBridgeTests",
            dependencies: ["ClawdBridge"],
            path: "Tests/ClawdBridgeTests"
        ),
    ]
)
