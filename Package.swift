// swift-tools-version: 5.9
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "betterBCool",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BetterBCoolCore", targets: ["BetterBCoolCore"]),
        .library(name: "BetterBCoolUI", targets: ["BetterBCoolUI"]),
        .library(name: "FeverFridaKit", targets: ["FeverFridaKit"])
    ],
    targets: [
        .target(name: "BetterBCoolCore"),
        .target(name: "BetterBCoolUI", dependencies: ["BetterBCoolCore"]),
        .target(name: "FeverFridaKit"),
        .testTarget(name: "BetterBCoolCoreTests", dependencies: ["BetterBCoolCore"]),
        .testTarget(name: "FeverFridaKitTests", dependencies: ["FeverFridaKit"])
    ]
)
