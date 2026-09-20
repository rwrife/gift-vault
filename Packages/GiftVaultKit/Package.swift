// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GiftVaultKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GiftVaultKit", targets: ["GiftVaultKit"]),
    ],
    targets: [
        .target(name: "GiftVaultKit"),
        .testTarget(name: "GiftVaultKitTests", dependencies: ["GiftVaultKit"]),
    ]
)
