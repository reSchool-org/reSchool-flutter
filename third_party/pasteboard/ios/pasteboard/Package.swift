// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pasteboard",
    platforms: [
        .iOS("9.0")
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
