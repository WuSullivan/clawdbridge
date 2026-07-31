// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClawdBridge",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "ClawdBridge", targets: ["ClawdBridge"]),
    ],
    targets: [
        .target(
            name: "ClawdBridge",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
