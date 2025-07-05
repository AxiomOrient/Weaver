// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Weaver",
    platforms: [
        .iOS(.v15),
        .watchOS(.v8),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Weaver",
            targets: ["Weaver"]),
    ],
    dependencies: [
        
    ],
    targets: [
        .target(
            name: "Weaver",
            dependencies: []
        ),
        .testTarget(
            name: "WeaverTests",
            dependencies: ["Weaver"]
        ),
    ]
)
