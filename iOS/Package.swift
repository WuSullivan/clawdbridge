// swift-tools-version: 5.9
// iOS companion app for ClawdBridge
// Build: swift build (via Xcode project generated separately)
// This Package.swift defines the iOS target.

import PackageDescription

let package = Package(
    name: "ClawdBridge",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "ClawdBridge", targets: ["ClawdBridge"])
    ],
    targets: [
        .executableTarget(
            name: "ClawdBridge",
            path: "ClawdBridge"
        )
    ]
)
