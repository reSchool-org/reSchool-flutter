// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "home_widget",
  platforms: [
    .iOS("14.0")
  ],
  products: [
    .library(name: "home-widget", targets: ["home_widget"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "home_widget",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ]
    )
  ]
)
