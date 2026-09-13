// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pasteboard",
    platforms: [
        .macOS("10.11")
    ],
    products: [
        .library(name: "pasteboard", targets: ["pasteboard"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "pasteboard",
            dependencies: [],
            resources: []
        )
    ]
)
