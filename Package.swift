// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-tca-experiment",
  products: [.library(name: "Composable", targets: ["Composable"])],
  targets: [
    .target(name: "Composable"),
    .testTarget(name: "ComposableTests", dependencies: ["Composable"]),
  ],
  swiftLanguageVersions: [.v6]
)
